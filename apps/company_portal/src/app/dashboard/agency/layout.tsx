import { redirect } from 'next/navigation';
import { createClient, getCompanyContext } from '@/lib/supabase/server';

/**
 * The client-recruitment section.
 *
 * It used to be a separate dashboard for a separate kind of company. It is now
 * a section of the one workspace, and what decides whether you see it is
 * whether this organization has turned client recruitment on — not what sort
 * of business it is.
 *
 * Convenience routing only: every read below goes through RLS and
 * organization-scoped RPCs, which refuse a non-member whatever this says.
 */
export default async function ClientRecruitmentLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const ctx = await getCompanyContext();
  if (!ctx) redirect('/onboarding');

  const supabase = await createClient();
  const [{ data: cap }, { count: clients }] = await Promise.all([
    supabase
      .from('company_capabilities')
      .select('is_enabled')
      .eq('company_id', ctx.companyId)
      .eq('capability', 'client_recruitment')
      .maybeSingle(),
    supabase
      .from('agency_clients')
      .select('id', { count: 'exact', head: true })
      .eq('agency_id', ctx.companyId),
  ]);

  // R10-084: an explicit choice or nothing. Work that already exists stays
  // reachable either way, so turning the module off never hides real records.
  const on = cap?.is_enabled ?? false;
  if (!on && (clients ?? 0) === 0) redirect('/dashboard/company');

  return children;
}
