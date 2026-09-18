import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { cache } from 'react';
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

type CompanyRole = Database['public']['Enums']['company_role'];

/** The cookie that remembers which company (workspace) the user is working in. */
export const WORKSPACE_COOKIE = 'omelo_company';

/** Most to least privileged: a person holding several roles acts as the first. */
const ROLE_ORDER: CompanyRole[] = [
  'owner',
  'admin',
  'recruiter',
  'hiring_manager',
  'hr',
  'coordinator',
  'sourcer',
  'interviewer',
  'finance',
  'viewer',
];

export type CompanyKind = 'employer' | 'agency';

export type CompanyContext = {
  companyId: string;
  companyName: string;
  slug: string;
  /** The most privileged role this person holds in the company. */
  role: CompanyRole;
  /** Every active role (company_members is unique per company, person, role). */
  roles: CompanyRole[];
  isVerified: boolean;
  kind: CompanyKind;
  /** A solo recruiter's agency. */
  isIndependent: boolean;
};

/** One company the user belongs to (same shape as the active context). */
export type Membership = CompanyContext;

/**
 * Every company the signed-in user is an active member of, one entry per
 * company. Cached per request: the layout, the page and server actions all
 * ask for it.
 */
export const getMemberships = cache(async (): Promise<Membership[]> => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return [];

  const { data } = await supabase
    .from('company_members')
    .select(
      'role, joined_at, companies!inner ( id, display_name, slug, is_verified, company_kind, is_independent_recruiter, deleted_at )'
    )
    .eq('person_id', user.id)
    .eq('is_active', true)
    .order('joined_at', { ascending: true });

  const byCompany = new Map<string, Membership>();
  for (const row of data ?? []) {
    const c = row.companies as unknown as {
      id: string;
      display_name: string;
      slug: string;
      is_verified: boolean;
      company_kind: string;
      is_independent_recruiter: boolean;
      deleted_at: string | null;
    } | null;
    if (!c || c.deleted_at) continue;
    const existing = byCompany.get(c.id);
    if (existing) {
      existing.roles.push(row.role);
      continue;
    }
    byCompany.set(c.id, {
      companyId: c.id,
      companyName: c.display_name,
      slug: c.slug,
      role: row.role,
      roles: [row.role],
      isVerified: c.is_verified,
      kind: c.company_kind === 'agency' ? 'agency' : 'employer',
      isIndependent: c.is_independent_recruiter,
    });
  }
  for (const m of byCompany.values()) {
    m.roles.sort((a, b) => ROLE_ORDER.indexOf(a) - ROLE_ORDER.indexOf(b));
    m.role = m.roles[0];
  }
  return [...byCompany.values()];
});

/**
 * Resolves the active company context.
 *
 * Every authorisation check evaluates against this, never against the person
 * globally (A4 §2.3). A person can belong to several companies (say, an
 * employer and an agency); the workspace cookie picks one, falling back to
 * the oldest membership. The cookie is only a preference: membership is
 * re-read from the database on every request and RLS decides access.
 * Returns null when the user belongs to no company yet (onboarding).
 */
export const getCompanyContext = cache(async (): Promise<CompanyContext | null> => {
  const memberships = await getMemberships();
  if (memberships.length === 0) return null;
  const wanted = (await cookies()).get(WORKSPACE_COOKIE)?.value;
  return memberships.find((m) => m.companyId === wanted) ?? memberships[0];
});
