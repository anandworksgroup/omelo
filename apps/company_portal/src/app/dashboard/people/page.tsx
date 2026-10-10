import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { ROLE_HELP, roleLabel } from '@/lib/agency';
import { loadTeam, memberName } from '@/lib/team';
import { timeAgo } from '@/lib/format';
import {
  GRANT_SCOPE_LABEL,
  SCOPE_MODE_LABEL,
  enterpriseError,
  grantSentence,
  type GrantScope,
  type ScopeMode,
} from '@/lib/enterprise';
import { ErrorNote, PageHeader, Section } from '../agency/ui';
import { GrantForm, RemoveGrant, ScopeModeToggle, type ScopeOptions } from './people-forms';

export const metadata: Metadata = { title: 'People & access · Omelo' };

/**
 * Release 8 — people and what they reach.
 *
 * A member with scope mode "organization" works the way Omelo worked before:
 * the whole organization. A scoped member reaches only the business units,
 * departments, locations or legal entities granted to them, and everything
 * downstream follows — jobs, candidates, interviews, offers. The database
 * decides; this page only says it in words.
 */
export default async function PeoplePage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const [team, grantsRes, membersRes, unitsRes, deptsRes, locsRes, entitiesRes] = await Promise.all([
    loadTeam(supabase, ctx.companyId, user?.id ?? null, user?.email ?? null),
    supabase
      .from('company_role_grants')
      .select('id, person_id, role, scope_type, scope_id, created_at')
      .eq('company_id', ctx.companyId)
      .order('created_at'),
    supabase.from('company_members').select('person_id, scope_mode').eq('company_id', ctx.companyId),
    supabase.from('business_units').select('id, name, is_active').eq('company_id', ctx.companyId).order('name'),
    supabase.from('departments').select('id, name').eq('company_id', ctx.companyId).order('name'),
    supabase.from('company_locations').select('id, name').eq('company_id', ctx.companyId).order('name'),
    supabase
      .from('company_legal_entities')
      .select('id, legal_name, country_code')
      .eq('company_id', ctx.companyId)
      .order('legal_name'),
  ]);

  const canManage = ctx.roles.some((r) => r === 'owner' || r === 'admin');
  const isOwner = ctx.roles.includes('owner');
  const help = ROLE_HELP;
  const assignable = help.map((h) => h.role).filter((r) => r !== 'owner' || isOwner);

  const options: ScopeOptions = {
    business_unit: (unitsRes.data ?? []).filter((u) => u.is_active).map((u) => ({ id: u.id, name: u.name })),
    department: (deptsRes.data ?? []).map((d) => ({ id: d.id, name: d.name })),
    location: (locsRes.data ?? []).map((l) => ({ id: l.id, name: l.name ?? 'Unnamed location' })),
    legal_entity: (entitiesRes.data ?? []).map((e) => ({
      id: e.id,
      name: `${e.legal_name} · ${e.country_code.trim()}`,
    })),
  };
  const scopeName = new Map<string, string>();
  for (const list of Object.values(options)) for (const o of list) scopeName.set(o.id, o.name);

  const scopeModeByPerson = new Map<string, ScopeMode>();
  for (const m of membersRes.data ?? [])
    scopeModeByPerson.set(m.person_id, m.scope_mode === 'scoped' ? 'scoped' : 'organization');

  type Grant = { id: string; person_id: string; role: string; scope_type: string; scope_id: string | null };
  const grantsByPerson = new Map<string, Grant[]>();
  for (const g of grantsRes.data ?? []) {
    const list = grantsByPerson.get(g.person_id);
    if (list) list.push(g);
    else grantsByPerson.set(g.person_id, [g]);
  }

  // One card per person, not per membership row: a person can hold several roles.
  const people = new Map<
    string,
    { personId: string; label: string; roles: string[]; joinedAt: string; title: string | null; isActive: boolean }
  >();
  for (const m of team.members) {
    const e = people.get(m.personId);
    if (e) {
      e.roles.push(m.role);
      e.isActive = e.isActive || m.isActive;
      continue;
    }
    people.set(m.personId, {
      personId: m.personId,
      label: memberName(m),
      roles: [m.role],
      joinedAt: m.joinedAt,
      title: m.title,
      isActive: m.isActive,
    });
  }
  const list = [...people.values()];

  return (
    <div className="space-y-6 max-w-4xl">
      <PageHeader
        title="People &amp; access"
        subtitle="Who is in this organization, what they do, and which part of it they reach."
        action={
          <>
            <Link href="/dashboard/team" className="btn btn-ghost">
              Invitations
            </Link>
            <Link href="/dashboard/organization" className="btn btn-ghost">
              Organization
            </Link>
          </>
        }
      />

      <div className="card p-4 sm:p-5 space-y-2">
        <h2 className="font-bold">How access works</h2>
        <p className="text-sm muted leading-relaxed">
          A role says <strong>what</strong> someone does. Scope says <strong>where</strong>. Someone set to “
          {SCOPE_MODE_LABEL.organization}” works everywhere, as before. Someone set to “{SCOPE_MODE_LABEL.scoped}”
          reaches only the business units, departments, locations or legal entities granted to them — and so do the
          jobs, candidates, interviews and offers inside those.
        </p>
        {!canManage && (
          <p className="text-sm muted">
            Only owners and admins change this. You can see your own access and everyone else&apos;s.
          </p>
        )}
      </div>

      <Section title="Members" aside={<span className="text-sm muted">{list.length}</span>}>
        {team.error ? (
          <ErrorNote label="the team" message={team.error} />
        ) : list.length === 0 ? (
          <p className="text-sm muted">Nobody here yet.</p>
        ) : (
          <ul className="space-y-3">
            {list.map((p) => {
              const mode = scopeModeByPerson.get(p.personId) ?? 'organization';
              const grants = grantsByPerson.get(p.personId) ?? [];
              return (
                <li key={p.personId} className={`card p-4 space-y-3 ${p.isActive ? '' : 'opacity-60'}`}>
                  <div className="flex flex-wrap items-start gap-3">
                    <div className="flex-1 min-w-[12rem]">
                      <p className="font-semibold break-words">{p.label}</p>
                      <p className="text-xs muted break-words">
                        {p.roles.map(roleLabel).join(', ')}
                        {p.title ? ` · ${p.title}` : ''} · joined {timeAgo(p.joinedAt)}
                        {p.isActive ? '' : ' · deactivated'}
                      </p>
                    </div>
                    <span
                      className="pill"
                      style={mode === 'scoped' ? { color: 'var(--color-warn)', borderColor: 'var(--color-warn)' } : undefined}
                    >
                      {SCOPE_MODE_LABEL[mode]}
                    </span>
                  </div>

                  {canManage ? (
                    <ScopeModeToggle personId={p.personId} mode={mode} />
                  ) : (
                    <p className="text-sm muted">
                      {mode === 'scoped'
                        ? 'They reach only what is listed below.'
                        : 'They work across the whole organization.'}
                    </p>
                  )}

                  <div className="border-t hairline pt-3 space-y-2">
                    <p className="label !mb-0">Granted access</p>
                    {grants.length === 0 ? (
                      <p className="text-sm muted">
                        {mode === 'scoped'
                          ? 'Nothing granted yet — they cannot reach any part of the organization.'
                          : 'Nothing granted. Their role already covers the whole organization.'}
                      </p>
                    ) : (
                      <ul className="space-y-1.5">
                        {grants.map((g) => (
                          <li key={g.id} className="flex flex-wrap items-center gap-2 text-sm">
                            <span className="break-words flex-1 min-w-[12rem]">
                              {grantSentence(
                                g.role,
                                g.scope_type,
                                g.scope_id ? (scopeName.get(g.scope_id) ?? null) : null
                              )}
                            </span>
                            <span className="pill">
                              {GRANT_SCOPE_LABEL[g.scope_type as GrantScope] ?? g.scope_type}
                            </span>
                            {canManage && <RemoveGrant id={g.id} />}
                          </li>
                        ))}
                      </ul>
                    )}
                    {canManage && p.isActive && (
                      <GrantForm personId={p.personId} roles={assignable} options={options} />
                    )}
                  </div>
                </li>
              );
            })}
          </ul>
        )}
        {grantsRes.error && <ErrorNote label="granted access" message={enterpriseError(grantsRes.error).text} />}
        {membersRes.error && <ErrorNote label="scope settings" message={enterpriseError(membersRes.error).text} />}
      </Section>

      <Section title="What each role can do">
        <div className="overflow-x-auto -mx-4 px-4 sm:mx-0 sm:px-0">
          <table className="w-full text-sm table-fixed min-w-[28rem]">
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
          A grant never widens what a role can do — it only says where that role applies. The database enforces every
          rule on this page.
        </p>
      </Section>
    </div>
  );
}
