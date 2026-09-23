-- OMELO 68 — Release 8: Enterprise organizations — structure and scoped roles.
--
-- One organization model, different capabilities. `companies` stays the organization; R8 adds what
-- it is (organization_type) and the structure inside it. `company_kind` keeps its existing meaning
-- ('employer' or 'agency') because R4/R5 authority rules read it — a trigger keeps the two in step.
--
--   Organization (companies)
--   ├── Legal entities      company_legal_entities  (R6)
--   ├── Business units      business_units          (new, nestable)
--   ├── Departments         departments             (+ business_unit_id)
--   ├── Locations           company_locations       (R1)
--   ├── Teams               teams / team_members    (new)
--   └── Members             company_members         (+ scope_mode) and company_role_grants (new)
--
-- Roles answer WHO / WHAT / WHERE:
--   * a member with scope_mode 'organization' works the way they always did (whole organization)
--   * a member with scope_mode 'scoped' acts only inside the business units, departments, locations
--     or legal entities granted to them in company_role_grants (R8-002)
--
-- Nothing is duplicated: no second company row for a business unit, and no new job or application
-- tables. Only the two authority helpers change, so every existing policy inherits the scope rules.
--
-- Rollback: drop the new tables and columns, restore omelo_can_access_job from 08/11 and the
-- jobs_company_write policy from 08_rls_policies.

-- 1. What kind of organization ------------------------------------------------------------------
alter table companies
  add column if not exists organization_type text not null default 'employer'
    check (organization_type in ('employer','staffing_agency','recruitment_agency','rpo_provider','workforce_provider'));
update companies set organization_type = 'staffing_agency' where company_kind = 'agency' and organization_type = 'employer';

create or replace function omelo_private.omelo_sync_organization_type()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  -- company_kind is the capability switch the rest of Omelo already reads.
  if tg_op = 'UPDATE' and new.organization_type is distinct from old.organization_type then
    new.company_kind := case when new.organization_type = 'employer' then 'employer' else 'agency' end;
  elsif tg_op = 'UPDATE' and new.company_kind is distinct from old.company_kind then
    new.organization_type := case when new.company_kind = 'employer' then 'employer'
                                  when new.organization_type = 'employer' then 'staffing_agency'
                                  else new.organization_type end;
  elsif tg_op = 'INSERT' then
    new.company_kind := case when new.organization_type = 'employer' then coalesce(new.company_kind, 'employer')
                             else 'agency' end;
    if new.company_kind = 'agency' and new.organization_type = 'employer' then
      new.organization_type := 'staffing_agency';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists companies_sync_organization_type on companies;
create trigger companies_sync_organization_type before insert or update on companies
  for each row execute function omelo_private.omelo_sync_organization_type();

-- 2. Business units, teams ------------------------------------------------------------------------
create table if not exists public.business_units (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  parent_id   uuid references business_units(id) on delete cascade,
  name        text not null check (length(trim(name)) between 2 and 120),
  code        text check (code is null or length(code) <= 40),
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  unique (company_id, name)
);
create index if not exists business_units_company on business_units (company_id);
alter table departments add column if not exists business_unit_id uuid references business_units(id) on delete set null;
create index if not exists departments_business_unit on departments (business_unit_id);

create table if not exists public.teams (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references companies(id) on delete cascade,
  business_unit_id uuid references business_units(id) on delete set null,
  department_id    uuid references departments(id) on delete set null,
  name             text not null check (length(trim(name)) between 2 and 120),
  purpose          text check (purpose is null or purpose in ('hiring','workforce','rpo','general')),
  lead_person_id   uuid references persons(id) on delete set null,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now(),
  unique (company_id, name)
);
create table if not exists public.team_members (
  team_id    uuid not null references teams(id) on delete cascade,
  person_id  uuid not null references persons(id) on delete cascade,
  added_at   timestamptz not null default now(),
  primary key (team_id, person_id)
);
create index if not exists team_members_person on team_members (person_id);

-- 3. Scoped roles -----------------------------------------------------------------------------------
alter table company_members
  add column if not exists scope_mode text not null default 'organization'
    check (scope_mode in ('organization','scoped'));

create table if not exists public.company_role_grants (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  person_id   uuid not null references persons(id) on delete cascade,
  role        company_role not null,
  scope_type  text not null check (scope_type in ('organization','business_unit','department','location','legal_entity')),
  scope_id    uuid,
  granted_by  uuid references persons(id) on delete set null,
  created_at  timestamptz not null default now(),
  check ((scope_type = 'organization') = (scope_id is null))
);
create unique index if not exists company_role_grants_unique
  on company_role_grants (company_id, person_id, role, scope_type, coalesce(scope_id, '00000000-0000-0000-0000-000000000000'::uuid));
create index if not exists company_role_grants_person on company_role_grants (person_id, company_id);

create or replace function omelo_private.omelo_validate_role_grant()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if not exists (select 1 from company_members m
                  where m.company_id = new.company_id and m.person_id = new.person_id and m.is_active) then
    raise exception 'Add the person to the team before granting a scoped role' using errcode = '22023';
  end if;
  if new.scope_type = 'business_unit' and not exists (select 1 from business_units b where b.id = new.scope_id and b.company_id = new.company_id)
  or new.scope_type = 'department' and not exists (select 1 from departments d where d.id = new.scope_id and d.company_id = new.company_id)
  or new.scope_type = 'location' and not exists (select 1 from company_locations l where l.id = new.scope_id and l.company_id = new.company_id)
  or new.scope_type = 'legal_entity' and not exists (select 1 from company_legal_entities e where e.id = new.scope_id and e.company_id = new.company_id) then
    raise exception 'That scope belongs to another organization' using errcode = '42501';
  end if;
  return new;
end;
$$;
drop trigger if exists company_role_grants_validate on company_role_grants;
create trigger company_role_grants_validate before insert or update on company_role_grants
  for each row execute function omelo_private.omelo_validate_role_grant();

-- 4. Reading the structure --------------------------------------------------------------------------
alter table business_units enable row level security;
alter table teams enable row level security;
alter table team_members enable row level security;
alter table company_role_grants enable row level security;

drop policy if exists business_units_read on business_units;
drop policy if exists business_units_write on business_units;
create policy business_units_read on business_units for select to authenticated
  using (omelo_private.omelo_is_company_member(company_id));
create policy business_units_write on business_units for all to authenticated
  using (omelo_private.omelo_has_company_role(company_id, array['owner','admin']::company_role[]))
  with check (omelo_private.omelo_has_company_role(company_id, array['owner','admin']::company_role[]));

drop policy if exists teams_read on teams;
drop policy if exists teams_write on teams;
create policy teams_read on teams for select to authenticated
  using (omelo_private.omelo_is_company_member(company_id));
create policy teams_write on teams for all to authenticated
  using (omelo_private.omelo_has_company_role(company_id, array['owner','admin','hr']::company_role[]))
  with check (omelo_private.omelo_has_company_role(company_id, array['owner','admin','hr']::company_role[]));

drop policy if exists team_members_read on team_members;
drop policy if exists team_members_write on team_members;
create policy team_members_read on team_members for select to authenticated
  using (exists (select 1 from teams t where t.id = team_id and omelo_private.omelo_is_company_member(t.company_id)));
create policy team_members_write on team_members for all to authenticated
  using (exists (select 1 from teams t where t.id = team_id
                  and omelo_private.omelo_has_company_role(t.company_id, array['owner','admin','hr']::company_role[])))
  with check (exists (select 1 from teams t where t.id = team_id
                  and omelo_private.omelo_has_company_role(t.company_id, array['owner','admin','hr']::company_role[])));

-- A member sees their own grants; owners, admins and HR see the organization's grants.
drop policy if exists company_role_grants_read on company_role_grants;
drop policy if exists company_role_grants_write on company_role_grants;
create policy company_role_grants_read on company_role_grants for select to authenticated
  using (person_id = (select auth.uid())
         or omelo_private.omelo_has_company_role(company_id, array['owner','admin','hr']::company_role[]));
create policy company_role_grants_write on company_role_grants for all to authenticated
  using (omelo_private.omelo_has_company_role(company_id, array['owner','admin']::company_role[]))
  with check (omelo_private.omelo_has_company_role(company_id, array['owner','admin']::company_role[]));

-- 5. Scope-aware authority ----------------------------------------------------------------------------
-- A business-unit grant also covers the units below it.
create or replace function omelo_private.omelo_unit_in_tree(p_unit uuid, p_root uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  with recursive up as (
    select id, parent_id from business_units where id = p_unit
    union all
    select b.id, b.parent_id from business_units b join up on up.parent_id = b.id)
  select exists (select 1 from up where id = p_root);
$$;

-- Does this person's role reach this part of the organization? A member who is not scoped reaches
-- all of it (how Omelo worked before R8).
create or replace function omelo_private.omelo_scope_covers(p_company uuid, p_person uuid, p_roles company_role[],
                                                            p_department uuid, p_company_location uuid, p_legal_entity uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select exists (
    select 1 from company_members m
     where m.company_id = p_company and m.person_id = p_person and m.is_active
       and (
         -- the member's own role, when they are not scoped: the whole organization
         (m.role = any (p_roles) and m.scope_mode = 'organization')
         -- or a grant that reaches this part of it (a grant never widens a scoped member)
         or exists (
           select 1 from company_role_grants g
            where g.company_id = p_company and g.person_id = p_person and g.role = any (p_roles)
              and (g.scope_type = 'organization'
                   or (g.scope_type = 'department' and g.scope_id = p_department)
                   or (g.scope_type = 'location' and g.scope_id = p_company_location)
                   or (g.scope_type = 'legal_entity' and g.scope_id = p_legal_entity)
                   or (g.scope_type = 'business_unit'
                       and exists (select 1 from departments d where d.id = p_department
                                    and omelo_private.omelo_unit_in_tree(d.business_unit_id, g.scope_id)))))));
$$;

-- Same question for a job row.
create or replace function omelo_private.omelo_scope_covers_job(p_job uuid, p_roles company_role[])
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select exists (select 1 from jobs j
                  where j.id = p_job
                    and omelo_private.omelo_scope_covers(j.company_id, auth.uid(), p_roles,
                                                         j.department_id, j.company_location_id, j.legal_entity_id));
$$;

create or replace function omelo_private.omelo_can_access_job(p_job_id uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select omelo_private.omelo_scope_covers_job(p_job_id,
           array['owner','admin','recruiter','hiring_manager','hr']::company_role[]);
$$;

-- Creating and editing a job now respects the same scope.
drop policy if exists jobs_company_write on jobs;
create policy jobs_company_write on jobs for all to authenticated
  using (omelo_private.omelo_scope_covers(company_id, (select auth.uid()),
                                          array['owner','admin','recruiter']::company_role[],
                                          department_id, company_location_id, legal_entity_id))
  with check (omelo_private.omelo_scope_covers(company_id, (select auth.uid()),
                                               array['owner','admin','recruiter']::company_role[],
                                               department_id, company_location_id, legal_entity_id));

-- RLS runs these as the calling role, so both client roles must be able to execute them
-- (the same rule as the other policy helpers — see invariant 1).
revoke all on function omelo_private.omelo_scope_covers(uuid, uuid, company_role[], uuid, uuid, uuid) from public;
revoke all on function omelo_private.omelo_scope_covers_job(uuid, company_role[]) from public;
revoke all on function omelo_private.omelo_unit_in_tree(uuid, uuid) from public;
grant execute on function omelo_private.omelo_scope_covers(uuid, uuid, company_role[], uuid, uuid, uuid) to anon, authenticated;
grant execute on function omelo_private.omelo_scope_covers_job(uuid, company_role[]) to anon, authenticated;
grant execute on function omelo_private.omelo_unit_in_tree(uuid, uuid) to anon, authenticated;
