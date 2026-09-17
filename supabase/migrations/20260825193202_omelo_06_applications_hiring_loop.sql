-- =====================================================================
-- OMELO 06 — Applications, Interviews, Offers, and the Hiring Loop
--
--   JOB -> APPLICATION -> INTERVIEW -> OFFER -> HIRED
--        -> EMPLOYMENT -> VERIFIED EXPERIENCE -> NEXT OPPORTUNITY
--
-- The loop is the whole point: a hire made on Omelo becomes verified
-- work history that makes the person more employable next time.
-- =====================================================================

create table applications (
  id                uuid primary key default gen_random_uuid(),
  job_id            uuid not null references jobs(id) on delete cascade,
  person_id         uuid not null references persons(id) on delete cascade,
  company_id        uuid not null references companies(id) on delete cascade,

  stage_id          uuid references job_stages(id),
  state             application_state not null default 'applied',
  is_archived       boolean generated always as (
                      state in ('rejected','withdrawn','expired','declined_by_candidate')
                    ) stored,

  match_score       smallint check (match_score between 0 and 100),
  cover_note        text,
  answers           jsonb not null default '[]'::jsonb,
  resume_document_id uuid references documents(id) on delete set null,

  -- Immutable copy of the work identity at submission time. Editing the
  -- profile later must never silently change a live application.
  identity_snapshot jsonb not null default '{}'::jsonb,

  applied_via       text not null default 'omelo'
                    check (applied_via in ('omelo','quick_apply','walk_in','phone','import')),
  first_viewed_at   timestamptz,
  last_activity_at  timestamptz not null default now(),
  applied_at        timestamptz not null default now(),
  closed_at         timestamptz,
  rejection_reason  text,
  rejected_by       uuid references persons(id),
  withdrawal_reason text,
  unique (job_id, person_id)
);
create index applications_person_idx  on applications (person_id, applied_at desc);
create index applications_job_idx     on applications (job_id, state);
create index applications_company_idx on applications (company_id, applied_at desc);
create index applications_stale_idx   on applications (last_activity_at)
  where state in ('applied','viewed','shortlisted','screening','assessment','interview','offer');

-- Append-only history. Basis for the candidate timeline, employer
-- response statistics, and any later dispute.
create table application_events (
  id             bigserial primary key,
  application_id uuid not null references applications(id) on delete cascade,
  event_type     application_event_type not null,
  actor_type     actor_type not null,
  actor_id       uuid references persons(id),
  from_state     application_state,
  to_state       application_state,
  from_stage_id  uuid,
  to_stage_id    uuid,
  reason         text,
  metadata       jsonb not null default '{}'::jsonb,
  occurred_at    timestamptz not null default now()
);
create index application_events_app_idx on application_events (application_id, occurred_at);

-- Employer stage moves derive the candidate-visible state automatically.
-- An employer cannot invent a state or hide movement.
create or replace function omelo_sync_application_state()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_state application_state;
begin
  if new.stage_id is not null and new.stage_id is distinct from old.stage_id then
    select js.maps_to_state into v_state from job_stages js where js.id = new.stage_id;
    if v_state is not null then
      new.state := v_state;
    end if;
  end if;

  if new.state is distinct from old.state then
    new.last_activity_at := now();
    if new.state in ('rejected','withdrawn','expired','declined_by_candidate','hired')
       and new.closed_at is null then
      new.closed_at := now();
    end if;
  end if;

  return new;
end;
$$;

create trigger applications_sync_state
  before update on applications
  for each row execute function omelo_sync_application_state();

-- Log every state change immutably.
create or replace function omelo_log_application_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into application_events (application_id, event_type, actor_type, actor_id, to_state)
    values (new.id, 'created', 'candidate', new.person_id, new.state);
  elsif new.state is distinct from old.state then
    insert into application_events
      (application_id, event_type, actor_type, actor_id,
       from_state, to_state, from_stage_id, to_stage_id, reason)
    values
      (new.id, 'stage_changed', 'system', null,
       old.state, new.state, old.stage_id, new.stage_id, new.rejection_reason);
  end if;
  return new;
end;
$$;

create trigger applications_log_event
  after insert or update on applications
  for each row execute function omelo_log_application_event();

-- ---------------------------------------------------------------
-- Interviews
-- ---------------------------------------------------------------
create table interviews (
  id             uuid primary key default gen_random_uuid(),
  application_id uuid not null references applications(id) on delete cascade,
  job_id         uuid not null references jobs(id) on delete cascade,
  company_id     uuid not null references companies(id) on delete cascade,
  person_id      uuid not null references persons(id) on delete cascade,
  type           interview_type not null,
  status         interview_status not null default 'scheduled',
  round          smallint not null default 1,
  scheduled_at   timestamptz,
  duration_minutes smallint,
  timezone       text,
  meeting_url    text,
  location_text  text,
  geo            extensions.geography(Point,4326),
  instructions   text,
  candidate_confirmed_at timestamptz,
  completed_at   timestamptz,
  cancelled_at   timestamptz,
  cancel_reason  text,
  created_by     uuid references persons(id),
  created_at     timestamptz not null default now()
);
create index interviews_application_idx on interviews (application_id);
create index interviews_company_idx     on interviews (company_id, scheduled_at);
create index interviews_person_idx      on interviews (person_id, scheduled_at);

create table interview_interviewers (
  interview_id uuid not null references interviews(id) on delete cascade,
  person_id    uuid not null references persons(id) on delete cascade,
  is_lead      boolean not null default false,
  primary key (interview_id, person_id)
);

create table interview_scorecards (
  id             uuid primary key default gen_random_uuid(),
  interview_id   uuid not null references interviews(id) on delete cascade,
  interviewer_id uuid not null references persons(id) on delete cascade,
  scores         jsonb not null default '{}'::jsonb,
  overall_score  numeric(3,1) check (overall_score between 0 and 5),
  recommendation interview_recommendation,
  notes          text,
  submitted_at   timestamptz not null default now(),
  unique (interview_id, interviewer_id)
);

comment on table interview_scorecards is
  'An interviewer must not read peer scorecards before submitting their own. Enforced in the service layer to prevent anchoring.';

-- ---------------------------------------------------------------
-- Assessments
-- ---------------------------------------------------------------
create table assessments (
  id             uuid primary key default gen_random_uuid(),
  application_id uuid not null references applications(id) on delete cascade,
  job_id         uuid not null references jobs(id) on delete cascade,
  name           text not null,
  kind           text not null default 'custom'
                 check (kind in ('custom','partner','trial_shift','practical','questionnaire')),
  provider       text,
  external_url   text,
  sent_at        timestamptz,
  due_at         timestamptz,
  completed_at   timestamptz,
  score          numeric(6,2),
  max_score      numeric(6,2),
  result         jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default now()
);
create index assessments_application_idx on assessments (application_id);

-- ---------------------------------------------------------------
-- Offers
-- ---------------------------------------------------------------
create table offers (
  id             uuid primary key default gen_random_uuid(),
  application_id uuid not null references applications(id) on delete cascade,
  job_id         uuid not null references jobs(id) on delete cascade,
  company_id     uuid not null references companies(id) on delete cascade,
  person_id      uuid not null references persons(id) on delete cascade,
  status         offer_status not null default 'draft',
  title          text not null,
  pay_amount     numeric(14,2),
  pay_period     pay_period,
  pay_currency   char(3),
  pay_basis      pay_basis default 'gross',
  work_type      work_type,
  workplace_type workplace_type,
  location_text  text,
  start_date     date,
  hours_per_week smallint,
  shift_types    shift_type[] not null default '{}',
  benefits       jsonb not null default '[]'::jsonb,
  conditions     text,
  contract_document_id uuid references documents(id) on delete set null,
  expires_at     timestamptz,
  sent_at        timestamptz,
  viewed_at      timestamptz,
  responded_at   timestamptz,
  decline_reason text,
  created_by     uuid references persons(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index offers_application_idx on offers (application_id);
create index offers_person_idx      on offers (person_id, status);

create trigger offers_set_updated_at
  before update on offers
  for each row execute function extensions.moddatetime(updated_at);

-- ---------------------------------------------------------------
-- EMPLOYMENT — the candidate does not disappear after being hired
-- ---------------------------------------------------------------
create table employments (
  id             uuid primary key default gen_random_uuid(),
  person_id      uuid not null references persons(id) on delete cascade,
  company_id     uuid not null references companies(id) on delete cascade,
  job_id         uuid references jobs(id) on delete set null,
  application_id uuid references applications(id) on delete set null,
  offer_id       uuid references offers(id) on delete set null,
  profession_id  uuid references professions(id),
  title          text not null,
  department_id  uuid references departments(id),
  work_type      work_type,
  workplace_type workplace_type,
  location_id    uuid references locations(id),
  started_on     date not null,
  ended_on       date,
  status         employment_status not null default 'active',
  end_reason     text,
  -- Employment created through an Omelo hire is verified by construction.
  is_omelo_hire  boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index employments_person_idx  on employments (person_id, started_on desc);
create index employments_company_idx on employments (company_id, status);

create trigger employments_set_updated_at
  before update on employments
  for each row execute function extensions.moddatetime(updated_at);

alter table experiences
  add constraint experiences_employment_fk
  foreign key (verified_employment_id) references employments(id) on delete set null;

-- Closing the loop: an Omelo hire writes a verified experience row onto
-- the person's work identity automatically.
create or replace function omelo_employment_to_experience()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_employer text;
begin
  select c.display_name into v_employer from companies c where c.id = new.company_id;

  insert into experiences (
    person_id, company_id, employer_name, profession_id, title,
    work_type, workplace_type, location_id, started_on, ended_on,
    is_current, is_verified, verified_employment_id, source
  ) values (
    new.person_id, new.company_id, coalesce(v_employer, 'Unknown'), new.profession_id, new.title,
    new.work_type, new.workplace_type, new.location_id, new.started_on, new.ended_on,
    (new.status = 'active'), true, new.id, 'employer'
  )
  on conflict do nothing;

  insert into verifications (subject_type, subject_id, person_id, type, status, method, claim, verified_at)
  values ('experience', new.id, new.person_id, 'employment', 'verified', 'employer_confirmation',
          jsonb_build_object('employment_id', new.id, 'basis', 'hired_through_omelo'), now());

  return new;
end;
$$;

create trigger employments_create_experience
  after insert on employments
  for each row when (new.is_omelo_hire)
  execute function omelo_employment_to_experience();

-- ---------------------------------------------------------------
-- Matching — materialised, versioned, explainable
-- ---------------------------------------------------------------
create table weight_profiles (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  category_id uuid references job_categories(id),
  weights     jsonb not null,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

create table matches (
  id              uuid primary key default gen_random_uuid(),
  person_id       uuid not null references persons(id) on delete cascade,
  job_id          uuid not null references jobs(id) on delete cascade,
  score           smallint not null check (score between 0 and 100),
  eligible        boolean not null default true,
  gate_failures   text[] not null default '{}',
  -- Full computed feature set. Required to reproduce and explain any
  -- score that was ever displayed.
  feature_vector  jsonb not null,
  weight_profile_id uuid references weight_profiles(id),
  engine_version  text not null,
  computed_at     timestamptz not null default now(),
  unique (person_id, job_id, engine_version)
);
create index matches_person_idx on matches (person_id, score desc) where eligible;
create index matches_job_idx    on matches (job_id, score desc) where eligible;
create index matches_stale_idx  on matches (computed_at);

comment on table matches is
  'Scores are deterministic and computed from feature_vector by versioned code. No LLM produces a score. feature_vector + engine_version make any displayed score reproducible and explainable later.';
