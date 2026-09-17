-- =====================================================================
-- OMELO 03 — Person and Work Identity
--
-- PERSON -> WORK IDENTITY -> OPPORTUNITY
--
-- A work identity may be almost empty at signup. Omelo builds it
-- progressively. Nothing below is required to search or apply.
-- =====================================================================

create table persons (
  id                  uuid primary key references auth.users(id) on delete cascade,
  display_name        text,
  given_name          text,
  family_name         text,
  headline            text,
  about               text,
  avatar_url          text,
  email               text,
  phone               text,
  date_of_birth       date,          -- collected only where legally required; never a match feature
  -- Location
  location_id         uuid references locations(id),
  location_text       text,
  geo                 extensions.geography(Point,4326),
  country_code        char(2),
  timezone            text,
  -- Work identity summary (derived, correctable)
  primary_profession_id uuid references professions(id),
  primary_profession_source source_type default 'user',
  primary_category_id uuid references job_categories(id),
  total_experience_months integer,
  highest_education   education_level,
  -- Platform
  locale              text not null default 'en',
  discoverability     discoverability not null default 'private',
  profile_slug        text unique,
  completeness_score  smallint not null default 0 check (completeness_score between 0 and 100),
  identity_embedding  extensions.vector(1536),
  onboarding_stage    text not null default 'new',
  last_active_at      timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz
);
create index persons_profession_idx    on persons (primary_profession_id) where deleted_at is null;
create index persons_category_idx      on persons (primary_category_id) where deleted_at is null;
create index persons_geo_idx           on persons using gist (geo);
create index persons_discoverable_idx  on persons (discoverability) where deleted_at is null;
create index persons_country_idx       on persons (country_code) where deleted_at is null;
create index persons_embedding_idx     on persons using hnsw (identity_embedding extensions.vector_cosine_ops);

create trigger persons_set_updated_at
  before update on persons
  for each row execute function extensions.moddatetime(updated_at);

comment on column persons.date_of_birth is
  'Collected only where a jurisdiction legally requires age verification for a role. Never used as a matching feature. See country_policies.age_criteria_permitted.';

-- ---------------------------------------------------------------
-- What work am I looking for?  (set during onboarding, before profile)
-- ---------------------------------------------------------------
create table person_work_preferences (
  person_id            uuid primary key references persons(id) on delete cascade,
  seeking              boolean not null default true,
  work_types           work_type[] not null default '{}',
  workplace_types      workplace_type[] not null default '{}',
  shift_types          shift_type[] not null default '{}',
  availability         availability_window not null default 'immediate',
  available_from       date,
  notice_period_days   integer,
  max_weekly_hours     smallint,
  willing_to_relocate  boolean not null default false,
  willing_to_travel    boolean not null default false,
  needs_accommodation  boolean not null default false,
  needs_transport      boolean not null default false,
  -- Pay expectations. Period matters as much as amount.
  current_pay_amount   numeric(14,2),
  current_pay_period   pay_period,
  expected_pay_amount  numeric(14,2),
  expected_pay_period  pay_period,
  minimum_pay_amount   numeric(14,2),
  minimum_pay_period   pay_period,
  pay_currency         char(3),
  pay_basis            pay_basis default 'gross',
  -- Inbound contact control
  min_outreach_pay_amount numeric(14,2),
  min_outreach_pay_period pay_period,
  updated_at           timestamptz not null default now()
);
create trigger person_work_preferences_set_updated_at
  before update on person_work_preferences
  for each row execute function extensions.moddatetime(updated_at);

-- Where do you want to work? (near me / my city / country / remote / abroad)
create table person_location_preferences (
  id             uuid primary key default gen_random_uuid(),
  person_id      uuid not null references persons(id) on delete cascade,
  kind           text not null check (kind in ('nearby','city','region','country','remote','anywhere')),
  location_id    uuid references locations(id),
  country_code   char(2),
  radius_km      integer,
  priority       smallint not null default 1,
  created_at     timestamptz not null default now()
);
create index person_location_prefs_idx on person_location_preferences (person_id);

-- Which professions am I open to? Supports the very common case of a
-- person willing to do several unrelated kinds of work.
create table person_professions (
  person_id      uuid not null references persons(id) on delete cascade,
  profession_id  uuid not null references professions(id),
  relationship   text not null check (relationship in ('current','experienced','seeking','goal')),
  months_experience integer,
  priority       smallint not null default 1,
  created_at     timestamptz not null default now(),
  primary key (person_id, profession_id, relationship)
);
create index person_professions_prof_idx on person_professions (profession_id, relationship);

-- ---------------------------------------------------------------
-- Skills
-- ---------------------------------------------------------------
create table person_skills (
  id            uuid primary key default gen_random_uuid(),
  person_id     uuid not null references persons(id) on delete cascade,
  skill_id      uuid not null references skills(id),
  proficiency   proficiency_level,
  months_used   integer,
  last_used_on  date,
  evidence_type evidence_type not null default 'self_declared',
  evidence_refs jsonb not null default '[]'::jsonb,
  is_verified   boolean not null default false,
  source        source_type not null default 'user',
  created_at    timestamptz not null default now(),
  unique (person_id, skill_id)
);
create index person_skills_skill_idx on person_skills (skill_id);

-- ---------------------------------------------------------------
-- Adaptive attribute values (vehicle classes, specialisations, ...)
-- ---------------------------------------------------------------
create table person_attributes (
  id           uuid primary key default gen_random_uuid(),
  person_id    uuid not null references persons(id) on delete cascade,
  attribute_id uuid not null references profile_attributes(id) on delete cascade,
  value_text   text,
  value_number numeric(14,2),
  value_bool   boolean,
  value_date   date,
  value_json   jsonb,
  source       source_type not null default 'user',
  created_at   timestamptz not null default now(),
  unique (person_id, attribute_id)
);
create index person_attributes_attr_idx on person_attributes (attribute_id);

-- ---------------------------------------------------------------
-- Experience
--
-- company_id is NULLABLE and company_name is free text. Self-employment,
-- informal work, family businesses, and daily-wage work are all valid
-- experience. Requiring a registered employer would exclude a large
-- share of the world's workers from having any work history at all.
-- ---------------------------------------------------------------
create table experiences (
  id                uuid primary key default gen_random_uuid(),
  person_id         uuid not null references persons(id) on delete cascade,
  company_id        uuid,                         -- FK added in omelo_04
  employer_name     text not null,
  is_self_employed  boolean not null default false,
  is_informal       boolean not null default false,
  profession_id     uuid references professions(id),
  title             text not null,
  work_type         work_type,
  workplace_type    workplace_type,
  location_id       uuid references locations(id),
  location_text     text,
  started_on        date,
  ended_on          date,
  is_current        boolean not null default false,
  months_duration   integer,
  description       text,
  responsibilities  jsonb not null default '[]'::jsonb,
  pay_amount        numeric(14,2),
  pay_period        pay_period,
  pay_currency      char(3),
  reason_for_leaving text,
  is_verified       boolean not null default false,
  -- Set when the experience originated from a hire made on Omelo.
  verified_employment_id uuid,
  source            source_type not null default 'user',
  created_at        timestamptz not null default now(),
  check (ended_on is null or started_on is null or ended_on >= started_on),
  check (not (is_current and ended_on is not null))
);
create index experiences_person_idx     on experiences (person_id, started_on desc nulls last);
create index experiences_profession_idx on experiences (profession_id);
create index experiences_company_idx    on experiences (company_id);

-- ---------------------------------------------------------------
-- Education
-- ---------------------------------------------------------------
create table educations (
  id                uuid primary key default gen_random_uuid(),
  person_id         uuid not null references persons(id) on delete cascade,
  institution_id    uuid references institutions(id),
  institution_name  text not null,
  level             education_level not null,
  field_of_study    text,
  started_on        date,
  ended_on          date,
  is_ongoing        boolean not null default false,
  grade             text,
  is_verified       boolean not null default false,
  source            source_type not null default 'user',
  created_at        timestamptz not null default now()
);
create index educations_person_idx on educations (person_id);

-- ---------------------------------------------------------------
-- Licenses  (driving, trade, professional, medical)
-- ---------------------------------------------------------------
create table person_licenses (
  id              uuid primary key default gen_random_uuid(),
  person_id       uuid not null references persons(id) on delete cascade,
  license_type_id uuid references license_types(id),
  name            text not null,
  license_class   text,
  license_number  text,
  issuing_body    text,
  country_code    char(2),
  issued_on       date,
  expires_on      date,
  document_id     uuid,                            -- FK added below
  is_verified     boolean not null default false,
  verification_status verification_status not null default 'unverified',
  created_at      timestamptz not null default now()
);
create index person_licenses_person_idx on person_licenses (person_id);
create index person_licenses_type_idx   on person_licenses (license_type_id);
create index person_licenses_expiry_idx on person_licenses (expires_on) where expires_on is not null;

-- ---------------------------------------------------------------
-- Certifications
-- ---------------------------------------------------------------
create table person_credentials (
  id                 uuid primary key default gen_random_uuid(),
  person_id          uuid not null references persons(id) on delete cascade,
  credential_type_id uuid references credential_types(id),
  name               text not null,
  issuer             text,
  credential_number  text,
  issued_on          date,
  expires_on         date,
  verification_url   text,
  document_id        uuid,
  is_verified        boolean not null default false,
  created_at         timestamptz not null default now()
);
create index person_credentials_person_idx on person_credentials (person_id);

-- ---------------------------------------------------------------
-- Projects / portfolio
-- ---------------------------------------------------------------
create table projects (
  id          uuid primary key default gen_random_uuid(),
  person_id   uuid not null references persons(id) on delete cascade,
  title       text not null,
  role        text,
  description text,
  url         text,
  media       jsonb not null default '[]'::jsonb,
  started_on  date,
  ended_on    date,
  created_at  timestamptz not null default now()
);
create index projects_person_idx on projects (person_id);

create table project_skills (
  project_id uuid not null references projects(id) on delete cascade,
  skill_id   uuid not null references skills(id),
  primary key (project_id, skill_id)
);

-- ---------------------------------------------------------------
-- Languages
-- ---------------------------------------------------------------
create table person_languages (
  person_id     uuid not null references persons(id) on delete cascade,
  language_code char(3) not null references languages(code),
  proficiency   language_proficiency not null,
  can_read      boolean,
  can_write     boolean,
  primary key (person_id, language_code)
);

-- ---------------------------------------------------------------
-- Work authorisation
-- ---------------------------------------------------------------
create table work_authorizations (
  id                   uuid primary key default gen_random_uuid(),
  person_id            uuid not null references persons(id) on delete cascade,
  country_code         char(2) not null,
  status               work_auth_status not null,
  expires_on           date,
  document_id          uuid,
  requires_sponsorship boolean generated always as (
    status in ('requires_sponsorship','no_right_to_work','student_visa_limited')
  ) stored,
  is_verified          boolean not null default false,
  created_at           timestamptz not null default now(),
  unique (person_id, country_code)
);
create index work_auth_country_idx on work_authorizations (country_code, status);

-- ---------------------------------------------------------------
-- References
-- ---------------------------------------------------------------
create table person_references (
  id           uuid primary key default gen_random_uuid(),
  person_id    uuid not null references persons(id) on delete cascade,
  name         text not null,
  relationship text,
  company_name text,
  phone        text,
  email        text,
  is_verified  boolean not null default false,
  -- Contact details are released only when the person shares them for a
  -- specific application. Never bulk-visible in talent search.
  created_at   timestamptz not null default now()
);
create index person_references_person_idx on person_references (person_id);

-- ---------------------------------------------------------------
-- DOCUMENT VAULT
--
-- Sensitive documents are NEVER automatically exposed to employers.
-- Access requires an explicit, per-recipient, revocable share.
-- ---------------------------------------------------------------
create table documents (
  id            uuid primary key default gen_random_uuid(),
  person_id     uuid not null references persons(id) on delete cascade,
  type          document_type not null,
  name          text not null,
  storage_path  text not null,
  mime_type     text,
  size_bytes    bigint,
  is_sensitive  boolean not null default true,
  -- Generated resumes are marked so the app can regenerate them.
  is_generated  boolean not null default false,
  expires_on    date,
  scan_status   text not null default 'pending' check (scan_status in ('pending','clean','infected','failed')),
  created_at    timestamptz not null default now(),
  deleted_at    timestamptz
);
create index documents_person_idx on documents (person_id) where deleted_at is null;
create index documents_type_idx   on documents (person_id, type) where deleted_at is null;

alter table person_licenses
  add constraint person_licenses_document_fk foreign key (document_id) references documents(id) on delete set null;
alter table person_credentials
  add constraint person_credentials_document_fk foreign key (document_id) references documents(id) on delete set null;
alter table work_authorizations
  add constraint work_authorizations_document_fk foreign key (document_id) references documents(id) on delete set null;

-- Explicit consent record. One row = one grant to one company, revocable.
create table document_shares (
  id             uuid primary key default gen_random_uuid(),
  document_id    uuid not null references documents(id) on delete cascade,
  person_id      uuid not null references persons(id) on delete cascade,
  company_id     uuid,                            -- FK added in omelo_04
  application_id uuid,                            -- FK added in omelo_06
  granted_at     timestamptz not null default now(),
  expires_at     timestamptz,
  revoked_at     timestamptz,
  unique (document_id, company_id, application_id)
);
create index document_shares_company_idx on document_shares (company_id) where revoked_at is null;
create index document_shares_person_idx  on document_shares (person_id);

comment on table document_shares is
  'Explicit per-employer consent to view one document. Absence of a live row means no access, regardless of application state. Revocation is immediate.';

-- ---------------------------------------------------------------
-- Verification centre
-- ---------------------------------------------------------------
create table verifications (
  id            uuid primary key default gen_random_uuid(),
  subject_type  text not null check (subject_type in
                  ('person','company','experience','education','license','credential','document')),
  subject_id    uuid not null,
  person_id     uuid references persons(id) on delete cascade,
  type          verification_type not null,
  status        verification_status not null default 'pending',
  method        verification_method,
  -- Exactly what was checked. A badge never implies more than this.
  claim         jsonb not null default '{}'::jsonb,
  verified_by   uuid,
  provider      text,
  verified_at   timestamptz,
  expires_at    timestamptz,
  revoked_at    timestamptz,
  revoke_reason text,
  created_at    timestamptz not null default now()
);
create index verifications_subject_idx on verifications (subject_type, subject_id);
create index verifications_person_idx  on verifications (person_id, type);

-- ---------------------------------------------------------------
-- Career goals
-- ---------------------------------------------------------------
create table career_goals (
  id                uuid primary key default gen_random_uuid(),
  person_id         uuid not null references persons(id) on delete cascade,
  profession_id     uuid references professions(id),
  goal_text         text,
  target_countries  char(2)[] not null default '{}',
  target_pay_amount numeric(14,2),
  target_pay_period pay_period,
  target_currency   char(3),
  priority          smallint not null default 1,
  created_at        timestamptz not null default now()
);
create index career_goals_person_idx on career_goals (person_id);
