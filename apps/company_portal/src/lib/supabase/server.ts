import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import type { Database } from './database.types';

/**
 * Server-side Supabase client, authenticated as the SIGNED-IN USER.
 *
 * Deliberately NOT the service role. Server components read through RLS
 * exactly as the browser would, so a missing policy fails loudly in
 * development instead of silently leaking in production (A4 §14.2).
 */
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            );
          } catch {
            // Called from a Server Component, where cookies are read-only.
            // Middleware refreshes the session, so this is safe to ignore.
          }
        },
      },
    }
  );
}

/** The signed-in user, or null. */
export async function getUser() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return user;
}

export type CompanyContext = {
  companyId: string;
  companyName: string;
  slug: string;
  role: Database['public']['Enums']['company_role'];
  isVerified: boolean;
};

/**
 * Resolves the active company context.
 *
 * Every authorisation check evaluates against this, never against the person
 * globally (A4 §2.3). Returns null when the user belongs to no company yet,
 * which routes them to onboarding.
 */
export async function getCompanyContext(): Promise<CompanyContext | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data } = await supabase
    .from('company_members')
    .select('role, companies!inner ( id, display_name, slug, is_verified )')
    .eq('person_id', user.id)
    .eq('is_active', true)
    .limit(1)
    .maybeSingle();

  if (!data?.companies) return null;
  const c = data.companies as unknown as {
    id: string;
    display_name: string;
    slug: string;
    is_verified: boolean;
  };

  return {
    companyId: c.id,
    companyName: c.display_name,
    slug: c.slug,
    role: data.role,
    isVerified: c.is_verified,
  };
}
