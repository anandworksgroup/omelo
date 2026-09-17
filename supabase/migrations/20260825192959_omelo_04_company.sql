-- =====================================================================
-- OMELO 04 — Company Identity and Team
--
-- Must serve both a 200,000-person multinational and a single-location
-- restaurant hiring one cook. Departments and multi-location are
-- optional everywhere.
-- =====================================================================

create table companies (
  id             uuid primary key default gen_random_uuid(),
  slug           text unique not null,
  display_name   text not null,
  legal_name     text,
  industry_id    uuid references industries(id),
  size_band      company_size_band,
  founded_year   smallint,
  website        text,
  logo_url       text,
  cover_url      text,
  about          text,
  culture        jsonb not null default '{}'::jsonb,
  media          jsonb not null default '[]'::jsonb,
  -- Registration / legal
  registration_number text,
  tax_id         text,
  country_code   char(2),
  hq_location_id uuid references locations(id),
  -- Verification gates posting and talent search
  is_verified    boolean not null default false,
  verified_at    timestamptz,
  verification_method verification_method,
  -- Hiring behaviour, recomputed on schedule and shown to candidates
  response_rate_pct     numeric(5,2),
  median_response_hours integer,
  total_hires           integer not null default 0,
  stats_computed_at     timestamptz,
  created_by     uuid references persons(id),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz
);
create index companies_name_trgm    on companies using gin (display_name extensions.gin_trgm_ops);
create index companies_country_idx  on companies (country_code) where deleted_at is null;
create index companies_verified_idx on companies (is_verified) where deleted_at is null;

create trigger companies_set_updated_at
  before update on companies
  for each row execute function extensions.moddatetime(updated_at);

-- Deferred FKs from omelo_03
alter table experiences
  add constraint experiences_company_fk
  foreign key (company_id) references companies(id) on delete set null;

alter table document_shares
  add constraint document_shares_company_fk
  foreign key (company_id) references companies(id) on delete cascade;

create table company_locations (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references companies(id) on delete cascade,
  location_id  uuid references locations(id),
  name         text,
  address      text,
  geo          extensions.geography(Point,4326),
  is_hq        boolean not null default false,
  created_at   timestamptz not null default now()
);
create index company_locations_company_idx on company_locations (company_id);
create index company_locations_geo_idx     on company_locations using gist (geo);

create table departments (
  id         uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  name       text not null,
  parent_id  uuid references departments(id),
  created_at timestamptz not null default now(),
  unique (company_id, name)
);

create table company_members (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  person_id   uuid not null references persons(id) on delete cascade,
  role        company_role not null,
  title       text,
  department_id uuid references departments(id),
  is_active   boolean not null default true,
  invited_by  uuid references persons(id),
  joined_at   timestamptz not null default now(),
  unique (company_id, person_id, role)
);
create index company_members_person_idx  on company_members (person_id) where is_active;
create index company_members_company_idx on company_members (company_id) where is_active;

create table company_invitations (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  email       text not null,
  role        company_role not null,
  token_hash  text not null,
  invited_by  uuid references persons(id),
  accepted_at timestamptz,
  expires_at  timestamptz not null,
  created_at  timestamptz not null default now(),
  unique (company_id, email)
);

-- Entitlements enforced at the service layer, never in the UI alone.
create table company_entitlements (
  company_id            uuid primary key references companies(id) on delete cascade,
  plan                  text not null default 'free',
  recruiter_seats       smallint not null default 1,
  active_job_slots      smallint not null default 3,
  talent_search_enabled boolean not null default false,
  talent_search_quota_monthly integer not null default 0,
  outreach_quota_daily  integer not null default 0,
  ai_credits_monthly    integer not null default 0,
  valid_until           date,
  updated_at            timestamptz not null default now()
);
create trigger company_entitlements_set_updated_at
  before update on company_entitlements
  for each row execute function extensions.moddatetime(updated_at);
