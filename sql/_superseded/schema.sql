-- =====================================================================
-- OMELO — Core Graph Schema
-- Target: PostgreSQL 15+ (Supabase), extensions: pgcrypto, pgvector, pg_trgm
-- Status: Phase 0 specification artifact. Not yet migrated.
--
-- Conventions:
--   * All PKs are uuid, generated with gen_random_uuid()
--   * All timestamps are timestamptz, stored UTC
--   * Money is ALWAYS (amount, currency, period, basis) — never a bare number
--   * Every edge carries created_at and source for provenance
--   * Nothing here is authoritative outside Postgres; all indexes are derived
-- =====================================================================

create extension if not exists pgcrypto;
create extension if not exists vector;
create extension if not exists pg_trgm;

-- =====================================================================
-- 0. ENUMS
-- =====================================================================

create type source_type as enum ('user', 'import', 'inference', 'admin', 'partner');

create type employment_type as enum
  ('full_time', 'part_time', 'contract', 'internship', 'temporary', 'apprenticeship', 'volunteer');

create type remote_mode as enum ('onsite', 'hybrid', 'remote', 'remote_anywhere');

create type seniority_level as enum
  ('intern', 'entry', 'junior', 'mid', 'senior', 'staff', 'principal', 'lead', 'manager', 'director', 'executive');

create type skill_type as enum ('technical', 'tool', 'domain', 'method', 'language', 'transferable');

create type requirement_level as enum ('required', 'preferred', 'nice_to_have');

create type evidence_type as enum ('self_declared', 'experience', 'project', 'credential', 'assessment', 'endorsement');

create type degree_level as enum
  ('secondary', 'diploma', 'associate', 'bachelor', 'master', 'doctorate', 'professional', 'other');

create type cefr_level as enum ('A1', 'A2', 'B1', 'B2', 'C1', 'C2', 'native');

create type work_auth_status as enum
  ('citizen', 'permanent_resident', 'work_permit', 'student_visa_limited', 'requires_sponsorship', 'no_right_to_work');

create type salary_period as enum ('hour', 'day', 'week', 'month', 'year');
create type salary_basis  as enum ('gross', 'net');

create type discoverability as enum ('private', 'discoverable', 'public');

create type verification_method as enum
  ('domain_email', 'employer_confirmation', 'document_review', 'issuer_api', 'institution_partner', 'manual_admin');

create type company_role as enum
  ('owner', 'admin', 'recruiter', 'hiring_manager', 'interviewer', 'billing');

create type job_status as enum ('draft', 'pending_review', 'published', 'paused', 'closed', 'expired', 'rejected');

create type application_public_state as enum (
  'submitted', 'viewed', 'contacted', 'screening', 'interview',
  'final_interview', 'offer', 'hired', 'rejected',
  'withdrawn', 'declined_by_candidate', 'expired'
);

create type application_event_type as enum (
  'created', 'viewed', 'stage_changed', 'message_sent', 'note_added',
  'interview_scheduled', 'assessment_sent', 'assessment_completed',
  'offer_extended', 'decision_made', 'withdrawn', 'expired'
);

create type actor_type as enum ('candidate', 'recruiter', 'system', 'admin');

create type message_kind as enum ('text', 'action', 'attachment', 'system');

create type relation_kind as enum ('adjacent_to', 'prerequisite_of', 'substitutable_for', 'specialisation_of');

create type taxonomy_status as enum ('active', 'pending_review', 'deprecated', 'merged');

-- =====================================================================
-- 1. REFERENCE / TAXONOMY NODES
--    Curated. Users never insert directly (see docs/02 taxonomy governance).
-- =====================================================================

create table locations (
  id            uuid primary key default gen_random_uuid(),
  parent_id     uuid references locations(id),
  kind          text not null check (kind in ('country', 'region', 'city')),
  name          text not null,
  country_code  char(2),                       -- ISO 3166-1 alpha-2
  admin_code    text,
  latitude      double precision,
  longitude     double precision,
  timezone      text,
  created_at    timestamptz not null default now()
);
create index on locations (country_code);
create index on locations (parent_id);
create index locations_name_trgm on locations using gin (name gin_trgm_ops);

create table industries (
  id         uuid primary key default gen_random_uuid(),
  parent_id  uuid references industries(id),
  code       text unique not null,
  name       text not null
);

create table institutions (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  country_code  char(2),
  website       text,
  status        taxonomy_status not null default 'active',
  created_at    timestamptz not null default now()
);
create index institutions_name_trgm on institutions using gin (name gin_trgm_ops);

create table languages (
  code  char(3) primary key,                   -- ISO 639-3
  name  text not null
);

-- --- Skills -----------------------------------------------------------

create table skills (
  id            uuid primary key default gen_random_uuid(),
  slug          text unique not null,
  name          text not null,
  type          skill_type not null,
  description   text,
  external_ids  jsonb not null default '{}'::jsonb,  -- {"esco": "...", "onet": "..."}
  status        taxonomy_status not null default 'active',
  merged_into   uuid references skills(id),
  embedding     vector(1536),
  created_at    timestamptz not null default now()
);
create index skills_name_trgm on skills using gin (name gin_trgm_ops);
create index skills_embedding_idx on skills using hnsw (embedding vector_cosine_ops);

-- Unrecognised user input lands here as a pending alias, never as a new skill node.
create table skill_aliases (
  id            uuid primary key default gen_random_uuid(),
  skill_id      uuid references skills(id) on delete cascade,
  alias         text not null,
  locale        text,
  status        taxonomy_status not null default 'pending_review',
  occurrences   integer not null default 1,
  created_at    timestamptz not null default now(),
  unique (alias, locale)
);

create table skill_relations (
  from_skill_id uuid not null references skills(id) on delete cascade,
  to_skill_id   uuid not null references skills(id) on delete cascade,
  kind          relation_kind not null,
  strength      numeric(4,3) not null default 0.5 check (strength between 0 and 1),
  source        source_type not null default 'admin',
  created_at    timestamptz not null default now(),
  primary key (from_skill_id, to_skill_id, kind)
);

-- --- Occupations ------------------------------------------------------

create table occupations (
  id            uuid primary key default gen_random_uuid(),
  slug          text unique not null,
  name          text not null,
  family        text,
  description   text,
  external_ids  jsonb not null default '{}'::jsonb,
  status        taxonomy_status not null default 'active',
  merged_into   uuid references occupations(id),
  embedding     vector(1536),
  created_at    timestamptz not null default now()
);
create index occupations_name_trgm on occupations using gin (name gin_trgm_ops);
create index occupations_embedding_idx on occupations using hnsw (embedding vector_cosine_ops);

create table occupation_aliases (
  id             uuid primary key default gen_random_uuid(),
  occupation_id  uuid references occupations(id) on delete cascade,
  alias          text not null,
  locale         text,
  status         taxonomy_status not null default 'pending_review',
  occurrences    integer not null default 1,
  unique (alias, locale)
);

-- Career-path backbone. observed_count/median_months exist from day one so the
-- switch from seeded priors to real observed data is a data migration only.
create table occupation_transitions (
  from_occupation_id uuid not null references occupations(id) on delete cascade,
  to_occupation_id   uuid not null references occupations(id) on delete cascade,
  prior_strength     numeric(4,3) not null default 0.0 check (prior_strength between 0 and 1),
  observed_count     integer not null default 0,
  median_months      integer,
  median_salary_delta_pct numeric(6,2),
  last_computed_at   timestamptz,
  primary key (from_occupation_id, to_occupation_id)
);

create table occupation_skills (
  occupation_id uuid not null references occupations(id) on delete cascade,
  skill_id      uuid not null references skills(id) on delete cascade,
  importance    numeric(4,3) not null check (importance between 0 and 1),
  source        source_type not null default 'admin',
  primary key (occupation_id, skill_id)
);

create table credential_types (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  issuer        text not null,
  verify_url_tpl text,
  status        taxonomy_status not null default 'active',
  unique (name, issuer)
);

-- =====================================================================
-- 2. PERSON
-- =====================================================================

-- Supabase: id references auth.users(id)
create table persons (
  id                  uuid primary key,
  display_name        text not null,
  given_name          text,
  family_name         text,
  headline            text,
  summary             text,
  avatar_url          text,
  primary_email       text not null,
  phone               text,
  location_id         uuid references locations(id),
  current_occupation_id uuid references occupations(id),
  current_occupation_source source_type default 'inference',
  current_occupation_confidence numeric(4,3),
  seniority           seniority_level,
  years_experience    numeric(4,1),
  discoverability     discoverability not null default 'private',
  open_to_remote      boolean not null default false,
  open_to_relocation  boolean not null default false,
  profile_slug        text unique,
  completeness_score  integer not null default 0 check (completeness_score between 0 and 100),
  identity_embedding  vector(1536),
  locale              text not null default 'en',
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz
);
create index persons_occupation_idx on persons (current_occupation_id) where deleted_at is null;
create index persons_discoverable_idx on persons (discoverability) where deleted_at is null;
create index persons_embedding_idx on persons using hnsw (identity_embedding vector_cosine_ops);

create table person_preferences (
  person_id            uuid primary key references persons(id) on delete cascade,
  desired_salary_min   numeric(12,2),
  desired_salary_currency char(3),
  desired_salary_period salary_period default 'year',
  desired_salary_basis  salary_basis default 'gross',
  desired_employment_types employment_type[] not null default '{}',
  desired_remote_modes  remote_mode[] not null default '{}',
  notice_period_days   integer,
  available_from       date,
  min_outreach_salary  numeric(12,2),          -- "only contact me above X"
  outreach_occupations uuid[] not null default '{}',
  updated_at           timestamptz not null default now()
);

create table person_skills (
  id            uuid primary key default gen_random_uuid(),
  person_id     uuid not null references persons(id) on delete cascade,
  skill_id      uuid not null references skills(id),
  proficiency   smallint check (proficiency between 1 and 5),
  years_used    numeric(4,1),
  last_used_at  date,
  evidence_type evidence_type not null default 'self_declared',
  evidence_refs jsonb not null default '[]'::jsonb,
  is_verified   boolean not null default false,
  source        source_type not null default 'user',
  created_at    timestamptz not null default now(),
  unique (person_id, skill_id)
);
create index person_skills_skill_idx on person_skills (skill_id);

create table experiences (
  id                uuid primary key default gen_random_uuid(),
  person_id         uuid not null references persons(id) on delete cascade,
  company_id        uuid,                       -- FK added after companies
  company_name_raw  text not null,
  occupation_id     uuid references occupations(id),
  title_as_written  text not null,
  seniority         seniority_level,
  employment_type   employment_type,
  location_id       uuid references locations(id),
  remote_mode       remote_mode,
  started_on        date not null,
  ended_on          date,
  is_current        boolean not null default false,
  description       text,
  achievements      jsonb not null default '[]'::jsonb,
  is_verified       boolean not null default false,
  source            source_type not null default 'user',
  created_at        timestamptz not null default now(),
  check (ended_on is null or ended_on >= started_on),
  check (is_current = false or ended_on is null)
);
create index experiences_person_idx on experiences (person_id, started_on desc);
create index experiences_occupation_idx on experiences (occupation_id);

create table educations (
  id              uuid primary key default gen_random_uuid(),
  person_id       uuid not null references persons(id) on delete cascade,
  institution_id  uuid references institutions(id),
  institution_name_raw text not null,
  degree_level    degree_level,
  field_of_study  text,
  started_on      date,
  ended_on        date,
  grade           text,
  is_verified     boolean not null default false,
  source          source_type not null default 'user',
  created_at      timestamptz not null default now()
);
create index educations_person_idx on educations (person_id);

create table projects (
  id           uuid primary key default gen_random_uuid(),
  person_id    uuid not null references persons(id) on delete cascade,
  title        text not null,
  role         text,
  description  text,
  url          text,
  media        jsonb not null default '[]'::jsonb,
  started_on   date,
  ended_on     date,
  created_at   timestamptz not null default now()
);

create table project_skills (
  project_id uuid not null references projects(id) on delete cascade,
  skill_id   uuid not null references skills(id),
  primary key (project_id, skill_id)
);

create table credential_holdings (
  id                 uuid primary key default gen_random_uuid(),
  person_id          uuid not null references persons(id) on delete cascade,
  credential_type_id uuid references credential_types(id),
  name_raw           text not null,
  issuer_raw         text,
  credential_id      text,
  issued_on          date,
  expires_on         date,
  verification_url   text,
  is_verified        boolean not null default false,
  created_at         timestamptz not null default now()
);

create table work_authorizations (
  id                   uuid primary key default gen_random_uuid(),
  person_id            uuid not null references persons(id) on delete cascade,
  country_code         char(2) not null,
  status               work_auth_status not null,
  expires_on           date,
  requires_sponsorship  boolean generated always as
                        (status in ('requires_sponsorship', 'no_right_to_work', 'student_visa_limited')) stored,
  created_at           timestamptz not null default now(),
  unique (person_id, country_code)
);
create index work_auth_country_idx on work_authorizations (country_code, status);

create table career_targets (
  id             uuid primary key default gen_random_uuid(),
  person_id      uuid not null references persons(id) on delete cascade,
  occupation_id  uuid not null references occupations(id),
  priority       smallint not null default 1,
  target_countries char(2)[] not null default '{}',
  target_salary_min numeric(12,2),
  target_salary_currency char(3),
  declared_at    timestamptz not null default now(),
  unique (person_id, occupation_id)
);

create table person_languages (
  person_id  uuid not null references persons(id) on delete cascade,
  language_code char(3) not null references languages(code),
  level      cefr_level not null,
  primary key (person_id, language_code)
);

-- =====================================================================
-- 3. COMPANY
-- =====================================================================

create table companies (
  id             uuid primary key default gen_random_uuid(),
  slug           text unique not null,
  display_name   text not null,
  legal_name     text,
  industry_id    uuid references industries(id),
  size_band      text check (size_band in ('1-10','11-50','51-200','201-500','501-1000','1001-5000','5001-10000','10000+')),
  founded_year   integer,
  website        text,
  logo_url       text,
  description    text,
  benefits       jsonb not null default '[]'::jsonb,
  culture        jsonb not null default '{}'::jsonb,
  is_verified    boolean not null default false,
  verified_at    timestamptz,
  verification_method verification_method,
  hq_location_id uuid references locations(id),
  -- Denormalised hiring-behaviour stats (FR-334), recomputed on schedule
  response_rate_pct        numeric(5,2),
  median_response_hours    integer,
  stats_computed_at        timestamptz,
  created_at     timestamptz not null default now(),
  deleted_at     timestamptz
);
create index companies_name_trgm on companies using gin (display_name gin_trgm_ops);

alter table experiences
  add constraint experiences_company_fk foreign key (company_id) references companies(id);

create table company_locations (
  company_id  uuid not null references companies(id) on delete cascade,
  location_id uuid not null references locations(id),
  is_hq       boolean not null default false,
  primary key (company_id, location_id)
);

create table company_members (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  person_id   uuid not null references persons(id) on delete cascade,
  role        company_role not null,
  is_active   boolean not null default true,
  invited_by  uuid references persons(id),
  joined_at   timestamptz not null default now(),
  unique (company_id, person_id, role)
);
create index company_members_person_idx on company_members (person_id) where is_active;

-- =====================================================================
-- 4. JOB
-- =====================================================================

create table jobs (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references companies(id) on delete cascade,
  created_by        uuid references persons(id),
  title             text not null,
  occupation_id     uuid references occupations(id),
  occupation_source source_type default 'inference',
  description       text not null,
  responsibilities  jsonb not null default '[]'::jsonb,
  requirements_text jsonb not null default '[]'::jsonb,
  seniority         seniority_level,
  min_years         numeric(4,1),
  max_years         numeric(4,1),
  min_degree_level  degree_level,
  employment_type   employment_type not null,
  remote_mode       remote_mode not null,
  primary_location_id uuid references locations(id),
  relocation_support boolean not null default false,
  -- Sponsorship is EMPLOYER-DECLARED ONLY. null means unknown, never inferred (FR-221).
  visa_sponsorship  boolean,
  salary_min        numeric(12,2),
  salary_max        numeric(12,2),
  salary_currency   char(3),
  salary_period     salary_period,
  salary_basis      salary_basis,
  salary_disclosed  boolean generated always as (salary_min is not null) stored,
  content_language  char(3),
  status            job_status not null default 'draft',
  published_at      timestamptz,
  expires_at        timestamptz,
  closed_at         timestamptz,
  external_source   text,                       -- partner feed identifier, null if native
  external_id       text,
  external_apply_url text,
  applicant_count   integer not null default 0,
  job_embedding     vector(1536),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (salary_max is null or salary_min is null or salary_max >= salary_min),
  check (salary_min is null or salary_currency is not null),
  unique (external_source, external_id)
);
create index jobs_status_published_idx on jobs (status, published_at desc) where status = 'published';
create index jobs_occupation_idx on jobs (occupation_id) where status = 'published';
create index jobs_location_idx on jobs (primary_location_id) where status = 'published';
create index jobs_company_idx on jobs (company_id);
create index jobs_embedding_idx on jobs using hnsw (job_embedding vector_cosine_ops);
create index jobs_title_trgm on jobs using gin (title gin_trgm_ops);

create table job_skills (
  job_id            uuid not null references jobs(id) on delete cascade,
  skill_id          uuid not null references skills(id),
  requirement_level requirement_level not null default 'required',
  weight            numeric(4,3) not null default 1.0 check (weight between 0 and 1),
  min_years         numeric(4,1),
  primary key (job_id, skill_id)
);
create index job_skills_skill_idx on job_skills (skill_id);

create table job_languages (
  job_id            uuid not null references jobs(id) on delete cascade,
  language_code     char(3) not null references languages(code),
  min_level         cefr_level not null,
  requirement_level requirement_level not null default 'required',
  primary key (job_id, language_code)
);

create table job_locations (
  job_id      uuid not null references jobs(id) on delete cascade,
  location_id uuid not null references locations(id),
  primary key (job_id, location_id)
);

-- Employer-configurable pipeline stages. maps_to_public_state makes FR-509
-- a structural invariant rather than a policy someone must remember.
create table job_stages (
  id                    uuid primary key default gen_random_uuid(),
  job_id                uuid not null references jobs(id) on delete cascade,
  name                  text not null,
  position              smallint not null,
  maps_to_public_state  application_public_state not null,
  is_terminal           boolean not null default false,
  unique (job_id, position)
);

create table job_questions (
  id          uuid primary key default gen_random_uuid(),
  job_id      uuid not null references jobs(id) on delete cascade,
  position    smallint not null,
  prompt      text not null,
  answer_type text not null check (answer_type in ('text','long_text','boolean','single_choice','multi_choice','number','file')),
  options     jsonb,
  is_required boolean not null default true,
  is_knockout boolean not null default false
);

-- =====================================================================
-- 5. APPLICATION
-- =====================================================================

create table applications (
  id             uuid primary key default gen_random_uuid(),
  job_id         uuid not null references jobs(id) on delete cascade,
  person_id      uuid not null references persons(id) on delete cascade,
  stage_id       uuid references job_stages(id),
  public_state   application_public_state not null default 'submitted',
  match_score    integer check (match_score between 0 and 100),
  cover_note     text,
  answers        jsonb not null default '[]'::jsonb,
  resume_file_id uuid,
  -- Immutable copy of identity at submission time (docs/02 snapshot rule)
  identity_snapshot jsonb not null,
  first_viewed_at   timestamptz,
  last_activity_at  timestamptz not null default now(),
  submitted_at      timestamptz not null default now(),
  closed_at         timestamptz,
  rejection_reason  text,
  unique (job_id, person_id)
);
create index applications_person_idx on applications (person_id, submitted_at desc);
create index applications_job_state_idx on applications (job_id, public_state);
create index applications_stale_idx on applications (last_activity_at)
  where public_state in ('submitted','viewed','contacted','screening','interview','final_interview');

-- Append-only. Never updated, never deleted. Basis for FR-334, NFR-10, NFR-11.
create table application_events (
  id             uuid primary key default gen_random_uuid(),
  application_id uuid not null references applications(id) on delete cascade,
  event_type     application_event_type not null,
  actor_type     actor_type not null,
  actor_id       uuid references persons(id),
  from_state     application_public_state,
  to_state       application_public_state,
  from_stage_id  uuid,
  to_stage_id    uuid,
  reason         text,
  metadata       jsonb not null default '{}'::jsonb,
  occurred_at    timestamptz not null default now()
);
create index application_events_app_idx on application_events (application_id, occurred_at);

-- =====================================================================
-- 6. MATCH — materialised, versioned, explainable
-- =====================================================================

create table matches (
  id                uuid primary key default gen_random_uuid(),
  person_id         uuid not null references persons(id) on delete cascade,
  job_id            uuid not null references jobs(id) on delete cascade,
  score             integer not null check (score between 0 and 100),
  eligible          boolean not null,
  gate_failures     text[] not null default '{}',
  feature_vector    jsonb not null,            -- required for NFR-11 reproducibility
  weight_profile_id uuid,
  engine_version    text not null,
  computed_at       timestamptz not null default now(),
  unique (person_id, job_id, engine_version)
);
create index matches_person_score_idx on matches (person_id, score desc) where eligible;
create index matches_job_score_idx on matches (job_id, score desc) where eligible;

create table weight_profiles (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  occupation_family text,
  weights       jsonb not null,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);

-- =====================================================================
-- 7. CONVERSATION
-- =====================================================================

create table conversations (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references companies(id) on delete cascade,
  person_id     uuid not null references persons(id) on delete cascade,
  job_id        uuid references jobs(id) on delete set null,   -- always anchored to a job
  application_id uuid references applications(id) on delete set null,
  initiated_by  actor_type not null,
  is_archived_by_person boolean not null default false,
  last_message_at timestamptz,
  created_at    timestamptz not null default now(),
  unique (company_id, person_id, job_id)
);
create index conversations_person_idx on conversations (person_id, last_message_at desc);
create index conversations_company_idx on conversations (company_id, last_message_at desc);

create table messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations(id) on delete cascade,
  sender_person_id uuid references persons(id),
  sender_type     actor_type not null,
  kind            message_kind not null default 'text',
  body            text,
  action_type     text,
  action_payload  jsonb,
  attachment_id   uuid,
  read_at         timestamptz,
  sent_at         timestamptz not null default now()
);
create index messages_conversation_idx on messages (conversation_id, sent_at);

-- =====================================================================
-- 8. RELATIONSHIP / PREFERENCE EDGES
-- =====================================================================

create table follows (
  person_id    uuid not null references persons(id) on delete cascade,
  target_type  text not null check (target_type in ('company','occupation','skill')),
  target_id    uuid not null,
  created_at   timestamptz not null default now(),
  primary key (person_id, target_type, target_id)
);

-- Enforced at QUERY time in talent search, never by post-filtering the UI (FR-713)
create table blocks (
  person_id    uuid not null references persons(id) on delete cascade,
  target_type  text not null check (target_type in ('company','person')),
  target_id    uuid not null,
  reason       text,
  created_at   timestamptz not null default now(),
  primary key (person_id, target_type, target_id)
);
create index blocks_target_idx on blocks (target_type, target_id);

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
  id           uuid primary key default gen_random_uuid(),
  person_id    uuid not null references persons(id) on delete cascade,
  name         text not null,
  facets       jsonb not null,
  alert_cadence text not null default 'daily' check (alert_cadence in ('instant','daily','weekly','off')),
  last_alerted_at timestamptz,
  created_at   timestamptz not null default now()
);

create table profile_views (
  id          uuid primary key default gen_random_uuid(),
  person_id   uuid not null references persons(id) on delete cascade,   -- who was viewed
  viewer_company_id uuid references companies(id) on delete set null,
  viewer_person_id  uuid references persons(id) on delete set null,
  context_job_id    uuid references jobs(id) on delete set null,
  viewed_at   timestamptz not null default now()
);
create index profile_views_person_idx on profile_views (person_id, viewed_at desc);

create table talent_pools (
  id         uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  name       text not null,
  created_by uuid references persons(id),
  created_at timestamptz not null default now()
);

create table talent_pool_members (
  pool_id    uuid not null references talent_pools(id) on delete cascade,
  person_id  uuid not null references persons(id) on delete cascade,
  added_by   uuid references persons(id),
  note       text,
  added_at   timestamptz not null default now(),
  primary key (pool_id, person_id)
);

-- =====================================================================
-- 9. VERIFICATION & AUDIT
-- =====================================================================

create table verifications (
  id             uuid primary key default gen_random_uuid(),
  subject_type   text not null check (subject_type in ('person','company','experience','education','credential')),
  subject_id     uuid not null,
  method         verification_method not null,
  verified_by    uuid references persons(id),
  claim          jsonb not null,               -- exactly what was checked (FR-134)
  verified_at    timestamptz not null default now(),
  expires_at     timestamptz,
  revoked_at     timestamptz,
  revoke_reason  text
);
create index verifications_subject_idx on verifications (subject_type, subject_id);

-- Append-only audit trail (NFR-10)
create table audit_log (
  id           bigserial primary key,
  actor_type   actor_type not null,
  actor_id     uuid,
  action       text not null,
  subject_type text not null,
  subject_id   uuid,
  company_id   uuid,
  ip_hash      text,
  metadata     jsonb not null default '{}'::jsonb,
  occurred_at  timestamptz not null default now()
);
create index audit_log_subject_idx on audit_log (subject_type, subject_id, occurred_at desc);
create index audit_log_actor_idx on audit_log (actor_id, occurred_at desc);

-- Records every automated ranking shown to a user, for GDPR Art. 22 / EU AI Act
-- human-review requests (FR-715).
create table automated_decision_log (
  id            bigserial primary key,
  person_id     uuid references persons(id) on delete set null,
  job_id        uuid references jobs(id) on delete set null,
  company_id    uuid references companies(id) on delete set null,
  decision_kind text not null,                 -- 'ranking' | 'recommendation' | 'gate'
  outcome       jsonb not null,
  engine_version text not null,
  human_reviewed boolean not null default false,
  occurred_at   timestamptz not null default now()
);

-- =====================================================================
-- 10. INGESTION
-- =====================================================================

create table job_sources (
  id           uuid primary key default gen_random_uuid(),
  name         text not null unique,
  kind         text not null check (kind in ('ats_api','xml_feed','partner_api','direct_post')),
  is_active    boolean not null default true,
  terms_url    text,
  contract_ref text,                            -- proof of authorisation to ingest
  last_synced_at timestamptz
);

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
