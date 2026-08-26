-- =====================================================================
-- OMELO — Row Level Security Policies
--
-- IMPORTANT: RLS is the LAST LINE OF DEFENCE, not the authorisation model.
-- Primary enforcement lives in the service layer (see docs/06 §5).
-- These policies exist so that a service-layer bug is contained rather
-- than catastrophic, and so direct database access cannot bypass consent.
--
-- Target: PostgreSQL 15+ / Supabase (auth.uid() available)
-- =====================================================================

-- =====================================================================
-- 0. HELPER FUNCTIONS
--    SECURITY DEFINER so policies are one indexed lookup, not a
--    correlated subquery evaluated per row.
-- =====================================================================

create or replace function omelo_company_role(p_company_id uuid)
returns company_role
language sql
stable
security definer
set search_path = public
as $$
  select role
  from company_members
  where company_id = p_company_id
    and person_id = auth.uid()
    and is_active
  order by array_position(
    array['owner','admin','recruiter','hiring_manager','interviewer','billing']::company_role[],
    role
  )
  limit 1;
$$;

create or replace function omelo_is_company_member(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from company_members
    where company_id = p_company_id
      and person_id = auth.uid()
      and is_active
  );
$$;

create or replace function omelo_has_company_role(p_company_id uuid, p_roles company_role[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from company_members
    where company_id = p_company_id
      and person_id = auth.uid()
      and is_active
      and role = any(p_roles)
  );
$$;

-- Recruiters and hiring managers are scoped to assigned jobs.
-- Assignment table is created below.
create or replace function omelo_can_access_job(p_job_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from jobs j
    join company_members cm
      on cm.company_id = j.company_id
     and cm.person_id = auth.uid()
     and cm.is_active
    where j.id = p_job_id
      and (
        cm.role in ('owner','admin')
        or exists (
          select 1 from job_assignments ja
          where ja.job_id = j.id and ja.person_id = auth.uid()
        )
      )
  );
$$;

-- THE CONSENT PREDICATE (docs/06 §4.2).
-- Implemented once. Every talent surface calls this. Never re-implemented
-- per feature, and never applied as a post-filter.
create or replace function omelo_is_discoverable_to(p_person_id uuid, p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    exists (
      select 1 from persons p
      where p.id = p_person_id
        and p.deleted_at is null
        and p.discoverability <> 'private'
    )
    and exists (
      select 1 from companies c
      where c.id = p_company_id
        and c.is_verified
        and c.deleted_at is null
    )
    -- candidate has not blocked the company
    and not exists (
      select 1 from blocks b
      where b.person_id = p_person_id
        and b.target_type = 'company'
        and b.target_id = p_company_id
    )
    -- candidate has not blocked the querying recruiter
    and not exists (
      select 1 from blocks b
      where b.person_id = p_person_id
        and b.target_type = 'person'
        and b.target_id = auth.uid()
    );
$$;

-- Job assignment scoping for recruiters / hiring managers / interviewers
create table if not exists job_assignments (
  job_id     uuid not null references jobs(id) on delete cascade,
  person_id  uuid not null references persons(id) on delete cascade,
  assigned_by uuid references persons(id),
  assigned_at timestamptz not null default now(),
  primary key (job_id, person_id)
);

create table if not exists interview_assignments (
  id             uuid primary key default gen_random_uuid(),
  application_id uuid not null references applications(id) on delete cascade,
  interviewer_id uuid not null references persons(id) on delete cascade,
  scheduled_at   timestamptz not null,
  completed_at   timestamptz,
  unique (application_id, interviewer_id, scheduled_at)
);

-- =====================================================================
-- 1. PERSON-OWNED TABLES
--    Rule: person_id = auth.uid()
-- =====================================================================

alter table persons enable row level security;

create policy persons_self_all on persons
  for all using (id = auth.uid()) with check (id = auth.uid());

-- Companies see a person only through an application they received,
-- or through the consent predicate. Column-level shaping is the service
-- layer's job (response projections, docs/06 §5.2).
create policy persons_via_application on persons
  for select using (
    exists (
      select 1
      from applications a
      join jobs j on j.id = a.job_id
      where a.person_id = persons.id
        and omelo_can_access_job(j.id)
    )
  );

create policy persons_via_consent on persons
  for select using (
    exists (
      select 1 from company_members cm
      where cm.person_id = auth.uid()
        and cm.is_active
        and cm.role in ('owner','admin','recruiter')
        and omelo_is_discoverable_to(persons.id, cm.company_id)
    )
  );

create policy persons_public_profile on persons
  for select using (discoverability = 'public' and deleted_at is null);

-- Uniform policy for the person-owned identity tables
do $$
declare t text;
begin
  foreach t in array array[
    'person_preferences','person_skills','experiences','educations','projects',
    'credential_holdings','work_authorizations','career_targets','person_languages',
    'follows','blocks','saved_jobs','hidden_jobs','saved_searches'
  ]
  loop
    execute format('alter table %I enable row level security', t);
    execute format(
      'create policy %I on %I for all using (person_id = auth.uid()) with check (person_id = auth.uid())',
      t || '_self_all', t
    );
  end loop;
end $$;

-- Identity sub-records become readable to a company only through an
-- application that company received.
do $$
declare t text;
begin
  foreach t in array array[
    'person_skills','experiences','educations','projects',
    'credential_holdings','work_authorizations','person_languages'
  ]
  loop
    execute format($f$
      create policy %I on %I for select using (
        exists (
          select 1 from applications a
          join jobs j on j.id = a.job_id
          where a.person_id = %I.person_id
            and omelo_can_access_job(j.id)
        )
      )
    $f$, t || '_via_application', t, t);
  end loop;
end $$;

-- BLOCKS: the blocked party must never be able to detect the block.
-- Only the owner may read. There is deliberately NO select policy for
-- anyone else — enforcement of blocking happens inside SECURITY DEFINER
-- functions, which is exactly why it produces absence, not a signal.

-- =====================================================================
-- 2. COMPANY TABLES
-- =====================================================================

alter table companies enable row level security;

create policy companies_public_read on companies
  for select using (deleted_at is null);

create policy companies_admin_write on companies
  for update using (omelo_has_company_role(id, array['owner','admin']::company_role[]))
  with check (omelo_has_company_role(id, array['owner','admin']::company_role[]));

create policy companies_owner_delete on companies
  for delete using (omelo_has_company_role(id, array['owner']::company_role[]));

alter table company_members enable row level security;

create policy company_members_read on company_members
  for select using (
    person_id = auth.uid()
    or omelo_has_company_role(company_id, array['owner','admin','recruiter','hiring_manager']::company_role[])
  );

create policy company_members_manage on company_members
  for all using (omelo_has_company_role(company_id, array['owner','admin']::company_role[]))
  with check (omelo_has_company_role(company_id, array['owner','admin']::company_role[]));

alter table company_locations enable row level security;
create policy company_locations_read on company_locations for select using (true);
create policy company_locations_write on company_locations
  for all using (omelo_has_company_role(company_id, array['owner','admin']::company_role[]))
  with check (omelo_has_company_role(company_id, array['owner','admin']::company_role[]));

alter table job_assignments enable row level security;
create policy job_assignments_read on job_assignments
  for select using (person_id = auth.uid() or omelo_can_access_job(job_id));
create policy job_assignments_write on job_assignments
  for all using (
    exists (select 1 from jobs j where j.id = job_id
            and omelo_has_company_role(j.company_id, array['owner','admin']::company_role[]))
  )
  with check (
    exists (select 1 from jobs j where j.id = job_id
            and omelo_has_company_role(j.company_id, array['owner','admin']::company_role[]))
  );

-- =====================================================================
-- 3. JOBS
-- =====================================================================

alter table jobs enable row level security;

create policy jobs_public_read on jobs
  for select using (status = 'published');

create policy jobs_company_read on jobs
  for select using (omelo_is_company_member(company_id));

create policy jobs_company_write on jobs
  for all using (
    omelo_has_company_role(company_id, array['owner','admin']::company_role[])
    or (omelo_has_company_role(company_id, array['recruiter']::company_role[]) and omelo_can_access_job(id))
  )
  with check (
    omelo_has_company_role(company_id, array['owner','admin','recruiter']::company_role[])
  );

do $$
declare t text;
begin
  foreach t in array array['job_skills','job_languages','job_locations','job_stages','job_questions']
  loop
    execute format('alter table %I enable row level security', t);
    execute format($f$
      create policy %I on %I for select using (
        exists (select 1 from jobs j where j.id = %I.job_id
                and (j.status = 'published' or omelo_is_company_member(j.company_id)))
      )
    $f$, t || '_read', t, t);
    execute format($f$
      create policy %I on %I for all using (
        exists (select 1 from jobs j where j.id = %I.job_id and omelo_can_access_job(j.id))
      ) with check (
        exists (select 1 from jobs j where j.id = %I.job_id and omelo_can_access_job(j.id))
      )
    $f$, t || '_write', t, t, t);
  end loop;
end $$;

-- =====================================================================
-- 4. APPLICATIONS
-- =====================================================================

alter table applications enable row level security;

create policy applications_candidate_read on applications
  for select using (person_id = auth.uid());

create policy applications_candidate_insert on applications
  for insert with check (person_id = auth.uid());

-- Candidates may only withdraw. All other state movement is employer-side
-- or system-side and goes through the service layer.
create policy applications_candidate_withdraw on applications
  for update using (person_id = auth.uid())
  with check (person_id = auth.uid() and public_state = 'withdrawn');

create policy applications_employer_read on applications
  for select using (omelo_can_access_job(job_id));

-- Interviewers: scheduled interviews only (docs/06 §3.1)
create policy applications_interviewer_read on applications
  for select using (
    exists (
      select 1 from interview_assignments ia
      where ia.application_id = applications.id
        and ia.interviewer_id = auth.uid()
    )
  );

create policy applications_employer_update on applications
  for update using (
    omelo_can_access_job(job_id)
    and exists (select 1 from jobs j where j.id = job_id
                and omelo_has_company_role(j.company_id,
                    array['owner','admin','recruiter','hiring_manager']::company_role[]))
  )
  with check (omelo_can_access_job(job_id));

-- APPLICATION_EVENTS: append-only. No update or delete policy exists,
-- by design. Absence of a policy = denial.
alter table application_events enable row level security;

create policy application_events_read on application_events
  for select using (
    exists (
      select 1 from applications a
      where a.id = application_id
        and (a.person_id = auth.uid() or omelo_can_access_job(a.job_id))
    )
  );

create policy application_events_insert on application_events
  for insert with check (
    exists (
      select 1 from applications a
      where a.id = application_id
        and (a.person_id = auth.uid() or omelo_can_access_job(a.job_id))
    )
  );

-- =====================================================================
-- 5. MATCHES
--    A candidate can always see their own scores and feature vectors
--    (FR-714). An employer sees scores only for their own jobs.
-- =====================================================================

alter table matches enable row level security;

create policy matches_candidate_read on matches
  for select using (person_id = auth.uid());

create policy matches_employer_read on matches
  for select using (omelo_can_access_job(job_id));

-- =====================================================================
-- 6. CONVERSATIONS & MESSAGES
-- =====================================================================

alter table conversations enable row level security;

create policy conversations_participant_read on conversations
  for select using (
    person_id = auth.uid()
    or (omelo_is_company_member(company_id)
        and (job_id is null or omelo_can_access_job(job_id)))
  );

create policy conversations_participant_write on conversations
  for all using (
    person_id = auth.uid()
    or (omelo_is_company_member(company_id)
        and omelo_has_company_role(company_id,
            array['owner','admin','recruiter','hiring_manager']::company_role[]))
  )
  with check (
    person_id = auth.uid()
    or omelo_has_company_role(company_id,
        array['owner','admin','recruiter','hiring_manager']::company_role[])
  );

alter table messages enable row level security;

create policy messages_participant_read on messages
  for select using (
    exists (
      select 1 from conversations c
      where c.id = conversation_id
        and (c.person_id = auth.uid()
             or (omelo_is_company_member(c.company_id)
                 and (c.job_id is null or omelo_can_access_job(c.job_id))))
    )
  );

create policy messages_participant_insert on messages
  for insert with check (
    sender_person_id = auth.uid()
    and exists (
      select 1 from conversations c
      where c.id = conversation_id
        and (c.person_id = auth.uid()
             or omelo_has_company_role(c.company_id,
                 array['owner','admin','recruiter','hiring_manager']::company_role[]))
    )
  );

-- Messages are immutable once sent, except for read receipts, which the
-- service layer handles with elevated privilege. No update policy here.

-- =====================================================================
-- 7. TALENT POOLS
-- =====================================================================

alter table talent_pools enable row level security;
create policy talent_pools_company on talent_pools
  for all using (omelo_has_company_role(company_id,
        array['owner','admin','recruiter','hiring_manager']::company_role[]))
  with check (omelo_has_company_role(company_id,
        array['owner','admin','recruiter']::company_role[]));

alter table talent_pool_members enable row level security;
create policy talent_pool_members_company on talent_pool_members
  for all using (
    exists (select 1 from talent_pools tp where tp.id = pool_id
            and omelo_has_company_role(tp.company_id,
                array['owner','admin','recruiter','hiring_manager']::company_role[]))
  )
  with check (
    exists (select 1 from talent_pools tp where tp.id = pool_id
            and omelo_has_company_role(tp.company_id,
                array['owner','admin','recruiter']::company_role[]))
  );

-- =====================================================================
-- 8. PROFILE VIEWS
--    Candidates see who viewed them (FR-409). Companies see their own.
-- =====================================================================

alter table profile_views enable row level security;

create policy profile_views_subject_read on profile_views
  for select using (person_id = auth.uid());

create policy profile_views_company_read on profile_views
  for select using (viewer_company_id is not null and omelo_is_company_member(viewer_company_id));

-- =====================================================================
-- 9. TAXONOMY — readable by all authenticated users, writable only by
--    the taxonomy steward service role.
-- =====================================================================

do $$
declare t text;
begin
  foreach t in array array[
    'locations','industries','institutions','languages','skills','skill_aliases',
    'skill_relations','occupations','occupation_aliases','occupation_transitions',
    'occupation_skills','credential_types','weight_profiles'
  ]
  loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy %I on %I for select using (true)', t || '_read', t);
    -- No insert/update/delete policy: only the service role (which bypasses
    -- RLS) may write. This is the taxonomy governance rule in schema form.
  end loop;
end $$;

-- =====================================================================
-- 10. VERIFICATION & AUDIT
-- =====================================================================

alter table verifications enable row level security;

create policy verifications_subject_read on verifications
  for select using (
    (subject_type = 'person'  and subject_id = auth.uid())
    or (subject_type = 'company' and omelo_is_company_member(subject_id))
    or (subject_type in ('experience','education','credential') and exists (
          select 1 from persons p where p.id = auth.uid()
        ) and subject_id in (
          select id from experiences where person_id = auth.uid()
          union all select id from educations where person_id = auth.uid()
          union all select id from credential_holdings where person_id = auth.uid()
        ))
  );

-- Verified badges must be readable wherever a profile is readable.
create policy verifications_public_badges on verifications
  for select using (revoked_at is null);

alter table audit_log enable row level security;

-- A person sees audit entries that concern them (docs/06 §6).
create policy audit_log_subject_read on audit_log
  for select using (
    (subject_type = 'person' and subject_id = auth.uid())
    or actor_id = auth.uid()
    or (company_id is not null
        and omelo_has_company_role(company_id, array['owner','admin']::company_role[]))
  );

-- No insert policy: audit rows are written by the service role only.
-- No update or delete policy anywhere: append-only by absence.

alter table automated_decision_log enable row level security;

create policy automated_decision_subject_read on automated_decision_log
  for select using (person_id = auth.uid());

-- =====================================================================
-- 11. DENY-BY-DEFAULT VERIFICATION
--
-- Any table with personal data and no policy for a given operation
-- denies that operation. Run this in CI to catch tables that were
-- added without RLS being enabled.
-- =====================================================================

-- select c.relname
-- from pg_class c
-- join pg_namespace n on n.oid = c.relnamespace
-- where n.nspname = 'public'
--   and c.relkind = 'r'
--   and not c.relrowsecurity;
