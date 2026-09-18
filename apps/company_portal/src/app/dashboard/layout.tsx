import Link from 'next/link';
import { redirect } from 'next/navigation';
import { createClient, getCompanyContext, getMemberships, getUser } from '@/lib/supabase/server';
import { parseTeamInvitations } from '@/lib/agency';
import { asTrustStatus, daysUntil } from '@/lib/account';
import { isPlatformAdmin } from '@/lib/admin';
import { reportError } from '@/lib/observability';
import NotificationBell from '@/components/notifications/bell';
import { signOut } from '../auth/actions';
import DashboardNav from './nav';
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
  const [trustRes, isAdmin, memberships, invitesRes] = await Promise.all([
    supabase.rpc('omelo_my_trust_status'),
    isPlatformAdmin(),
    getMemberships(),
    supabase.rpc('omelo_my_team_invitations'),
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

        <DashboardNav companyId={ctx.companyId} kind={ctx.kind} isAdmin={isAdmin} />
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

      <main className="flex-1 max-w-6xl w-full mx-auto px-4 sm:px-6 py-6 sm:py-8">
        {children}
      </main>
    </div>
  );
}
