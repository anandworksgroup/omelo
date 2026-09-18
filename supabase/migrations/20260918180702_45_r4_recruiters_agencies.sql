-- OMELO 45 — Release 4: Recruiters & Agencies
--
-- Principle: a recruiter can represent a worker for a specific opportunity
-- only with the worker's explicit consent, for a defined period and purpose.
-- The recruiter never owns the candidate.
--
-- What already existed and is REUSED (nothing is duplicated):
--   agency            = companies row with company_kind = 'agency'
--   agency members    = company_members (+ roles sourcer, coordinator from 44)
--   member invites    = company_invitations
--   talent pools      = talent_pools / talent_pool_members (agency-owned)
--   talent search     = R3 engine; its core is factored out and shared
--   client pipeline   = applications / interviews / offers / employments
--                       (a submission to a linked client IS an application)
--   audit             = domain_events + append-only *_events tables
--
-- New (each with FKs, checks, indexes, RLS, audit):
--   agency_clients, agency_client_contacts   clients of an agency
--   job_orders, job_order_recruiters         what the agency recruits for;
--                                            each order has a private,
--                                            agency-owned draft job so the
--                                            existing matcher can score it
--   candidate_consents (+ _events)           scoped representation consent:
--                                            candidate + identity + agency +
--                                            recruiter + job order + client +
--                                            purpose + information scope +
--                                            expiry
--   candidate_submissions (+ _events)        only from an accepted, unexpired
--                                            consent that matches exactly
--   placements                               a hire that came through an agency
--
-- Enforced in the database (not the UI):
--   * no submission without an accepted, unexpired, matching consent
--     (validation trigger runs for every role, including service_role)
--   * consent lifecycle requested -> accepted -> active -> expired/revoked,
--     requested -> declined/withdrawn/expired; everything else is rejected
--   * consents, submissions, placements, job orders are written only by
--     functions; clients and recruiters cannot insert/update them
--   * pool membership never grants anything; agency membership grants full
--     candidate rows only to owner/admin/recruiter and only with consent
--     (or the worker's own visibility setting)
--   * an agency cannot claim a client company: the client confirms the link
--   * a narrowed consent scope hides live profile rows from the client; it
--     sees the snapshot that was legitimately submitted
--
-- Rollback: drop the functions and triggers below, the new tables, the two
-- new columns; restore omelo_can_view_identity (38), omelo_guard_pool_member
-- (41), omelo_search_talent (41/42), omelo_guard_company_trust (38).

-- 0. Agency flags ------------------------------------------------------------------
alter table companies add column if not exists is_independent_recruiter boolean not null default false;
alter table work_identities add column if not exists allow_recruiter_requests boolean not null default true;

create or replace function omelo_private.omelo_guard_company_trust()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if omelo_private.omelo_is_privileged() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if coalesce(new.is_verified, false) or new.verified_at is not null or new.verification_method is not null then
      raise exception 'Company verification is done by Omelo' using errcode = '42501';
    end if;
    if new.company_kind <> 'employer' or coalesce(new.is_independent_recruiter, false) then
      raise exception 'Create an agency with Omelo''s agency sign-up' using errcode = '42501';
    end if;
    new.response_rate_pct := null;
    new.median_response_hours := null;
    new.total_hires := 0;
    new.stats_computed_at := null;
    return new;
  end if;
  if new.is_verified is distinct from old.is_verified
  or new.verified_at is distinct from old.verified_at
  or new.verification_method is distinct from old.verification_method
  or new.company_kind is distinct from old.company_kind
  or new.is_independent_recruiter is distinct from old.is_independent_recruiter then
    raise exception 'Company verification and type are managed by Omelo' using errcode = '42501';
  end if;
  if new.response_rate_pct is distinct from old.response_rate_pct
  or new.median_response_hours is distinct from old.median_response_hours
  or new.total_hires is distinct from old.total_hires
  or new.stats_computed_at is distinct from old.stats_computed_at then
    raise exception 'Hiring statistics are computed by Omelo' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- 1. Agency RBAC ---------------------------------------------------------------------
-- One table of truth for "who in an agency may do what". Roles compared as
-- text so this function never depends on enum ordering.
create or replace function omelo_private.omelo_agency_roles(p_action text)
returns text[]
language sql immutable
as $$
  select case p_action
    when 'manage_agency'          then array['owner','admin']
    when 'manage_members'         then array['owner','admin']
    when 'manage_clients'         then array['owner','admin','recruiter']
    when 'create_job_order'       then array['owner','admin','recruiter']
    when 'search_talent'          then array['owner','admin','recruiter','sourcer']
    when 'request_consent'        then array['owner','admin','recruiter','sourcer']
    when 'submit'                 then array['owner','admin','recruiter']
    when 'schedule_interview'     then array['owner','admin','recruiter','coordinator']
    when 'view_candidate_details' then array['owner','admin','recruiter']
    when 'view_candidate_limited' then array['owner','admin','recruiter','sourcer','coordinator']
    when 'manage_placements'      then array['owner','admin','recruiter','coordinator']
    when 'view'                   then array['owner','admin','recruiter','sourcer','coordinator']
    else array[]::text[]
  end;
$$;

create or replace function omelo_private.omelo_agency_can(p_agency uuid, p_action text)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select exists (
    select 1 from companies c
      join company_members cm on cm.company_id = c.id and cm.person_id = (select auth.uid()) and cm.is_active
     where c.id = p_agency and c.company_kind = 'agency' and c.deleted_at is null
       and cm.role::text = any (omelo_private.omelo_agency_roles(p_action)));
$$;
grant execute on function omelo_private.omelo_agency_can(uuid, text) to authenticated;
grant execute on function omelo_private.omelo_agency_roles(text) to authenticated;

create or replace function omelo_private.omelo_person_agency_can(p_person uuid, p_agency uuid, p_action text)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select exists (
    select 1 from companies c
      join company_members cm on cm.company_id = c.id and cm.person_id = p_person and cm.is_active
     where c.id = p_agency and c.company_kind = 'agency' and c.deleted_at is null
       and cm.role::text = any (omelo_private.omelo_agency_roles(p_action)));
$$;
grant execute on function omelo_private.omelo_person_agency_can(uuid, uuid, text) to authenticated;

create or replace function public.omelo_create_agency(p_name text, p_independent boolean default false,
                                                      p_country text default null)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_uid uuid := auth.uid(); v_id uuid; v_name text := trim(coalesce(p_name, ''));
begin
  if v_uid is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  if length(v_name) not between 2 and 120 then
    raise exception 'Give the agency a name between 2 and 120 characters' using errcode = '22023';
  end if;
  if (select count(*) from companies c join company_members cm on cm.company_id = c.id
       where cm.person_id = v_uid and cm.role = 'owner' and cm.is_active
         and c.company_kind = 'agency' and c.deleted_at is null) >= 3 then
    raise exception 'You can own at most 3 agencies' using errcode = '22023';
  end if;
  insert into companies (slug, display_name, country_code, company_kind, is_independent_recruiter, created_by)
  values (public.omelo_company_slug(v_name), v_name,
          upper(coalesce(nullif(p_country, ''), (select country_code from persons where id = v_uid), 'IN')),
          'agency', coalesce(p_independent, false), v_uid)
  returning id into v_id;
  perform omelo_private.omelo_emit('AgencyCreated', 'company', v_id, v_id, v_uid,
                                   jsonb_build_object('independent', coalesce(p_independent, false)));
  return v_id;
end;
$$;

-- 2. Clients -------------------------------------------------------------------------
create table if not exists public.agency_clients (
  id                   uuid primary key default gen_random_uuid(),
  agency_id            uuid not null references companies(id) on delete cascade,
  name                 text not null check (length(trim(name)) between 2 and 120),
  client_company_id    uuid references companies(id) on delete set null,   -- set only when the client confirms
  requested_company_id uuid references companies(id) on delete set null,
  link_status          text not null default 'unlinked'
                       check (link_status in ('unlinked','pending','confirmed','declined')),
  relationship_status  text not null default 'prospect'
                       check (relationship_status in ('prospect','active','on_hold','ended')),
  owner_id             uuid references persons(id) on delete set null,
  industry             text check (industry is null or length(industry) <= 120),
  website              text check (website is null or length(website) <= 300),
  locations            text[] not null default '{}',
  departments          text[] not null default '{}',
  notes                text check (notes is null or length(notes) <= 4000),
  created_by           uuid references persons(id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  check (link_status <> 'confirmed' or client_company_id is not null),
  check (client_company_id is null or client_company_id <> agency_id),
  check (cardinality(locations) <= 50 and cardinality(departments) <= 50)
);
create unique index if not exists agency_clients_linked_key on agency_clients (agency_id, client_company_id)
  where client_company_id is not null;
create index if not exists agency_clients_agency_idx on agency_clients (agency_id, relationship_status);
create index if not exists agency_clients_company_idx on agency_clients (client_company_id) where client_company_id is not null;
create index if not exists agency_clients_requested_idx on agency_clients (requested_company_id) where requested_company_id is not null;

create table if not exists public.agency_client_contacts (
  id          uuid primary key default gen_random_uuid(),
  client_id   uuid not null references agency_clients(id) on delete cascade,
  name        text not null check (length(trim(name)) between 1 and 120),
  title       text check (title is null or length(title) <= 120),
  email       text check (email is null or (length(email) <= 254 and position('@' in email) > 1)),
  phone       text check (phone is null or length(phone) <= 40),
  is_primary  boolean not null default false,
  notes       text check (notes is null or length(notes) <= 1000),
  created_at  timestamptz not null default now()
);
create index if not exists agency_client_contacts_client_idx on agency_client_contacts (client_id);

create or replace function omelo_private.omelo_guard_agency_client()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if omelo_private.omelo_is_privileged() then
    new.updated_at := now();
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.client_company_id := null;
    new.requested_company_id := null;
    new.link_status := 'unlinked';
    new.created_by := auth.uid();
  else
    if new.agency_id is distinct from old.agency_id
    or new.client_company_id is distinct from old.client_company_id
    or new.requested_company_id is distinct from old.requested_company_id
    or new.link_status is distinct from old.link_status
    or new.created_by is distinct from old.created_by then
      raise exception 'Linking a client company goes through the client''s confirmation' using errcode = '42501';
    end if;
  end if;
  if new.owner_id is not null
     and not omelo_private.omelo_person_agency_can(new.owner_id, new.agency_id, 'view') then
    raise exception 'The client owner must be a member of the agency' using errcode = '22023';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists agency_clients_guard on agency_clients;
create trigger agency_clients_guard before insert or update on agency_clients
  for each row execute function omelo_private.omelo_guard_agency_client();

alter table agency_clients enable row level security;
alter table agency_client_contacts enable row level security;
drop policy if exists agency_clients_read on agency_clients;
drop policy if exists agency_clients_insert on agency_clients;
drop policy if exists agency_clients_update on agency_clients;
drop policy if exists agency_clients_delete on agency_clients;
create policy agency_clients_read on agency_clients for select to authenticated
  using (omelo_private.omelo_agency_can(agency_id, 'view'));
create policy agency_clients_insert on agency_clients for insert to authenticated
  with check (omelo_private.omelo_agency_can(agency_id, 'manage_clients'));
create policy agency_clients_update on agency_clients for update to authenticated
  using (omelo_private.omelo_agency_can(agency_id, 'manage_clients'))
  with check (omelo_private.omelo_agency_can(agency_id, 'manage_clients'));
create policy agency_clients_delete on agency_clients for delete to authenticated
  using (omelo_private.omelo_agency_can(agency_id, 'manage_agency'));

drop policy if exists agency_client_contacts_read on agency_client_contacts;
drop policy if exists agency_client_contacts_write on agency_client_contacts;
create policy agency_client_contacts_read on agency_client_contacts for select to authenticated
  using (exists (select 1 from agency_clients ac where ac.id = client_id
                   and omelo_private.omelo_agency_can(ac.agency_id, 'view')));
create policy agency_client_contacts_write on agency_client_contacts for all to authenticated
  using (exists (select 1 from agency_clients ac where ac.id = client_id
                   and omelo_private.omelo_agency_can(ac.agency_id, 'manage_clients')))
  with check (exists (select 1 from agency_clients ac where ac.id = client_id
                        and omelo_private.omelo_agency_can(ac.agency_id, 'manage_clients')));

-- 3. Job orders ----------------------------------------------------------------------
create table if not exists public.job_orders (
  id                   uuid primary key default gen_random_uuid(),
  agency_id            uuid not null references companies(id) on delete cascade,
  client_id            uuid not null references agency_clients(id) on delete cascade,
  reference            text not null check (length(reference) between 1 and 40),
  title                text not null check (length(trim(title)) between 2 and 120),
  profession_id        uuid references professions(id) on delete set null,
  openings             integer not null default 1 check (openings between 1 and 10000),
  location_id          uuid references locations(id) on delete set null,
  location_text        text check (location_text is null or length(location_text) <= 200),
  workplace_type       workplace_type not null default 'onsite',
  work_type            work_type not null default 'full_time',
  shift_types          shift_type[] not null default '{}',
  pay_min              numeric check (pay_min is null or pay_min >= 0),
  pay_max              numeric check (pay_max is null or pay_max >= 0),
  pay_period           pay_period,
  pay_currency         char(3),
  min_experience_months integer check (min_experience_months is null or min_experience_months between 0 and 720),
  required_skill_ids   uuid[] not null default '{}',
  hard_requirements    text[] not null default '{}',
  description          text check (description is null or length(description) <= 8000),
  start_date           date,
  closing_date         date,
  priority             text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  status               text not null default 'open'
                       check (status in ('draft','open','on_hold','filled','closed','cancelled')),
  job_id               uuid not null unique references jobs(id) on delete cascade,  -- private, agency-owned: for matching
  client_job_id        uuid references jobs(id) on delete set null,                  -- the client's job: the pipeline
  notes                text check (notes is null or length(notes) <= 4000),
  created_by           uuid references persons(id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  unique (agency_id, reference),
  check (pay_max is null or pay_min is null or pay_max >= pay_min),
  check (cardinality(required_skill_ids) <= 50 and cardinality(hard_requirements) <= 30)
);
create index if not exists job_orders_agency_idx on job_orders (agency_id, status);
create index if not exists job_orders_client_idx on job_orders (client_id);
create index if not exists job_orders_client_job_idx on job_orders (client_job_id) where client_job_id is not null;

create table if not exists public.job_order_recruiters (
  job_order_id uuid not null references job_orders(id) on delete cascade,
  person_id    uuid not null references persons(id) on delete cascade,
  role         text not null default 'support' check (role in ('lead','support')),
  assigned_by  uuid references persons(id) on delete set null,
  assigned_at  timestamptz not null default now(),
  primary key (job_order_id, person_id)
);
create index if not exists job_order_recruiters_person_idx on job_order_recruiters (person_id);

alter table job_orders enable row level security;
alter table job_order_recruiters enable row level security;
drop policy if exists job_orders_read on job_orders;
create policy job_orders_read on job_orders for select to authenticated
  using (omelo_private.omelo_agency_can(agency_id, 'view'));
drop policy if exists job_order_recruiters_read on job_order_recruiters;
create policy job_order_recruiters_read on job_order_recruiters for select to authenticated
  using (exists (select 1 from job_orders jo where jo.id = job_order_id
                   and omelo_private.omelo_agency_can(jo.agency_id, 'view')));
revoke insert, update, delete on job_orders, job_order_recruiters from anon, authenticated;

-- Apply order fields to the backing job (the matcher's view of the order).
create or replace function omelo_private.omelo_sync_order_job(p_order uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare jo job_orders;
begin
  select * into jo from job_orders where id = p_order;
  update jobs
     set title = jo.title, profession_id = jo.profession_id,
         category_id = (select category_id from professions where id = jo.profession_id),
         location_id = jo.location_id, location_text = jo.location_text,
         workplace_type = jo.workplace_type, work_type = jo.work_type, shift_types = jo.shift_types,
         pay_min = jo.pay_min, pay_max = jo.pay_max, pay_period = jo.pay_period,
         pay_currency = coalesce(jo.pay_currency, pay_currency),
         min_experience_months = jo.min_experience_months,
         accepts_no_experience = coalesce(jo.min_experience_months, 0) = 0,
         start_date = jo.start_date, openings = least(jo.openings, 32767),
         description = jo.description
   where id = jo.job_id;
  delete from job_skills where job_id = jo.job_id and not (skill_id = any (jo.required_skill_ids));
  insert into job_skills (job_id, skill_id, requirement_level)
  select jo.job_id, s, 'required' from unnest(jo.required_skill_ids) s
   where exists (select 1 from skills where id = s)
  on conflict do nothing;
end;
$$;
revoke execute on function omelo_private.omelo_sync_order_job(uuid) from public, anon, authenticated;

-- Parse the editable fields of a job order from JSON into the row.
create or replace function omelo_private.omelo_apply_order_fields(jo job_orders, p jsonb)
returns job_orders
language plpgsql stable
set search_path = public, omelo_private
as $$
begin
  if p ? 'title'             then jo.title := trim(p->>'title'); end if;
  if p ? 'profession_id'     then jo.profession_id := nullif(p->>'profession_id', '')::uuid; end if;
  if p ? 'openings'          then jo.openings := (p->>'openings')::int; end if;
  if p ? 'location_id'       then jo.location_id := nullif(p->>'location_id', '')::uuid; end if;
  if p ? 'location_text'     then jo.location_text := nullif(trim(p->>'location_text'), ''); end if;
  if p ? 'workplace_type'    then jo.workplace_type := (p->>'workplace_type')::workplace_type; end if;
  if p ? 'work_type'         then jo.work_type := (p->>'work_type')::work_type; end if;
  if p ? 'shift_types'       then jo.shift_types := array(select jsonb_array_elements_text(p->'shift_types'))::shift_type[]; end if;
  if p ? 'pay_min'           then jo.pay_min := nullif(p->>'pay_min', '')::numeric; end if;
  if p ? 'pay_max'           then jo.pay_max := nullif(p->>'pay_max', '')::numeric; end if;
  if p ? 'pay_period'        then jo.pay_period := nullif(p->>'pay_period', '')::pay_period; end if;
  if p ? 'pay_currency'      then jo.pay_currency := upper(nullif(p->>'pay_currency', '')); end if;
  if p ? 'min_experience_months' then jo.min_experience_months := nullif(p->>'min_experience_months', '')::int; end if;
  if p ? 'required_skill_ids' then jo.required_skill_ids := array(select jsonb_array_elements_text(p->'required_skill_ids'))::uuid[]; end if;
  if p ? 'hard_requirements' then jo.hard_requirements := array(select trim(x) from jsonb_array_elements_text(p->'hard_requirements') x where length(trim(x)) between 1 and 200); end if;
  if p ? 'description'       then jo.description := nullif(p->>'description', ''); end if;
  if p ? 'start_date'        then jo.start_date := nullif(p->>'start_date', '')::date; end if;
  if p ? 'closing_date'      then jo.closing_date := nullif(p->>'closing_date', '')::date; end if;
  if p ? 'priority'          then jo.priority := p->>'priority'; end if;
  if p ? 'status'            then jo.status := p->>'status'; end if;
  if p ? 'notes'             then jo.notes := nullif(p->>'notes', ''); end if;
  return jo;
end;
$$;
revoke execute on function omelo_private.omelo_apply_order_fields(job_orders, jsonb) from public, anon, authenticated;

create or replace function public.omelo_create_job_order(p_client uuid, p_order jsonb)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare cl agency_clients; jo job_orders; v_job uuid;
begin
  select * into cl from agency_clients where id = p_client;
  if cl.id is null or not omelo_private.omelo_agency_can(cl.agency_id, 'create_job_order') then
    raise exception 'Only the agency''s recruiters can create job orders' using errcode = '42501';
  end if;
  if cl.relationship_status = 'ended' then
    raise exception 'This client relationship has ended' using errcode = '22023';
  end if;
  jo.id := gen_random_uuid();
  jo.agency_id := cl.agency_id;
  jo.client_id := cl.id;
  jo.openings := 1; jo.workplace_type := 'onsite'; jo.work_type := 'full_time'; jo.shift_types := '{}';
  jo.required_skill_ids := '{}'; jo.hard_requirements := '{}'; jo.priority := 'normal'; jo.status := 'open';
  begin
    jo := omelo_private.omelo_apply_order_fields(jo, coalesce(p_order, '{}'::jsonb));
  exception when others then
    raise exception 'Check the job order details: %', sqlerrm using errcode = '22023';
  end;
  if jo.title is null then raise exception 'Give the job order a title' using errcode = '22023'; end if;
  jo.reference := coalesce(nullif(trim(p_order->>'reference'), ''),
                           'JO-' || (1001 + (select count(*) from job_orders where agency_id = cl.agency_id))::text);

  insert into jobs (company_id, created_by, title, status, workplace_type, work_type, pay_currency)
  values (cl.agency_id, auth.uid(), jo.title, 'draft', jo.workplace_type, jo.work_type, coalesce(jo.pay_currency, 'INR'))
  returning id into v_job;
  jo.job_id := v_job;
  jo.created_by := auth.uid();
  jo.created_at := now(); jo.updated_at := now();
  insert into job_orders select jo.*;
  insert into job_order_recruiters (job_order_id, person_id, role, assigned_by)
  values (jo.id, auth.uid(), 'lead', auth.uid());
  perform omelo_private.omelo_sync_order_job(jo.id);
  perform omelo_private.omelo_emit('JobOrderCreated', 'job_order', jo.id, cl.agency_id, null,
    jsonb_build_object('client_id', cl.id, 'openings', jo.openings));
  return jo.id;
end;
$$;

create or replace function public.omelo_update_job_order(p_order uuid, p_changes jsonb)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare jo job_orders; v_old text;
begin
  select * into jo from job_orders where id = p_order;
  if jo.id is null or not omelo_private.omelo_agency_can(jo.agency_id, 'create_job_order')
     or not (omelo_private.omelo_agency_can(jo.agency_id, 'manage_agency')
             or exists (select 1 from job_order_recruiters where job_order_id = jo.id and person_id = auth.uid())) then
    raise exception 'Only the agency''s admins or recruiters on this order can change it' using errcode = '42501';
  end if;
  v_old := jo.status;
  begin
    jo := omelo_private.omelo_apply_order_fields(jo, coalesce(p_changes, '{}'::jsonb) - 'reference');
  exception when others then
    raise exception 'Check the job order details: %', sqlerrm using errcode = '22023';
  end;
  update job_orders set
    title = jo.title, profession_id = jo.profession_id, openings = jo.openings, location_id = jo.location_id,
    location_text = jo.location_text, workplace_type = jo.workplace_type, work_type = jo.work_type,
    shift_types = jo.shift_types, pay_min = jo.pay_min, pay_max = jo.pay_max, pay_period = jo.pay_period,
    pay_currency = jo.pay_currency, min_experience_months = jo.min_experience_months,
    required_skill_ids = jo.required_skill_ids, hard_requirements = jo.hard_requirements,
    description = jo.description, start_date = jo.start_date, closing_date = jo.closing_date,
    priority = jo.priority, status = jo.status, notes = jo.notes, updated_at = now()
  where id = jo.id;
  perform omelo_private.omelo_sync_order_job(jo.id);
  if jo.status is distinct from v_old then
    perform omelo_private.omelo_emit('JobOrderStatusChanged', 'job_order', jo.id, jo.agency_id, null,
      jsonb_build_object('from', v_old, 'to', jo.status));
  end if;
end;
$$;

create or replace function public.omelo_assign_job_order_recruiter(p_order uuid, p_person uuid,
                                                                   p_assign boolean default true, p_role text default 'support')
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare jo job_orders;
begin
  select * into jo from job_orders where id = p_order;
  if jo.id is null or not (omelo_private.omelo_agency_can(jo.agency_id, 'manage_agency')
       or exists (select 1 from job_order_recruiters where job_order_id = jo.id and person_id = auth.uid() and role = 'lead')) then
    raise exception 'Only agency admins or the lead recruiter can assign recruiters' using errcode = '42501';
  end if;
  if p_assign then
    if not omelo_private.omelo_person_agency_can(p_person, jo.agency_id, 'request_consent') then
      raise exception 'Only agency recruiters and sourcers can be assigned to a job order' using errcode = '22023';
    end if;
    insert into job_order_recruiters (job_order_id, person_id, role, assigned_by)
    values (jo.id, p_person, case when p_role = 'lead' then 'lead' else 'support' end, auth.uid())
    on conflict (job_order_id, person_id) do update set role = excluded.role;
  else
    delete from job_order_recruiters where job_order_id = jo.id and person_id = p_person;
  end if;
end;
$$;

-- 4. Consent ---------------------------------------------------------------------------
create table if not exists public.candidate_consents (
  id                 uuid primary key default gen_random_uuid(),
  person_id          uuid not null references persons(id) on delete cascade,
  work_identity_id   uuid not null references work_identities(id) on delete cascade,
  agency_id          uuid not null references companies(id) on delete cascade,
  recruiter_id       uuid references persons(id) on delete set null,
  job_order_id       uuid not null references job_orders(id) on delete cascade,
  client_id          uuid not null references agency_clients(id) on delete cascade,
  purpose            text not null default 'submission' check (purpose in ('submission')),
  information_scope  text[] not null
                     check (information_scope <@ array['identity','skills','experience','evidence','answers','contact']
                            and 'identity' = any (information_scope)),
  terms              jsonb not null,
  message            text check (message is null or length(message) <= 1000),
  status             text not null default 'requested'
                     check (status in ('requested','accepted','active','declined','expired','revoked','withdrawn')),
  valid_days         integer not null default 60 check (valid_days between 7 and 180),
  requested_at       timestamptz not null default now(),
  request_expires_at timestamptz not null default now() + interval '7 days',
  responded_at       timestamptz,
  expires_at         timestamptz,
  revoked_at         timestamptz,
  decline_reason     text check (decline_reason is null or length(decline_reason) <= 300),
  revoke_reason      text check (revoke_reason is null or length(revoke_reason) <= 300),
  updated_at         timestamptz not null default now(),
  check (status not in ('accepted','active') or expires_at is not null)
);
create unique index if not exists candidate_consents_one_open on candidate_consents (person_id, job_order_id)
  where status in ('requested','accepted','active');
create index if not exists candidate_consents_person_idx on candidate_consents (person_id, requested_at desc);
create index if not exists candidate_consents_agency_idx on candidate_consents (agency_id, status, requested_at desc);
create index if not exists candidate_consents_order_idx on candidate_consents (job_order_id, status);
create index if not exists candidate_consents_identity_idx on candidate_consents (work_identity_id);

create table if not exists public.candidate_consent_events (
  id           bigint generated always as identity primary key,
  consent_id   uuid not null references candidate_consents(id) on delete cascade,
  from_status  text,
  to_status    text not null,
  actor_id     uuid references persons(id) on delete set null,
  actor_type   text not null check (actor_type in ('candidate','recruiter','system')),
  reason       text,
  occurred_at  timestamptz not null default now()
);
create index if not exists candidate_consent_events_consent_idx on candidate_consent_events (consent_id, occurred_at);

-- The lifecycle and the scope are enforced for every writer, service_role included.
create or replace function omelo_private.omelo_validate_consent()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare jo job_orders;
begin
  if tg_op = 'INSERT' then
    if new.status <> 'requested' then
      raise exception 'A consent starts as a request to the candidate' using errcode = '23514';
    end if;
    if not exists (select 1 from work_identities where id = new.work_identity_id and person_id = new.person_id) then
      raise exception 'The identity does not belong to this candidate' using errcode = '23514';
    end if;
    select * into jo from job_orders where id = new.job_order_id;
    if jo.agency_id is distinct from new.agency_id or jo.client_id is distinct from new.client_id then
      raise exception 'The consent must name the job order''s own agency and client' using errcode = '23514';
    end if;
    new.expires_at := null;
    new.responded_at := null;
    new.revoked_at := null;
    return new;
  end if;

  if new.person_id is distinct from old.person_id or new.work_identity_id is distinct from old.work_identity_id
  or new.agency_id is distinct from old.agency_id or new.recruiter_id is distinct from old.recruiter_id
  or new.job_order_id is distinct from old.job_order_id or new.client_id is distinct from old.client_id
  or new.purpose is distinct from old.purpose or new.information_scope is distinct from old.information_scope
  or new.terms is distinct from old.terms or new.valid_days is distinct from old.valid_days
  or new.requested_at is distinct from old.requested_at or new.message is distinct from old.message then
    raise exception 'The terms of a consent cannot change; ask for a new one' using errcode = '23514';
  end if;
  if new.status is distinct from old.status and not (
       (old.status = 'requested' and new.status in ('accepted','declined','expired','withdrawn'))
    or (old.status = 'accepted'  and new.status in ('active','expired','revoked'))
    or (old.status = 'active'    and new.status in ('expired','revoked'))) then
    raise exception 'A consent cannot go from % to %', old.status, new.status using errcode = '23514';
  end if;
  if new.status = 'accepted' and old.status = 'requested' and old.request_expires_at <= now() then
    raise exception 'This request has expired' using errcode = '23514';
  end if;
  if new.status is distinct from old.status and old.status = 'requested' and new.status = 'accepted' then
    new.expires_at := now() + make_interval(days => new.valid_days);
  end if;
  if new.status in ('accepted','declined') and old.status = 'requested' then
    new.responded_at := now();
  end if;
  if new.status = 'revoked' and old.status <> 'revoked' then
    new.revoked_at := now();
  end if;
  new.updated_at := now();
  return new;
end;
$$;
revoke execute on function omelo_private.omelo_validate_consent() from public, anon, authenticated;
drop trigger if exists candidate_consents_validate on candidate_consents;
create trigger candidate_consents_validate before insert or update on candidate_consents
  for each row execute function omelo_private.omelo_validate_consent();

create or replace function omelo_private.omelo_log_consent_event()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_from text; v_actor uuid := auth.uid();
begin
  if tg_op = 'UPDATE' then
    if new.status is not distinct from old.status then return null; end if;
    v_from := old.status;
  end if;
  insert into candidate_consent_events (consent_id, from_status, to_status, actor_id, actor_type, reason)
  values (new.id, v_from, new.status, v_actor,
          case when v_actor is null then 'system' when v_actor = new.person_id then 'candidate' else 'recruiter' end,
          case new.status when 'declined' then new.decline_reason when 'revoked' then new.revoke_reason end);
  perform omelo_private.omelo_emit(
    case new.status when 'requested' then 'RepresentationRequested' when 'accepted' then 'RepresentationGranted'
                    when 'active' then 'RepresentationActivated' when 'declined' then 'RepresentationDeclined'
                    when 'expired' then 'RepresentationExpired' when 'revoked' then 'RepresentationRevoked'
                    else 'RepresentationWithdrawn' end,
    'candidate_consent', new.id, new.agency_id, new.person_id,
    jsonb_build_object('job_order_id', new.job_order_id, 'from', v_from, 'to', new.status));
  return null;
end;
$$;
revoke execute on function omelo_private.omelo_log_consent_event() from public, anon, authenticated;
drop trigger if exists candidate_consents_log on candidate_consents;
create trigger candidate_consents_log after insert or update on candidate_consents
  for each row execute function omelo_private.omelo_log_consent_event();

alter table candidate_consents enable row level security;
alter table candidate_consent_events enable row level security;
drop policy if exists candidate_consents_person on candidate_consents;
drop policy if exists candidate_consents_agency on candidate_consents;
create policy candidate_consents_person on candidate_consents for select to authenticated
  using (person_id = (select auth.uid()));
create policy candidate_consents_agency on candidate_consents for select to authenticated
  using (omelo_private.omelo_agency_can(agency_id, 'view'));
drop policy if exists candidate_consent_events_read on candidate_consent_events;
create policy candidate_consent_events_read on candidate_consent_events for select to authenticated
  using (exists (select 1 from candidate_consents c where c.id = consent_id
                   and (c.person_id = (select auth.uid()) or omelo_private.omelo_agency_can(c.agency_id, 'view'))));
revoke insert, update, delete on candidate_consents, candidate_consent_events from anon, authenticated;

-- 5. Submissions -----------------------------------------------------------------------
create table if not exists public.candidate_submissions (
  id                uuid primary key default gen_random_uuid(),
  consent_id        uuid not null references candidate_consents(id) on delete cascade,
  person_id         uuid not null references persons(id) on delete cascade,
  work_identity_id  uuid not null references work_identities(id) on delete cascade,
  agency_id         uuid not null references companies(id) on delete cascade,
  recruiter_id      uuid references persons(id) on delete set null,
  client_id         uuid not null references agency_clients(id) on delete cascade,
  job_order_id      uuid not null references job_orders(id) on delete cascade,
  application_id    uuid unique references applications(id) on delete set null,
  snapshot          jsonb not null,
  status            text not null default 'submitted'
                    check (status in ('submitted','reviewing','shortlisted','interview','offer','hired','rejected','withdrawn')),
  recruiter_note    text check (recruiter_note is null or length(recruiter_note) <= 2000),
  client_response   text check (client_response is null or length(client_response) <= 2000),
  rejection_reason  text,
  submitted_at      timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (job_order_id, person_id),
  unique (consent_id)
);
create index if not exists candidate_submissions_agency_idx on candidate_submissions (agency_id, status, submitted_at desc);
create index if not exists candidate_submissions_person_idx on candidate_submissions (person_id);
create index if not exists candidate_submissions_order_idx on candidate_submissions (job_order_id);

create table if not exists public.candidate_submission_events (
  id             bigint generated always as identity primary key,
  submission_id  uuid not null references candidate_submissions(id) on delete cascade,
  from_status    text,
  to_status      text not null,
  actor_id       uuid references persons(id) on delete set null,
  reason         text,
  occurred_at    timestamptz not null default now()
);
create index if not exists candidate_submission_events_sub_idx on candidate_submission_events (submission_id, occurred_at);

-- R4-001..005: runs for every writer, service_role included.
create or replace function omelo_private.omelo_validate_submission()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare c candidate_consents;
begin
  if tg_op = 'INSERT' then
    select * into c from candidate_consents where id = new.consent_id for update;
    if c.id is null then
      raise exception 'A submission needs the candidate''s consent' using errcode = '23514';
    end if;
    if c.status <> 'accepted' then
      raise exception 'The candidate has not given consent for this submission (consent is %)', c.status using errcode = '23514';
    end if;
    if c.expires_at is null or c.expires_at <= now() then
      raise exception 'This consent has expired' using errcode = '23514';
    end if;
    if new.person_id is distinct from c.person_id or new.work_identity_id is distinct from c.work_identity_id
    or new.agency_id is distinct from c.agency_id or new.job_order_id is distinct from c.job_order_id
    or new.client_id is distinct from c.client_id then
      raise exception 'A submission must match its consent exactly (candidate, identity, agency, client, job order)'
        using errcode = '23514';
    end if;
    if new.recruiter_id is null
       or not omelo_private.omelo_person_agency_can(new.recruiter_id, new.agency_id, 'submit')
       or not (omelo_private.omelo_person_agency_can(new.recruiter_id, new.agency_id, 'manage_agency')
               or exists (select 1 from job_order_recruiters r
                           where r.job_order_id = new.job_order_id and r.person_id = new.recruiter_id)) then
      raise exception 'Only a recruiter assigned to this job order can submit to it' using errcode = '23514';
    end if;
    new.status := 'submitted';
    new.submitted_at := now();
    new.updated_at := now();
    new.application_id := null;
    return new;
  end if;

  if new.consent_id is distinct from old.consent_id or new.person_id is distinct from old.person_id
  or new.work_identity_id is distinct from old.work_identity_id or new.agency_id is distinct from old.agency_id
  or new.recruiter_id is distinct from old.recruiter_id or new.client_id is distinct from old.client_id
  or new.job_order_id is distinct from old.job_order_id or new.snapshot is distinct from old.snapshot
  or new.submitted_at is distinct from old.submitted_at then
    raise exception 'What was submitted cannot be changed' using errcode = '23514';
  end if;
  if old.application_id is not null and new.application_id is distinct from old.application_id
     and new.application_id is not null then
    raise exception 'A submission belongs to one application' using errcode = '23514';
  end if;
  if new.status is distinct from old.status and old.status in ('hired','rejected','withdrawn') then
    raise exception 'This submission is closed (%)', old.status using errcode = '23514';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
revoke execute on function omelo_private.omelo_validate_submission() from public, anon, authenticated;
drop trigger if exists candidate_submissions_validate on candidate_submissions;
create trigger candidate_submissions_validate before insert or update on candidate_submissions
  for each row execute function omelo_private.omelo_validate_submission();

create or replace function omelo_private.omelo_after_submission()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_from text; v_title text;
begin
  if tg_op = 'INSERT' then
    update candidate_consents set status = 'active' where id = new.consent_id and status = 'accepted';
  else
    if new.status is not distinct from old.status then return null; end if;
    v_from := old.status;
  end if;
  insert into candidate_submission_events (submission_id, from_status, to_status, actor_id, reason)
  values (new.id, v_from, new.status, auth.uid(),
          case new.status when 'rejected' then new.rejection_reason else new.client_response end);
  perform omelo_private.omelo_emit(case when tg_op = 'INSERT' then 'CandidateSubmitted' else 'SubmissionStatusChanged' end,
    'candidate_submission', new.id, new.agency_id, new.person_id,
    jsonb_build_object('job_order_id', new.job_order_id, 'from', v_from, 'to', new.status,
                       'application_id', new.application_id));
  if tg_op = 'UPDATE' and new.recruiter_id is not null and new.status <> 'withdrawn' then
    select title into v_title from job_orders where id = new.job_order_id;
    perform omelo_private.omelo_notify(new.recruiter_id, 'representation_update'::notification_type,
      'Submission update: ' || initcap(new.status),
      coalesce(new.snapshot->'identity'->>'name', 'Your candidate') || ' · ' || coalesce(v_title, ''),
      'candidate_submission', new.id, '/dashboard/agency/submissions');
  end if;
  return null;
end;
$$;
revoke execute on function omelo_private.omelo_after_submission() from public, anon, authenticated;
drop trigger if exists candidate_submissions_after on candidate_submissions;
create trigger candidate_submissions_after after insert or update on candidate_submissions
  for each row execute function omelo_private.omelo_after_submission();

alter table candidate_submissions enable row level security;
alter table candidate_submission_events enable row level security;
drop policy if exists candidate_submissions_agency on candidate_submissions;
drop policy if exists candidate_submissions_person on candidate_submissions;
drop policy if exists candidate_submissions_client on candidate_submissions;
create policy candidate_submissions_agency on candidate_submissions for select to authenticated
  using (omelo_private.omelo_agency_can(agency_id, 'view'));
create policy candidate_submissions_person on candidate_submissions for select to authenticated
  using (person_id = (select auth.uid()));
create policy candidate_submissions_client on candidate_submissions for select to authenticated
  using (application_id is not null and exists (select 1 from applications a where a.id = application_id
                                                  and omelo_private.omelo_can_access_job(a.job_id)));
drop policy if exists candidate_submission_events_read on candidate_submission_events;
create policy candidate_submission_events_read on candidate_submission_events for select to authenticated
  using (exists (select 1 from candidate_submissions s where s.id = submission_id
                   and (s.person_id = (select auth.uid()) or omelo_private.omelo_agency_can(s.agency_id, 'view'))));
revoke insert, update, delete on candidate_submissions, candidate_submission_events from anon, authenticated;

-- 6. Placements --------------------------------------------------------------------------
create table if not exists public.placements (
  id                uuid primary key default gen_random_uuid(),
  submission_id     uuid not null unique references candidate_submissions(id) on delete cascade,
  agency_id         uuid not null references companies(id) on delete cascade,
  client_id         uuid not null references agency_clients(id) on delete cascade,
  job_order_id      uuid not null references job_orders(id) on delete cascade,
  person_id         uuid not null references persons(id) on delete cascade,
  application_id    uuid references applications(id) on delete set null,
  employment_id     uuid references employments(id) on delete set null,
  title             text,
  start_date        date,
  status            text not null default 'pending_start'
                    check (status in ('pending_start','active','completed','fell_through')),
  guarantee_ends_on date,
  fee_amount        numeric check (fee_amount is null or fee_amount >= 0),
  fee_currency      char(3),
  notes             text check (notes is null or length(notes) <= 2000),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index if not exists placements_agency_idx on placements (agency_id, status);
create index if not exists placements_order_idx on placements (job_order_id);
create index if not exists placements_person_idx on placements (person_id);
alter table placements enable row level security;
drop policy if exists placements_agency on placements;
drop policy if exists placements_person on placements;
create policy placements_agency on placements for select to authenticated
  using (omelo_private.omelo_agency_can(agency_id, 'view'));
create policy placements_person on placements for select to authenticated
  using (person_id = (select auth.uid()));
revoke insert, update, delete on placements from anon, authenticated;

create or replace function omelo_private.omelo_create_placement(p_submission uuid, p_start date)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare s candidate_submissions; v_id uuid; jo job_orders;
begin
  select * into s from candidate_submissions where id = p_submission;
  select * into jo from job_orders where id = s.job_order_id;
  insert into placements (submission_id, agency_id, client_id, job_order_id, person_id, application_id,
                          employment_id, title, start_date, guarantee_ends_on)
  values (s.id, s.agency_id, s.client_id, s.job_order_id, s.person_id, s.application_id,
          (select e.id from employments e where e.application_id = s.application_id limit 1),
          jo.title, p_start, coalesce(p_start, current_date) + 90)
  on conflict (submission_id) do nothing
  returning id into v_id;
  if v_id is not null then
    perform omelo_private.omelo_emit('PlacementMade', 'placement', v_id, s.agency_id, s.person_id,
      jsonb_build_object('job_order_id', s.job_order_id, 'submission_id', s.id));
    if (select count(*) from placements where job_order_id = jo.id and status <> 'fell_through') >= jo.openings then
      update job_orders set status = 'filled', updated_at = now() where id = jo.id and status in ('open','on_hold');
    end if;
  end if;
  return v_id;
end;
$$;
revoke execute on function omelo_private.omelo_create_placement(uuid, date) from public, anon, authenticated;

-- 7. The client's pipeline stays the source of truth: mirror it -----------------------
create or replace function omelo_private.omelo_mirror_submission_from_application()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_status text; s candidate_submissions;
begin
  if new.state is not distinct from old.state then return null; end if;
  select * into s from candidate_submissions where application_id = new.id;
  if s.id is null then return null; end if;
  v_status := case new.state::text
    when 'viewed' then 'reviewing' when 'shortlisted' then 'shortlisted' when 'screening' then 'shortlisted'
    when 'assessment' then 'shortlisted' when 'interview' then 'interview' when 'offer' then 'offer'
    when 'hired' then 'hired' when 'rejected' then 'rejected' when 'expired' then 'rejected'
    when 'withdrawn' then 'withdrawn' when 'declined_by_candidate' then 'withdrawn' else null end;
  if v_status is not null and v_status is distinct from s.status and s.status not in ('hired','rejected','withdrawn') then
    update candidate_submissions
       set status = v_status,
           rejection_reason = case when v_status = 'rejected' then new.rejection_reason else rejection_reason end
     where id = s.id;
  end if;
  if v_status = 'hired' then
    perform omelo_private.omelo_create_placement(s.id,
      (select o.start_date from offers o where o.application_id = new.id and o.status = 'accepted'
        order by o.responded_at desc nulls last limit 1));
  end if;
  return null;
end;
$$;
revoke execute on function omelo_private.omelo_mirror_submission_from_application() from public, anon, authenticated;
drop trigger if exists applications_mirror_submission on applications;
create trigger applications_mirror_submission after update of state on applications
  for each row execute function omelo_private.omelo_mirror_submission_from_application();

create or replace function omelo_private.omelo_link_placement_employment()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if new.application_id is not null then
    update placements set employment_id = new.id, updated_at = now()
     where application_id = new.application_id and employment_id is null;
  end if;
  return null;
end;
$$;
revoke execute on function omelo_private.omelo_link_placement_employment() from public, anon, authenticated;
drop trigger if exists employments_link_placement on employments;
create trigger employments_link_placement after insert on employments
  for each row execute function omelo_private.omelo_link_placement_employment();

-- 8. Visibility: consent opens a window; a narrowed scope keeps the client on the snapshot
create or replace function omelo_private.omelo_can_view_identity(p_identity uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select exists (
           select 1 from applications a
            where a.work_identity_id = p_identity
              and (omelo_private.omelo_can_access_job(a.job_id)
                   or exists (select 1 from interviews i
                                join interview_interviewers ii on ii.interview_id = i.id and ii.person_id = (select auth.uid())
                                join company_members cm on cm.company_id = i.company_id and cm.person_id = (select auth.uid()) and cm.is_active
                               where i.application_id = a.id and i.status <> 'cancelled'))
              and not exists (select 1 from candidate_submissions s join candidate_consents c on c.id = s.consent_id
                               where s.application_id = a.id
                                 and not (c.information_scope @> array['identity','skills','experience','evidence','answers'])))
      or exists (
           select 1 from company_members cm
            where cm.person_id = (select auth.uid()) and cm.is_active
              and cm.role in ('owner','admin','recruiter')
              and omelo_private.omelo_is_identity_discoverable_to(p_identity, cm.company_id))
      or exists (
           select 1 from candidate_consents c
            where c.work_identity_id = p_identity
              and (c.status = 'active' or (c.status = 'accepted' and c.expires_at > now()))
              and c.information_scope @> array['identity','skills','experience','evidence','answers']
              and omelo_private.omelo_agency_can(c.agency_id, 'view_candidate_details'));
$$;

-- Pools: sourcers may save candidates they can find; saving grants nothing (R4-009)
create or replace function omelo_private.omelo_guard_pool_member()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if omelo_private.omelo_is_privileged() then
    return new;
  end if;
  if new.work_identity_id is null then
    raise exception 'Choose which work identity to save' using errcode = '22023';
  end if;
  if not exists (select 1 from work_identities where id = new.work_identity_id and person_id = new.person_id) then
    raise exception 'That work identity does not belong to this person' using errcode = '22023';
  end if;
  if not (omelo_private.omelo_can_view_identity(new.work_identity_id)
          or exists (select 1 from talent_pools tp
                      where tp.id = new.pool_id
                        and omelo_private.omelo_agency_can(tp.company_id, 'search_talent')
                        and omelo_private.omelo_is_identity_discoverable_to(new.work_identity_id, tp.company_id))) then
    raise exception 'You can only save candidates who are visible to your company' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' then
    new.added_by := auth.uid();
    new.added_at := now();
  end if;
  if new.note is not null and length(new.note) > 500 then
    raise exception 'Keep the note under 500 characters' using errcode = '22023';
  end if;
  return new;
end;
$$;

-- 9. Talent search: one core, used by R3 (jobs) and R4 (job orders) ----------------------
create or replace function omelo_private.omelo_talent_search_core(
  p_job_id uuid, p_company uuid, p_filters jsonb, p_limit integer, p_offset integer, p_job_order uuid default null)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private, extensions
as $$
declare
  j jobs; f jsonb := coalesce(p_filters, '{}'::jsonb);
  v_q text; v_like text; v_radius int; v_prof uuid; v_skills uuid[] := '{}'; v_avail text[]; v_work text[];
  v_min_exp int; v_max_exp int; v_max_pay numeric; v_verified boolean; v_auth text; v_consent text;
  v_prev boolean; v_pool uuid;
  c record; r jsonb; v_found jsonb := '[]'::jsonb; v_page jsonb; v_total int;
  v_limit int := greatest(1, least(coalesce(p_limit, 25), 50));
  v_offset int := greatest(0, least(coalesce(p_offset, 0), 500));
begin
  select * into j from jobs where id = p_job_id;
  begin
    v_q := nullif(trim(coalesce(f->>'query', '')), '');
    v_radius := greatest(1, least(coalesce(nullif(f->>'radius_km', '')::int, 50), 500));
    v_prof := nullif(f->>'profession_id', '')::uuid;
    if jsonb_typeof(f->'skill_ids') = 'array' then
      v_skills := array(select jsonb_array_elements_text(f->'skill_ids'))::uuid[];
    end if;
    if jsonb_typeof(f->'availability') = 'array' and jsonb_array_length(f->'availability') > 0 then
      v_avail := array(select jsonb_array_elements_text(f->'availability'));
    end if;
    if jsonb_typeof(f->'work_types') = 'array' and jsonb_array_length(f->'work_types') > 0 then
      v_work := array(select jsonb_array_elements_text(f->'work_types'));
      perform v_work::work_type[];
    end if;
    v_min_exp := nullif(f->>'min_experience_months', '')::int;
    v_max_exp := nullif(f->>'max_experience_months', '')::int;
    v_max_pay := nullif(f->>'max_expected_pay_monthly', '')::numeric;
    v_verified := coalesce(nullif(f->>'verified_only', '')::boolean, false);
    v_auth := upper(nullif(f->>'work_auth_country', ''));
    v_consent := coalesce(nullif(f->>'consent_status', ''), 'any');
    v_prev := nullif(f->>'previous_relationship', '')::boolean;
    v_pool := nullif(f->>'pool_id', '')::uuid;
  exception when others then
    raise exception 'Check the search filters: %', sqlerrm using errcode = '22023';
  end;
  if v_q is not null and length(v_q) > 80 then
    raise exception 'Keep the search under 80 characters' using errcode = '22023';
  end if;
  if v_consent not in ('any','none','requested','accepted','active','declined','expired','revoked') then
    raise exception 'Unknown consent filter %', v_consent using errcode = '22023';
  end if;
  if v_pool is not null and not exists (select 1 from talent_pools where id = v_pool and company_id = p_company) then
    raise exception 'That talent pool belongs to another company' using errcode = '42501';
  end if;
  v_like := case when v_q is not null
                 then '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%' end;

  for c in
    select wi.id, wi.person_id,
           case when j.geo is null or j.workplace_type = 'remote' then null
                else round((least(
                       case when p.geo is not null then st_distance(p.geo, j.geo) end,
                       (select min(st_distance(l.geo, j.geo))
                          from person_location_preferences plp join locations l on l.id = plp.location_id
                         where plp.work_identity_id = wi.id and l.geo is not null)) / 1000.0)::numeric, 1)
           end as km,
           pwp.availability::text as availability, pwp.expected_pay_amount, pwp.expected_pay_period,
           pwp.pay_currency as expected_currency
      from work_identities wi
      join persons p on p.id = wi.person_id and p.deleted_at is null
      left join person_work_preferences pwp on pwp.work_identity_id = wi.id
     where wi.status = 'active'
       and wi.discoverability::text <> 'private'
       and wi.person_id <> (select auth.uid())
       and case when v_prof is not null then wi.profession_id = v_prof
                else (wi.profession_id = j.profession_id or wi.category_id = j.category_id) end
       and not exists (select 1 from applications a where a.job_id = j.id and a.person_id = wi.person_id)
       and (v_like is null
            or wi.label ilike v_like or wi.headline ilike v_like
            or exists (select 1 from person_skills ps join skills s on s.id = ps.skill_id
                        where ps.person_id = wi.person_id
                          and (ps.work_identity_id = wi.id or ps.work_identity_id is null)
                          and s.name ilike v_like))
       and (cardinality(v_skills) = 0
            or (select count(distinct ps.skill_id) from person_skills ps
                 where ps.person_id = wi.person_id and (ps.work_identity_id = wi.id or ps.work_identity_id is null)
                   and ps.skill_id = any (v_skills)) = cardinality(v_skills))
       and (v_min_exp is null or coalesce(wi.total_experience_months, 0) >= v_min_exp)
       and (v_max_exp is null or coalesce(wi.total_experience_months, 0) <= v_max_exp)
       and (v_avail is null or pwp.availability::text = any (v_avail))
       and (v_work is null or pwp.work_types && v_work::work_type[])
       and (v_max_pay is null or pwp.expected_pay_amount is null
            or public.omelo_pay_monthly(pwp.expected_pay_amount, pwp.expected_pay_period, p.country_code) <= v_max_pay)
       and (not v_verified
            or exists (select 1 from experiences x where x.person_id = wi.person_id and x.is_verified)
            or exists (select 1 from person_skills ps where ps.person_id = wi.person_id and ps.is_verified))
       and (v_auth is null
            or p.country_code = v_auth
            or exists (select 1 from work_authorizations wa
                        where wa.person_id = wi.person_id and wa.country_code = v_auth
                          and wa.status::text in ('citizen','permanent_resident','work_permit','dependent_visa_work_rights')
                          and (wa.expires_on is null or wa.expires_on >= current_date)))
       and (v_pool is null or exists (select 1 from talent_pool_members m where m.pool_id = v_pool and m.person_id = wi.person_id))
       and (v_prev is null or v_prev = exists (select 1 from candidate_consents cc
                                                where cc.person_id = wi.person_id and cc.agency_id = p_company))
       and (v_consent = 'any' or p_job_order is null
            or case when v_consent = 'none'
                    then not exists (select 1 from candidate_consents cc where cc.job_order_id = p_job_order
                                        and cc.person_id = wi.person_id)
                    else exists (select 1 from candidate_consents cc where cc.job_order_id = p_job_order
                                    and cc.person_id = wi.person_id and cc.status = v_consent) end)
     order by (wi.profession_id is not distinct from coalesce(v_prof, j.profession_id)) desc,
              wi.completeness_score desc, p.last_active_at desc nulls last
     limit 150
  loop
    continue when c.km is not null and c.km > v_radius;
    r := omelo_private.omelo_store_match(c.id, j.id);
    continue when not omelo_private.omelo_is_identity_discoverable_to(c.id, p_company);
    v_found := v_found || jsonb_build_array(
      omelo_private.omelo_talent_card(c.id, j.id, p_company)
      || jsonb_build_object(
           'distance_km', c.km,
           'score', (r->>'score')::int, 'eligible', (r->>'eligible')::boolean,
           'strengths', coalesce(r->'strengths', '[]'::jsonb),
           'gaps', coalesce(r->'gaps', '[]'::jsonb),
           'availability', c.availability,
           'expected_pay', case when c.expected_pay_amount is not null then jsonb_build_object(
                             'amount', c.expected_pay_amount, 'period', c.expected_pay_period,
                             'currency', c.expected_currency) end,
           'verified_employers', (select count(distinct coalesce(x.company_id::text, lower(x.employer_name)))
                                    from experiences x where x.person_id = c.person_id and x.is_verified),
           'employer_confirmed_skills', (select count(*) from person_skills ps
                                          where ps.person_id = c.person_id and ps.is_verified
                                            and (ps.work_identity_id = c.id or ps.work_identity_id is null)),
           'accepts_recruiter_requests', (select allow_recruiter_requests from work_identities where id = c.id),
           'previous_relationship', exists (select 1 from candidate_consents cc
                                             where cc.person_id = c.person_id and cc.agency_id = p_company),
           'consent', case when p_job_order is not null then (
                        select jsonb_build_object('id', cc.id,
                                 'status', case when cc.status = 'requested' and cc.request_expires_at <= now() then 'expired'
                                                when cc.status = 'accepted' and cc.expires_at <= now() then 'expired'
                                                else cc.status end)
                          from candidate_consents cc where cc.job_order_id = p_job_order and cc.person_id = c.person_id
                         order by cc.requested_at desc limit 1) end));
  end loop;

  v_total := jsonb_array_length(v_found);
  select coalesce(jsonb_agg(x order by o), '[]'::jsonb) into v_page
    from (select x, row_number() over (order by (x->>'eligible')::boolean desc, (x->>'score')::int desc,
                                                (x->>'distance_km')::numeric asc nulls last) as o
            from jsonb_array_elements(v_found) x) s
   where o > v_offset and o <= v_offset + v_limit;
  return jsonb_build_object('results', v_page, 'total', v_total);
end;
$$;
revoke execute on function omelo_private.omelo_talent_search_core(uuid, uuid, jsonb, integer, integer, uuid) from public, anon, authenticated;

-- R3 search now delegates to the shared core (same contract, same checks).
create or replace function public.omelo_search_talent(
  p_job_id uuid, p_query text default null, p_radius_km integer default 50,
  p_limit integer default 25, p_offset integer default 0)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private, extensions
as $$
declare j jobs; e company_entitlements; v_used int; v jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  select * into j from jobs where id = p_job_id;
  if j.id is null or not omelo_private.omelo_has_company_role(j.company_id, array['owner','admin','recruiter']::company_role[]) then
    raise exception 'Only the hiring team can search for this job' using errcode = '42501';
  end if;
  if j.status <> 'published' then
    raise exception 'Publish the job before searching for candidates' using errcode = '22023';
  end if;
  e := omelo_private.omelo_require_talent_access(j.company_id);
  select count(*) into v_used from domain_events
   where event_type = 'TalentSearched' and company_id = j.company_id and occurred_at >= date_trunc('month', now());
  if e.talent_search_quota_monthly > 0 and v_used >= e.talent_search_quota_monthly then
    raise exception 'Your company has used its % talent searches for this month', e.talent_search_quota_monthly
      using errcode = '22023';
  end if;
  v := omelo_private.omelo_talent_search_core(j.id, j.company_id,
         jsonb_build_object('query', p_query, 'radius_km', p_radius_km), p_limit, p_offset, null);
  perform omelo_private.omelo_emit('TalentSearched', 'job', j.id, j.company_id, auth.uid(),
    jsonb_build_object('query', nullif(trim(coalesce(p_query, '')), ''), 'radius_km', p_radius_km, 'found', v->'total'));
  return v || jsonb_build_object('quota', jsonb_build_object('used', v_used + 1,
                                                             'limit', nullif(e.talent_search_quota_monthly, 0)));
end;
$$;

create or replace function public.omelo_search_talent_for_order(
  p_job_order uuid, p_filters jsonb default '{}'::jsonb, p_limit integer default 25, p_offset integer default 0)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private, extensions
as $$
declare jo job_orders; e company_entitlements; v_used int; v jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  select * into jo from job_orders where id = p_job_order;
  if jo.id is null or not omelo_private.omelo_agency_can(jo.agency_id, 'search_talent') then
    raise exception 'Only the agency''s recruiters and sourcers can search for this job order' using errcode = '42501';
  end if;
  if jo.status not in ('draft','open','on_hold') then
    raise exception 'This job order is %', jo.status using errcode = '22023';
  end if;
  e := omelo_private.omelo_require_talent_access(jo.agency_id);
  select count(*) into v_used from domain_events
   where event_type = 'TalentSearched' and company_id = jo.agency_id and occurred_at >= date_trunc('month', now());
  if e.talent_search_quota_monthly > 0 and v_used >= e.talent_search_quota_monthly then
    raise exception 'Your agency has used its % talent searches for this month', e.talent_search_quota_monthly
      using errcode = '22023';
  end if;
  v := omelo_private.omelo_talent_search_core(jo.job_id, jo.agency_id, p_filters, p_limit, p_offset, jo.id);
  perform omelo_private.omelo_emit('TalentSearched', 'job_order', jo.id, jo.agency_id, auth.uid(),
    jsonb_build_object('filters', coalesce(p_filters, '{}'::jsonb), 'found', v->'total'));
  return v || jsonb_build_object('quota', jsonb_build_object('used', v_used + 1,
                                                             'limit', nullif(e.talent_search_quota_monthly, 0)));
end;
$$;

-- 10. What a recruiter / client may see of a consented candidate -------------------------
create or replace function omelo_private.omelo_scoped_profile(p_identity uuid, p_scope text[], p_with_contact boolean)
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'identity', jsonb_build_object('work_identity_id', wi.id, 'name', p.display_name, 'label', wi.label,
                                   'profession', pr.name, 'headline', wi.headline, 'about', wi.about,
                                   'experience_months', wi.total_experience_months, 'location_text', p.location_text,
                                   'avatar_url', p.avatar_url),
    'skills', case when 'skills' = any (p_scope) then coalesce((
       select jsonb_agg(jsonb_build_object('name', s.name, 'proficiency', ps.proficiency, 'months_used', ps.months_used,
                                           'verified', ps.is_verified) order by ps.is_verified desc, s.name)
         from person_skills ps join skills s on s.id = ps.skill_id
        where ps.person_id = wi.person_id and (ps.work_identity_id = wi.id or ps.work_identity_id is null)), '[]'::jsonb) end,
    'experience', case when 'experience' = any (p_scope) then coalesce((
       select jsonb_agg(jsonb_build_object('title', x.title, 'employer', x.employer_name, 'started_on', x.started_on,
                                           'ended_on', x.ended_on, 'is_current', x.is_current, 'verified', x.is_verified,
                                           'description', left(x.description, 600))
                        order by x.is_current desc, x.started_on desc nulls last)
         from experiences x
        where x.person_id = wi.person_id and (x.work_identity_id = wi.id or x.work_identity_id is null)), '[]'::jsonb) end,
    'evidence', case when 'evidence' = any (p_scope) then jsonb_build_object(
       'verified_employment', coalesce((select jsonb_agg(jsonb_build_object('employer', x.employer_name, 'title', x.title,
                                                                            'started_on', x.started_on, 'ended_on', x.ended_on))
                                          from experiences x where x.person_id = wi.person_id and x.is_verified), '[]'::jsonb),
       'verified_skills', coalesce((select jsonb_agg(s.name) from person_skills ps join skills s on s.id = ps.skill_id
                                     where ps.person_id = wi.person_id and ps.is_verified
                                       and (ps.work_identity_id = wi.id or ps.work_identity_id is null)), '[]'::jsonb),
       'licences', coalesce((select jsonb_agg(jsonb_build_object('name', coalesce(lt.name, pl.name), 'verified', pl.is_verified,
                                                                 'expires_on', pl.expires_on))
                               from person_licenses pl left join license_types lt on lt.id = pl.license_type_id
                              where pl.person_id = wi.person_id), '[]'::jsonb),
       'email_verified', exists (select 1 from verifications v where v.person_id = wi.person_id
                                   and v.type::text = 'email' and v.status::text = 'verified')) end,
    'answers', case when 'answers' = any (p_scope) then coalesce((
       select jsonb_agg(jsonb_build_object('label', a.label, 'data_type', a.data_type, 'unit', a.unit,
                          'value', coalesce(pa.value_json, to_jsonb(pa.value_text), to_jsonb(pa.value_number),
                                            to_jsonb(pa.value_bool), to_jsonb(pa.value_date))) order by a.position)
         from person_attributes pa join profile_attributes a on a.id = pa.attribute_id
        where pa.work_identity_id = wi.id), '[]'::jsonb) end,
    'contact', case when p_with_contact and 'contact' = any (p_scope)
                    then jsonb_build_object('email', p.email, 'phone', p.phone) end,
    'scope', to_jsonb(p_scope)))
  from work_identities wi
  join persons p on p.id = wi.person_id
  left join professions pr on pr.id = wi.profession_id
  where wi.id = p_identity;
$$;
revoke execute on function omelo_private.omelo_scoped_profile(uuid, text[], boolean) from public, anon, authenticated;

-- 11. Representation: request, respond, revoke ------------------------------------------
create or replace function public.omelo_request_representation(
  p_job_order uuid, p_identity uuid,
  p_scope text[] default array['identity','skills','experience','evidence','answers','contact'],
  p_valid_days integer default 60, p_message text default null)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare
  jo job_orders; cl agency_clients; wi work_identities; e company_entitlements; ag companies;
  v_id uuid; v_msg text := nullif(trim(coalesce(p_message, '')), ''); v_terms jsonb; v_client_name text;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  select * into jo from job_orders where id = p_job_order;
  if jo.id is null or not omelo_private.omelo_agency_can(jo.agency_id, 'request_consent') then
    raise exception 'Only the agency''s recruiters and sourcers can ask for consent' using errcode = '42501';
  end if;
  if jo.status not in ('open','on_hold') then
    raise exception 'This job order is not open' using errcode = '22023';
  end if;
  e := omelo_private.omelo_require_talent_access(jo.agency_id);
  select * into wi from work_identities where id = p_identity;
  if wi.id is null or wi.status <> 'active'
     or not omelo_private.omelo_is_identity_discoverable_to(wi.id, jo.agency_id) then
    raise exception 'This candidate is not visible to your agency' using errcode = '42501';
  end if;
  if not wi.allow_recruiter_requests then
    raise exception 'This candidate is not accepting recruiter requests' using errcode = '22023';
  end if;
  if p_scope is null or not (p_scope <@ array['identity','skills','experience','evidence','answers','contact'])
     or not ('identity' = any (p_scope)) then
    raise exception 'Choose what will be shared (the professional identity is always included)' using errcode = '22023';
  end if;
  if coalesce(p_valid_days, 60) not between 7 and 180 then
    raise exception 'Consent can last between 7 and 180 days' using errcode = '22023';
  end if;
  if v_msg is not null and length(v_msg) > 1000 then
    raise exception 'Keep the message under 1000 characters' using errcode = '22023';
  end if;
  if exists (select 1 from candidate_consents where person_id = wi.person_id and job_order_id = jo.id
              and status in ('requested','accepted','active')) then
    raise exception 'You already asked this candidate about this job order' using errcode = '22023';
  end if;
  if exists (select 1 from candidate_consents where person_id = wi.person_id and job_order_id = jo.id
              and status = 'declined' and responded_at > now() - interval '30 days') then
    raise exception 'The candidate declined this request recently' using errcode = '22023';
  end if;
  if exists (select 1 from candidate_submissions where person_id = wi.person_id and job_order_id = jo.id) then
    raise exception 'This candidate was already submitted to this job order' using errcode = '22023';
  end if;
  if e.outreach_quota_daily > 0 and
     ((select count(*) from candidate_consents where agency_id = jo.agency_id and requested_at > now() - interval '1 day')
    + (select count(*) from candidate_invitations where company_id = jo.agency_id and sent_at > now() - interval '1 day'))
       >= e.outreach_quota_daily then
    raise exception 'Your agency has sent its % requests for today', e.outreach_quota_daily using errcode = '22023';
  end if;
  if (select count(*) from candidate_consents where person_id = wi.person_id
        and requested_at > now() - interval '1 day') >= 5 then
    raise exception 'This candidate has received several recruiter requests today. Try again tomorrow.' using errcode = '22023';
  end if;

  select * into cl from agency_clients where id = jo.client_id;
  select * into ag from companies where id = jo.agency_id;
  v_client_name := coalesce((select display_name from companies where id = cl.client_company_id), cl.name);
  v_terms := jsonb_build_object(
    'agency', jsonb_build_object('id', ag.id, 'name', ag.display_name, 'verified', ag.is_verified,
                                 'independent', ag.is_independent_recruiter, 'logo_url', ag.logo_url),
    'recruiter', jsonb_build_object('id', auth.uid(), 'name', (select display_name from persons where id = auth.uid())),
    'client', jsonb_build_object('name', v_client_name, 'on_omelo', cl.link_status = 'confirmed',
                                 'company_id', case when cl.link_status = 'confirmed' then cl.client_company_id end),
    'position', jo.title, 'reference', jo.reference, 'openings', jo.openings,
    'location', jo.location_text, 'workplace_type', jo.workplace_type, 'work_type', jo.work_type,
    'shift_types', to_jsonb(jo.shift_types),
    'pay', jsonb_build_object('min', jo.pay_min, 'max', jo.pay_max, 'period', jo.pay_period, 'currency', jo.pay_currency),
    'start_date', jo.start_date, 'closing_date', jo.closing_date,
    'hard_requirements', to_jsonb(jo.hard_requirements), 'description', left(jo.description, 1000),
    'identity_label', wi.label);

  insert into candidate_consents (person_id, work_identity_id, agency_id, recruiter_id, job_order_id, client_id,
                                  information_scope, terms, message, valid_days)
  values (wi.person_id, wi.id, jo.agency_id, auth.uid(), jo.id, jo.client_id,
          (select array_agg(distinct x order by x) from unnest(p_scope) x), v_terms, v_msg, coalesce(p_valid_days, 60))
  returning id into v_id;

  perform omelo_private.omelo_notify(wi.person_id, 'representation_request'::notification_type,
    ag.display_name || ' wants to represent you',
    jo.title || ' at ' || v_client_name || coalesce(' · ' || jo.location_text, ''),
    'candidate_consent', v_id, '/representations/' || v_id);
  perform omelo_private.omelo_enqueue_email(wi.person_id, 'representation_request',
    ag.display_name || ' wants to represent you for ' || jo.title,
    v_terms || jsonb_build_object('consent_id', v_id, 'message', v_msg, 'scope', to_jsonb(p_scope),
                                  'valid_days', coalesce(p_valid_days, 60)),
    'consent:' || v_id, now());
  return v_id;
end;
$$;

create or replace function public.omelo_withdraw_representation_request(p_consent uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare c candidate_consents;
begin
  select * into c from candidate_consents where id = p_consent;
  if c.id is null or not omelo_private.omelo_agency_can(c.agency_id, 'request_consent') then
    raise exception 'Request not found' using errcode = '42501';
  end if;
  if c.status <> 'requested' then
    raise exception 'Only an unanswered request can be withdrawn' using errcode = '22023';
  end if;
  update candidate_consents set status = 'withdrawn' where id = c.id;
end;
$$;

create or replace function public.omelo_respond_to_representation(p_consent uuid, p_accept boolean,
                                                                  p_reason text default null)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare c candidate_consents; v_name text;
begin
  select * into c from candidate_consents where id = p_consent and person_id = auth.uid();
  if c.id is null then raise exception 'Request not found' using errcode = '42501'; end if;
  if c.status <> 'requested' then
    raise exception 'You already answered this request' using errcode = '22023';
  end if;
  if c.request_expires_at <= now() then
    update candidate_consents set status = 'expired' where id = c.id;
    raise exception 'This request has expired' using errcode = '22023';
  end if;
  if p_accept then
    update candidate_consents set status = 'accepted' where id = c.id;
  else
    update candidate_consents
       set status = 'declined', decline_reason = left(nullif(trim(coalesce(p_reason, '')), ''), 300)
     where id = c.id;
  end if;
  select display_name into v_name from persons where id = c.person_id;
  if c.recruiter_id is not null then
    perform omelo_private.omelo_notify(c.recruiter_id, 'representation_update'::notification_type,
      coalesce(split_part(v_name, ' ', 1), 'A candidate') || case when p_accept then ' accepted your request' else ' declined your request' end,
      coalesce(c.terms->>'position', '') || ' · ' || coalesce(c.terms->'client'->>'name', ''),
      'candidate_consent', c.id, '/dashboard/agency/candidates');
  end if;
end;
$$;

create or replace function public.omelo_revoke_representation(p_consent uuid, p_reason text default null)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare c candidate_consents; s candidate_submissions;
begin
  select * into c from candidate_consents where id = p_consent and person_id = auth.uid();
  if c.id is null then raise exception 'Representation not found' using errcode = '42501'; end if;
  if c.status not in ('accepted','active') then
    raise exception 'There is nothing to revoke (this representation is %)', c.status using errcode = '22023';
  end if;
  select * into s from candidate_submissions where consent_id = c.id;
  if s.id is not null and s.status not in ('submitted','reviewing','rejected','withdrawn') then
    raise exception 'The employer is already considering you through this agency. To stop, withdraw your application.'
      using errcode = '22023';
  end if;
  if s.id is not null and s.status in ('submitted','reviewing') then
    if s.application_id is not null then
      update applications
         set state = 'withdrawn', closed_at = now(),
             withdrawal_reason = 'The candidate withdrew consent from the recruiting agency'
       where id = s.application_id and state in ('applied','viewed');
    end if;
    update candidate_submissions set status = 'withdrawn', client_response = 'Candidate withdrew consent'
     where id = s.id and status in ('submitted','reviewing');
  end if;
  update candidate_consents
     set status = 'revoked', revoke_reason = left(nullif(trim(coalesce(p_reason, '')), ''), 300)
   where id = c.id;
  if c.recruiter_id is not null then
    perform omelo_private.omelo_notify(c.recruiter_id, 'representation_update'::notification_type,
      'A candidate withdrew consent', coalesce(c.terms->>'position', ''),
      'candidate_consent', c.id, '/dashboard/agency/candidates');
  end if;
end;
$$;

create or replace function public.omelo_my_representations()
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select coalesce(jsonb_agg(x order by (x->>'status' = 'requested') desc, x->>'requested_at' desc), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', c.id, 'terms', c.terms, 'scope', to_jsonb(c.information_scope), 'message', c.message,
      'work_identity_id', c.work_identity_id, 'identity_label', wi.label,
      'requested_at', c.requested_at, 'request_expires_at', c.request_expires_at,
      'responded_at', c.responded_at, 'expires_at', c.expires_at, 'valid_days', c.valid_days,
      'decline_reason', c.decline_reason, 'revoke_reason', c.revoke_reason,
      'status', case when c.status = 'requested' and c.request_expires_at <= now() then 'expired'
                     when c.status = 'accepted' and c.expires_at <= now() then 'expired'
                     else c.status end,
      'can_revoke', c.status in ('accepted','active')
                    and coalesce(s.status, 'submitted') in ('submitted','reviewing','rejected','withdrawn'),
      'submission', case when s.id is null then null else jsonb_build_object(
                      'id', s.id, 'status', s.status, 'submitted_at', s.submitted_at,
                      'application_id', s.application_id) end,
      'placement', (select jsonb_build_object('id', pl.id, 'status', pl.status, 'start_date', pl.start_date)
                      from placements pl where pl.submission_id = s.id)) as x
      from candidate_consents c
      left join work_identities wi on wi.id = c.work_identity_id
      left join candidate_submissions s on s.consent_id = c.id
     where c.person_id = (select auth.uid())
     order by c.requested_at desc
     limit 200) q;
$$;

-- 12. Submission ------------------------------------------------------------------------
create or replace function public.omelo_submit_candidate(p_consent uuid, p_note text default null)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare
  c candidate_consents; jo job_orders; v_sub uuid; v_app uuid; v_snapshot jsonb; v_company uuid;
  v_note text := left(nullif(trim(coalesce(p_note, '')), ''), 2000); v_agency text; m record;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  select * into c from candidate_consents where id = p_consent;
  if c.id is null or not omelo_private.omelo_agency_can(c.agency_id, 'submit') then
    raise exception 'Only the agency''s recruiters can submit candidates' using errcode = '42501';
  end if;
  select * into jo from job_orders where id = c.job_order_id;
  if jo.status <> 'open' then
    raise exception 'This job order is not open' using errcode = '22023';
  end if;
  if not (omelo_private.omelo_agency_can(c.agency_id, 'manage_agency')
          or exists (select 1 from job_order_recruiters where job_order_id = jo.id and person_id = auth.uid())) then
    raise exception 'Only recruiters assigned to this job order can submit to it' using errcode = '42501';
  end if;
  if jo.client_job_id is not null
     and exists (select 1 from applications where job_id = jo.client_job_id and person_id = c.person_id) then
    raise exception 'This candidate has already applied to this job directly' using errcode = '22023';
  end if;
  select display_name into v_agency from companies where id = c.agency_id;

  v_snapshot := omelo_private.omelo_scoped_profile(c.work_identity_id, c.information_scope, true)
    || jsonb_build_object('submitted_via', jsonb_build_object(
         'agency_id', c.agency_id, 'agency', v_agency,
         'recruiter', (select display_name from persons where id = auth.uid()),
         'consent_id', c.id, 'consent_expires_at', c.expires_at, 'job_order', jo.reference,
         'note', v_note, 'submitted_at', now()));

  insert into candidate_submissions (consent_id, person_id, work_identity_id, agency_id, recruiter_id, client_id,
                                     job_order_id, snapshot, recruiter_note)
  values (c.id, c.person_id, c.work_identity_id, c.agency_id, auth.uid(), c.client_id, jo.id, v_snapshot, v_note)
  returning id into v_sub;

  if jo.client_job_id is not null then
    select company_id into v_company from jobs where id = jo.client_job_id;
    insert into applications (job_id, person_id, company_id, work_identity_id, identity_snapshot, applied_via,
                              state, stage_id, cover_note)
    values (jo.client_job_id, c.person_id, v_company, c.work_identity_id, v_snapshot, 'agency',
            'applied', omelo_private.omelo_first_stage(jo.client_job_id, 'applied'), v_note)
    returning id into v_app;
    update candidate_submissions set application_id = v_app where id = v_sub;
    for m in select distinct cm.person_id from company_members cm
              where cm.company_id = v_company and cm.is_active
                and cm.role in ('owner','admin','recruiter','hiring_manager') loop
      perform omelo_private.omelo_notify(m.person_id, 'representation_update'::notification_type,
        v_agency || ' submitted a candidate',
        coalesce(v_snapshot->'identity'->>'label', 'Candidate') || ' for ' || jo.title,
        'application', v_app, '/dashboard/candidates/' || v_app);
    end loop;
  end if;

  perform omelo_private.omelo_notify(c.person_id, 'representation_update'::notification_type,
    v_agency || ' submitted your profile',
    jo.title || ' at ' || coalesce(c.terms->'client'->>'name', 'the client'),
    'candidate_consent', c.id, '/representations/' || c.id);
  return v_sub;
end;
$$;

create or replace function public.omelo_withdraw_submission(p_submission uuid, p_reason text default null)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare s candidate_submissions;
begin
  select * into s from candidate_submissions where id = p_submission;
  if s.id is null or not omelo_private.omelo_agency_can(s.agency_id, 'submit') then
    raise exception 'Submission not found' using errcode = '42501';
  end if;
  if s.status not in ('submitted','reviewing') then
    raise exception 'Only a submission the client has not progressed can be withdrawn' using errcode = '22023';
  end if;
  if s.application_id is not null then
    update applications set state = 'withdrawn', closed_at = now(),
           withdrawal_reason = left(coalesce(nullif(trim(p_reason), ''), 'Withdrawn by the recruiting agency'), 300)
     where id = s.application_id and state in ('applied','viewed');
  end if;
  update candidate_submissions set status = 'withdrawn', client_response = left(nullif(trim(p_reason), ''), 2000)
   where id = s.id and status in ('submitted','reviewing');
end;
$$;

-- Off-platform clients only: the agency records what the client said.
create or replace function public.omelo_record_submission_outcome(p_submission uuid, p_status text,
                                                                  p_note text default null, p_start_date date default null)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare s candidate_submissions;
begin
  select * into s from candidate_submissions where id = p_submission;
  if s.id is null or not (omelo_private.omelo_agency_can(s.agency_id, 'submit')
                          or omelo_private.omelo_agency_can(s.agency_id, 'manage_placements')) then
    raise exception 'Submission not found' using errcode = '42501';
  end if;
  if s.application_id is not null then
    raise exception 'This client is on Omelo: its own hiring team moves the candidate' using errcode = '42501';
  end if;
  if p_status not in ('reviewing','shortlisted','interview','offer','hired','rejected') then
    raise exception 'Unknown outcome %', p_status using errcode = '22023';
  end if;
  update candidate_submissions
     set status = p_status,
         client_response = case when p_status <> 'rejected' then left(nullif(trim(p_note), ''), 2000) else client_response end,
         rejection_reason = case when p_status = 'rejected' then left(nullif(trim(p_note), ''), 500) else rejection_reason end
   where id = s.id;
  if p_status = 'hired' then
    perform omelo_private.omelo_create_placement(s.id, p_start_date);
  end if;
end;
$$;

create or replace function public.omelo_update_placement(p_placement uuid, p_changes jsonb)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare pl placements; v_status text;
begin
  select * into pl from placements where id = p_placement;
  if pl.id is null or not omelo_private.omelo_agency_can(pl.agency_id, 'manage_placements') then
    raise exception 'Placement not found' using errcode = '42501';
  end if;
  v_status := coalesce(p_changes->>'status', pl.status);
  if v_status is distinct from pl.status and not (
       (pl.status = 'pending_start' and v_status in ('active','fell_through'))
    or (pl.status = 'active' and v_status in ('completed','fell_through'))) then
    raise exception 'A placement cannot go from % to %', pl.status, v_status using errcode = '22023';
  end if;
  begin
    update placements set
      status = v_status,
      start_date = case when p_changes ? 'start_date' then nullif(p_changes->>'start_date', '')::date else start_date end,
      guarantee_ends_on = case when p_changes ? 'guarantee_ends_on' then nullif(p_changes->>'guarantee_ends_on', '')::date else guarantee_ends_on end,
      fee_amount = case when p_changes ? 'fee_amount' then nullif(p_changes->>'fee_amount', '')::numeric else fee_amount end,
      fee_currency = case when p_changes ? 'fee_currency' then upper(nullif(p_changes->>'fee_currency', '')) else fee_currency end,
      notes = case when p_changes ? 'notes' then left(nullif(p_changes->>'notes', ''), 2000) else notes end,
      updated_at = now()
    where id = pl.id;
  exception when others then
    raise exception 'Check the placement details: %', sqlerrm using errcode = '22023';
  end;
  if v_status is distinct from pl.status then
    perform omelo_private.omelo_emit('PlacementStatusChanged', 'placement', pl.id, pl.agency_id, pl.person_id,
      jsonb_build_object('from', pl.status, 'to', v_status));
  end if;
end;
$$;

-- 13. Client links: an agency cannot claim a company; the company confirms ---------------
create or replace function public.omelo_request_client_link(p_client uuid, p_company uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare cl agency_clients; v_agency text; m record;
begin
  select * into cl from agency_clients where id = p_client;
  if cl.id is null or not omelo_private.omelo_agency_can(cl.agency_id, 'manage_clients') then
    raise exception 'Client not found' using errcode = '42501';
  end if;
  if not exists (select 1 from companies where id = p_company and company_kind = 'employer' and deleted_at is null)
     or p_company = cl.agency_id then
    raise exception 'Choose an employer company on Omelo' using errcode = '22023';
  end if;
  if exists (select 1 from agency_clients where agency_id = cl.agency_id and client_company_id = p_company and id <> cl.id) then
    raise exception 'Another client record is already linked to that company' using errcode = '22023';
  end if;
  update agency_clients set requested_company_id = p_company, link_status = 'pending',
         client_company_id = null
   where id = cl.id;
  select display_name into v_agency from companies where id = cl.agency_id;
  for m in select distinct person_id from company_members
            where company_id = p_company and is_active and role in ('owner','admin') loop
    perform omelo_private.omelo_notify(m.person_id, 'representation_update'::notification_type,
      v_agency || ' wants to recruit for you', 'Confirm or decline the agency relationship',
      'agency_client', cl.id, '/dashboard/agencies');
  end loop;
  perform omelo_private.omelo_emit('ClientLinkRequested', 'agency_client', cl.id, cl.agency_id, null,
    jsonb_build_object('company_id', p_company));
end;
$$;

create or replace function public.omelo_respond_client_link(p_client uuid, p_accept boolean)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare cl agency_clients;
begin
  select * into cl from agency_clients where id = p_client;
  if cl.id is null or cl.requested_company_id is null
     or not omelo_private.omelo_has_company_role(cl.requested_company_id, array['owner','admin']::company_role[]) then
    raise exception 'Only the company''s owners or admins can answer this' using errcode = '42501';
  end if;
  if cl.link_status <> 'pending' then
    raise exception 'This request was already answered' using errcode = '22023';
  end if;
  if p_accept then
    update agency_clients set client_company_id = requested_company_id, link_status = 'confirmed',
           relationship_status = case when relationship_status = 'prospect' then 'active' else relationship_status end
     where id = cl.id;
  else
    update agency_clients set link_status = 'declined' where id = cl.id;
  end if;
  perform omelo_private.omelo_emit(case when p_accept then 'ClientLinkConfirmed' else 'ClientLinkDeclined' end,
    'agency_client', cl.id, cl.agency_id, null, jsonb_build_object('company_id', cl.requested_company_id));
end;
$$;

create or replace function public.omelo_end_client_link(p_client uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare cl agency_clients;
begin
  select * into cl from agency_clients where id = p_client;
  if cl.id is null or not (omelo_private.omelo_agency_can(cl.agency_id, 'manage_agency')
       or (cl.client_company_id is not null
           and omelo_private.omelo_has_company_role(cl.client_company_id, array['owner','admin']::company_role[]))) then
    raise exception 'Only the agency''s or the company''s admins can end this link' using errcode = '42501';
  end if;
  update agency_clients set client_company_id = null, link_status = 'unlinked' where id = cl.id;
  update job_orders set client_job_id = null, updated_at = now() where client_id = cl.id;
  perform omelo_private.omelo_emit('ClientLinkEnded', 'agency_client', cl.id, cl.agency_id, null, '{}'::jsonb);
end;
$$;

create or replace function public.omelo_my_agency_relationships()
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'client_id', cl.id, 'company_id', coalesce(cl.client_company_id, cl.requested_company_id),
      'link_status', cl.link_status, 'relationship_status', cl.relationship_status,
      'agency', jsonb_build_object('id', ag.id, 'name', ag.display_name, 'verified', ag.is_verified,
                                   'independent', ag.is_independent_recruiter, 'logo_url', ag.logo_url),
      'job_orders', (select count(*) from job_orders jo where jo.client_id = cl.id and jo.status in ('open','on_hold')),
      'submissions', (select count(*) from candidate_submissions s where s.client_id = cl.id and s.application_id is not null),
      'can_answer', cl.link_status = 'pending'
                    and omelo_private.omelo_has_company_role(cl.requested_company_id, array['owner','admin']::company_role[]))
      order by (cl.link_status = 'pending') desc, ag.display_name), '[]'::jsonb)
  from agency_clients cl
  join companies ag on ag.id = cl.agency_id
  where (cl.link_status = 'confirmed' and omelo_private.omelo_has_company_role(cl.client_company_id,
           array['owner','admin','recruiter','hiring_manager','hr']::company_role[]))
     or (cl.link_status = 'pending' and omelo_private.omelo_has_company_role(cl.requested_company_id,
           array['owner','admin']::company_role[]));
$$;

create or replace function public.omelo_client_job_orders()
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', jo.id, 'reference', jo.reference, 'title', jo.title, 'openings', jo.openings, 'status', jo.status,
      'location_text', jo.location_text, 'work_type', jo.work_type, 'start_date', jo.start_date,
      'pay', jsonb_build_object('min', jo.pay_min, 'max', jo.pay_max, 'period', jo.pay_period, 'currency', jo.pay_currency),
      'client_job_id', jo.client_job_id,
      'client_job_title', (select title from jobs where id = jo.client_job_id),
      'agency', jsonb_build_object('id', ag.id, 'name', ag.display_name, 'verified', ag.is_verified),
      'submissions', (select count(*) from candidate_submissions s where s.job_order_id = jo.id and s.application_id is not null))
      order by jo.created_at desc), '[]'::jsonb)
  from job_orders jo
  join agency_clients cl on cl.id = jo.client_id and cl.link_status = 'confirmed'
  join companies ag on ag.id = jo.agency_id
  where omelo_private.omelo_has_company_role(cl.client_company_id,
          array['owner','admin','recruiter','hiring_manager','hr']::company_role[])
    and jo.status <> 'draft';
$$;

create or replace function public.omelo_link_job_order(p_job_order uuid, p_job uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare jo job_orders; cl agency_clients; v_company uuid; m record;
begin
  select * into jo from job_orders where id = p_job_order;
  select * into cl from agency_clients where id = jo.client_id;
  select company_id into v_company from jobs where id = p_job;
  if jo.id is null or cl.link_status <> 'confirmed' or v_company is distinct from cl.client_company_id
     or not omelo_private.omelo_has_company_role(v_company, array['owner','admin','recruiter','hiring_manager']::company_role[]) then
    raise exception 'Only the client''s hiring team can connect one of its jobs to this order' using errcode = '42501';
  end if;
  if not exists (select 1 from job_stages where job_id = p_job) then
    raise exception 'Add pipeline stages to the job first' using errcode = '22023';
  end if;
  update job_orders set client_job_id = p_job, updated_at = now() where id = jo.id;
  for m in select person_id from job_order_recruiters where job_order_id = jo.id loop
    perform omelo_private.omelo_notify(m.person_id, 'representation_update'::notification_type,
      'The client connected a job to ' || jo.reference, 'Submissions now go straight into the client''s pipeline',
      'job_order', jo.id, '/dashboard/agency/job-orders/' || jo.id);
  end loop;
end;
$$;

-- 14. Read models for the portal ----------------------------------------------------------
create or replace function public.omelo_agency_candidates(p_agency uuid, p_job_order uuid default null)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
begin
  if not omelo_private.omelo_agency_can(p_agency, 'view') then
    raise exception 'Only agency members can see this' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'consent_id', c.id, 'job_order_id', c.job_order_id, 'job_order', jo.reference, 'position', jo.title,
      'client', c.terms->'client'->>'name',
      'status', case when c.status = 'requested' and c.request_expires_at <= now() then 'expired'
                     when c.status = 'accepted' and c.expires_at <= now() then 'expired' else c.status end,
      'scope', to_jsonb(c.information_scope), 'requested_at', c.requested_at, 'responded_at', c.responded_at,
      'expires_at', c.expires_at, 'decline_reason', c.decline_reason,
      'recruiter', (select display_name from persons where id = c.recruiter_id),
      'submission', (select jsonb_build_object('id', s.id, 'status', s.status, 'submitted_at', s.submitted_at)
                       from candidate_submissions s where s.consent_id = c.id),
      'candidate', case when c.status in ('requested','accepted','active')
                        then omelo_private.omelo_talent_card(c.work_identity_id, null, p_agency)
                        else jsonb_build_object('name', coalesce(c.terms->>'identity_label', 'Candidate')) end)
      order by c.requested_at desc)
      from candidate_consents c join job_orders jo on jo.id = c.job_order_id
     where c.agency_id = p_agency and (p_job_order is null or c.job_order_id = p_job_order)), '[]'::jsonb);
end;
$$;

create or replace function public.omelo_consent_candidate(p_consent uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare c candidate_consents;
begin
  select * into c from candidate_consents where id = p_consent;
  if c.id is null or not omelo_private.omelo_agency_can(c.agency_id, 'view_candidate_limited') then
    raise exception 'Not found' using errcode = '42501';
  end if;
  if not (c.status = 'active' or (c.status = 'accepted' and c.expires_at > now())) then
    raise exception 'The candidate''s consent is not in force (%)', c.status using errcode = '42501';
  end if;
  if omelo_private.omelo_agency_can(c.agency_id, 'view_candidate_details') then
    return omelo_private.omelo_scoped_profile(c.work_identity_id, c.information_scope, true);
  end if;
  -- sourcers and coordinators: the card and skills only
  return omelo_private.omelo_scoped_profile(c.work_identity_id,
           array(select x from unnest(c.information_scope) x where x in ('identity','skills')), false);
end;
$$;

create or replace function public.omelo_agency_submissions(p_agency uuid, p_job_order uuid default null)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
begin
  if not omelo_private.omelo_agency_can(p_agency, 'view') then
    raise exception 'Only agency members can see this' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', s.id, 'status', s.status, 'submitted_at', s.submitted_at, 'updated_at', s.updated_at,
      'job_order_id', s.job_order_id, 'job_order', jo.reference, 'position', jo.title,
      'client', coalesce((select display_name from companies where id = cl.client_company_id), cl.name),
      'on_omelo', s.application_id is not null,
      'candidate', jsonb_build_object('name', s.snapshot->'identity'->>'name', 'label', s.snapshot->'identity'->>'label',
                                      'profession', s.snapshot->'identity'->>'profession'),
      'recruiter', (select display_name from persons where id = s.recruiter_id),
      'recruiter_note', s.recruiter_note, 'client_response', s.client_response, 'rejection_reason', s.rejection_reason,
      'consent_status', (select status from candidate_consents where id = s.consent_id),
      'application_state', (select state from applications where id = s.application_id),
      'next_interview', (select min(i.scheduled_at) from interviews i
                          where i.application_id = s.application_id and i.status::text in ('scheduled','confirmed')
                            and i.scheduled_at > now()),
      'offer_status', (select o.status from offers o where o.application_id = s.application_id
                        order by o.created_at desc limit 1),
      'placement', (select jsonb_build_object('id', pl.id, 'status', pl.status, 'start_date', pl.start_date,
                                              'fee_amount', pl.fee_amount, 'fee_currency', pl.fee_currency)
                      from placements pl where pl.submission_id = s.id))
      order by s.submitted_at desc)
      from candidate_submissions s
      join job_orders jo on jo.id = s.job_order_id
      join agency_clients cl on cl.id = s.client_id
     where s.agency_id = p_agency and (p_job_order is null or s.job_order_id = p_job_order)), '[]'::jsonb);
end;
$$;

create or replace function public.omelo_client_submissions(p_job_id uuid default null)
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'submission_id', s.id, 'application_id', a.id, 'job_id', a.job_id, 'job_title', j.title,
      'candidate', s.snapshot->'identity', 'applied_as', s.snapshot->'identity'->>'label',
      'match_score', a.match_score, 'stage', a.state, 'submitted_at', s.submitted_at,
      'agency', jsonb_build_object('id', ag.id, 'name', ag.display_name, 'verified', ag.is_verified,
                                   'independent', ag.is_independent_recruiter),
      'recruiter', (select display_name from persons where id = s.recruiter_id),
      'recruiter_note', s.recruiter_note,
      'consent_status', case (select status from candidate_consents where id = s.consent_id)
                          when 'active' then 'active' when 'accepted' then 'active'
                          when 'revoked' then 'withdrawn' else 'ended' end,
      'shared', s.snapshot->'scope')
      order by s.submitted_at desc), '[]'::jsonb)
  from candidate_submissions s
  join applications a on a.id = s.application_id
  join jobs j on j.id = a.job_id
  join companies ag on ag.id = s.agency_id
  where omelo_private.omelo_can_access_job(a.job_id)
    and (p_job_id is null or a.job_id = p_job_id);
$$;

create or replace function public.omelo_agency_dashboard(p_agency uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare v_since timestamptz := now() - interval '30 days';
begin
  if not omelo_private.omelo_agency_can(p_agency, 'view') then
    raise exception 'Only agency members can see this' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'active_job_orders', (select count(*) from job_orders where agency_id = p_agency and status in ('open','on_hold')),
    'openings', (select coalesce(sum(openings), 0) from job_orders where agency_id = p_agency and status in ('open','on_hold')),
    'candidates_sourced', (select count(distinct person_id) from (
                             select person_id from candidate_consents where agency_id = p_agency and requested_at >= v_since
                             union all
                             select m.person_id from talent_pool_members m join talent_pools tp on tp.id = m.pool_id
                              where tp.company_id = p_agency and m.added_at >= v_since) x),
    'consent_requests', (select count(*) from candidate_consents where agency_id = p_agency and requested_at >= v_since),
    'consents_accepted', (select count(*) from candidate_consents where agency_id = p_agency and requested_at >= v_since
                            and status in ('accepted','active','expired','revoked') and responded_at is not null),
    'submissions', (select count(*) from candidate_submissions where agency_id = p_agency and submitted_at >= v_since),
    'interviews', (select count(*) from candidate_submissions where agency_id = p_agency and submitted_at >= v_since
                     and status in ('interview','offer','hired')),
    'offers', (select count(*) from candidate_submissions where agency_id = p_agency and submitted_at >= v_since
                 and status in ('offer','hired')),
    'placements', (select count(*) from placements where agency_id = p_agency and created_at >= v_since
                     and status <> 'fell_through'),
    'days', 30);
end;
$$;

-- 15. Expiry ---------------------------------------------------------------------------
create or replace function omelo_private.omelo_expire_representations()
returns integer
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare n1 int; n2 int; n3 int;
begin
  update candidate_consents set status = 'expired'
   where status = 'requested' and request_expires_at <= now();
  get diagnostics n1 = row_count;
  update candidate_consents set status = 'expired'
   where status = 'accepted' and expires_at <= now();
  get diagnostics n2 = row_count;
  -- an active consent ends at its expiry once the submission it made is finished
  update candidate_consents c set status = 'expired'
   where c.status = 'active' and c.expires_at <= now()
     and exists (select 1 from candidate_submissions s where s.consent_id = c.id
                  and s.status in ('hired','rejected','withdrawn'));
  get diagnostics n3 = row_count;
  return n1 + n2 + n3;
end;
$$;
revoke execute on function omelo_private.omelo_expire_representations() from public, anon, authenticated;

do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'omelo-representation-expiry';
  perform cron.schedule('omelo-representation-expiry', '23 * * * *',
                        'select omelo_private.omelo_expire_representations()');
end;
$$;

-- 16. Grants -----------------------------------------------------------------------------
do $$
declare fn text;
begin
  foreach fn in array array[
    'omelo_create_agency(text, boolean, text)',
    'omelo_create_job_order(uuid, jsonb)',
    'omelo_update_job_order(uuid, jsonb)',
    'omelo_assign_job_order_recruiter(uuid, uuid, boolean, text)',
    'omelo_search_talent_for_order(uuid, jsonb, integer, integer)',
    'omelo_request_representation(uuid, uuid, text[], integer, text)',
    'omelo_withdraw_representation_request(uuid)',
    'omelo_respond_to_representation(uuid, boolean, text)',
    'omelo_revoke_representation(uuid, text)',
    'omelo_my_representations()',
    'omelo_submit_candidate(uuid, text)',
    'omelo_withdraw_submission(uuid, text)',
    'omelo_record_submission_outcome(uuid, text, text, date)',
    'omelo_update_placement(uuid, jsonb)',
    'omelo_request_client_link(uuid, uuid)',
    'omelo_respond_client_link(uuid, boolean)',
    'omelo_end_client_link(uuid)',
    'omelo_my_agency_relationships()',
    'omelo_client_job_orders()',
    'omelo_link_job_order(uuid, uuid)',
    'omelo_agency_candidates(uuid, uuid)',
    'omelo_consent_candidate(uuid)',
    'omelo_agency_submissions(uuid, uuid)',
    'omelo_client_submissions(uuid)',
    'omelo_agency_dashboard(uuid)'
  ] loop
    execute format('revoke execute on function public.%s from public, anon', fn);
    execute format('grant execute on function public.%s to authenticated', fn);
  end loop;
end;
$$;
