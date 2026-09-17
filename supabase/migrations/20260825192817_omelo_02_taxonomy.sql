-- =====================================================================
-- OMELO 02 — Universal Taxonomy
--
-- Category -> Profession is the user-facing spine of the whole product.
-- "Construction > Electrician" and "Technology > Mobile Developer" are
-- siblings in the same tree. Nothing here privileges office work.
-- =====================================================================

-- ---------------------------------------------------------------
-- Geography
-- ---------------------------------------------------------------
create table locations (
  id            uuid primary key default gen_random_uuid(),
  parent_id     uuid references locations(id),
  kind          text not null check (kind in ('country','region','city','district','area')),
  name          text not null,
  country_code  char(2),
  admin_code    text,
  latitude      double precision,
  longitude     double precision,
  geo           extensions.geography(Point,4326),
  timezone      text,
  population    integer,
  status        taxonomy_status not null default 'active',
  created_at    timestamptz not null default now()
);
create index locations_parent_idx  on locations (parent_id);
create index locations_country_idx on locations (country_code);
create index locations_geo_idx     on locations using gist (geo);
create index locations_name_trgm   on locations using gin (name extensions.gin_trgm_ops);

-- Country-level policy. Makes internationalisation configuration
-- rather than code branches, and is the gate for legally sensitive
-- job fields (see omelo_05, job_legal_restrictions).
create table country_policies (
  country_code              char(2) primary key,
  name                      text not null,
  default_currency          char(3) not null,
  default_pay_period        pay_period not null default 'month',
  salary_disclosure_required boolean not null default false,
  phone_auth_preferred      boolean not null default false,
  -- Gender/age criteria in job postings are unlawful in most of the world.
  -- Default is PROHIBITED. Enabling either requires a recorded legal basis.
  gender_criteria_permitted boolean not null default false,
  age_criteria_permitted    boolean not null default false,
  legal_basis_note          text,
  required_documents        document_type[] not null default '{}',
  supported                 boolean not null default false,
  created_at                timestamptz not null default now()
);

-- ---------------------------------------------------------------
-- Job categories and professions — the universal spine
-- ---------------------------------------------------------------
create table job_categories (
  id           uuid primary key default gen_random_uuid(),
  slug         text unique not null,
  name         text not null,
  icon         text,
  position     smallint not null default 0,
  status       taxonomy_status not null default 'active',
  created_at   timestamptz not null default now()
);

create table professions (
  id             uuid primary key default gen_random_uuid(),
  category_id    uuid not null references job_categories(id),
  slug           text unique not null,
  name           text not null,
  description    text,
  -- Typical shape of this profession, used for onboarding defaults and
  -- for deciding which adaptive profile sections to show.
  typical_education_level education_level,
  requires_license        boolean not null default false,
  is_entry_level_friendly boolean not null default false,
  typical_work_types      work_type[] not null default '{}',
  external_ids   jsonb not null default '{}'::jsonb,
  status         taxonomy_status not null default 'active',
  merged_into    uuid references professions(id),
  embedding      extensions.vector(1536),
  created_at     timestamptz not null default now()
);
create index professions_category_idx on professions (category_id);
create index professions_name_trgm    on professions using gin (name extensions.gin_trgm_ops);
create index professions_embedding_idx on professions using hnsw (embedding extensions.vector_cosine_ops);

-- Free-text job titles resolve here. Never create a profession from user input.
create table profession_aliases (
  id            uuid primary key default gen_random_uuid(),
  profession_id uuid references professions(id) on delete cascade,
  alias         text not null,
  locale        text,
  status        taxonomy_status not null default 'pending_review',
  occurrences   integer not null default 1,
  created_at    timestamptz not null default now(),
  unique (alias, locale)
);
create index profession_aliases_status_idx on profession_aliases (status, occurrences desc);

-- Career mobility backbone. observed_count/median_months exist from day
-- one so the shift from seeded priors to real data is a data migration.
create table profession_transitions (
  from_profession_id uuid not null references professions(id) on delete cascade,
  to_profession_id   uuid not null references professions(id) on delete cascade,
  prior_strength     numeric(4,3) not null default 0 check (prior_strength between 0 and 1),
  observed_count     integer not null default 0,
  median_months      integer,
  median_pay_delta_pct numeric(6,2),
  last_computed_at   timestamptz,
  primary key (from_profession_id, to_profession_id)
);

-- ---------------------------------------------------------------
-- Skills
-- ---------------------------------------------------------------
create table skills (
  id           uuid primary key default gen_random_uuid(),
  slug         text unique not null,
  name         text not null,
  type         skill_type not null,
  description  text,
  external_ids jsonb not null default '{}'::jsonb,
  status       taxonomy_status not null default 'active',
  merged_into  uuid references skills(id),
  embedding    extensions.vector(1536),
  created_at   timestamptz not null default now()
);
create index skills_type_idx      on skills (type);
create index skills_name_trgm     on skills using gin (name extensions.gin_trgm_ops);
create index skills_embedding_idx on skills using hnsw (embedding extensions.vector_cosine_ops);

create table skill_aliases (
  id          uuid primary key default gen_random_uuid(),
  skill_id    uuid references skills(id) on delete cascade,
  alias       text not null,
  locale      text,
  status      taxonomy_status not null default 'pending_review',
  occurrences integer not null default 1,
  created_at  timestamptz not null default now(),
  unique (alias, locale)
);
create index skill_aliases_status_idx on skill_aliases (status, occurrences desc);

create table skill_relations (
  from_skill_id uuid not null references skills(id) on delete cascade,
  to_skill_id   uuid not null references skills(id) on delete cascade,
  kind          relation_kind not null,
  strength      numeric(4,3) not null default 0.5 check (strength between 0 and 1),
  source        source_type not null default 'admin',
  primary key (from_skill_id, to_skill_id, kind)
);

create table profession_skills (
  profession_id uuid not null references professions(id) on delete cascade,
  skill_id      uuid not null references skills(id) on delete cascade,
  importance    numeric(4,3) not null check (importance between 0 and 1),
  source        source_type not null default 'admin',
  primary key (profession_id, skill_id)
);

-- ---------------------------------------------------------------
-- Licenses and credentials
--
-- First-class, not a sub-type of "certification". A driving licence,
-- an electrician's trade licence, and a nursing registration are the
-- primary employability gate for hundreds of millions of workers.
-- ---------------------------------------------------------------
create table license_types (
  id            uuid primary key default gen_random_uuid(),
  slug          text unique not null,
  name          text not null,
  country_code  char(2),
  issuing_body  text,
  category_id   uuid references job_categories(id),
  -- e.g. driving licence classes, trade levels, medical registrations
  class_options text[] not null default '{}',
  verify_url_tpl text,
  renewable     boolean not null default true,
  status        taxonomy_status not null default 'active',
  created_at    timestamptz not null default now()
);
create index license_types_country_idx on license_types (country_code);

create table credential_types (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  issuer         text not null,
  category_id    uuid references job_categories(id),
  verify_url_tpl text,
  status         taxonomy_status not null default 'active',
  unique (name, issuer)
);

create table institutions (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  country_code char(2),
  website      text,
  status       taxonomy_status not null default 'active',
  created_at   timestamptz not null default now()
);
create index institutions_name_trgm on institutions using gin (name extensions.gin_trgm_ops);

create table industries (
  id        uuid primary key default gen_random_uuid(),
  parent_id uuid references industries(id),
  slug      text unique not null,
  name      text not null
);

create table languages (
  code char(3) primary key,
  name text not null,
  native_name text,
  rtl  boolean not null default false
);

-- ---------------------------------------------------------------
-- ADAPTIVE PROFILE SCHEMA
--
-- The mechanism that makes one profile serve a driver, a nurse, and a
-- software engineer. Attributes are declared per category or per
-- profession; the app renders whatever applies to the person's chosen
-- work. No profession-specific columns anywhere in the person tables.
-- ---------------------------------------------------------------
create table profile_attributes (
  id            uuid primary key default gen_random_uuid(),
  slug          text unique not null,
  label         text not null,
  help_text     text,
  data_type     attribute_data_type not null,
  -- Scope: attach to a whole category, a single profession, or globally.
  category_id   uuid references job_categories(id),
  profession_id uuid references professions(id),
  options       jsonb not null default '[]'::jsonb,
  unit          text,
  is_required   boolean not null default false,
  is_filterable boolean not null default true,
  -- Attributes usable as job requirements appear in the job wizard too.
  usable_as_requirement boolean not null default true,
  position      smallint not null default 0,
  status        taxonomy_status not null default 'active',
  created_at    timestamptz not null default now(),
  check (not (category_id is not null and profession_id is not null))
);
create index profile_attributes_category_idx   on profile_attributes (category_id);
create index profile_attributes_profession_idx on profile_attributes (profession_id);

comment on table profile_attributes is
  'Adaptive profile schema. Declares which fields a profession or category needs (vehicle classes for drivers, specialisations for nurses, stacks for engineers). Person values live in person_attributes; job requirements in job_attribute_requirements.';
