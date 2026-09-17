create table if not exists public.domain_events (
  id             bigint generated always as identity primary key,
  event_type     text        not null,
  aggregate_type text        not null,
  aggregate_id   uuid        not null,
  company_id     uuid        references companies(id) on delete set null,
  person_id      uuid        references persons(id)   on delete set null,
  actor_id       uuid,
  payload        jsonb       not null default '{}'::jsonb,
  occurred_at    timestamptz not null default now(),
  processed_at   timestamptz
);

create index if not exists domain_events_unprocessed on domain_events (id) where processed_at is null;
create index if not exists domain_events_type_time   on domain_events (event_type, occurred_at desc);
create index if not exists domain_events_company     on domain_events (company_id, occurred_at desc);

alter table domain_events enable row level security;
revoke all on domain_events from anon, authenticated;

create or replace function omelo_private.omelo_domain_events_append_only()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'domain_events is append-only';
  end if;
  if (to_jsonb(new) - 'processed_at') is distinct from (to_jsonb(old) - 'processed_at') then
    raise exception 'domain_events is append-only (only processed_at may be set)';
  end if;
  return new;
end;
$$;

drop trigger if exists domain_events_append_only on domain_events;
create trigger domain_events_append_only
  before update or delete on domain_events
  for each row execute function omelo_private.omelo_domain_events_append_only();

create or replace function omelo_private.omelo_emit(
  p_type text, p_aggregate_type text, p_aggregate_id uuid,
  p_company uuid, p_person uuid, p_payload jsonb
) returns void
language sql security definer
set search_path = public, omelo_private
as $$
  insert into domain_events (event_type, aggregate_type, aggregate_id, company_id, person_id, actor_id, payload)
  values (p_type, p_aggregate_type, p_aggregate_id, p_company, p_person, auth.uid(), coalesce(p_payload, '{}'));
$$;
revoke execute on function omelo_private.omelo_emit(text, text, uuid, uuid, uuid, jsonb) from public, anon, authenticated;

create or replace function omelo_private.omelo_emit_from_application_event()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare
  a record;
  v_type text;
begin
  select job_id, company_id, person_id, work_identity_id, match_score into a
    from applications where id = new.application_id;

  v_type := case
    when new.event_type = 'created'                                 then 'WorkerApplied'
    when new.event_type = 'viewed'                                  then 'ApplicationViewed'
    when new.event_type = 'shortlisted'                             then 'CandidateShortlisted'
    when new.event_type = 'decision_made' and new.to_state = 'rejected'              then 'CandidateRejected'
    when new.event_type = 'decision_made' and new.to_state = 'hired'                 then 'WorkerHired'
    when new.event_type = 'decision_made' and new.to_state = 'declined_by_candidate' then 'OfferDeclined'
    when new.event_type = 'withdrawn'                               then 'ApplicationWithdrawn'
    when new.event_type = 'interview_scheduled' and new.metadata ? 'confirmed'        then 'InterviewConfirmed'
    when new.event_type = 'interview_scheduled' and new.metadata ? 'rescheduled_from' then 'InterviewRescheduled'
    when new.event_type = 'interview_scheduled'                     then 'InterviewScheduled'
    when new.event_type = 'interview_completed' and new.metadata->>'outcome' = 'cancelled' then 'InterviewCancelled'
    when new.event_type = 'interview_completed'                     then 'InterviewCompleted'
    when new.event_type = 'offer_extended'                          then 'OfferSent'
    when new.event_type = 'offer_responded' and new.metadata->>'status' = 'accepted'  then 'OfferAccepted'
    when new.event_type = 'offer_responded' and new.metadata->>'status' = 'withdrawn' then 'OfferWithdrawn'
    when new.event_type = 'stage_changed'                           then 'ApplicationStageChanged'
    else null end;

  if v_type is null
     or (new.event_type = 'offer_responded' and new.metadata->>'status' = 'declined') then
    return new;
  end if;

  perform omelo_private.omelo_emit(v_type, 'application', new.application_id, a.company_id, a.person_id,
    jsonb_build_object(
      'job_id', a.job_id, 'work_identity_id', a.work_identity_id, 'match_score', a.match_score,
      'from_state', new.from_state, 'to_state', new.to_state,
      'actor_type', new.actor_type, 'reason', new.reason,
      'application_event_id', new.id) || coalesce(new.metadata, '{}'));
  return new;
end;
$$;
revoke execute on function omelo_private.omelo_emit_from_application_event() from public, anon, authenticated;

drop trigger if exists application_events_emit on application_events;
create trigger application_events_emit
  after insert on application_events
  for each row execute function omelo_private.omelo_emit_from_application_event();

create or replace function omelo_private.omelo_emit_employment_verified()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  perform omelo_private.omelo_emit('EmploymentVerified', 'employment', new.id, new.company_id, new.person_id,
    jsonb_build_object('offer_id', new.offer_id, 'application_id', new.application_id, 'job_id', new.job_id,
                       'profession_id', new.profession_id, 'title', new.title, 'started_on', new.started_on));
  return new;
end;
$$;
revoke execute on function omelo_private.omelo_emit_employment_verified() from public, anon, authenticated;

drop trigger if exists employments_emit_verified on employments;
create trigger employments_emit_verified
  after insert on employments
  for each row execute function omelo_private.omelo_emit_employment_verified();

create or replace function omelo_private.omelo_emit_job_status()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if new.status is distinct from old.status and new.status in ('published','closed','paused','expired') then
    perform omelo_private.omelo_emit(
      case new.status when 'published' then 'JobPublished' when 'closed' then 'JobClosed'
                      when 'paused' then 'JobPaused' else 'JobExpired' end,
      'job', new.id, new.company_id, null,
      jsonb_build_object('from_status', old.status, 'profession_id', new.profession_id,
                         'category_id', new.category_id, 'country_code', new.country_code));
  end if;
  return new;
end;
$$;
revoke execute on function omelo_private.omelo_emit_job_status() from public, anon, authenticated;

drop trigger if exists jobs_emit_status on jobs;
create trigger jobs_emit_status
  after update on jobs
  for each row execute function omelo_private.omelo_emit_job_status();

alter function omelo_private.omelo_is_open_state(application_state) set search_path = public, omelo_private;