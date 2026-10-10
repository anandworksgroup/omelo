import Link from 'next/link';
import { redirect } from 'next/navigation';
import { createClient, getCompanyContext, getMemberships, getUser } from '@/lib/supabase/server';
import { parseTeamInvitations } from '@/lib/agency';
import { asTrustStatus, daysUntil } from '@/lib/account';
import { isPlatformAdmin } from '@/lib/admin';
import { reportError } from '@/lib/observability';
import NotificationBell from '@/components/notifications/bell';
import { signOut } from '../auth/actions';
import DashboardNav, { type Capabilities } from './nav';
import WorkspaceSwitcher from './workspace-switcher';
import LocalTime from './local-time';
import { cancelAccountDeletionForm } from './settings/actions';

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const user = await getUser();
  if (!user) redirect('/sign-in');

  const ctx = await getCompanyContext();
  if (!ctx) redirect('/onboarding');

  const supabase = await createClient();
  const [trustRes, isAdmin, memberships, invitesRes, capsRes, orgRes, rpoRes, clientRes, workforceRes] =
    await Promise.all([
      supabase.rpc('omelo_my_trust_status'),
      isPlatformAdmin(),
      getMemberships(),
      supabase.rpc('omelo_my_team_invitations'),
      // R10: what this organization has turned on. One menu for everyone; the
      // optional sections appear when they are switched on or already in use.
      supabase
        .from('company_capabilities')
        .select('capability, is_enabled')
        .eq('company_id', ctx.companyId),
      // The business type is still what supplies the defaults.
      supabase.from('companies').select('organization_type').eq('id', ctx.companyId).maybeSingle(),
      // RLS shows only engagements this workspace is one side of.
      supabase.from('rpo_engagements').select('id', { count: 'exact', head: true }),
      supabase.from('agency_clients').select('id', { count: 'exact', head: true }).eq('agency_id', ctx.companyId),
      supabase
        .from('workforce_requirements')
        .select('id', { count: 'exact', head: true })
        .eq('company_id', ctx.companyId),
    ]);
  if (trustRes.error) reportError(trustRes.error, { action: 'dashboardLayout.trustStatus' });
  if (invitesRes.error) reportError(invitesRes.error, { action: 'dashboardLayout.teamInvitations' });
  const invitations = parseTeamInvitations(invitesRes.data ?? null);
  const workspaces = memberships.map((m) => ({
    companyId: m.companyId,
    companyName: m.companyName,
    kind: m.kind,
    isIndependent: m.isIndependent,
    isVerified: m.isVerified,
    role: m.role,
  }));
  // A capability row is an explicit choice. Without one the business type
  // supplies the default, exactly as omelo_has_capability does in the database,
  // and anything already in use stays visible whatever the switch says.
  const orgType = orgRes.data?.organization_type ?? 'employer';
  const agencyLike = ['recruitment_agency', 'staffing_agency', 'rpo_provider', 'workforce_provider'];
  const byType: Capabilities = {
    client_recruitment: agencyLike.includes(orgType),
    workforce: ['staffing_agency', 'workforce_provider'].includes(orgType),
    rpo: orgType === 'rpo_provider',
    billing: orgType !== 'employer',
  };
  const capabilities: Capabilities = { ...byType };
  for (const row of capsRes.data ?? []) {
    capabilities[row.capability as keyof Capabilities] = row.is_enabled;
  }
  if ((clientRes.count ?? 0) > 0) capabilities.client_recruitment = true;
  if ((workforceRes.count ?? 0) > 0) capabilities.workforce = true;
  if ((rpoRes.count ?? 0) > 0) capabilities.rpo = true;
  const deletionAt = asTrustStatus(trustRes.data)?.deletion_scheduled_for ?? null;
  const deletionDays = deletionAt ? daysUntil(deletionAt) : 0;
  const initial = (user.email ?? '?').trim().charAt(0).toUpperCase();

  return (
    <div className="min-h-screen flex flex-col">
      <header className="border-b hairline">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 min-h-14 py-2 flex items-center gap-3 sm:gap-6 flex-wrap">
          <Link href="/dashboard" className="font-black tracking-tight text-brand-600 shrink-0">
            Omelo
          </Link>

          <WorkspaceSwitcher
            current={workspaces.find((w) => w.companyId === ctx.companyId) ?? workspaces[0]}
            options={workspaces}
          />

          <div className="ml-auto flex items-center gap-2 sm:gap-3">
            <NotificationBell personId={user.id} />
            <Link
              href="/dashboard/settings"
              className="flex items-center gap-2 rounded-full hover:opacity-80"
              aria-label="Account settings"
              title="Account settings"
            >
              <span
                aria-hidden
                className="w-8 h-8 rounded-full grid place-items-center text-sm font-bold"
                style={{ background: 'var(--color-brand-100)', color: 'var(--color-brand-700)' }}
              >
                {initial}
              </span>
              <span className="text-sm muted hidden lg:inline">{user.email}</span>
            </Link>
            <form action={signOut}>
              <button className="text-sm underline muted">Sign out</button>
            </form>
          </div>
        </div>

      </header>

      {invitations.length > 0 && (
        <div role="status" style={{ background: 'var(--color-brand-50)', color: 'var(--color-brand-900)' }}>
          <div className="max-w-6xl mx-auto px-4 sm:px-6 py-2.5 flex items-center gap-3 flex-wrap text-sm">
            <p className="flex-1 min-w-0 break-words">
              <strong>{invitations[0].company.name}</strong> invited you to join as{' '}
              {invitations[0].role.replace(/_/g, ' ')}
              {invitations.length > 1 ? ` (and ${invitations.length - 1} more invitation${invitations.length > 2 ? 's' : ''})` : ''}.
            </p>
            <Link href={`/join/${invitations[0].id}`} className="btn btn-primary" style={{ height: 36 }}>
              Review invitation
            </Link>
          </div>
        </div>
      )}

      {deletionAt && (
        <div role="status" style={{ background: 'color-mix(in srgb, var(--color-danger) 10%, var(--bg))' }}>
          <div className="max-w-6xl mx-auto px-4 sm:px-6 py-2.5 flex items-center gap-3 flex-wrap text-sm">
            <p className="flex-1 min-w-0">
              <strong style={{ color: 'var(--color-danger)' }}>Your account will be deleted</strong> on{' '}
              <LocalTime iso={deletionAt} withTime={false} />
              {deletionDays > 0 ? ` (in ${deletionDays} ${deletionDays === 1 ? 'day' : 'days'})` : ''}. Changed
              your mind?
            </p>
            <form action={cancelAccountDeletionForm}>
              <button className="btn btn-primary" style={{ height: 36 }}>
                Cancel deletion
              </button>
            </form>
          </div>
        </div>
      )}

      <div className="flex-1 w-full max-w-[84rem] mx-auto lg:flex lg:gap-8 lg:px-6">
        <DashboardNav
          companyId={ctx.companyId}
          isAdmin={isAdmin}
          capabilities={capabilities}
        />

        {/* min-w-0 so a wide table or a long job title scrolls inside the
            column instead of stretching the whole page sideways. */}
        <main className="flex-1 min-w-0 px-4 sm:px-6 lg:px-0 py-6 sm:py-8">
          {children}
        </main>
      </div>
    </div>
  );
}
