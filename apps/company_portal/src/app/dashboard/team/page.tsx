import type { Metadata } from 'next';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { AGENCY_ROLE_HELP, EMPLOYER_ROLE_HELP, roleLabel } from '@/lib/agency';
import { loadTeam, memberName } from '@/lib/team';
import { timeAgo } from '@/lib/format';
import LocalTime from '../local-time';
import { CancelInvitation, InviteForm, MemberControls } from './team-forms';

export const metadata: Metadata = { title: 'Team · Omelo' };

export default async function TeamPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const isAgency = ctx.kind === 'agency';
  const canManage = ctx.roles.some((r) => r === 'owner' || r === 'admin');
  const isOwner = ctx.roles.includes('owner');

  const team = await loadTeam(supabase, ctx.companyId, user?.id ?? null, user?.email ?? null);
  const help = isAgency ? AGENCY_ROLE_HELP : EMPLOYER_ROLE_HELP;
  // Only owners may grant the owner role; sourcer/coordinator exist only in agencies.
  const assignable = help.map((h) => h.role).filter((r) => r !== 'owner' || isOwner);
  const active = team.members.filter((m) => m.isActive);
  const inactive = team.members.filter((m) => !m.isActive);

  return (
    <div className="space-y-8 max-w-4xl">
      <div>
        <h1 className="text-xl sm:text-2xl font-bold">Team</h1>
        <p className="text-sm muted mt-1">
          People who work in {ctx.companyName}. Nobody joins without accepting an invitation sent to their own
          email address.
        </p>
      </div>

      {canManage ? (
        <section className="space-y-2">
          <h2 className="font-bold">Invite someone</h2>
          <InviteForm roles={assignable} defaultRole="recruiter" />
        </section>
      ) : (
        <p className="card p-4 text-sm muted">Only owners and admins can invite people or change roles.</p>
      )}

      <section className="space-y-3">
        <h2 className="font-bold">
          Members <span className="muted font-normal">· {active.length}</span>
        </h2>
        {team.error ? (
          <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
            Could not load the team: <span className="muted">{team.error}</span>
          </p>
        ) : (
          <ul className="card divide-y" style={{ borderColor: 'var(--line)' }}>
            {[...active, ...inactive].map((m) => (
              <li
                key={m.memberId}
                className={`p-4 flex flex-wrap items-center gap-3 ${m.isActive ? '' : 'opacity-60'}`}
              >
                <div className="flex-1 min-w-[12rem]">
                  <p className="font-semibold text-sm break-words">{memberName(m)}</p>
                  <p className="text-xs muted break-words">
                    {roleLabel(m.role)}
                    {m.title ? ` · ${m.title}` : ''} · joined {timeAgo(m.joinedAt)}
                    {m.isActive ? '' : ' · deactivated'}
                  </p>
                </div>
                {canManage && (m.role !== 'owner' || isOwner) ? (
                  <MemberControls
                    memberId={m.memberId}
                    role={m.role}
                    isActive={m.isActive}
                    roles={assignable}
                    isYou={m.isYou}
                  />
                ) : (
                  <span className="pill">{roleLabel(m.role)}</span>
                )}
              </li>
            ))}
          </ul>
        )}
        {!team.invitesReadable && <p className="hint">Teammates&apos; names are shown to owners and admins.</p>}
      </section>

      {canManage && (
        <section className="space-y-3">
          <h2 className="font-bold">
            Pending invitations <span className="muted font-normal">· {team.pending.length}</span>
          </h2>
          {team.pending.length === 0 ? (
            <p className="text-sm muted">No invitations waiting.</p>
          ) : (
            <ul className="card divide-y" style={{ borderColor: 'var(--line)' }}>
              {team.pending.map((i) => (
                <li key={i.id} className="p-4 flex flex-wrap items-center gap-3">
                  <div className="flex-1 min-w-[12rem]">
                    <p className="font-semibold text-sm break-all">{i.email}</p>
                    <p className="text-xs muted">
                      {roleLabel(i.role)} · sent {timeAgo(i.createdAt)} · expires{' '}
                      <LocalTime iso={i.expiresAt} withTime={false} />
                    </p>
                  </div>
                  <CancelInvitation id={i.id} />
                </li>
              ))}
            </ul>
          )}
        </section>
      )}

      <section className="space-y-3">
        <h2 className="font-bold">What each role can do</h2>
        <div className="card overflow-hidden">
          <table className="w-full text-sm table-fixed">
            <thead>
              <tr className="text-left surface">
                <th className="p-3 font-semibold w-28 sm:w-40">Role</th>
                <th className="p-3 font-semibold">Can</th>
              </tr>
            </thead>
            <tbody className="divide-y" style={{ borderColor: 'var(--line)' }}>
              {help.map((h) => (
                <tr key={h.role} className="align-top">
                  <td className="p-3 font-semibold break-words">{roleLabel(h.role)}</td>
                  <td className="p-3 break-words">{h.does}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="hint">
          Only an owner can invite another owner or change an owner&apos;s role.
          {isAgency ? '' : ' Sourcer and coordinator are agency-only roles.'} The database enforces every rule;
          this table only explains them.
        </p>
      </section>
    </div>
  );
}
