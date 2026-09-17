-- ============================================================
-- OMELO 25 — Hiring loop integrity
--
-- Closes the authorisation holes proven with real logins before the hiring
-- loop UI was built on top of them (architecture/A5 §4):
--
--   H1  employer set applications.state = 'hired' directly (no offer, no acceptance)
--   H2  employer rejected with no reason
--   H3  employer inserted an employment -> forged VERIFIED work history
--   H4  worker self-inserted is_verified experiences / employer_verified skills
--   H5  employer set companies.is_verified on its own company
--   H6  candidate could rewrite offer terms while accepting
--   H7  either party could insert arbitrary application_events (forged audit trail)
--
-- The model: privileged transitions happen ONLY inside SECURITY DEFINER
-- functions below. Guard triggers are SECURITY INVOKER, so inside them
-- current_user is the real caller role: 'authenticated'/'anon' for a client
-- request, the function owner inside a definer function. A client cannot
-- change current_user, so the check cannot be forged.
-- ============================================================

create or replace function omelo_private.omelo_is_privileged()
returns boolean
language sql stable
set search_path = public, omelo_private
as $$
  select current_user not in ('authenticated', 'anon');
$$;

create or replace function omelo_private.omelo_is_open_state(p_state application_state)
returns boolean
language sql immutable
as $$
  select p_state in ('applied','viewed','shortlisted','screening','assessment','interview','offer');
$$;

-- Lookups used by the invoker-rights guards. They must see the real row even
-- when RLS would hide it from the caller, or a guard could pass or fail on
-- missing data. They expose nothing: omelo_private is not in the API.
create or replace function omelo_private.omelo_application_keys(p_application_id uuid)
returns table (job_id uuid, company_id uuid, person_id uuid)
language sql stable security definer
set search_path = public, omelo_private
as $$
  select a.job_id, a.company_id, a.person_id from applications a where a.id = p_application_id;
$$;

create or replace function omelo_private.omelo_job_company(p_job_id uuid)
returns uuid
language sql stable security definer
set search_path = public, omelo_private
as $$
  select company_id from jobs where id = p_job_id;
$$;

create or replace function omelo_private.omelo_stage_in_job(p_stage_id uuid, p_job_id uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select exists (select 1 from job_stages where id = p_stage_id and job_id = p_job_id);
$$;

create or replace function omelo_private.omelo_first_stage(p_job_id uuid, p_state application_state)
returns uuid
language sql stable security definer
set search_path = public, omelo_private
as $$
  select id from job_stages where job_id = p_job_id and maps_to_state = p_state order by position limit 1;
$$;

grant execute on function omelo_private.omelo_application_keys(uuid) to authenticated;
grant execute on function omelo_private.omelo_job_company(uuid) to anon, authenticated;
grant execute on function omelo_private.omelo_stage_in_job(uuid, uuid) to authenticated;
grant execute on function omelo_private.omelo_first_stage(uuid, application_state) to authenticated;

-- ============================================================
-- GUARDS
-- ============================================================

-- applications: state, stage and decision fields move only through functions.
-- (is_archived is generated from state, so it is never compared here: in a
-- BEFORE trigger a generated column is still null.)
create or replace function omelo_private.omelo_guard_application_transitions()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  -- Always: a stage must belong to the application's own job.
  if new.stage_id is not null and new.stage_id is distinct from old.stage_id
     and not omelo_private.omelo_stage_in_job(new.stage_id, new.job_id) then
    raise exception 'That stage belongs to a different job' using errcode = '23514';
  end if;

  if omelo_private.omelo_is_privileged() then
    return new;
  end if;

  -- The one direct change a candidate may make: withdraw an open application.
  if old.person_id = auth.uid()
     and new.state = 'withdrawn' and omelo_private.omelo_is_open_state(old.state)
     and new.stage_id is not distinct from old.stage_id
     and new.rejection_reason is not distinct from old.rejection_reason
     and new.rejected_by is not distinct from old.rejected_by
     and new.first_viewed_at is not distinct from old.first_viewed_at
     and new.match_score is not distinct from old.match_score then
    return new;
  end if;

  if new.state            is distinct from old.state
  or new.stage_id         is distinct from old.stage_id
  or new.rejection_reason is distinct from old.rejection_reason
  or new.rejected_by      is distinct from old.rejected_by
  or new.withdrawal_reason is distinct from old.withdrawal_reason
  or new.first_viewed_at  is distinct from old.first_viewed_at
  or new.closed_at        is distinct from old.closed_at
  or new.match_score      is distinct from old.match_score
  or new.cover_note       is distinct from old.cover_note
  or new.answers          is distinct from old.answers
  or new.resume_document_id is distinct from old.resume_document_id
  or new.applied_via      is distinct from old.applied_via then
    raise exception 'Application status changes go through Omelo hiring actions (move, reject, interview, offer)'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

drop trigger if exists applications_guard_transitions on applications;
create trigger applications_guard_transitions
  before update on applications
  for each row execute function omelo_private.omelo_guard_application_transitions();

-- A new application always starts at the beginning, unscored by the client.
create or replace function omelo_private.omelo_guard_application_insert()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if not omelo_private.omelo_is_privileged() then
    new.state := 'applied';
    new.stage_id := omelo_private.omelo_first_stage(new.job_id, 'applied');
    new.first_viewed_at := null;
    new.closed_at := null;
    new.rejection_reason := null;
    new.rejected_by := null;
  end if;
  -- company_id must be the job's company, whoever inserts.
  if new.company_id is distinct from omelo_private.omelo_job_company(new.job_id) then
    raise exception 'Application company does not match the job' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists applications_guard_insert on applications;
create trigger applications_guard_insert
  before insert on applications
  for each row execute function omelo_private.omelo_guard_application_insert();

-- application_events: written only by triggers and hiring functions.
drop policy if exists application_events_insert on application_events;

-- application_notes: the author is whoever is signed in.
create or replace function omelo_private.omelo_guard_application_note()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if not omelo_private.omelo_is_privileged() then
    new.author_id := auth.uid();
  end if;
  if new.company_id is distinct from (select k.company_id from omelo_private.omelo_application_keys(new.application_id) k) then
    raise exception 'Note company does not match the application' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists application_notes_guard on application_notes;
create trigger application_notes_guard
  before insert or update on application_notes
  for each row execute function omelo_private.omelo_guard_application_note();

-- offers: employers may draft; sending, withdrawing and responding are functions.
create or replace function omelo_private.omelo_guard_offer()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
declare a record;
begin
  if tg_op in ('INSERT', 'UPDATE') then
    select k.job_id, k.company_id, k.person_id into a from omelo_private.omelo_application_keys(new.application_id) k;
    if a.job_id is null
       or new.job_id is distinct from a.job_id
       or new.company_id is distinct from a.company_id
       or new.person_id is distinct from a.person_id then
      raise exception 'Offer does not match its application' using errcode = '23514';
    end if;
  end if;

  if omelo_private.omelo_is_privileged() then
    return coalesce(new, old);
  end if;

  if tg_op = 'INSERT' then
    if new.status <> 'draft' or new.sent_at is not null or new.responded_at is not null
       or new.viewed_at is not null then
      raise exception 'Create the offer as a draft, then send it' using errcode = '42501';
    end if;
    new.created_by := auth.uid();
    return new;
  elsif tg_op = 'UPDATE' then
    if old.status <> 'draft' or new.status <> 'draft'
       or new.sent_at is distinct from old.sent_at
       or new.viewed_at is distinct from old.viewed_at
       or new.responded_at is distinct from old.responded_at then
      raise exception 'A sent offer cannot be edited; withdraw it and send a new one' using errcode = '42501';
    end if;
    return new;
  else
    if old.status <> 'draft' then
      raise exception 'A sent offer is part of the hiring record and cannot be deleted' using errcode = '42501';
    end if;
    return old;
  end if;
end;
$$;

drop trigger if exists offers_guard on offers;
create trigger offers_guard
  before insert or update or delete on offers
  for each row execute function omelo_private.omelo_guard_offer();

drop policy if exists offers_candidate_respond on offers;

-- interviews: scheduling, confirmation and outcomes are functions; employers
-- may still edit logistics directly.
create or replace function omelo_private.omelo_guard_interview()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
declare a record;
begin
  if tg_op in ('INSERT', 'UPDATE') then
    select k.job_id, k.company_id, k.person_id into a from omelo_private.omelo_application_keys(new.application_id) k;
    if a.job_id is null
       or new.job_id is distinct from a.job_id
       or new.company_id is distinct from a.company_id
       or new.person_id is distinct from a.person_id then
      raise exception 'Interview does not match its application' using errcode = '23514';
    end if;
  end if;

  if omelo_private.omelo_is_privileged() then
    return coalesce(new, old);
  end if;

  if tg_op = 'INSERT' then
    raise exception 'Schedule interviews with omelo_schedule_interview' using errcode = '42501';
  elsif tg_op = 'DELETE' then
    raise exception 'Cancel an interview instead of deleting it' using errcode = '42501';
  end if;

  if new.status is distinct from old.status
  or new.scheduled_at is distinct from old.scheduled_at
  or new.candidate_confirmed_at is distinct from old.candidate_confirmed_at
  or new.completed_at is distinct from old.completed_at
  or new.cancelled_at is distinct from old.cancelled_at
  or new.cancel_reason is distinct from old.cancel_reason
  or new.round is distinct from old.round
  or new.type is distinct from old.type
  or new.created_by is distinct from old.created_by then
    raise exception 'Interview status changes go through Omelo interview actions' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists interviews_guard on interviews;
create trigger interviews_guard
  before insert or update or delete on interviews
  for each row execute function omelo_private.omelo_guard_interview();

-- employments: created only by accepting an offer. Employers can record the end.
drop policy if exists employments_company on employments;

create policy employments_company_read on employments
  for select to authenticated
  using (omelo_private.omelo_has_company_role(company_id,
    array['owner','admin','hr','recruiter','hiring_manager']::company_role[]));

create policy employments_company_update on employments
  for update to authenticated
  using (omelo_private.omelo_has_company_role(company_id, array['owner','admin','hr']::company_role[]))
  with check (omelo_private.omelo_has_company_role(company_id, array['owner','admin','hr']::company_role[]));

create or replace function omelo_private.omelo_guard_employment()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if omelo_private.omelo_is_privileged() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    raise exception 'Employment records are created when a worker accepts an offer' using errcode = '42501';
  end if;
  if new.person_id is distinct from old.person_id
  or new.company_id is distinct from old.company_id
  or new.job_id is distinct from old.job_id
  or new.application_id is distinct from old.application_id
  or new.offer_id is distinct from old.offer_id
  or new.title is distinct from old.title
  or new.profession_id is distinct from old.profession_id
  or new.started_on is distinct from old.started_on
  or new.is_omelo_hire is distinct from old.is_omelo_hire then
    raise exception 'Only the end of an employment (status, end date, reason) can be updated' using errcode = '42501';
  end if;
  if new.ended_on is not null and new.ended_on < new.started_on then
    raise exception 'End date is before the start date' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists employments_guard on employments;
create trigger employments_guard
  before insert or update on employments
  for each row execute function omelo_private.omelo_guard_employment();

-- The verified experience follows the employment it came from.
create or replace function omelo_private.omelo_employment_sync_experience()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if new.ended_on is distinct from old.ended_on or new.status is distinct from old.status then
    update experiences
       set ended_on = new.ended_on,
           is_current = (new.status in ('active','on_notice') and new.ended_on is null)
     where verified_employment_id = new.id;
  end if;
  return new;
end;
$$;
revoke execute on function omelo_private.omelo_employment_sync_experience() from public, anon, authenticated;

drop trigger if exists employments_sync_experience on employments;
create trigger employments_sync_experience
  after update on employments
  for each row execute function omelo_private.omelo_employment_sync_experience();

-- Trust fields on the worker's own records. A worker owns their profile, but
-- "verified" is a claim Omelo makes, so only Omelo may set it. Verified rows
-- keep their facts locked; the worker can still delete them.
-- TG_ARGV = the columns that are locked once the row is verified.
create or replace function omelo_private.omelo_guard_trust_fields()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
declare
  n jsonb := to_jsonb(new);
  o jsonb;
  col text;
begin
  if omelo_private.omelo_is_privileged() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if coalesce((n->>'is_verified')::boolean, false)
       or (n ? 'verified_employment_id' and n->>'verified_employment_id' is not null)
       or (n ? 'verification_status' and coalesce(n->>'verification_status', 'unverified') not in ('unverified','pending'))
       or (tg_table_name = 'person_skills' and n->>'evidence_type' in ('employer_verified','assessment'))
       or (n ? 'source' and n->>'source' in ('employer','admin','partner')) then
      raise exception 'Verification is added by Omelo, not by the profile owner' using errcode = '42501';
    end if;
    return new;
  end if;

  o := to_jsonb(old);
  foreach col in array array['is_verified','verified_employment_id','verification_status','evidence_type','source'] loop
    continue when not (n ? col) or (n->col) is not distinct from (o->col);
    continue when col = 'verification_status'
              and n->>col in ('unverified','pending') and o->>col in ('unverified','pending');
    continue when col = 'evidence_type'
              and coalesce(n->>col, '') not in ('employer_verified','assessment')
              and coalesce(o->>col, '') not in ('employer_verified','assessment');
    continue when col = 'source'
              and coalesce(n->>col, '') not in ('employer','admin','partner')
              and coalesce(o->>col, '') not in ('employer','admin','partner');
    raise exception 'Verification is added by Omelo, not by the profile owner' using errcode = '42501';
  end loop;

  if coalesce((o->>'is_verified')::boolean, false) then
    foreach col in array tg_argv loop
      if (n->col) is distinct from (o->col) then
        raise exception 'This record is verified, so % cannot be edited', col using errcode = '42501';
      end if;
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists experiences_guard_trust on experiences;
create trigger experiences_guard_trust before insert or update on experiences
  for each row execute function omelo_private.omelo_guard_trust_fields(
    'person_id','company_id','employer_name','title','profession_id','started_on','ended_on','is_current','work_type');

drop trigger if exists person_skills_guard_trust on person_skills;
create trigger person_skills_guard_trust before insert or update on person_skills
  for each row execute function omelo_private.omelo_guard_trust_fields('person_id','skill_id');

drop trigger if exists educations_guard_trust on educations;
create trigger educations_guard_trust before insert or update on educations
  for each row execute function omelo_private.omelo_guard_trust_fields(
    'person_id','institution_id','institution_name','level','field_of_study','started_on','ended_on');

drop trigger if exists person_credentials_guard_trust on person_credentials;
create trigger person_credentials_guard_trust before insert or update on person_credentials
  for each row execute function omelo_private.omelo_guard_trust_fields(
    'person_id','credential_type_id','name','issuer','credential_number','issued_on','expires_on');

drop trigger if exists person_licenses_guard_trust on person_licenses;
create trigger person_licenses_guard_trust before insert or update on person_licenses
  for each row execute function omelo_private.omelo_guard_trust_fields(
    'person_id','license_type_id','license_class','license_number','issued_on','expires_on');

drop trigger if exists person_references_guard_trust on person_references;
create trigger person_references_guard_trust before insert or update on person_references
  for each row execute function omelo_private.omelo_guard_trust_fields(
    'person_id','name','company_name','phone','email');

drop trigger if exists work_authorizations_guard_trust on work_authorizations;
create trigger work_authorizations_guard_trust before insert or update on work_authorizations
  for each row execute function omelo_private.omelo_guard_trust_fields(
    'person_id','country_code','status','expires_on');

-- companies: the verified badge and hiring stats are Omelo's to set.
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
    new.response_rate_pct := null;
    new.median_response_hours := null;
    new.total_hires := 0;
    new.stats_computed_at := null;
    return new;
  end if;
  if new.is_verified is distinct from old.is_verified
  or new.verified_at is distinct from old.verified_at
  or new.verification_method is distinct from old.verification_method then
    raise exception 'Company verification is done by Omelo' using errcode = '42501';
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

drop trigger if exists companies_guard_trust on companies;
create trigger companies_guard_trust before insert or update on companies
  for each row execute function omelo_private.omelo_guard_company_trust();

-- ============================================================
-- AUDIT: who did it, and a meaningful event type
-- ============================================================
create or replace function public.omelo_log_application_event()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare
  v_uid uuid := auth.uid();
  v_actor actor_type;
  v_type application_event_type;
begin
  if tg_op = 'INSERT' then
    insert into application_events (application_id, event_type, actor_type, actor_id, to_state, to_stage_id)
    values (new.id, 'created', 'candidate', new.person_id, new.state, new.stage_id);
    return new;
  end if;

  v_actor := case when v_uid is null then 'system'
                  when v_uid = new.person_id then 'candidate'
                  else 'recruiter' end;

  if new.state is distinct from old.state then
    v_type := case new.state
      when 'viewed'                then 'viewed'
      when 'shortlisted'           then 'shortlisted'
      when 'withdrawn'             then 'withdrawn'
      when 'expired'               then 'expired'
      when 'offer'                 then 'offer_extended'
      when 'hired'                 then 'decision_made'
      when 'rejected'              then 'decision_made'
      when 'declined_by_candidate' then 'decision_made'
      else 'stage_changed' end;
    insert into application_events
      (application_id, event_type, actor_type, actor_id,
       from_state, to_state, from_stage_id, to_stage_id, reason)
    values
      (new.id, v_type, v_actor, v_uid,
       old.state, new.state, old.stage_id, new.stage_id,
       case new.state when 'rejected' then new.rejection_reason
                      when 'withdrawn' then new.withdrawal_reason end);
  elsif old.first_viewed_at is null and new.first_viewed_at is not null then
    insert into application_events (application_id, event_type, actor_type, actor_id, from_state, to_state)
    values (new.id, 'viewed', v_actor, v_uid, old.state, new.state);
  end if;
  return new;
end;
$$;

-- Verified employment -> verified experience, now on the identity the worker
-- applied with, and with the verification pointing at the experience itself.
create or replace function public.omelo_employment_to_experience()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare
  v_employer text;
  v_identity uuid;
  v_experience uuid;
begin
  select c.display_name into v_employer from companies c where c.id = new.company_id;
  select a.work_identity_id into v_identity from applications a where a.id = new.application_id;

  insert into experiences (
    person_id, work_identity_id, company_id, employer_name, profession_id, title,
    work_type, workplace_type, location_id, started_on, ended_on,
    is_current, is_verified, verified_employment_id, source
  ) values (
    new.person_id, v_identity, new.company_id, coalesce(v_employer, 'Unknown'), new.profession_id, new.title,
    new.work_type, new.workplace_type, new.location_id, new.started_on, new.ended_on,
    (new.status in ('active','on_notice') and new.ended_on is null), true, new.id, 'employer'
  )
  returning id into v_experience;

  insert into verifications (subject_type, subject_id, person_id, type, status, method, claim, verified_at)
  values ('experience', v_experience, new.person_id, 'employment', 'verified', 'employer_confirmation',
          jsonb_build_object('employment_id', new.id, 'offer_id', new.offer_id,
                             'application_id', new.application_id, 'basis', 'hired_through_omelo'),
          now());
  return new;
end;
$$;

-- ============================================================
-- HIRING FUNCTIONS (client-callable, authorise first)
-- ============================================================

create or replace function omelo_private.omelo_notify(
  p_person uuid, p_type notification_type, p_title text, p_body text,
  p_entity_type text, p_entity_id uuid, p_deeplink text default null
) returns void
language sql security definer
set search_path = public, omelo_private
as $$
  insert into notifications (person_id, type, title, body, entity_type, entity_id, deeplink)
  values (p_person, p_type, p_title, p_body, p_entity_type, p_entity_id, p_deeplink);
$$;
revoke execute on function omelo_private.omelo_notify(uuid, notification_type, text, text, text, uuid, text)
  from public, anon, authenticated;

-- Move to a state, landing on the job's first stage for that state.
create or replace function omelo_private.omelo_set_application_state(p_application_id uuid, p_state application_state)
returns void
language sql security definer
set search_path = public, omelo_private
as $$
  update applications a
     set stage_id = (select s.id from job_stages s
                      where s.job_id = a.job_id and s.maps_to_state = p_state
                      order by s.position limit 1),
         state = p_state
   where a.id = p_application_id and a.state is distinct from p_state;
$$;
revoke execute on function omelo_private.omelo_set_application_state(uuid, application_state)
  from public, anon, authenticated;

create or replace function omelo_private.omelo_employer_application(p_application_id uuid)
returns applications
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare a applications;
begin
  if auth.uid() is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;
  select * into a from applications where id = p_application_id;
  if a.id is null or not omelo_private.omelo_can_access_job(a.job_id) then
    raise exception 'Application not found, or you do not have access to it' using errcode = '42501';
  end if;
  return a;
end;
$$;
revoke execute on function omelo_private.omelo_employer_application(uuid) from public, anon, authenticated;

-- Shortlist / screening / assessment / interview (and back), for open applications.
create or replace function public.omelo_move_application(p_application_id uuid, p_state application_state)
returns application_state
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare a applications; v_company text;
begin
  a := omelo_private.omelo_employer_application(p_application_id);
  if p_state not in ('viewed','shortlisted','screening','assessment','interview') then
    raise exception 'Use the reject, offer or hire actions for %', p_state using errcode = '22023';
  end if;
  if a.state not in ('applied','viewed','shortlisted','screening','assessment','interview') then
    raise exception 'This application is % and cannot be moved', a.state using errcode = '22023';
  end if;
  if a.first_viewed_at is null then
    update applications set first_viewed_at = now() where id = a.id;
  end if;
  perform omelo_private.omelo_set_application_state(a.id, p_state);

  if p_state = 'shortlisted' and a.state <> 'shortlisted' then
    select c.display_name into v_company from companies c where c.id = a.company_id;
    perform omelo_private.omelo_notify(a.person_id, 'application_update',
      'You were shortlisted',
      coalesce(v_company, 'The employer') || ' shortlisted you for ' ||
        (select title from jobs where id = a.job_id) || '.',
      'application', a.id, '/applications/' || a.id);
  end if;
  return p_state;
end;
$$;

create or replace function public.omelo_reject_application(p_application_id uuid, p_reason text)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare a applications; v_company text;
begin
  a := omelo_private.omelo_employer_application(p_application_id);
  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'A reason is required to reject a candidate' using errcode = '22023';
  end if;
  if not omelo_private.omelo_is_open_state(a.state) then
    raise exception 'This application is already %', a.state using errcode = '22023';
  end if;

  update interviews set status = 'cancelled', cancelled_at = now(), cancel_reason = 'Application closed'
   where application_id = a.id and status in ('scheduled','rescheduled');
  update offers set status = 'withdrawn', responded_at = coalesce(responded_at, now())
   where application_id = a.id and status in ('sent','viewed','negotiating','draft');

  update applications
     set rejection_reason = trim(p_reason),
         rejected_by = auth.uid(),
         first_viewed_at = coalesce(first_viewed_at, now())
   where id = a.id;
  perform omelo_private.omelo_set_application_state(a.id, 'rejected');

  select c.display_name into v_company from companies c where c.id = a.company_id;
  perform omelo_private.omelo_notify(a.person_id, 'application_update',
    'Application update',
    coalesce(v_company, 'The employer') || ' is not moving forward with your application for ' ||
      (select title from jobs where id = a.job_id) || '.',
    'application', a.id, '/applications/' || a.id);
end;
$$;

create or replace function public.omelo_withdraw_application(p_application_id uuid, p_reason text default null)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare a applications;
begin
  select * into a from applications where id = p_application_id and person_id = auth.uid();
  if a.id is null then
    raise exception 'Application not found' using errcode = '42501';
  end if;
  if not omelo_private.omelo_is_open_state(a.state) then
    raise exception 'This application is already %', a.state using errcode = '22023';
  end if;
  update interviews set status = 'cancelled', cancelled_at = now(), cancel_reason = 'Candidate withdrew'
   where application_id = a.id and status in ('scheduled','rescheduled');
  update offers set status = 'declined', responded_at = now(), decline_reason = coalesce(p_reason, 'Candidate withdrew')
   where application_id = a.id and status in ('sent','viewed','negotiating');
  update applications set withdrawal_reason = nullif(trim(p_reason), '') where id = a.id;
  perform omelo_private.omelo_set_application_state(a.id, 'withdrawn');
end;
$$;

-- Interviews ------------------------------------------------------------------

create or replace function public.omelo_schedule_interview(
  p_application_id uuid,
  p_type interview_type,
  p_scheduled_at timestamptz,
  p_duration_minutes integer default 30,
  p_timezone text default null,
  p_meeting_url text default null,
  p_location_text text default null,
  p_instructions text default null
) returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare a applications; v_id uuid; v_round int; v_company text;
begin
  a := omelo_private.omelo_employer_application(p_application_id);
  if a.state not in ('applied','viewed','shortlisted','screening','assessment','interview') then
    raise exception 'Cannot schedule an interview for a % application', a.state using errcode = '22023';
  end if;
  if p_scheduled_at is null or p_scheduled_at < now() - interval '10 minutes' then
    raise exception 'Choose a time in the future' using errcode = '22023';
  end if;

  select coalesce(max(round), 0) + 1 into v_round from interviews where application_id = a.id;

  insert into interviews (application_id, job_id, company_id, person_id, type, status, round,
                          scheduled_at, duration_minutes, timezone, meeting_url, location_text,
                          instructions, created_by)
  values (a.id, a.job_id, a.company_id, a.person_id, p_type, 'scheduled', v_round,
          p_scheduled_at, greatest(5, least(coalesce(p_duration_minutes, 30), 600)),
          p_timezone, nullif(trim(p_meeting_url), ''),
          coalesce(nullif(trim(p_location_text), ''),
                   case when p_type not in ('phone','video') then (select location_text from jobs where id = a.job_id) end),
          nullif(trim(p_instructions), ''), auth.uid())
  returning id into v_id;

  insert into interview_interviewers (interview_id, person_id, is_lead)
  values (v_id, auth.uid(), true) on conflict do nothing;

  update applications set first_viewed_at = coalesce(first_viewed_at, now()) where id = a.id;
  perform omelo_private.omelo_set_application_state(a.id, 'interview');

  insert into application_events (application_id, event_type, actor_type, actor_id, from_state, to_state, metadata)
  values (a.id, 'interview_scheduled', 'recruiter', auth.uid(), a.state, 'interview',
          jsonb_build_object('interview_id', v_id, 'round', v_round, 'type', p_type, 'scheduled_at', p_scheduled_at));

  select c.display_name into v_company from companies c where c.id = a.company_id;
  perform omelo_private.omelo_notify(a.person_id, 'interview_scheduled',
    'Interview scheduled',
    coalesce(v_company, 'The employer') || ' invited you to a ' || replace(p_type::text, '_', ' ') ||
      ' interview. Please confirm you can attend.',
    'interview', v_id, '/applications/' || a.id);
  return v_id;
end;
$$;

create or replace function public.omelo_reschedule_interview(
  p_interview_id uuid, p_scheduled_at timestamptz, p_reason text default null
) returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare i interviews;
begin
  select * into i from interviews where id = p_interview_id;
  if i.id is null or not omelo_private.omelo_can_access_job(i.job_id) then
    raise exception 'Interview not found, or you do not have access to it' using errcode = '42501';
  end if;
  if i.status not in ('scheduled','rescheduled') then
    raise exception 'This interview is %', i.status using errcode = '22023';
  end if;
  if p_scheduled_at is null or p_scheduled_at < now() - interval '10 minutes' then
    raise exception 'Choose a time in the future' using errcode = '22023';
  end if;
  update interviews set scheduled_at = p_scheduled_at, status = 'rescheduled', candidate_confirmed_at = null
   where id = i.id;
  insert into application_events (application_id, event_type, actor_type, actor_id, reason, metadata)
  values (i.application_id, 'interview_scheduled', 'recruiter', auth.uid(), p_reason,
          jsonb_build_object('interview_id', i.id, 'rescheduled_from', i.scheduled_at, 'scheduled_at', p_scheduled_at));
  perform omelo_private.omelo_notify(i.person_id, 'interview_scheduled', 'Interview time changed',
    'Your interview was moved. Please confirm the new time.', 'interview', i.id, '/applications/' || i.application_id);
end;
$$;

create or replace function public.omelo_confirm_interview(p_interview_id uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare i interviews;
begin
  select * into i from interviews where id = p_interview_id and person_id = auth.uid();
  if i.id is null then
    raise exception 'Interview not found' using errcode = '42501';
  end if;
  if i.status not in ('scheduled','rescheduled') then
    raise exception 'This interview is %', i.status using errcode = '22023';
  end if;
  update interviews set candidate_confirmed_at = now() where id = i.id;
  insert into application_events (application_id, event_type, actor_type, actor_id, metadata)
  values (i.application_id, 'interview_scheduled', 'candidate', auth.uid(),
          jsonb_build_object('interview_id', i.id, 'confirmed', true));
end;
$$;

create or replace function public.omelo_cancel_interview(p_interview_id uuid, p_reason text)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare i interviews; v_is_candidate boolean;
begin
  select * into i from interviews where id = p_interview_id;
  v_is_candidate := i.person_id = auth.uid();
  if i.id is null or not (v_is_candidate or omelo_private.omelo_can_access_job(i.job_id)) then
    raise exception 'Interview not found, or you do not have access to it' using errcode = '42501';
  end if;
  if i.status not in ('scheduled','rescheduled') then
    raise exception 'This interview is %', i.status using errcode = '22023';
  end if;
  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'A reason is required to cancel' using errcode = '22023';
  end if;
  update interviews set status = 'cancelled', cancelled_at = now(), cancel_reason = trim(p_reason) where id = i.id;
  insert into application_events (application_id, event_type, actor_type, actor_id, reason, metadata)
  values (i.application_id, 'interview_completed',
          case when v_is_candidate then 'candidate' else 'recruiter' end::actor_type, auth.uid(), trim(p_reason),
          jsonb_build_object('interview_id', i.id, 'outcome', 'cancelled'));
  if not v_is_candidate then
    perform omelo_private.omelo_notify(i.person_id, 'interview_scheduled', 'Interview cancelled',
      trim(p_reason), 'interview', i.id, '/applications/' || i.application_id);
  end if;
end;
$$;

-- Outcome is visible to the candidate; the scorecard is an employer-only note.
create or replace function public.omelo_complete_interview(
  p_interview_id uuid,
  p_outcome interview_status default 'completed',
  p_rating smallint default null,
  p_recommendation text default null,
  p_notes text default null
) returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare i interviews;
begin
  select * into i from interviews where id = p_interview_id;
  if i.id is null or not omelo_private.omelo_can_access_job(i.job_id) then
    raise exception 'Interview not found, or you do not have access to it' using errcode = '42501';
  end if;
  if i.status not in ('scheduled','rescheduled') then
    raise exception 'This interview is already %', i.status using errcode = '22023';
  end if;
  if p_outcome not in ('completed','no_show_candidate','no_show_employer') then
    raise exception 'Outcome must be completed or a no-show' using errcode = '22023';
  end if;
  if p_rating is not null and p_rating not between 1 and 5 then
    raise exception 'Rating is 1 to 5' using errcode = '22023';
  end if;
  if p_recommendation is not null and p_recommendation not in ('strong_yes','yes','no','strong_no') then
    raise exception 'Recommendation must be strong_yes, yes, no or strong_no' using errcode = '22023';
  end if;

  update interviews set status = p_outcome, completed_at = now() where id = i.id;

  insert into application_events (application_id, event_type, actor_type, actor_id, metadata)
  values (i.application_id, 'interview_completed', 'recruiter', auth.uid(),
          jsonb_build_object('interview_id', i.id, 'round', i.round, 'outcome', p_outcome));

  if p_rating is not null or p_recommendation is not null or coalesce(trim(p_notes), '') <> '' then
    insert into application_notes (application_id, company_id, author_id, body)
    values (i.application_id, i.company_id, auth.uid(),
            'Interview round ' || i.round || ' scorecard' ||
            coalesce(E'\nRating: ' || p_rating || '/5', '') ||
            coalesce(E'\nRecommendation: ' || replace(p_recommendation, '_', ' '), '') ||
            coalesce(E'\n' || nullif(trim(p_notes), ''), ''));
  end if;
end;
$$;

-- Offers ------------------------------------------------------------------------

create or replace function public.omelo_send_offer(
  p_application_id uuid,
  p_pay_amount numeric,
  p_pay_period pay_period,
  p_start_date date,
  p_title text default null,
  p_expires_at timestamptz default null,
  p_conditions text default null,
  p_benefits jsonb default null
) returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare a applications; j jobs; v_id uuid; v_company text;
begin
  a := omelo_private.omelo_employer_application(p_application_id);
  if a.state not in ('applied','viewed','shortlisted','screening','assessment','interview') then
    raise exception 'Cannot send an offer to a % application', a.state using errcode = '22023';
  end if;
  if exists (select 1 from offers where application_id = a.id and status in ('sent','viewed','negotiating')) then
    raise exception 'An offer is already open; withdraw it first' using errcode = '22023';
  end if;
  if p_pay_amount is null or p_pay_amount <= 0 then
    raise exception 'Enter the pay for this offer' using errcode = '22023';
  end if;
  if p_start_date is null or p_start_date < current_date then
    raise exception 'Choose a start date from today onwards' using errcode = '22023';
  end if;
  if p_expires_at is not null and p_expires_at <= now() then
    raise exception 'The offer must expire in the future' using errcode = '22023';
  end if;

  select * into j from jobs where id = a.job_id;

  -- Drafts for this application are superseded by the offer actually sent.
  delete from offers where application_id = a.id and status = 'draft';

  insert into offers (application_id, job_id, company_id, person_id, status, title,
                      pay_amount, pay_period, pay_currency, pay_basis, work_type, workplace_type,
                      location_text, start_date, hours_per_week, shift_types, benefits, conditions,
                      expires_at, sent_at, created_by)
  values (a.id, a.job_id, a.company_id, a.person_id, 'sent', coalesce(nullif(trim(p_title), ''), j.title),
          p_pay_amount, p_pay_period, coalesce(j.pay_currency, 'INR'), coalesce(j.pay_basis, 'gross'),
          j.work_type, j.workplace_type, j.location_text, p_start_date, j.hours_per_week,
          coalesce(j.shift_types, '{}'),
          coalesce(p_benefits, (select coalesce(jsonb_agg(benefit_type), '[]') from job_benefits where job_id = j.id)),
          nullif(trim(p_conditions), ''),
          coalesce(p_expires_at, now() + interval '7 days'), now(), auth.uid())
  returning id into v_id;

  update applications set first_viewed_at = coalesce(first_viewed_at, now()) where id = a.id;
  perform omelo_private.omelo_set_application_state(a.id, 'offer');

  update application_events
     set metadata = coalesce(metadata, '{}') || jsonb_build_object('offer_id', v_id)
   where id = (select max(id) from application_events where application_id = a.id and event_type = 'offer_extended');

  select c.display_name into v_company from companies c where c.id = a.company_id;
  perform omelo_private.omelo_notify(a.person_id, 'offer_received',
    'You received a job offer',
    coalesce(v_company, 'The employer') || ' offered you ' || coalesce(nullif(trim(p_title), ''), j.title) || '.',
    'offer', v_id, '/applications/' || a.id);
  return v_id;
end;
$$;

create or replace function public.omelo_withdraw_offer(p_offer_id uuid, p_reason text)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare o offers; v_back application_state;
begin
  select * into o from offers where id = p_offer_id;
  if o.id is null or not omelo_private.omelo_has_company_role(o.company_id,
       array['owner','admin','recruiter','hiring_manager','hr']::company_role[]) then
    raise exception 'Offer not found, or you do not have access to it' using errcode = '42501';
  end if;
  if o.status not in ('sent','viewed','negotiating') then
    raise exception 'This offer is %', o.status using errcode = '22023';
  end if;
  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'A reason is required to withdraw an offer' using errcode = '22023';
  end if;
  update offers set status = 'withdrawn', responded_at = now(), decline_reason = trim(p_reason) where id = o.id;

  -- Return the application to where it was before the offer.
  select from_state into v_back from application_events
   where application_id = o.application_id and to_state = 'offer' order by id desc limit 1;
  if (select state from applications where id = o.application_id) = 'offer' then
    perform omelo_private.omelo_set_application_state(o.application_id,
      case when v_back in ('applied','viewed','shortlisted','screening','assessment','interview')
           then v_back else 'shortlisted' end);
  end if;
  insert into application_events (application_id, event_type, actor_type, actor_id, reason, metadata)
  values (o.application_id, 'offer_responded', 'recruiter', auth.uid(), trim(p_reason),
          jsonb_build_object('offer_id', o.id, 'status', 'withdrawn'));
  perform omelo_private.omelo_notify(o.person_id, 'application_update', 'Offer withdrawn',
    trim(p_reason), 'offer', o.id, '/applications/' || o.application_id);
end;
$$;

create or replace function public.omelo_view_offer(p_offer_id uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  update offers
     set viewed_at = coalesce(viewed_at, now()),
         status = case when status = 'sent' then 'viewed'::offer_status else status end
   where id = p_offer_id and person_id = auth.uid() and status in ('sent','viewed','negotiating');
end;
$$;

-- ACCEPT -> hired -> employment -> verified experience on the worker's identity.
create or replace function public.omelo_respond_to_offer(
  p_offer_id uuid, p_accept boolean, p_reason text default null
) returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare
  o offers; j jobs; a applications;
  v_employment uuid; v_experience uuid; v_notify uuid;
begin
  select * into o from offers where id = p_offer_id and person_id = auth.uid() for update;
  if o.id is null then
    raise exception 'Offer not found' using errcode = '42501';
  end if;
  if o.status not in ('sent','viewed','negotiating') then
    raise exception 'This offer is %', o.status using errcode = '22023';
  end if;
  if o.expires_at is not null and o.expires_at < now() then
    raise exception 'This offer has expired' using errcode = '22023';
  end if;
  select * into a from applications where id = o.application_id;
  if a.state <> 'offer' then
    raise exception 'This application is %', a.state using errcode = '22023';
  end if;
  select * into j from jobs where id = o.job_id;

  if p_accept then
    update offers set status = 'accepted', responded_at = now(), viewed_at = coalesce(viewed_at, now())
     where id = o.id;
    perform omelo_private.omelo_set_application_state(a.id, 'hired');

    insert into employments (person_id, company_id, job_id, application_id, offer_id, profession_id,
                             title, department_id, work_type, workplace_type, location_id,
                             started_on, status, is_omelo_hire)
    values (o.person_id, o.company_id, o.job_id, a.id, o.id, j.profession_id,
            o.title, j.department_id, coalesce(o.work_type, j.work_type), coalesce(o.workplace_type, j.workplace_type),
            j.location_id, coalesce(o.start_date, current_date), 'active', true)
    returning id into v_employment;

    select id into v_experience from experiences where verified_employment_id = v_employment;

    update companies set total_hires = coalesce(total_hires, 0) + 1 where id = o.company_id;

    insert into application_events (application_id, event_type, actor_type, actor_id, metadata)
    values (a.id, 'offer_responded', 'candidate', auth.uid(),
            jsonb_build_object('offer_id', o.id, 'status', 'accepted',
                               'employment_id', v_employment, 'experience_id', v_experience));
  else
    update offers set status = 'declined', responded_at = now(), decline_reason = nullif(trim(p_reason), '')
     where id = o.id;
    perform omelo_private.omelo_set_application_state(a.id, 'declined_by_candidate');
    insert into application_events (application_id, event_type, actor_type, actor_id, reason, metadata)
    values (a.id, 'offer_responded', 'candidate', auth.uid(), nullif(trim(p_reason), ''),
            jsonb_build_object('offer_id', o.id, 'status', 'declined'));
  end if;

  -- Tell whoever sent the offer.
  v_notify := coalesce(o.created_by, j.created_by);
  if v_notify is not null then
    perform omelo_private.omelo_notify(v_notify, 'application_update',
      case when p_accept then 'Offer accepted' else 'Offer declined' end,
      coalesce((select display_name from persons where id = o.person_id), 'The candidate') ||
        case when p_accept then ' accepted your offer for ' else ' declined your offer for ' end || o.title || '.',
      'application', a.id, '/dashboard/candidates/' || a.id);
  end if;

  return jsonb_build_object('status', case when p_accept then 'accepted' else 'declined' end,
                            'employment_id', v_employment, 'experience_id', v_experience);
end;
$$;

-- viewed marker now also opens the audit trail with the reviewer's identity.
create or replace function public.omelo_mark_application_viewed(p_application_id uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare a applications;
begin
  a := omelo_private.omelo_employer_application(p_application_id);
  if a.first_viewed_at is not null then
    return;
  end if;
  update applications
     set first_viewed_at = now(),
         last_activity_at = now(),
         state = case when state = 'applied' then 'viewed'::application_state else state end,
         stage_id = case when state = 'applied'
                         then coalesce((select s.id from job_stages s where s.job_id = a.job_id
                                         and s.maps_to_state = 'viewed' order by s.position limit 1), stage_id)
                         else stage_id end
   where id = a.id;
end;
$$;

-- ============================================================
-- Matching v1 follow-ups
-- ============================================================

-- Recommendations honour p_limit and come back best first.
create or replace function public.omelo_recommend_jobs(
  p_lat double precision, p_lng double precision,
  p_radius_km integer default 25, p_limit integer default 20,
  p_work_identity_id uuid default null
) returns table (job_id uuid, score int, eligible boolean, distance_km numeric,
                 strengths jsonb, gaps jsonb)
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_identity uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  v_identity := coalesce(p_work_identity_id,
    (select id from work_identities where person_id = auth.uid() and is_primary limit 1));
  if not exists (select 1 from work_identities where id = v_identity and person_id = auth.uid()) then
    raise exception 'Not your work identity' using errcode = '42501';
  end if;

  return query
    with scored as (
      select n.job_id as jid, n.distance_km as km,
             omelo_private.omelo_store_match(v_identity, n.job_id) as r
        from public.omelo_nearby_jobs(p_lat, p_lng, p_radius_km, null, null, 80) n
    )
    select s.jid, (s.r->>'score')::int, (s.r->>'eligible')::boolean, s.km,
           s.r->'strengths', s.r->'gaps'
      from scored s
     order by (s.r->>'eligible')::boolean desc, (s.r->>'score')::int desc, s.km asc
     limit greatest(1, least(coalesce(p_limit, 20), 50));
end;
$$;

-- "Different profession (Cook)" named the worker's profession, which read as
-- if the JOB were a cook. Name both sides.
do $$
declare
  v_def text := pg_get_functiondef('omelo_private.omelo_score_match(uuid, uuid)'::regprocedure);
  v_old text := $q$omelo_factor(0.1, 'gap', 'Different profession' || coalesce(' (' || v_prof_name || ')', ''))$q$;
  v_new text := $q$omelo_factor(0.1, 'gap', coalesce(v_job_prof_name, 'This job') || ' role; profile is ' || coalesce(v_prof_name, 'a different profession'))$q$;
begin
  if position(v_old in v_def) = 0 then
    raise exception 'omelo_score_match does not contain the expected profession_fit text';
  end if;
  execute replace(v_def, v_old, v_new);
end;
$$;

-- ============================================================
-- GRANTS
-- ============================================================
do $$
declare fn text;
begin
  foreach fn in array array[
    'omelo_move_application(uuid, application_state)',
    'omelo_reject_application(uuid, text)',
    'omelo_withdraw_application(uuid, text)',
    'omelo_schedule_interview(uuid, interview_type, timestamptz, integer, text, text, text, text)',
    'omelo_reschedule_interview(uuid, timestamptz, text)',
    'omelo_confirm_interview(uuid)',
    'omelo_cancel_interview(uuid, text)',
    'omelo_complete_interview(uuid, interview_status, smallint, text, text)',
    'omelo_send_offer(uuid, numeric, pay_period, date, text, timestamptz, text, jsonb)',
    'omelo_withdraw_offer(uuid, text)',
    'omelo_view_offer(uuid)',
    'omelo_respond_to_offer(uuid, boolean, text)',
    'omelo_mark_application_viewed(uuid)',
    'omelo_recommend_jobs(double precision, double precision, integer, integer, uuid)'
  ] loop
    execute format('revoke execute on function public.%s from public, anon', fn);
    execute format('grant execute on function public.%s to authenticated', fn);
  end loop;
end;
$$;

grant execute on function omelo_private.omelo_is_privileged() to anon, authenticated;
grant execute on function omelo_private.omelo_is_open_state(application_state) to anon, authenticated;
