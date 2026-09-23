import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { loadTeam, peopleOf } from '@/lib/team';
import {
  ORGANIZATION_TYPE_HELP,
  ORGANIZATION_TYPE_LABEL,
  TEAM_PURPOSE_LABEL,
  asOrganizationType,
  enterpriseError,
  unitTree,
  type BusinessUnit,
  type TeamPurpose,
} from '@/lib/enterprise';
import { ErrorNote, PageHeader, Section } from '../agency/ui';
import {
  AddTeamMember,
  DeleteDepartment,
  DeleteLocation,
  DepartmentForm,
  LocationForm,
  OrgTypeForm,
  RemoveTeamMember,
  TeamActive,
  TeamForm,
  UnitActive,
  UnitForm,
} from './org-forms';

export const metadata: Metadata = { title: 'Organization · Omelo' };

/**
 * Release 8 — the shape of the organization: what kind it is, its business
 * units, departments, locations and teams.
 *
 * Every member can read this. Who may change what is the database's decision
 * (business units: owner and admin; departments and locations: owner, admin,
 * recruiter; teams: owner, admin, HR) — the page only hides the controls that
 * would be refused, and says so.
 */
export default async function OrganizationPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const [companyRes, unitsRes, deptsRes, locsRes, teamsRes, teamMembersRes, team] = await Promise.all([
    supabase.from('companies').select('organization_type, company_kind').eq('id', ctx.companyId).maybeSingle(),
    supabase
      .from('business_units')
      .select('id, parent_id, name, code, is_active')
      .eq('company_id', ctx.companyId)
      .order('name'),
    supabase.from('departments').select('id, name, business_unit_id').eq('company_id', ctx.companyId).order('name'),
    supabase
      .from('company_locations')
      .select('id, name, address, is_hq')
      .eq('company_id', ctx.companyId)
      .order('is_hq', { ascending: false })
      .order('name'),
    supabase
      .from('teams')
      .select('id, name, purpose, business_unit_id, department_id, lead_person_id, is_active')
      .eq('company_id', ctx.companyId)
      .order('name'),
    supabase.from('team_members').select('team_id, person_id'),
    loadTeam(supabase, ctx.companyId, user?.id ?? null, user?.email ?? null),
  ]);

  const orgType = asOrganizationType(companyRes.data?.organization_type);
  const isOwnerAdmin = ctx.roles.some((r) => r === 'owner' || r === 'admin');
  const canEditUnits = isOwnerAdmin;
  const canEditDepts = ctx.roles.some((r) => r === 'owner' || r === 'admin' || r === 'recruiter');
  const canEditTeams = ctx.roles.some((r) => r === 'owner' || r === 'admin' || r === 'hr');

  const units: BusinessUnit[] = (unitsRes.data ?? []).map((u) => ({
    id: u.id,
    parentId: u.parent_id,
    name: u.name,
    code: u.code,
    isActive: u.is_active,
  }));
  const tree = unitTree(units);
  const unitOptions = units.filter((u) => u.isActive).map((u) => ({ id: u.id, name: u.name }));
  const unitName = new Map(units.map((u) => [u.id, u.name]));

  const departments = deptsRes.data ?? [];
  const deptOptions = departments.map((d) => ({ id: d.id, name: d.name }));
  const locations = locsRes.data ?? [];
  const teams = teamsRes.data ?? [];

  const people = peopleOf(team.members);
  const personLabel = new Map(people.map((p) => [p.personId, p.label]));
  const membersByTeam = new Map<string, string[]>();
  for (const tm of teamMembersRes.data ?? []) {
    const list = membersByTeam.get(tm.team_id);
    if (list) list.push(tm.person_id);
    else membersByTeam.set(tm.team_id, [tm.person_id]);
  }

  return (
    <div className="space-y-6 max-w-4xl">
      <PageHeader
        title="Organization"
        subtitle="The shape of your organization: what kind it is, the units and departments inside it, where it works, and the teams that do the work."
        action={
          <Link href="/dashboard/people" className="btn btn-ghost">
            People &amp; access
          </Link>
        }
      />

      {!isOwnerAdmin && (
        <p className="card p-4 text-sm muted">
          You can read the whole structure. Owners and admins change business units and the organization type;
          recruiters can also change departments and locations; HR can change teams.
        </p>
      )}

      {/* What kind of organization ------------------------------------ */}
      <Section
        title="What kind of organization this is"
        aside={<span className="pill">{ORGANIZATION_TYPE_LABEL[orgType]}</span>}
      >
        {companyRes.error ? (
          <ErrorNote label="the organization type" message={enterpriseError(companyRes.error).text} />
        ) : isOwnerAdmin ? (
          <OrgTypeForm current={orgType} />
        ) : (
          <p className="text-sm muted leading-relaxed">{ORGANIZATION_TYPE_HELP[orgType]}</p>
        )}
      </Section>

      {/* Business units ---------------------------------------------- */}
      <Section
        title="Business units"
        aside={<span className="text-sm muted">{units.filter((u) => u.isActive).length} active</span>}
      >
        <p className="text-sm muted leading-relaxed">
          Divisions, brands or regions. A unit can sit inside another one, and a role granted on a unit also reaches
          everything below it.
        </p>
        {unitsRes.error ? (
          <ErrorNote label="business units" message={enterpriseError(unitsRes.error).text} />
        ) : tree.length === 0 ? (
          <p className="text-sm muted">No business units yet. Departments work without them.</p>
        ) : (
          <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
            {tree.map((u) => (
              <li
                key={u.id}
                className={`py-3 flex flex-wrap items-start gap-3 ${u.isActive ? '' : 'opacity-60'}`}
                style={{ paddingLeft: `${u.depth * 1.25}rem` }}
              >
                <div className="flex-1 min-w-[10rem]">
                  <p className="font-semibold text-sm break-words">
                    {u.depth > 0 && <span aria-hidden className="muted">↳ </span>}
                    {u.name}
                    {u.code ? <span className="muted font-normal"> · {u.code}</span> : null}
                  </p>
                  <p className="text-xs muted">
                    {departments.filter((d) => d.business_unit_id === u.id).length} departments
                    {u.isActive ? '' : ' · archived'}
                  </p>
                </div>
                {canEditUnits && (
                  <div className="flex flex-wrap gap-2 items-start">
                    <UnitForm
                      unit={{ id: u.id, name: u.name, code: u.code, parentId: u.parentId }}
                      units={unitOptions}
                      label="Edit"
                    />
                    <UnitActive id={u.id} isActive={u.isActive} />
                  </div>
                )}
              </li>
            ))}
          </ul>
        )}
        {canEditUnits && (
          <div className="pt-1">
            <UnitForm units={unitOptions} label="Add a business unit" />
          </div>
        )}
      </Section>

      {/* Departments -------------------------------------------------- */}
      <Section title="Departments" aside={<span className="text-sm muted">{departments.length}</span>}>
        <p className="text-sm muted leading-relaxed">
          Jobs and people belong to a department. Put each one in a business unit so scoped roles line up with the
          structure.
        </p>
        {deptsRes.error ? (
          <ErrorNote label="departments" message={enterpriseError(deptsRes.error).text} />
        ) : departments.length === 0 ? (
          <p className="text-sm muted">No departments yet.</p>
        ) : (
          <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
            {departments.map((d) => (
              <li key={d.id} className="py-3 flex flex-wrap items-start gap-3">
                <div className="flex-1 min-w-[10rem]">
                  <p className="font-semibold text-sm break-words">{d.name}</p>
                  <p className="text-xs muted break-words">
                    {d.business_unit_id ? (unitName.get(d.business_unit_id) ?? 'A business unit') : 'Not in a business unit'}
                  </p>
                </div>
                {canEditDepts && (
                  <div className="flex flex-wrap gap-2 items-start">
                    <DepartmentForm
                      department={{ id: d.id, name: d.name, businessUnitId: d.business_unit_id }}
                      units={unitOptions}
                      label="Edit"
                    />
                    <DeleteDepartment id={d.id} name={d.name} />
                  </div>
                )}
              </li>
            ))}
          </ul>
        )}
        {canEditDepts && (
          <div className="pt-1">
            <DepartmentForm units={unitOptions} label="Add a department" />
          </div>
        )}
      </Section>

      {/* Locations ---------------------------------------------------- */}
      <Section title="Locations" aside={<span className="text-sm muted">{locations.length}</span>}>
        <p className="text-sm muted leading-relaxed">
          The places you work from. A role can be granted for one location only, and jobs attached to it inherit its
          position on the map.
        </p>
        {locsRes.error ? (
          <ErrorNote label="locations" message={enterpriseError(locsRes.error).text} />
        ) : locations.length === 0 ? (
          <p className="text-sm muted">No locations yet.</p>
        ) : (
          <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
            {locations.map((l) => (
              <li key={l.id} className="py-3 flex flex-wrap items-start gap-3">
                <div className="flex-1 min-w-[10rem]">
                  <p className="font-semibold text-sm break-words">{l.name ?? 'Unnamed location'}</p>
                  <p className="text-xs muted break-words">{l.address ?? 'No address'}</p>
                </div>
                {l.is_hq && <span className="pill">Head office</span>}
                {canEditDepts && (
                  <div className="flex flex-wrap gap-2 items-start">
                    <LocationForm location={{ id: l.id, name: l.name, address: l.address }} label="Edit" />
                    {!l.is_hq && <DeleteLocation id={l.id} name={l.name ?? 'this location'} />}
                  </div>
                )}
              </li>
            ))}
          </ul>
        )}
        {canEditDepts && (
          <div className="pt-1">
            <LocationForm label="Add a location" />
          </div>
        )}
      </Section>

      {/* Teams -------------------------------------------------------- */}
      <Section title="Teams" aside={<span className="text-sm muted">{teams.filter((t) => t.is_active).length} active</span>}>
        <p className="text-sm muted leading-relaxed">
          Groups of people who work together. A team does not grant access on its own — that is what roles and their
          scope do on <Link href="/dashboard/people" className="underline">People &amp; access</Link>.
        </p>
        {teamsRes.error ? (
          <ErrorNote label="teams" message={enterpriseError(teamsRes.error).text} />
        ) : teams.length === 0 ? (
          <p className="text-sm muted">No teams yet.</p>
        ) : (
          <ul className="space-y-3">
            {teams.map((t) => {
              const memberIds = membersByTeam.get(t.id) ?? [];
              const available = people.filter((p) => !memberIds.includes(p.personId));
              return (
                <li key={t.id} className={`card p-4 space-y-3 ${t.is_active ? '' : 'opacity-60'}`}>
                  <div className="flex flex-wrap items-start gap-3">
                    <div className="flex-1 min-w-[10rem]">
                      <p className="font-semibold break-words">{t.name}</p>
                      <p className="text-xs muted break-words">
                        {TEAM_PURPOSE_LABEL[(t.purpose ?? 'general') as TeamPurpose] ?? t.purpose}
                        {t.business_unit_id ? ` · ${unitName.get(t.business_unit_id) ?? 'business unit'}` : ''}
                        {t.department_id
                          ? ` · ${departments.find((d) => d.id === t.department_id)?.name ?? 'department'}`
                          : ''}
                        {t.lead_person_id ? ` · led by ${personLabel.get(t.lead_person_id) ?? 'a teammate'}` : ''}
                        {t.is_active ? '' : ' · archived'}
                      </p>
                    </div>
                    {canEditTeams && (
                      <div className="flex flex-wrap gap-2 items-start">
                        <TeamForm
                          team={{
                            id: t.id,
                            name: t.name,
                            purpose: t.purpose,
                            businessUnitId: t.business_unit_id,
                            departmentId: t.department_id,
                            leadPersonId: t.lead_person_id,
                          }}
                          units={unitOptions}
                          departments={deptOptions}
                          people={people}
                          label="Edit"
                        />
                        <TeamActive id={t.id} isActive={t.is_active} />
                      </div>
                    )}
                  </div>

                  <div className="border-t hairline pt-3 space-y-2">
                    {memberIds.length === 0 ? (
                      <p className="text-sm muted">Nobody on this team yet.</p>
                    ) : (
                      <ul className="flex flex-wrap gap-2">
                        {memberIds.map((pid) => (
                          <li key={pid} className="flex items-center gap-1.5">
                            <span className="pill">{personLabel.get(pid) ?? 'Teammate'}</span>
                            {canEditTeams && <RemoveTeamMember teamId={t.id} personId={pid} />}
                          </li>
                        ))}
                      </ul>
                    )}
                    {canEditTeams && <AddTeamMember teamId={t.id} people={available} />}
                  </div>
                </li>
              );
            })}
          </ul>
        )}
        {teamMembersRes.error && (
          <ErrorNote label="team members" message={enterpriseError(teamMembersRes.error).text} />
        )}
        {canEditTeams && (
          <div className="pt-1">
            <TeamForm units={unitOptions} departments={deptOptions} people={people} label="Add a team" />
          </div>
        )}
      </Section>
    </div>
  );
}
