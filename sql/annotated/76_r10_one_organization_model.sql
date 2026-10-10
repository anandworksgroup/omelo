-- OMELO 76 — One organization model, part 1: capability, not type.
--
-- Omelo has two entry options: a Personal Profile and an Organization Workspace.
-- Every organization gets the same core: a public page, jobs, candidates,
-- interviews, hiring, posts, team and permissions. What an organization *does*
-- for a living — private company, recruitment firm, staffing firm, RPO provider
-- — describes it and sets its defaults. It must not hand out or withhold the
-- product.
--
-- What was wrong
--
-- `company_kind` was doing two jobs at once: describing the business and
-- deciding what it was allowed to do. The decider lived in omelo_agency_can,
-- which 16 RPCs and 14 RLS policies route through, so one line —
-- `c.company_kind = 'agency'` — was the reason a private company could not
-- recruit for a client. Nothing in RLS ever read the type; all of it was in
-- twenty functions.
--
-- What changes here
--
-- 1. A company says which optional modules it has turned on
--    (company_capabilities). Core hiring is not a module: it is always on.
-- 2. Authority stops asking what kind of organization this is and keeps asking
--    the two questions that matter: are you a member, and is your role allowed
--    to do this.
-- 3. One role vocabulary. Sourcer and coordinator stop being "agency roles";
--    hiring manager and HR stop being "employer roles". All ten exist
--    everywhere, and each action names the roles that may perform it.
-- 4. The `recruiters` discoverability tag goes. Its only purpose was to let
--    agencies see workers that employers could not, which is exactly the kind
--    of type-based privilege this release removes. Who may discover a worker is
--    still decided by the worker's own setting, the company being verified, the
--    talent-search entitlement, and the worker's blocks — none of which are
--    type.
--
-- What does NOT change: every consent rule, every client-confidentiality rule,
-- and every employment-data boundary. Representation and submission consent
-- remain separate, explicit and mandatory. See migration 77, which moves those
-- rules off "is an agency" and onto "is working for a client", which is what
-- they were always about.
--
-- Rollback: restore the previous bodies of the eight functions below and drop
-- company_capabilities. The data migration (recruiters -> discoverable) is not
-- reversible in a meaningful sense; no row used it when this ran.

-- ---------------------------------------------------------------
-- 1. What an organization has turned on
-- ---------------------------------------------------------------

create table if not exists company_capabilities (
  company_id   uuid not null references companies(id) on delete cascade,
  capability   text not null check (capability in ('client_recruitment','workforce','rpo','billing')),
  is_enabled   boolean not null default true,
  enabled_by   uuid references persons(id) on delete set null,
  enabled_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  primary key (company_id, capability)
);

comment on table company_capabilities is
  'Optional modules an organization has turned on. Core hiring is never here: '
  'every organization has it. A capability decides what the workspace offers, '
  'never whether an authorization, consent or client relationship is valid.';

alter table company_capabilities enable row level security;

-- A member can see what their own organization has turned on. Writing goes
-- through omelo_set_capability so that owner/admin is checked in one place and
-- the change is audited.
drop policy if exists company_capabilities_read on company_capabilities;
create policy company_capabilities_read on company_capabilities
  for select using (omelo_private.omelo_is_company_member(company_id));

-- Supabase grants every privilege on a new public table by default, so the
-- write paths are taken back explicitly and RLS decides the reads.
revoke insert, update, delete, truncate on company_capabilities from authenticated, anon;
grant select on company_capabilities to authenticated, anon;

create index if not exists company_capabilities_enabled
  on company_capabilities (company_id) where is_enabled;

create or replace function omelo_private.omelo_has_capability(p_company uuid, p_capability text)
returns boolean
language sql
stable
security definer
set search_path = public, omelo_private
as $$
  select exists (
    select 1 from company_capabilities
     where company_id = p_company and capability = p_capability and is_enabled);
$$;

revoke execute on function omelo_private.omelo_has_capability(uuid, text) from public;
grant execute on function omelo_private.omelo_has_capability(uuid, text) to authenticated, anon;

create or replace function public.omelo_set_capability(
  p_company uuid, p_capability text, p_enabled boolean default true)
returns void
language plpgsql
security definer
set search_path = public, omelo_private
as $$
begin
  if not omelo_private.omelo_has_company_role(p_company, array['owner','admin']::company_role[]) then
    raise exception 'Only owners and admins can turn a capability on or off' using errcode = '42501';
  end if;
  if p_capability not in ('client_recruitment','workforce','rpo','billing') then
    raise exception 'Unknown capability %', p_capability using errcode = '22023';
  end if;

  insert into company_capabilities (company_id, capability, is_enabled, enabled_by)
  values (p_company, p_capability, coalesce(p_enabled, true), auth.uid())
  on conflict (company_id, capability) do update
    set is_enabled = excluded.is_enabled,
        enabled_by = excluded.enabled_by,
        updated_at = now();

  perform omelo_private.omelo_emit(
    case when coalesce(p_enabled, true) then 'CapabilityEnabled' else 'CapabilityDisabled' end,
    'company', p_company, p_company, auth.uid(),
    jsonb_build_object('capability', p_capability));
end;
$$;

revoke execute on function public.omelo_set_capability(uuid, text, boolean) from public;
grant execute on function public.omelo_set_capability(uuid, text, boolean) to authenticated;

-- Backfill. An organization that is already doing the work keeps doing it, and
-- the business type supplies the default for one that is not.
insert into company_capabilities (company_id, capability, is_enabled)
select c.id, 'client_recruitment', true
from companies c
where c.organization_type in ('recruitment_agency','staffing_agency','rpo_provider','workforce_provider')
   or c.company_kind = 'agency'
   or exists (select 1 from agency_clients a where a.agency_id = c.id)
   or exists (select 1 from job_orders j where j.agency_id = c.id)
on conflict do nothing;

insert into company_capabilities (company_id, capability, is_enabled)
select c.id, 'workforce', true
from companies c
where c.organization_type in ('staffing_agency','workforce_provider')
   or exists (select 1 from workforce_requirements r where r.company_id = c.id)
   or exists (select 1 from assignments a where a.company_id = c.id)
on conflict do nothing;

insert into company_capabilities (company_id, capability, is_enabled)
select c.id, 'rpo', true
from companies c
where c.organization_type = 'rpo_provider'
   or exists (select 1 from rpo_engagements e where e.provider_id = c.id or e.client_company_id = c.id)
on conflict do nothing;

insert into company_capabilities (company_id, capability, is_enabled)
select c.id, 'billing', true
from companies c
where c.organization_type in ('recruitment_agency','staffing_agency','rpo_provider','workforce_provider')
   or exists (select 1 from billing_records b where b.agency_id = c.id)
on conflict do nothing;

-- ---------------------------------------------------------------
-- 2. Authority asks about membership and role, never about type
-- ---------------------------------------------------------------

-- These two are the chokepoint: 16 RPCs and 14 RLS policies call them. Dropping
-- the company_kind test is what lets any organization run client recruitment.
-- The membership test, the active test and the role test are untouched, so no
-- one reaches a record they could not reach before.
create or replace function omelo_private.omelo_agency_can(p_agency uuid, p_action text)
returns boolean
language sql
stable
security definer
set search_path = public, omelo_private
as $$
  select exists (
    select 1
      from companies c
      join company_members cm
        on cm.company_id = c.id and cm.person_id = (select auth.uid()) and cm.is_active
     where c.id = p_agency
       and c.deleted_at is null
       and cm.role::text = any (omelo_private.omelo_agency_roles(p_action)));
$$;

create or replace function omelo_private.omelo_person_agency_can(p_person uuid, p_agency uuid, p_action text)
returns boolean
language sql
stable
security definer
set search_path = public, omelo_private
as $$
  select exists (
    select 1
      from companies c
      join company_members cm
        on cm.company_id = c.id and cm.person_id = p_person and cm.is_active
     where c.id = p_agency
       and c.deleted_at is null
       and cm.role::text = any (omelo_private.omelo_agency_roles(p_action)));
$$;

-- One vocabulary. The employer-side roles gain their agency-side analogue:
-- a hiring manager is to internal hiring what a recruiter is to client work, so
-- it joins the hiring-shaped actions. Nobody gains sight of anything an agency
-- role could not already see — 'view' adds hiring_manager and no one else.
create or replace function omelo_private.omelo_agency_roles(p_action text)
returns text[]
language sql
immutable
set search_path = pg_catalog
as $$
  select case p_action
    when 'manage_agency'          then array['owner','admin']
    when 'manage_members'         then array['owner','admin']
    when 'manage_clients'         then array['owner','admin','recruiter']
    when 'create_job_order'       then array['owner','admin','recruiter','hiring_manager']
    when 'search_talent'          then array['owner','admin','recruiter','sourcer','hiring_manager']
    when 'request_consent'        then array['owner','admin','recruiter','sourcer','hiring_manager']
    when 'submit'                 then array['owner','admin','recruiter','hiring_manager']
    when 'schedule_interview'     then array['owner','admin','recruiter','coordinator','hiring_manager','hr']
    when 'view_candidate_details' then array['owner','admin','recruiter','hiring_manager']
    when 'view_candidate_limited' then array['owner','admin','recruiter','sourcer','coordinator','hiring_manager','hr']
    when 'manage_placements'      then array['owner','admin','recruiter','coordinator','hiring_manager']
    when 'view'                   then array['owner','admin','recruiter','sourcer','coordinator','hiring_manager']
    else array[]::text[]
  end;
$$;

-- Workforce roles were two maps, one per kind, so an employer had no
-- coordinator and an agency had no HR. One map now, the union of the two.
create or replace function omelo_private.omelo_workforce_roles(p_action text)
returns text[]
language sql
immutable
set search_path = pg_catalog
as $$
  select case p_action
    when 'manage_workforce' then array['owner','admin','recruiter','coordinator','hiring_manager','hr']
    when 'approve_time'     then array['owner','admin','coordinator','hiring_manager','hr']
    when 'manage_pay'       then array['owner','admin','finance','coordinator','hr']
    when 'view'             then array['owner','admin','recruiter','sourcer','coordinator',
                                       'hiring_manager','interviewer','hr','finance','viewer']
    else array[]::text[]
  end;
$$;

create or replace function omelo_private.omelo_person_workforce_can(p_person uuid, p_company uuid, p_action text)
returns boolean
language sql
stable
security definer
set search_path = public, omelo_private
as $$
  select exists (
    select 1
      from companies c
      join company_members cm
        on cm.company_id = c.id and cm.person_id = p_person and cm.is_active
     where c.id = p_company
       and c.deleted_at is null
       and cm.role::text = any (omelo_private.omelo_workforce_roles(p_action)));
$$;

create or replace function omelo_private.omelo_notify_team(
  p_company uuid, p_action text, p_type text, p_title text, p_body text,
  p_entity text, p_id uuid, p_link text)
returns void
language plpgsql
security definer
set search_path = public, omelo_private
as $$
declare m record;
begin
  for m in
    select distinct cm.person_id
      from company_members cm
     where cm.company_id = p_company
       and cm.is_active
       and cm.role::text = any (omelo_private.omelo_workforce_roles(p_action))
  loop
    perform omelo_private.omelo_notify(m.person_id, p_type::notification_type, p_title, p_body, p_entity, p_id, p_link);
  end loop;
end;
$$;

drop function if exists omelo_private.omelo_workforce_roles(text, text);

-- ---------------------------------------------------------------
-- 3. Every role exists in every organization
-- ---------------------------------------------------------------

create or replace function omelo_private.omelo_guard_member_role()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if omelo_private.omelo_is_privileged() then return new; end if;
  if new.company_id is distinct from old.company_id or new.person_id is distinct from old.person_id then
    raise exception 'A membership cannot move to another person or company' using errcode = '42501';
  end if;
  if new.role is distinct from old.role then
    if (new.role::text = 'owner' or old.role::text = 'owner')
       and not omelo_private.omelo_has_company_role(new.company_id, array['owner']::company_role[]) then
      raise exception 'Only an owner can grant or remove the owner role' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------
-- 4. Discoverability is the worker's choice, not the company's type
-- ---------------------------------------------------------------

-- Nobody had chosen 'recruiters' when this ran, but the migration is written to
-- be correct if they had: it means the same thing as 'discoverable' now.
update work_identities set discoverability = 'discoverable'
where discoverability::text = 'recruiters';

update persons set discoverability = 'discoverable'
where discoverability::text = 'recruiters';

-- The enum value cannot be removed from the type, so it is refused instead:
-- a client that still sends it gets an error rather than a silent setting that
-- means nothing.
alter table work_identities drop constraint if exists work_identities_discoverability_live;
alter table work_identities add constraint work_identities_discoverability_live
  check (discoverability::text <> 'recruiters');

-- Who may find a worker: the worker's own setting, a verified company, a live
-- talent-search entitlement, and the worker's blocks. All four are about the
-- worker's consent and the company's standing. None of them is the company's
-- business type, and a recruitment firm now follows exactly the same rules as
-- a private company.
create or replace function omelo_private.omelo_is_identity_discoverable_to(
  p_work_identity_id uuid, p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, omelo_private
as $$
  select exists (
    select 1
      from work_identities wi
      join persons p on p.id = wi.person_id
     where wi.id = p_work_identity_id
       and wi.status = 'active'
       and p.deleted_at is null
       and case wi.discoverability::text
             when 'private' then false
             when 'matched_only' then exists (
               select 1 from matches m
               join jobs j on j.id = m.job_id
               where m.work_identity_id = wi.id
                 and j.company_id = p_company_id
                 and j.status = 'published'
                 and m.eligible
                 and m.score >= 70)
             when 'discoverable' then true
             when 'recruiters' then true   -- legacy label, same meaning
             when 'public' then true
             else false
           end)
   and exists (select 1 from companies c
                where c.id = p_company_id and c.is_verified and c.deleted_at is null)
   and exists (select 1 from company_entitlements e
                where e.company_id = p_company_id
                  and e.talent_search_enabled
                  and (e.valid_until is null or e.valid_until >= current_date))
   and not exists (
     select 1 from blocks b
     join work_identities wi on wi.id = p_work_identity_id
     where b.person_id = wi.person_id and b.target_type = 'company' and b.target_id = p_company_id)
   and not exists (
     select 1 from blocks b
     join work_identities wi on wi.id = p_work_identity_id
     where b.person_id = wi.person_id and b.target_type = 'person' and b.target_id = (select auth.uid()));
$$;

-- ---------------------------------------------------------------
-- 5. Inviting a team member
-- ---------------------------------------------------------------

create or replace function public.omelo_invite_team_member(p_company uuid, p_email text, p_role text)
returns uuid
language plpgsql
security definer
set search_path = public, omelo_private
as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
  v_id uuid;
  v_company companies;
  v_person uuid;
begin
  if not omelo_private.omelo_has_company_role(p_company, array['owner','admin']::company_role[]) then
    raise exception 'Only owners and admins can invite team members' using errcode = '42501';
  end if;
  select * into v_company from companies where id = p_company and deleted_at is null;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_email) > 254 then
    raise exception 'Enter a valid email address' using errcode = '22023';
  end if;
  if p_role is null or p_role not in (
       select e.enumlabel from pg_enum e join pg_type t on t.oid = e.enumtypid
        where t.typname = 'company_role') then
    raise exception 'Unknown role %', p_role using errcode = '22023';
  end if;
  if p_role = 'owner'
     and not omelo_private.omelo_has_company_role(p_company, array['owner']::company_role[]) then
    raise exception 'Only an owner can invite another owner' using errcode = '42501';
  end if;
  if exists (select 1 from company_members cm join persons p on p.id = cm.person_id
              where cm.company_id = p_company and cm.is_active
                and lower(p.email) = v_email and cm.role::text = p_role) then
    raise exception 'That person already has this role' using errcode = '22023';
  end if;
  if (select count(*) from company_invitations
       where company_id = p_company and created_at > now() - interval '1 day') >= 50 then
    raise exception 'Too many invitations today' using errcode = '22023';
  end if;

  insert into company_invitations (company_id, email, role, token_hash, invited_by, expires_at, accepted_at)
  values (p_company, v_email, p_role::company_role,
          encode(sha256(convert_to(gen_random_uuid()::text || gen_random_uuid()::text, 'UTF8')), 'hex'),
          auth.uid(), now() + interval '14 days', null)
  on conflict (company_id, email) do update
    set role = excluded.role, token_hash = excluded.token_hash, invited_by = excluded.invited_by,
        expires_at = excluded.expires_at, accepted_at = null, created_at = now()
  returning id into v_id;

  select id into v_person from persons where lower(email) = v_email and deleted_at is null;
  if v_person is not null then
    perform omelo_private.omelo_notify(
      v_person, 'company_update'::notification_type,
      v_company.display_name || ' invited you to join the team',
      'Role: ' || replace(p_role, '_', ' '), 'company_invitation', v_id, '/join/' || v_id);
  end if;
  perform omelo_private.omelo_emit('TeamMemberInvited', 'company', p_company, p_company, v_person,
                                   jsonb_build_object('role', p_role));
  return v_id;
end;
$$;
