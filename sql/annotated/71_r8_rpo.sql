-- OMELO 71 — Release 8: RPO (recruitment process outsourcing).
--
--   Client organization  --- engagement --->  RPO organization
--                                             ├── assigned recruiters (rpo_assignments)
--                                             ├── scope (rpo_scopes)
--                                             └── permissions (what they may do)
--
-- An RPO provider gets authorized access to *part* of a client's recruiting, never to the client.
-- The client confirms the engagement before it becomes active — the same two-sided handshake R4
-- uses for agency client links. Scope is explicit: organization, business unit, department,
-- location, a named job, or a profession. Nothing outside it is visible (R8-005, R8-006).
--
-- Candidate ownership does not change: the worker still owns their identity, and the RPO recruiter
-- works inside the client's own hiring pipeline (applications, interviews, offers), which is exactly
-- what the existing policies already govern through omelo_can_access_job.
--
-- Permissions on an engagement (a subset of):
--   view_jobs · manage_jobs · view_candidates · move_candidates · schedule_interviews ·
--   send_offers · view_reports
--
-- Rollback: drop the tables and functions, and restore omelo_can_access_job and jobs_company_write
-- from migration 68.

create table if not exists public.rpo_engagements (
  id                uuid primary key default gen_random_uuid(),
  provider_id       uuid not null references companies(id) on delete cascade,
  client_company_id uuid not null references companies(id) on delete cascade,
  title             text not null check (length(trim(title)) between 2 and 160),
  reference         text check (reference is null or length(reference) <= 60),
  status            text not null default 'draft'
                    check (status in ('draft','pending_approval','active','paused','completed','terminated')),
  permissions       text[] not null default '{view_jobs,view_candidates}',
  start_date        date,
  end_date          date,
  notes             text check (notes is null or length(notes) <= 2000),
  created_by        uuid references persons(id) on delete set null,
  proposed_at       timestamptz,
  responded_at      timestamptz,
  responded_by      uuid references persons(id) on delete set null,
  ended_at          timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (provider_id <> client_company_id),
  check (end_date is null or start_date is null or end_date >= start_date)
);
create index if not exists rpo_engagements_provider on rpo_engagements (provider_id, status);
create index if not exists rpo_engagements_client on rpo_engagements (client_company_id, status);

create table if not exists public.rpo_scopes (
  id            uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references rpo_engagements(id) on delete cascade,
  scope_type    text not null check (scope_type in ('organization','business_unit','department','location','job','profession')),
  scope_id      uuid,
  created_at    timestamptz not null default now(),
  check ((scope_type = 'organization') = (scope_id is null))
);
create unique index if not exists rpo_scopes_unique
  on rpo_scopes (engagement_id, scope_type, coalesce(scope_id, '00000000-0000-0000-0000-000000000000'::uuid));

create table if not exists public.rpo_assignments (
  id            uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references rpo_engagements(id) on delete cascade,
  person_id     uuid not null references persons(id) on delete cascade,
  role          text not null default 'recruiter' check (role in ('lead','recruiter','coordinator','sourcer')),
  is_active     boolean not null default true,
  added_by      uuid references persons(id) on delete set null,
  created_at    timestamptz not null default now(),
  unique (engagement_id, person_id)
);
create index if not exists rpo_assignments_person on rpo_assignments (person_id, is_active);

alter table rpo_engagements enable row level security;
alter table rpo_scopes enable row level security;
alter table rpo_assignments enable row level security;

-- Both sides read the engagement; nobody writes it directly.
drop policy if exists rpo_engagements_read on rpo_engagements;
create policy rpo_engagements_read on rpo_engagements for select to authenticated
  using (omelo_private.omelo_is_company_member(provider_id) or omelo_private.omelo_is_company_member(client_company_id));
revoke insert, update, delete on rpo_engagements from anon, authenticated;

drop policy if exists rpo_scopes_read on rpo_scopes;
create policy rpo_scopes_read on rpo_scopes for select to authenticated
  using (exists (select 1 from rpo_engagements e where e.id = engagement_id
                  and (omelo_private.omelo_is_company_member(e.provider_id)
                       or omelo_private.omelo_is_company_member(e.client_company_id))));
revoke insert, update, delete on rpo_scopes from anon, authenticated;

drop policy if exists rpo_assignments_read on rpo_assignments;
create policy rpo_assignments_read on rpo_assignments for select to authenticated
  using (person_id = (select auth.uid())
         or exists (select 1 from rpo_engagements e where e.id = engagement_id
                     and (omelo_private.omelo_is_company_member(e.provider_id)
                          or omelo_private.omelo_is_company_member(e.client_company_id))));
revoke insert, update, delete on rpo_assignments from anon, authenticated;

-- 1. Does an engagement authorize this person for this job? ------------------------------------------
create or replace function omelo_private.omelo_rpo_covers_job(p_job uuid, p_permission text)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select exists (
    select 1
      from jobs j
      join rpo_engagements e on e.client_company_id = j.company_id and e.status = 'active'
      join rpo_assignments a on a.engagement_id = e.id and a.person_id = auth.uid() and a.is_active
     where j.id = p_job
       and p_permission = any (e.permissions)
       and (e.start_date is null or e.start_date <= current_date)
       and (e.end_date is null or e.end_date >= current_date)
       and exists (
         select 1 from rpo_scopes s
          where s.engagement_id = e.id
            and (s.scope_type = 'organization'
                 or (s.scope_type = 'job' and s.scope_id = j.id)
                 or (s.scope_type = 'department' and s.scope_id = j.department_id)
                 or (s.scope_type = 'location' and s.scope_id = j.company_location_id)
                 or (s.scope_type = 'profession' and s.scope_id = j.profession_id)
                 or (s.scope_type = 'business_unit'
                     and exists (select 1 from departments d where d.id = j.department_id
                                  and omelo_private.omelo_unit_in_tree(d.business_unit_id, s.scope_id))))));
$$;

-- The client's own team, plus an RPO recruiter the client authorized.
create or replace function omelo_private.omelo_can_access_job(p_job_id uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select omelo_private.omelo_scope_covers_job(p_job_id,
           array['owner','admin','recruiter','hiring_manager','hr']::company_role[])
      or omelo_private.omelo_rpo_covers_job(p_job_id, 'view_candidates');
$$;

drop policy if exists jobs_company_write on jobs;
create policy jobs_company_write on jobs for all to authenticated
  using (omelo_private.omelo_scope_covers(company_id, (select auth.uid()),
                                          array['owner','admin','recruiter']::company_role[],
                                          department_id, company_location_id, legal_entity_id)
         or omelo_private.omelo_rpo_covers_job(id, 'manage_jobs'))
  with check (omelo_private.omelo_scope_covers(company_id, (select auth.uid()),
                                               array['owner','admin','recruiter']::company_role[],
                                               department_id, company_location_id, legal_entity_id)
         or omelo_private.omelo_rpo_covers_job(id, 'manage_jobs'));

-- 2. Running an engagement -------------------------------------------------------------------------
create or replace function omelo_private.omelo_rpo_manager(p_engagement uuid, p_side text)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select exists (select 1 from rpo_engagements e
                  where e.id = p_engagement
                    and ((p_side in ('provider','either')
                          and omelo_private.omelo_has_company_role(e.provider_id, array['owner','admin']::company_role[]))
                      or (p_side in ('client','either')
                          and omelo_private.omelo_has_company_role(e.client_company_id, array['owner','admin']::company_role[]))));
$$;

create or replace function public.omelo_create_rpo_engagement(p jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_provider uuid := nullif(p->>'provider_id', '')::uuid;
        v_client uuid := nullif(p->>'client_company_id', '')::uuid; e rpo_engagements; v_perms text[];
begin
  if not omelo_private.omelo_has_company_role(v_provider, array['owner','admin']::company_role[]) then
    raise exception 'Only an owner or admin of the provider sets up an engagement' using errcode = '42501';
  end if;
  if not exists (select 1 from companies c where c.id = v_provider and c.organization_type in ('rpo_provider','recruitment_agency','staffing_agency')) then
    raise exception 'Set the organization type to RPO provider first' using errcode = '22023';
  end if;
  if not exists (select 1 from companies c where c.id = v_client and c.deleted_at is null) then
    raise exception 'Client organization not found' using errcode = '22023';
  end if;
  v_perms := coalesce(array(select x from jsonb_array_elements_text(p->'permissions') x), array['view_jobs','view_candidates']);
  if exists (select 1 from unnest(v_perms) x where x not in ('view_jobs','manage_jobs','view_candidates','move_candidates',
                                                             'schedule_interviews','send_offers','view_reports')) then
    raise exception 'Unknown permission on the engagement' using errcode = '22023';
  end if;
  insert into rpo_engagements (provider_id, client_company_id, title, reference, permissions, start_date, end_date, notes, created_by)
  values (v_provider, v_client, coalesce(nullif(trim(p->>'title'), ''), 'RPO engagement'), nullif(trim(p->>'reference'), ''),
          v_perms, nullif(p->>'start_date', '')::date, nullif(p->>'end_date', '')::date, nullif(trim(p->>'notes'), ''), auth.uid())
  returning * into e;
  perform omelo_private.omelo_emit('RpoEngagementCreated', 'rpo_engagement', e.id, v_provider, auth.uid(),
                                   jsonb_build_object('client_company_id', v_client));
  return to_jsonb(e);
exception
  when check_violation or invalid_text_representation or invalid_datetime_format then
    raise exception 'Check the engagement: %', sqlerrm using errcode = '22023';
end;
$$;

create or replace function public.omelo_set_rpo_scope(p_engagement uuid, p_scope_type text, p_scope_id uuid default null,
                                                      p_add boolean default true)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare e rpo_engagements;
begin
  select * into e from rpo_engagements where id = p_engagement;
  if e.id is null then raise exception 'Engagement not found' using errcode = '22023'; end if;
  -- the client decides what an engagement may reach; the provider may only narrow a draft it owns
  if not (omelo_private.omelo_rpo_manager(p_engagement, 'client')
          or (e.status = 'draft' and omelo_private.omelo_rpo_manager(p_engagement, 'provider'))) then
    raise exception 'The client organization sets the scope of an engagement' using errcode = '42501';
  end if;
  if p_scope_type <> 'organization' then
    if p_scope_id is null then raise exception 'Choose what the scope points at' using errcode = '22023'; end if;
    if p_scope_type = 'department' and not exists (select 1 from departments d where d.id = p_scope_id and d.company_id = e.client_company_id)
    or p_scope_type = 'business_unit' and not exists (select 1 from business_units b where b.id = p_scope_id and b.company_id = e.client_company_id)
    or p_scope_type = 'location' and not exists (select 1 from company_locations l where l.id = p_scope_id and l.company_id = e.client_company_id)
    or p_scope_type = 'job' and not exists (select 1 from jobs j where j.id = p_scope_id and j.company_id = e.client_company_id)
    or p_scope_type = 'profession' and not exists (select 1 from professions pr where pr.id = p_scope_id) then
      raise exception 'That scope does not belong to the client organization' using errcode = '42501';
    end if;
  end if;
  if p_add then
    insert into rpo_scopes (engagement_id, scope_type, scope_id) values (p_engagement, p_scope_type, p_scope_id)
    on conflict do nothing;
  else
    delete from rpo_scopes where engagement_id = p_engagement and scope_type = p_scope_type
      and coalesce(scope_id, '00000000-0000-0000-0000-000000000000'::uuid)
          = coalesce(p_scope_id, '00000000-0000-0000-0000-000000000000'::uuid);
  end if;
  perform omelo_private.omelo_emit('RpoScopeChanged', 'rpo_engagement', p_engagement, e.client_company_id, auth.uid(),
                                   jsonb_build_object('scope_type', p_scope_type, 'scope_id', p_scope_id, 'added', p_add));
  return (select coalesce(jsonb_agg(jsonb_build_object('scope_type', s.scope_type, 'scope_id', s.scope_id)), '[]'::jsonb)
            from rpo_scopes s where s.engagement_id = p_engagement);
end;
$$;

create or replace function public.omelo_assign_rpo_recruiter(p_engagement uuid, p_person uuid, p_role text default 'recruiter',
                                                             p_active boolean default true)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare e rpo_engagements; a rpo_assignments;
begin
  select * into e from rpo_engagements where id = p_engagement;
  if e.id is null then raise exception 'Engagement not found' using errcode = '22023'; end if;
  if not omelo_private.omelo_rpo_manager(p_engagement, 'provider') then
    raise exception 'Only the provider assigns its own recruiters' using errcode = '42501';
  end if;
  if not exists (select 1 from company_members m where m.company_id = e.provider_id and m.person_id = p_person and m.is_active) then
    raise exception 'That person is not on the provider''s team' using errcode = '22023';
  end if;
  insert into rpo_assignments (engagement_id, person_id, role, is_active, added_by)
  values (p_engagement, p_person, p_role, p_active, auth.uid())
  on conflict (engagement_id, person_id) do update set role = excluded.role, is_active = excluded.is_active
  returning * into a;
  perform omelo_private.omelo_emit('RpoRecruiterAssigned', 'rpo_engagement', e.id, e.provider_id, p_person,
                                   jsonb_build_object('role', p_role, 'active', p_active));
  return to_jsonb(a);
end;
$$;

create or replace function public.omelo_propose_rpo_engagement(p_engagement uuid)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare e rpo_engagements;
begin
  select * into e from rpo_engagements where id = p_engagement for update;
  if e.id is null then raise exception 'Engagement not found' using errcode = '22023'; end if;
  if not omelo_private.omelo_rpo_manager(p_engagement, 'provider') then
    raise exception 'Only the provider can send this to the client' using errcode = '42501';
  end if;
  if e.status <> 'draft' then raise exception 'This engagement is already %', e.status using errcode = '22023'; end if;
  if not exists (select 1 from rpo_scopes s where s.engagement_id = e.id) then
    raise exception 'Set what the engagement covers before sending it' using errcode = '22023';
  end if;
  update rpo_engagements set status = 'pending_approval', proposed_at = now(), updated_at = now()
   where id = e.id returning * into e;
  perform omelo_private.omelo_notify_role(e.client_company_id, 'owner', 'rpo_update', 'RPO engagement proposed',
            (select display_name from companies where id = e.provider_id) || ' proposed: ' || e.title,
            'rpo_engagement', e.id, '/dashboard/rpo');
  perform omelo_private.omelo_notify_role(e.client_company_id, 'admin', 'rpo_update', 'RPO engagement proposed',
            (select display_name from companies where id = e.provider_id) || ' proposed: ' || e.title,
            'rpo_engagement', e.id, '/dashboard/rpo');
  perform omelo_private.omelo_emit('RpoEngagementProposed', 'rpo_engagement', e.id, e.client_company_id, auth.uid(), '{}'::jsonb);
  return to_jsonb(e);
end;
$$;

create or replace function public.omelo_respond_rpo_engagement(p_engagement uuid, p_accept boolean, p_note text default null)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare e rpo_engagements;
begin
  select * into e from rpo_engagements where id = p_engagement for update;
  if e.id is null then raise exception 'Engagement not found' using errcode = '22023'; end if;
  if not omelo_private.omelo_rpo_manager(p_engagement, 'client') then
    raise exception 'Only the client organization answers an engagement' using errcode = '42501';
  end if;
  if e.status <> 'pending_approval' then raise exception 'This engagement is %', e.status using errcode = '22023'; end if;
  update rpo_engagements
     set status = case when p_accept then 'active' else 'terminated' end,
         responded_at = now(), responded_by = auth.uid(), updated_at = now(),
         ended_at = case when p_accept then null else now() end,
         notes = coalesce(nullif(trim(p_note), ''), notes)
   where id = e.id returning * into e;
  perform omelo_private.omelo_notify_role(e.provider_id, 'owner', 'rpo_update',
            case when p_accept then 'Engagement confirmed' else 'Engagement declined' end, e.title,
            'rpo_engagement', e.id, '/dashboard/rpo');
  perform omelo_private.omelo_emit(case when p_accept then 'RpoEngagementActivated' else 'RpoEngagementDeclined' end,
                                   'rpo_engagement', e.id, e.client_company_id, auth.uid(), '{}'::jsonb);
  return to_jsonb(e);
end;
$$;

create or replace function public.omelo_set_rpo_status(p_engagement uuid, p_status text, p_note text default null)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare e rpo_engagements;
begin
  select * into e from rpo_engagements where id = p_engagement for update;
  if e.id is null then raise exception 'Engagement not found' using errcode = '22023'; end if;
  if not omelo_private.omelo_rpo_manager(p_engagement, 'either') then
    raise exception 'Only the two organizations manage this engagement' using errcode = '42501';
  end if;
  if p_status not in ('paused','active','completed','terminated') then
    raise exception 'Unknown status %', p_status using errcode = '22023';
  end if;
  if e.status in ('completed','terminated') then
    raise exception 'This engagement is already %', e.status using errcode = '22023';
  end if;
  if p_status = 'active' and e.status <> 'paused' then
    raise exception 'Only a paused engagement can be resumed' using errcode = '22023';
  end if;
  update rpo_engagements set status = p_status, updated_at = now(),
         ended_at = case when p_status in ('completed','terminated') then now() else null end,
         notes = coalesce(nullif(trim(p_note), ''), notes)
   where id = e.id returning * into e;
  perform omelo_private.omelo_emit('RpoEngagementStatusChanged', 'rpo_engagement', e.id, e.client_company_id, auth.uid(),
                                   jsonb_build_object('status', p_status));
  return to_jsonb(e);
end;
$$;

-- 3. Reading -------------------------------------------------------------------------------------------
create or replace function public.omelo_rpo_engagements(p_company uuid)
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', e.id, 'title', e.title, 'reference', e.reference, 'status', e.status,
           'side', case when e.provider_id = p_company then 'provider' else 'client' end,
           'provider', (select display_name from companies where id = e.provider_id),
           'client', (select display_name from companies where id = e.client_company_id),
           'provider_id', e.provider_id, 'client_company_id', e.client_company_id,
           'permissions', to_jsonb(e.permissions), 'start_date', e.start_date, 'end_date', e.end_date,
           'scopes', (select coalesce(jsonb_agg(jsonb_build_object('scope_type', s.scope_type, 'scope_id', s.scope_id,
                                                                   'label', case s.scope_type
                                                                     when 'department' then (select d.name from departments d where d.id = s.scope_id)
                                                                     when 'business_unit' then (select b.name from business_units b where b.id = s.scope_id)
                                                                     when 'location' then (select l.name from company_locations l where l.id = s.scope_id)
                                                                     when 'job' then (select j.title from jobs j where j.id = s.scope_id)
                                                                     when 'profession' then (select pr.name from professions pr where pr.id = s.scope_id)
                                                                     else 'Whole organization' end)), '[]'::jsonb)
                        from rpo_scopes s where s.engagement_id = e.id),
           'recruiters', (select coalesce(jsonb_agg(jsonb_build_object('person_id', a.person_id, 'role', a.role,
                                                                      'active', a.is_active,
                                                                      'name', (select display_name from persons p where p.id = a.person_id))), '[]'::jsonb)
                            from rpo_assignments a where a.engagement_id = e.id),
           'open_jobs', (select count(*) from jobs j where j.company_id = e.client_company_id and j.status = 'published'))
           order by e.created_at desc), '[]'::jsonb)
    from rpo_engagements e
   where (e.provider_id = p_company or e.client_company_id = p_company)
     and omelo_private.omelo_is_company_member(p_company);
$$;

-- What an RPO recruiter may actually work on.
create or replace function public.omelo_rpo_my_work(p_engagement uuid default null)
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select coalesce(jsonb_agg(x order by x->>'client', x->>'title'), '[]'::jsonb)
    from (
      select jsonb_build_object(
               'engagement_id', e.id, 'client', (select display_name from companies where id = e.client_company_id),
               'client_company_id', e.client_company_id, 'permissions', to_jsonb(e.permissions),
               'job_id', j.id, 'title', j.title, 'status', j.status, 'openings', j.openings,
               'department', (select d.name from departments d where d.id = j.department_id),
               'location_text', j.location_text,
               'applicants', (select count(*) from applications a where a.job_id = j.id),
               'new_applicants', (select count(*) from applications a where a.job_id = j.id and a.first_viewed_at is null),
               'published_at', j.published_at) x
        from rpo_engagements e
        join rpo_assignments a on a.engagement_id = e.id and a.person_id = auth.uid() and a.is_active
        join jobs j on j.company_id = e.client_company_id
       where e.status = 'active' and (p_engagement is null or e.id = p_engagement)
         and j.status in ('published','draft','paused','closed')
         and omelo_private.omelo_rpo_covers_job(j.id, 'view_jobs')) s;
$$;

revoke all on function omelo_private.omelo_rpo_covers_job(uuid, text) from public;
grant execute on function omelo_private.omelo_rpo_covers_job(uuid, text) to anon, authenticated;
revoke all on function omelo_private.omelo_rpo_manager(uuid, text) from public, anon, authenticated;
revoke all on function public.omelo_create_rpo_engagement(jsonb) from public, anon;
revoke all on function public.omelo_set_rpo_scope(uuid, text, uuid, boolean) from public, anon;
revoke all on function public.omelo_assign_rpo_recruiter(uuid, uuid, text, boolean) from public, anon;
revoke all on function public.omelo_propose_rpo_engagement(uuid) from public, anon;
revoke all on function public.omelo_respond_rpo_engagement(uuid, boolean, text) from public, anon;
revoke all on function public.omelo_set_rpo_status(uuid, text, text) from public, anon;
revoke all on function public.omelo_rpo_engagements(uuid) from public, anon;
revoke all on function public.omelo_rpo_my_work(uuid) from public, anon;
grant execute on function public.omelo_create_rpo_engagement(jsonb) to authenticated;
grant execute on function public.omelo_set_rpo_scope(uuid, text, uuid, boolean) to authenticated;
grant execute on function public.omelo_assign_rpo_recruiter(uuid, uuid, text, boolean) to authenticated;
grant execute on function public.omelo_propose_rpo_engagement(uuid) to authenticated;
grant execute on function public.omelo_respond_rpo_engagement(uuid, boolean, text) to authenticated;
grant execute on function public.omelo_set_rpo_status(uuid, text, text) to authenticated;
grant execute on function public.omelo_rpo_engagements(uuid) to authenticated;
grant execute on function public.omelo_rpo_my_work(uuid) to authenticated;
