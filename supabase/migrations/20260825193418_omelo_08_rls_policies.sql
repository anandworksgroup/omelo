-- =====================================================================
-- OMELO 08 — Row Level Security
--
-- RLS is the LAST LINE OF DEFENCE. Primary authorisation lives in the
-- service layer (entitlements, quotas, audience-shaped responses).
-- These policies contain service-layer bugs and block direct access.
-- =====================================================================

-- ---------------------------------------------------------------
-- Helper functions (SECURITY DEFINER = one indexed lookup per check)
-- ---------------------------------------------------------------
create or replace function omelo_is_company_member(p_company_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from company_members
    where company_id = p_company_id and person_id = auth.uid() and is_active
  );
$$;

create or replace function omelo_has_company_role(p_company_id uuid, p_roles company_role[])
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from company_members
    where company_id = p_company_id and person_id = auth.uid()
      and is_active and role = any(p_roles)
  );
$$;

create or replace function omelo_can_access_job(p_job_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from jobs j
    join company_members cm
      on cm.company_id = j.company_id and cm.person_id = auth.uid() and cm.is_active
    where j.id = p_job_id
      and cm.role in ('owner','admin','recruiter','hiring_manager','hr')
  );
$$;

create or replace function omelo_is_platform_admin(p_roles text[] default null)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from platform_admins
    where person_id = auth.uid() and is_active
      and (expires_at is null or expires_at > now())
      and (p_roles is null or role = any(p_roles))
  );
$$;

-- THE CONSENT PREDICATE. Implemented once. Every talent surface uses it.
create or replace function omelo_is_discoverable_to(p_person_id uuid, p_company_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select
    exists (select 1 from persons p
            where p.id = p_person_id and p.deleted_at is null
              and p.discoverability <> 'private')
    and exists (select 1 from companies c
                where c.id = p_company_id and c.is_verified and c.deleted_at is null)
    and exists (select 1 from company_entitlements e
                where e.company_id = p_company_id and e.talent_search_enabled)
    and not exists (select 1 from blocks b
                    where b.person_id = p_person_id
                      and b.target_type = 'company' and b.target_id = p_company_id)
    and not exists (select 1 from blocks b
                    where b.person_id = p_person_id
                      and b.target_type = 'person' and b.target_id = auth.uid());
$$;

-- True when the calling user is a company member who received an
-- application from this person.
create or replace function omelo_has_application_from(p_person_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from applications a
    join company_members cm
      on cm.company_id = a.company_id and cm.person_id = auth.uid() and cm.is_active
    where a.person_id = p_person_id
      and cm.role in ('owner','admin','recruiter','hiring_manager','hr')
  );
$$;

create or replace function omelo_is_interviewer_for(p_application_id uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from interviews i
    join interview_interviewers ii on ii.interview_id = i.id
    where i.application_id = p_application_id and ii.person_id = auth.uid()
  );
$$;

-- ---------------------------------------------------------------
-- 1. TAXONOMY — world-readable, service-role writable only
-- ---------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'locations','country_policies','job_categories','professions','profession_aliases',
    'profession_transitions','skills','skill_aliases','skill_relations','profession_skills',
    'license_types','credential_types','institutions','industries','languages',
    'profile_attributes','weight_profiles'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy %I on %I for select to authenticated, anon using (true)',
                   t||'_read', t);
  end loop;
end $$;

-- ---------------------------------------------------------------
-- 2. PERSON-OWNED TABLES
-- ---------------------------------------------------------------
alter table persons enable row level security;

create policy persons_self on persons
  for all to authenticated using (id = auth.uid()) with check (id = auth.uid());

create policy persons_public_profile on persons
  for select to authenticated, anon
  using (discoverability = 'public' and deleted_at is null);

create policy persons_via_application on persons
  for select to authenticated using (omelo_has_application_from(id));

create policy persons_via_consent on persons
  for select to authenticated using (
    exists (
      select 1 from company_members cm
      where cm.person_id = auth.uid() and cm.is_active
        and cm.role in ('owner','admin','recruiter')
        and omelo_is_discoverable_to(persons.id, cm.company_id)
    )
  );

create policy persons_admin on persons
  for select to authenticated using (omelo_is_platform_admin());

-- Uniform self-ownership across identity tables
do $$
declare t text;
begin
  foreach t in array array[
    'person_work_preferences','person_location_preferences','person_professions',
    'person_skills','person_attributes','experiences','educations','person_licenses',
    'person_credentials','projects','person_languages','work_authorizations',
    'person_references','career_goals','documents','document_shares',
    'follows','blocks','saved_jobs','hidden_jobs','saved_searches',
    'notification_preferences'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format(
      'create policy %I on %I for all to authenticated using (person_id = auth.uid()) with check (person_id = auth.uid())',
      t||'_self', t);
  end loop;
end $$;

-- Employers may read work-identity sub-records only for people who
-- applied to them, or who consented to be discoverable.
do $$
declare t text;
begin
  foreach t in array array[
    'person_work_preferences','person_professions','person_skills','person_attributes',
    'experiences','educations','person_licenses','person_credentials','projects',
    'person_languages','work_authorizations','person_location_preferences'
  ] loop
    execute format($f$
      create policy %I on %I for select to authenticated using (
        omelo_has_application_from(%I.person_id)
        or exists (
          select 1 from company_members cm
          where cm.person_id = auth.uid() and cm.is_active
            and cm.role in ('owner','admin','recruiter')
            and omelo_is_discoverable_to(%I.person_id, cm.company_id)
        )
      )$f$, t||'_employer_read', t, t, t);
  end loop;
end $$;

-- project_skills follows its parent project
alter table project_skills enable row level security;
create policy project_skills_owner on project_skills
  for all to authenticated
  using (exists (select 1 from projects p where p.id = project_id and p.person_id = auth.uid()))
  with check (exists (select 1 from projects p where p.id = project_id and p.person_id = auth.uid()));
create policy project_skills_read on project_skills
  for select to authenticated
  using (exists (select 1 from projects p where p.id = project_id and omelo_has_application_from(p.person_id)));

-- DOCUMENTS: employers get access ONLY through a live, unrevoked share.
-- There is deliberately no path from "received an application" to
-- "can read the passport scan".
create policy documents_shared_read on documents
  for select to authenticated using (
    exists (
      select 1 from document_shares ds
      where ds.document_id = documents.id
        and ds.revoked_at is null
        and (ds.expires_at is null or ds.expires_at > now())
        and ds.company_id is not null
        and omelo_is_company_member(ds.company_id)
    )
  );

create policy document_shares_company_read on document_shares
  for select to authenticated
  using (company_id is not null and omelo_is_company_member(company_id));

-- BLOCKS: only the owner may read. No other policy exists, by design —
-- a detectable block would endanger the person it protects.

-- Verifications: subject reads own; badges visible where profile is.
alter table verifications enable row level security;
create policy verifications_self on verifications
  for select to authenticated using (person_id = auth.uid());
create policy verifications_employer_read on verifications
  for select to authenticated using (
    person_id is not null and (
      omelo_has_application_from(person_id)
      or exists (select 1 from company_members cm
                 where cm.person_id = auth.uid() and cm.is_active
                   and omelo_is_discoverable_to(verifications.person_id, cm.company_id))
    )
  );
create policy verifications_company_subject on verifications
  for select to authenticated
  using (subject_type = 'company' and omelo_is_company_member(subject_id));
create policy verifications_admin on verifications
  for all to authenticated using (omelo_is_platform_admin())
  with check (omelo_is_platform_admin());

-- ---------------------------------------------------------------
-- 3. COMPANY
-- ---------------------------------------------------------------
alter table companies enable row level security;
create policy companies_public_read on companies
  for select to authenticated, anon using (deleted_at is null);
create policy companies_insert on companies
  for insert to authenticated with check (created_by = auth.uid());
create policy companies_admin_update on companies
  for update to authenticated
  using (omelo_has_company_role(id, array['owner','admin']::company_role[]))
  with check (omelo_has_company_role(id, array['owner','admin']::company_role[]));
create policy companies_owner_delete on companies
  for delete to authenticated
  using (omelo_has_company_role(id, array['owner']::company_role[]));

do $$
declare t text;
begin
  foreach t in array array['company_locations','departments','talent_pools'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy %I on %I for select to authenticated using (omelo_is_company_member(company_id))', t||'_read', t);
    execute format($f$create policy %I on %I for all to authenticated
      using (omelo_has_company_role(company_id, array['owner','admin','recruiter']::company_role[]))
      with check (omelo_has_company_role(company_id, array['owner','admin','recruiter']::company_role[]))$f$,
      t||'_write', t);
  end loop;
end $$;

create policy company_locations_public on company_locations
  for select to authenticated, anon using (true);

alter table company_members enable row level security;
create policy company_members_read on company_members
  for select to authenticated
  using (person_id = auth.uid() or omelo_is_company_member(company_id));
create policy company_members_manage on company_members
  for all to authenticated
  using (omelo_has_company_role(company_id, array['owner','admin']::company_role[]))
  with check (omelo_has_company_role(company_id, array['owner','admin']::company_role[]));

alter table company_invitations enable row level security;
create policy company_invitations_manage on company_invitations
  for all to authenticated
  using (omelo_has_company_role(company_id, array['owner','admin']::company_role[]))
  with check (omelo_has_company_role(company_id, array['owner','admin']::company_role[]));

alter table company_entitlements enable row level security;
create policy company_entitlements_read on company_entitlements
  for select to authenticated
  using (omelo_has_company_role(company_id, array['owner','admin','finance']::company_role[]));

-- ---------------------------------------------------------------
-- 4. JOBS
-- ---------------------------------------------------------------
alter table jobs enable row level security;
create policy jobs_public_read on jobs
  for select to authenticated, anon using (status = 'published');
create policy jobs_company_read on jobs
  for select to authenticated using (omelo_is_company_member(company_id));
create policy jobs_company_write on jobs
  for all to authenticated
  using (omelo_has_company_role(company_id, array['owner','admin','recruiter']::company_role[]))
  with check (omelo_has_company_role(company_id, array['owner','admin','recruiter']::company_role[]));

do $$
declare t text;
begin
  foreach t in array array[
    'job_skills','job_languages','job_licenses','job_credentials',
    'job_attribute_requirements','job_documents_required','job_benefits',
    'job_locations','job_stages','job_questions','job_legal_restrictions'
  ] loop
    execute format('alter table %I enable row level security', t);
    execute format($f$create policy %I on %I for select to authenticated, anon using (
      exists (select 1 from jobs j where j.id = %I.job_id
              and (j.status = 'published' or omelo_is_company_member(j.company_id))))$f$,
      t||'_read', t, t);
    execute format($f$create policy %I on %I for all to authenticated
      using (exists (select 1 from jobs j where j.id = %I.job_id and omelo_can_access_job(j.id)))
      with check (exists (select 1 from jobs j where j.id = %I.job_id and omelo_can_access_job(j.id)))$f$,
      t||'_write', t, t, t);
  end loop;
end $$;

do $$
declare t text;
begin
  foreach t in array array['job_sources','ingestion_runs'] loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy %I on %I for select to authenticated using (omelo_is_platform_admin())', t||'_admin', t);
  end loop;
end $$;

-- ---------------------------------------------------------------
-- 5. APPLICATIONS AND HIRING
-- ---------------------------------------------------------------
alter table applications enable row level security;
create policy applications_candidate_read on applications
  for select to authenticated using (person_id = auth.uid());
create policy applications_candidate_insert on applications
  for insert to authenticated with check (person_id = auth.uid());
create policy applications_candidate_update on applications
  for update to authenticated
  using (person_id = auth.uid())
  with check (person_id = auth.uid() and state in ('withdrawn','declined_by_candidate'));
create policy applications_employer_read on applications
  for select to authenticated using (omelo_can_access_job(job_id));
create policy applications_interviewer_read on applications
  for select to authenticated using (omelo_is_interviewer_for(id));
create policy applications_employer_update on applications
  for update to authenticated
  using (omelo_can_access_job(job_id)) with check (omelo_can_access_job(job_id));

alter table application_events enable row level security;
create policy application_events_read on application_events
  for select to authenticated using (
    exists (select 1 from applications a where a.id = application_id
            and (a.person_id = auth.uid() or omelo_can_access_job(a.job_id)))
  );
create policy application_events_insert on application_events
  for insert to authenticated with check (
    exists (select 1 from applications a where a.id = application_id
            and (a.person_id = auth.uid() or omelo_can_access_job(a.job_id)))
  );
-- No update or delete policy: append-only by absence.

alter table application_notes enable row level security;
create policy application_notes_company on application_notes
  for all to authenticated
  using (omelo_has_company_role(company_id, array['owner','admin','recruiter','hiring_manager','hr']::company_role[]))
  with check (omelo_has_company_role(company_id, array['owner','admin','recruiter','hiring_manager','hr']::company_role[]));

alter table interviews enable row level security;
create policy interviews_candidate on interviews
  for select to authenticated using (person_id = auth.uid());
create policy interviews_company on interviews
  for all to authenticated
  using (omelo_can_access_job(job_id)) with check (omelo_can_access_job(job_id));
create policy interviews_interviewer on interviews
  for select to authenticated
  using (exists (select 1 from interview_interviewers ii
                 where ii.interview_id = interviews.id and ii.person_id = auth.uid()));

alter table interview_interviewers enable row level security;
create policy interview_interviewers_read on interview_interviewers
  for select to authenticated using (
    person_id = auth.uid()
    or exists (select 1 from interviews i where i.id = interview_id and omelo_can_access_job(i.job_id))
  );
create policy interview_interviewers_write on interview_interviewers
  for all to authenticated
  using (exists (select 1 from interviews i where i.id = interview_id and omelo_can_access_job(i.job_id)))
  with check (exists (select 1 from interviews i where i.id = interview_id and omelo_can_access_job(i.job_id)));

alter table interview_scorecards enable row level security;
create policy interview_scorecards_own on interview_scorecards
  for all to authenticated
  using (interviewer_id = auth.uid()) with check (interviewer_id = auth.uid());
create policy interview_scorecards_hiring on interview_scorecards
  for select to authenticated using (
    exists (select 1 from interviews i where i.id = interview_id
            and omelo_has_company_role(i.company_id,
                array['owner','admin','recruiter','hiring_manager']::company_role[]))
  );

alter table assessments enable row level security;
create policy assessments_candidate on assessments
  for select to authenticated
  using (exists (select 1 from applications a where a.id = application_id and a.person_id = auth.uid()));
create policy assessments_company on assessments
  for all to authenticated
  using (omelo_can_access_job(job_id)) with check (omelo_can_access_job(job_id));

alter table offers enable row level security;
create policy offers_candidate_read on offers
  for select to authenticated using (person_id = auth.uid() and status <> 'draft');
create policy offers_candidate_respond on offers
  for update to authenticated
  using (person_id = auth.uid())
  with check (person_id = auth.uid() and status in ('accepted','declined','negotiating','viewed'));
create policy offers_company on offers
  for all to authenticated
  using (omelo_has_company_role(company_id, array['owner','admin','recruiter','hiring_manager','hr']::company_role[]))
  with check (omelo_has_company_role(company_id, array['owner','admin','recruiter','hiring_manager','hr']::company_role[]));

alter table employments enable row level security;
create policy employments_person on employments
  for select to authenticated using (person_id = auth.uid());
create policy employments_company on employments
  for all to authenticated
  using (omelo_has_company_role(company_id, array['owner','admin','hr','recruiter']::company_role[]))
  with check (omelo_has_company_role(company_id, array['owner','admin','hr','recruiter']::company_role[]));

alter table matches enable row level security;
create policy matches_person on matches
  for select to authenticated using (person_id = auth.uid());
create policy matches_company on matches
  for select to authenticated using (omelo_can_access_job(job_id));

-- ---------------------------------------------------------------
-- 6. MESSAGING
-- ---------------------------------------------------------------
alter table conversations enable row level security;
create policy conversations_participant on conversations
  for all to authenticated
  using (person_id = auth.uid() or omelo_is_company_member(company_id))
  with check (
    person_id = auth.uid()
    or omelo_has_company_role(company_id,
       array['owner','admin','recruiter','hiring_manager','hr']::company_role[])
  );

alter table messages enable row level security;
create policy messages_read on messages
  for select to authenticated using (
    exists (select 1 from conversations c where c.id = conversation_id
            and (c.person_id = auth.uid() or omelo_is_company_member(c.company_id)))
  );
create policy messages_insert on messages
  for insert to authenticated with check (
    sender_person_id = auth.uid()
    and exists (select 1 from conversations c where c.id = conversation_id
                and (c.person_id = auth.uid()
                     or omelo_has_company_role(c.company_id,
                        array['owner','admin','recruiter','hiring_manager','hr']::company_role[])))
  );

-- ---------------------------------------------------------------
-- 7. RELATIONSHIP EDGES
-- ---------------------------------------------------------------
alter table profile_views enable row level security;
create policy profile_views_subject on profile_views
  for select to authenticated using (person_id = auth.uid());
create policy profile_views_company on profile_views
  for select to authenticated
  using (viewer_company_id is not null and omelo_is_company_member(viewer_company_id));
create policy profile_views_insert on profile_views
  for insert to authenticated with check (true);

alter table talent_pool_members enable row level security;
create policy talent_pool_members_company on talent_pool_members
  for all to authenticated
  using (exists (select 1 from talent_pools tp where tp.id = pool_id and omelo_is_company_member(tp.company_id)))
  with check (exists (select 1 from talent_pools tp where tp.id = pool_id
              and omelo_has_company_role(tp.company_id, array['owner','admin','recruiter']::company_role[])));

alter table candidate_invitations enable row level security;
create policy candidate_invitations_person on candidate_invitations
  for select to authenticated using (person_id = auth.uid());
create policy candidate_invitations_respond on candidate_invitations
  for update to authenticated using (person_id = auth.uid()) with check (person_id = auth.uid());
create policy candidate_invitations_company on candidate_invitations
  for all to authenticated
  using (omelo_has_company_role(company_id, array['owner','admin','recruiter']::company_role[]))
  with check (omelo_has_company_role(company_id, array['owner','admin','recruiter']::company_role[]));

alter table notifications enable row level security;
create policy notifications_self on notifications
  for all to authenticated using (person_id = auth.uid()) with check (person_id = auth.uid());

-- ---------------------------------------------------------------
-- 8. TRUST, ADMIN, AUDIT
-- ---------------------------------------------------------------
alter table reports enable row level security;
create policy reports_reporter on reports
  for select to authenticated using (reporter_id = auth.uid());
create policy reports_create on reports
  for insert to authenticated with check (reporter_id = auth.uid());
create policy reports_admin on reports
  for all to authenticated
  using (omelo_is_platform_admin(array['trust_safety','superadmin']))
  with check (omelo_is_platform_admin(array['trust_safety','superadmin']));

do $$
declare t text;
begin
  foreach t in array array['moderation_actions','fraud_signals','platform_admins','support_sessions'] loop
    execute format('alter table %I enable row level security', t);
    execute format($f$create policy %I on %I for all to authenticated
      using (omelo_is_platform_admin(array['trust_safety','superadmin']))
      with check (omelo_is_platform_admin(array['trust_safety','superadmin']))$f$, t||'_admin', t);
  end loop;
end $$;

-- A person can always see support access to their own account.
create policy support_sessions_subject on support_sessions
  for select to authenticated using (person_id = auth.uid());

alter table audit_log enable row level security;
create policy audit_log_subject on audit_log
  for select to authenticated using (
    (subject_type = 'person' and subject_id = auth.uid())
    or actor_id = auth.uid()
    or (company_id is not null
        and omelo_has_company_role(company_id, array['owner','admin']::company_role[]))
    or omelo_is_platform_admin()
  );
-- No insert policy: written by the service role only.

alter table automated_decision_log enable row level security;
create policy automated_decision_subject on automated_decision_log
  for select to authenticated using (person_id = auth.uid() or omelo_is_platform_admin());
create policy automated_decision_review_request on automated_decision_log
  for update to authenticated using (person_id = auth.uid()) with check (person_id = auth.uid());
