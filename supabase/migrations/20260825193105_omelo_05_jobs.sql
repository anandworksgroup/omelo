-- =====================================================================
-- OMELO 05 — Universal Job Model
--
-- Every job answers the same twelve questions:
--   what work / where / when / how much / what skills / what experience
--   / what qualifications / what documents / what language / what benefits
--   / what conditions / who is hiring / how to apply
--
-- Only the answers differ between a housekeeper and a doctor.
-- =====================================================================

create table jobs (
  id                 uuid primary key default gen_random_uuid(),
  company_id         uuid not null references companies(id) on delete cascade,
  department_id      uuid references departments(id),
  created_by         uuid references persons(id),

  -- WHAT WORK
  title              text not null,
  profession_id      uuid references professions(id),
  category_id        uuid references job_categories(id),
  profession_source  source_type default 'employer',
  description        text,
  responsibilities   jsonb not null default '[]'::jsonb,
  requirements_text  jsonb not null default '[]'::jsonb,
  openings           smallint not null default 1,

  -- WHERE
  workplace_type     workplace_type not null default 'onsite',
  location_id        uuid references locations(id),
  location_text      text,
  geo                extensions.geography(Point,4326),
  country_code       char(2),
  company_location_id uuid references company_locations(id),
  relocation_support boolean not null default false,

  -- WHEN
  work_type          work_type not null default 'full_time',
  shift_types        shift_type[] not null default '{}',
  hours_per_week     smallint,
  working_days       smallint,
  schedule_note      text,
  start_date         date,
  is_immediate_start boolean not null default false,
  duration_months    smallint,                    -- for contract/temporary/seasonal

  -- HOW MUCH
  pay_min            numeric(14,2),
  pay_max            numeric(14,2),
  pay_period         pay_period,
  pay_currency       char(3),
  pay_basis          pay_basis default 'gross',
  pay_negotiable     boolean not null default false,
  pay_disclosed      boolean generated always as (pay_min is not null) stored,
  overtime_available boolean,

  -- WHAT EXPERIENCE / QUALIFICATIONS
  min_experience_months smallint,
  max_experience_months smallint,
  accepts_no_experience boolean not null default false,
  min_education      education_level,
  education_negotiable boolean not null default true,

  -- WORK AUTHORISATION
  -- NULL means UNKNOWN and renders as unknown. Never inferred.
  visa_sponsorship   boolean,
  accepts_non_residents boolean,

  -- CONDITIONS
  physical_requirements jsonb not null default '[]'::jsonb,
  work_environment   text,
  uniform_required   boolean,
  own_tools_required boolean,
  own_vehicle_required boolean,

  -- HOW TO APPLY
  application_method text not null default 'omelo'
                     check (application_method in ('omelo','external_url','walk_in','phone')),
  external_apply_url text,
  contact_phone      text,
  walk_in_details    text,
  -- Simple jobs should not demand a full profile.
  requires_resume    boolean not null default false,
  quick_apply_enabled boolean not null default true,

  -- LIFECYCLE
  status             job_status not null default 'draft',
  content_language   char(3),
  published_at       timestamptz,
  expires_at         timestamptz,
  closed_at          timestamptz,
  applicant_count    integer not null default 0,
  view_count         integer not null default 0,

  -- INGESTION
  source             source_type not null default 'employer',
  external_source_id uuid,
  external_id        text,

  job_embedding      extensions.vector(1536),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),

  check (pay_max is null or pay_min is null or pay_max >= pay_min),
  check (pay_min is null or (pay_currency is not null and pay_period is not null)),
  check (max_experience_months is null or min_experience_months is null
         or max_experience_months >= min_experience_months)
);
create index jobs_published_idx   on jobs (status, published_at desc) where status = 'published';
create index jobs_company_idx     on jobs (company_id);
create index jobs_profession_idx  on jobs (profession_id) where status = 'published';
create index jobs_category_idx    on jobs (category_id) where status = 'published';
create index jobs_geo_idx         on jobs using gist (geo);
create index jobs_country_idx     on jobs (country_code) where status = 'published';
create index jobs_worktype_idx    on jobs (work_type) where status = 'published';
create index jobs_title_trgm      on jobs using gin (title extensions.gin_trgm_ops);
create index jobs_embedding_idx   on jobs using hnsw (job_embedding extensions.vector_cosine_ops);
create index jobs_expiring_idx    on jobs (expires_at) where status = 'published';

create trigger jobs_set_updated_at
  before update on jobs
  for each row execute function extensions.moddatetime(updated_at);

comment on column jobs.visa_sponsorship is
  'Employer-declared only. NULL means unknown and must render as "Unknown". Inferring "no" would silently exclude migrant workers, who are a primary Omelo audience.';

-- ---------------------------------------------------------------
-- Requirements
-- ---------------------------------------------------------------
create table job_skills (
  job_id            uuid not null references jobs(id) on delete cascade,
  skill_id          uuid not null references skills(id),
  requirement_level requirement_level not null default 'required',
  weight            numeric(4,3) not null default 1.0 check (weight between 0 and 1),
  min_months        smallint,
  primary key (job_id, skill_id)
);
create index job_skills_skill_idx on job_skills (skill_id);

create table job_languages (
  job_id            uuid not null references jobs(id) on delete cascade,
  language_code     char(3) not null references languages(code),
  min_proficiency   language_proficiency not null default 'conversational',
  requirement_level requirement_level not null default 'required',
  primary key (job_id, language_code)
);

create table job_licenses (
  job_id            uuid not null references jobs(id) on delete cascade,
  license_type_id   uuid not null references license_types(id),
  license_class     text,
  requirement_level requirement_level not null default 'required',
  primary key (job_id, license_type_id)
);

create table job_credentials (
  job_id             uuid not null references jobs(id) on delete cascade,
  credential_type_id uuid not null references credential_types(id),
  requirement_level  requirement_level not null default 'required',
  primary key (job_id, credential_type_id)
);

-- Adaptive requirements mirroring profile_attributes
create table job_attribute_requirements (
  job_id            uuid not null references jobs(id) on delete cascade,
  attribute_id      uuid not null references profile_attributes(id) on delete cascade,
  requirement_level requirement_level not null default 'required',
  value_text        text,
  value_number_min  numeric(14,2),
  value_number_max  numeric(14,2),
  value_bool        boolean,
  value_json        jsonb,
  primary key (job_id, attribute_id)
);

create table job_documents_required (
  job_id        uuid not null references jobs(id) on delete cascade,
  document_type document_type not null,
  is_required   boolean not null default true,
  -- Documents are requested at the right stage, not at apply time.
  request_at_stage text not null default 'offer'
    check (request_at_stage in ('apply','screening','interview','offer','hired')),
  primary key (job_id, document_type)
);

comment on table job_documents_required is
  'Sensitive documents default to being requested at offer stage, not at apply. Demanding a passport scan to apply for a shift is both a privacy failure and a fraud pattern.';

create table job_benefits (
  job_id       uuid not null references jobs(id) on delete cascade,
  benefit_type benefit_type not null,
  detail       text,
  primary key (job_id, benefit_type)
);

create table job_locations (
  job_id      uuid not null references jobs(id) on delete cascade,
  location_id uuid not null references locations(id),
  primary key (job_id, location_id)
);

-- ---------------------------------------------------------------
-- LEGALLY RESTRICTED CRITERIA
--
-- Gender and age criteria are unlawful in most jurisdictions. They are
-- lawful and sometimes mandatory in a few (certain domestic, security,
-- and welfare roles). Modelled as an exception requiring an explicit
-- recorded legal basis, gated by country policy, and NEVER usable as a
-- matching feature.
-- ---------------------------------------------------------------
create table job_legal_restrictions (
  job_id         uuid primary key references jobs(id) on delete cascade,
  gender_requirement text check (gender_requirement in ('male','female','any')),
  min_age        smallint,
  max_age        smallint,
  legal_basis    text not null,
  approved_by    uuid references persons(id),
  approved_at    timestamptz,
  created_at     timestamptz not null default now()
);

create or replace function omelo_check_legal_restriction()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_country char(2);
  v_gender_ok boolean;
  v_age_ok boolean;
begin
  select j.country_code into v_country from jobs j where j.id = new.job_id;

  select coalesce(cp.gender_criteria_permitted, false),
         coalesce(cp.age_criteria_permitted, false)
    into v_gender_ok, v_age_ok
  from country_policies cp
  where cp.country_code = v_country;

  if new.gender_requirement is not null
     and new.gender_requirement <> 'any'
     and coalesce(v_gender_ok, false) = false then
    raise exception
      'Gender criteria are not permitted for jobs in country %. Set country_policies.gender_criteria_permitted with a recorded legal basis first.', v_country;
  end if;

  if (new.min_age is not null or new.max_age is not null)
     and coalesce(v_age_ok, false) = false then
    raise exception
      'Age criteria are not permitted for jobs in country %. Set country_policies.age_criteria_permitted with a recorded legal basis first.', v_country;
  end if;

  return new;
end;
$$;

create trigger job_legal_restrictions_guard
  before insert or update on job_legal_restrictions
  for each row execute function omelo_check_legal_restriction();

comment on table job_legal_restrictions is
  'Exception table. Default posture is prohibited: the guard trigger rejects gender or age criteria unless country_policies explicitly permits them for that country. These fields must never be used as matching features.';

-- ---------------------------------------------------------------
-- Hiring pipeline definition
--
-- Employers name and order their own stages ("Trial Shift", "Manager
-- Round"), but every stage MUST map to a candidate-visible state.
-- This makes application transparency structural, not a policy.
-- ---------------------------------------------------------------
create table job_stages (
  id                   uuid primary key default gen_random_uuid(),
  job_id               uuid not null references jobs(id) on delete cascade,
  name                 text not null,
  position             smallint not null,
  maps_to_state        application_state not null,
  is_terminal          boolean not null default false,
  created_at           timestamptz not null default now(),
  unique (job_id, position)
);

create table job_questions (
  id          uuid primary key default gen_random_uuid(),
  job_id      uuid not null references jobs(id) on delete cascade,
  position    smallint not null,
  prompt      text not null,
  answer_type text not null check (answer_type in
              ('text','long_text','boolean','single_choice','multi_choice','number','date','file')),
  options     jsonb,
  is_required boolean not null default true,
  is_knockout boolean not null default false,
  knockout_expected jsonb
);

-- ---------------------------------------------------------------
-- Candidate-side job relationships
-- ---------------------------------------------------------------
create table saved_jobs (
  person_id  uuid not null references persons(id) on delete cascade,
  job_id     uuid not null references jobs(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (person_id, job_id)
);

create table hidden_jobs (
  person_id  uuid not null references persons(id) on delete cascade,
  job_id     uuid not null references jobs(id) on delete cascade,
  reason     text,
  created_at timestamptz not null default now(),
  primary key (person_id, job_id)
);

create table saved_searches (
  id             uuid primary key default gen_random_uuid(),
  person_id      uuid not null references persons(id) on delete cascade,
  name           text not null,
  query_text     text,
  facets         jsonb not null default '{}'::jsonb,
  alert_cadence  text not null default 'daily'
                 check (alert_cadence in ('instant','daily','weekly','off')),
  last_alerted_at timestamptz,
  created_at     timestamptz not null default now()
);
create index saved_searches_person_idx on saved_searches (person_id);
create index saved_searches_alerts_idx on saved_searches (alert_cadence, last_alerted_at)
  where alert_cadence <> 'off';

-- ---------------------------------------------------------------
-- Job ingestion (partner feeds / ATS). Authorisation required.
-- ---------------------------------------------------------------
create table job_sources (
  id           uuid primary key default gen_random_uuid(),
  name         text not null unique,
  kind         text not null check (kind in ('ats_api','xml_feed','partner_api','direct_post')),
  is_active    boolean not null default false,
  terms_url    text,
  contract_ref text,
  last_synced_at timestamptz,
  created_at   timestamptz not null default now()
);

comment on column job_sources.contract_ref is
  'Proof of authorisation to ingest. A source without one must not be activated.';

alter table jobs
  add constraint jobs_external_source_fk
  foreign key (external_source_id) references job_sources(id) on delete set null;

create unique index jobs_external_unique_idx on jobs (external_source_id, external_id)
  where external_id is not null;

create table ingestion_runs (
  id           uuid primary key default gen_random_uuid(),
  source_id    uuid not null references job_sources(id) on delete cascade,
  started_at   timestamptz not null default now(),
  finished_at  timestamptz,
  jobs_seen    integer not null default 0,
  jobs_created integer not null default 0,
  jobs_updated integer not null default 0,
  jobs_closed  integer not null default 0,
  errors       jsonb not null default '[]'::jsonb
);
