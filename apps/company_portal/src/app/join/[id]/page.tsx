import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound, redirect } from 'next/navigation';
import { createClient, getMemberships, getUser } from '@/lib/supabase/server';
import { AGENCY_ROLE_HELP, EMPLOYER_ROLE_HELP, parseTeamInvitations, roleLabel } from '@/lib/agency';
import { UUID_RE } from '@/lib/talent';
import LocalTime from '../../dashboard/local-time';
import JoinButtons from './join-buttons';

export const metadata: Metadata = { title: 'Team invitation · Omelo' };

/**
 * An invitation to join a company's team (employer or agency). Joining needs
 * the invitee's own consent: nobody can be added to a team without it.
 */
export default async function JoinPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID_RE.test(id)) notFound();
  const user = await getUser();
  if (!user) redirect(`/sign-in?next=/join/${id}`);

  const supabase = await createClient();
  const [{ data, error }, memberships] = await Promise.all([
    supabase.rpc('omelo_my_team_invitations'),
    getMemberships(),
  ]);
  const invitation = parseTeamInvitations(data ?? null).find((i) => i.id === id) ?? null;
  const hasCompany = memberships.length > 0;
  const back = hasCompany ? '/dashboard' : '/onboarding';

  const help = invitation?.company.kind === 'agency' ? AGENCY_ROLE_HELP : EMPLOYER_ROLE_HELP;
  const roleHelp = invitation ? help.find((h) => h.role === invitation.role)?.does : null;

  return (
    <main className="min-h-screen max-w-xl mx-auto px-4 sm:px-6 py-10 sm:py-14">
      <Link href={back} className="text-xl font-black tracking-tight text-brand-600">
        Omelo
      </Link>

      {error ? (
        <div className="card p-5 mt-8" role="alert" style={{ borderColor: 'var(--color-danger)' }}>
          <p className="font-semibold" style={{ color: 'var(--color-danger)' }}>
            Could not load your invitations
          </p>
          <p className="text-sm muted mt-1">{error.message}</p>
        </div>
      ) : !invitation ? (
        <div className="card p-6 mt-8 space-y-2">
          <h1 className="text-xl font-bold">This invitation is not available</h1>
          <p className="text-sm muted leading-relaxed">
            It may have expired, been cancelled, already been used, or been sent to a different email address than
            the one you are signed in with ({user.email}). Ask the person who invited you to send a new one.
          </p>
          <Link href={back} className="btn btn-ghost mt-3">
            {hasCompany ? 'Go to the dashboard' : 'Continue'}
          </Link>
        </div>
      ) : (
        <div className="mt-8 space-y-6">
          <div>
            <p className="text-sm muted">
              {invitation.invitedBy ? `${invitation.invitedBy} invited you` : 'You have been invited'}
            </p>
            <h1 className="text-2xl sm:text-3xl font-bold mt-1 break-words">
              Join {invitation.company.name}
            </h1>
            <p className="text-sm mt-2 flex items-center gap-2 flex-wrap">
              <span className="pill">{invitation.company.kind === 'agency' ? 'Recruitment agency' : 'Employer'}</span>
              {invitation.company.verified ? (
                <span className="pill" style={{ color: 'var(--color-verified)', borderColor: 'var(--color-verified)' }}>
                  ✓ Verified by Omelo
                </span>
              ) : (
                <span className="pill" style={{ color: 'var(--color-warn)' }}>
                  Not verified yet
                </span>
              )}
            </p>
          </div>

          <dl className="card p-4 sm:p-5 grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
            <dt className="muted">Role</dt>
            <dd className="font-semibold">{roleLabel(invitation.role)}</dd>
            {roleHelp && (
              <>
                <dt className="muted">You can</dt>
                <dd>{roleHelp}</dd>
              </>
            )}
            <dt className="muted">Signed in as</dt>
            <dd className="break-all">{user.email}</dd>
            {invitation.expiresAt && (
              <>
                <dt className="muted">Expires</dt>
                <dd>
                  <LocalTime iso={invitation.expiresAt} />
                </dd>
              </>
            )}
          </dl>

          <p className="text-sm muted leading-relaxed">
            Accepting adds you to their team with this role. You keep any other company you belong to and can
            switch between them from the company menu. You can leave at any time by asking an owner or admin to
            remove you.
          </p>

          <JoinButtons invitationId={invitation.id} companyName={invitation.company.name} back={back} />
        </div>
      )}
    </main>
  );
}
