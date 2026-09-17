-- ============================================================
-- OMELO 12 — Multiple work identities per person
--
-- Model: a work identity is a LENS over one shared person record.
--   Person-level (shared, never duplicated): name, contact, documents,
--     licences, credentials, languages, education, work authorisation,
--     verifications, blocks, notification preferences.
--   Identity-level (differs per identity): profession anchor, headline,
--     pay expectation, availability, shift, work type, location
--     preference, adaptive attributes, discoverability, career goals.
--   Person-level with optional identity tagging (NULL = shared):
--     skills, experiences, projects.
--
-- person_id is deliberately retained alongside work_identity_id on
-- previously person-scoped tables so every existing RLS policy keeps
-- working as a single indexed comparison. A trigger guarantees the two
-- columns always agree.
-- ============================================================

create type work_identity_status as enum ('active', 'paused', 'archived');

create table work_identities (
  id                      uuid primary key default gen_random_uuid(),
  person_id               uuid not null references persons(id) on delete cascade,
  label                   text not null,
  profession_id           uuid references professions(id),
  category_id             uuid references job_categories(id),
  profession_source       source_type not null default 'user',
  headline                text,
  about                   text,
  is_primary              boolean not null default false,
  status                  work_identity_status not null default 'active',
  discoverability         discoverability not null default 'private',
  total_experience_months integer,
  completeness_score      smallint not null default 0 check (completeness_score between 0 and 100),
  identity_embedding      vector(1536),
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  constraint work_identities_label_unique unique (person_id, label)
);

create unique index work_identities_one_primary
  on work_identities (person_id) where is_primary;
create index work_identities_person_idx on work_identities (person_id);
create index work_identities_profession_idx on work_identities (profession_id) where status = 'active';
create index work_identities_category_idx on work_identities (category_id) where status = 'active';
create index work_identities_discoverable_idx
  on work_identities (discoverability) where status = 'active' and discoverability <> 'private';
create index work_identities_embedding_idx
  on work_identities using hnsw (identity_embedding vector_cosine_ops);

create trigger work_identities_updated_at
  before update on work_identities
  for each row execute function extensions.moddatetime (updated_at);

-- ------------------------------------------------------------
-- Guards
-- ------------------------------------------------------------

create or replace function omelo_guard_work_identity()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_count integer;
begin
  select count(*) into v_count
  from work_identities
  where person_id = new.person_id and id <> coalesce(new.id, gen_random_uuid());

  if tg_op = 'INSERT' and v_count >= 5 then
    raise exception 'A person may hold at most 5 work identities';
  end if;

  -- First identity is automatically primary; a person always has exactly one.
  if v_count = 0 then
    new.is_primary := true;
  end if;

  return new;
end;
$$;

create trigger work_identities_guard
  before insert or update on work_identities
  for each row execute function omelo_guard_work_identity();

-- Demote any other primary when one is promoted.
create or replace function omelo_single_primary_identity()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.is_primary then
    update work_identities
       set is_primary = false
     where person_id = new.person_id and id <> new.id and is_primary;
  end if;
  return new;
end;
$$;

create trigger work_identities_single_primary
  after insert or update of is_primary on work_identities
  for each row when (new.is_primary) execute function omelo_single_primary_identity();

-- Guarantees denormalised person_id always agrees with work_identity_id.
create or replace function omelo_check_identity_owner()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_owner uuid;
begin
  if new.work_identity_id is null then
    return new;
  end if;
  select person_id into v_owner from work_identities where id = new.work_identity_id;
  if v_owner is null then
    raise exception 'work_identity_id % does not exist', new.work_identity_id;
  end if;
  if new.person_id is not null and new.person_id <> v_owner then
    raise exception 'work_identity_id % does not belong to person %', new.work_identity_id, new.person_id;
  end if;
  new.person_id := v_owner;
  return new;
end;
$$;

-- ------------------------------------------------------------
-- Identity-scoped tables (work_identity_id required)
-- ------------------------------------------------------------

alter table person_work_preferences
  add column work_identity_id uuid references work_identities(id) on delete cascade;
alter table person_work_preferences drop constraint person_work_preferences_pkey;
alter table person_work_preferences alter column work_identity_id set not null;
alter table person_work_preferences add primary key (work_identity_id);
create index person_work_preferences_person_idx on person_work_preferences (person_id);

alter table person_location_preferences
  add column work_identity_id uuid not null references work_identities(id) on delete cascade;
create index person_location_preferences_identity_idx
  on person_location_preferences (work_identity_id);

alter table person_attributes
  add column work_identity_id uuid not null references work_identities(id) on delete cascade;
create index person_attributes_identity_idx on person_attributes (work_identity_id);

alter table person_professions
  add column work_identity_id uuid not null references work_identities(id) on delete cascade;
alter table person_professions drop constraint person_professions_pkey;
alter table person_professions add primary key (work_identity_id, profession_id);
create index person_professions_person_idx on person_professions (person_id);

alter table career_goals
  add column work_identity_id uuid not null references work_identities(id) on delete cascade;
create index career_goals_identity_idx on career_goals (work_identity_id);

-- ------------------------------------------------------------
-- Optionally identity-tagged (NULL = shared across all identities)
-- ------------------------------------------------------------

alter table person_skills
  add column work_identity_id uuid references work_identities(id) on delete set null;
create index person_skills_identity_idx on person_skills (work_identity_id);

alter table experiences
  add column work_identity_id uuid references work_identities(id) on delete set null;
create index experiences_identity_idx on experiences (work_identity_id);

alter table projects
  add column work_identity_id uuid references work_identities(id) on delete set null;
create index projects_identity_idx on projects (work_identity_id);

alter table saved_searches
  add column work_identity_id uuid references work_identities(id) on delete cascade;
create index saved_searches_identity_idx on saved_searches (work_identity_id);

-- ------------------------------------------------------------
-- Marketplace tables: you apply, match and get found AS an identity
-- ------------------------------------------------------------

alter table applications
  add column work_identity_id uuid not null references work_identities(id);
create index applications_identity_idx on applications (work_identity_id);

alter table matches
  add column work_identity_id uuid not null references work_identities(id) on delete cascade;
create index matches_identity_idx on matches (work_identity_id, score desc);

alter table profile_views
  add column work_identity_id uuid references work_identities(id) on delete set null;

alter table talent_pool_members
  add column work_identity_id uuid references work_identities(id) on delete set null;

alter table candidate_invitations
  add column work_identity_id uuid references work_identities(id) on delete set null;

-- Apply the owner-agreement guard everywhere both columns exist.
create trigger person_work_preferences_identity_owner
  before insert or update on person_work_preferences
  for each row execute function omelo_check_identity_owner();
create trigger person_location_preferences_identity_owner
  before insert or update on person_location_preferences
  for each row execute function omelo_check_identity_owner();
create trigger person_attributes_identity_owner
  before insert or update on person_attributes
  for each row execute function omelo_check_identity_owner();
create trigger person_professions_identity_owner
  before insert or update on person_professions
  for each row execute function omelo_check_identity_owner();
create trigger career_goals_identity_owner
  before insert or update on career_goals
  for each row execute function omelo_check_identity_owner();
create trigger person_skills_identity_owner
  before insert or update on person_skills
  for each row execute function omelo_check_identity_owner();
create trigger experiences_identity_owner
  before insert or update on experiences
  for each row execute function omelo_check_identity_owner();
create trigger projects_identity_owner
  before insert or update on projects
  for each row execute function omelo_check_identity_owner();
create trigger saved_searches_identity_owner
  before insert or update on saved_searches
  for each row execute function omelo_check_identity_owner();
create trigger applications_identity_owner
  before insert or update on applications
  for each row execute function omelo_check_identity_owner();
create trigger matches_identity_owner
  before insert or update on matches
  for each row execute function omelo_check_identity_owner();

-- ------------------------------------------------------------
-- persons: remove the now-duplicated identity columns.
-- These live on work_identities. Two sources of truth is worse than a
-- join, and the tables are empty, so this costs nothing today.
-- ------------------------------------------------------------

alter table persons drop column primary_profession_id;
alter table persons drop column primary_profession_source;
alter table persons drop column primary_category_id;
alter table persons drop column total_experience_months;
alter table persons drop column completeness_score;
alter table persons drop column identity_embedding;

-- persons.discoverability is retained as a master kill switch.
-- Per-identity discoverability sits on work_identities.
comment on column persons.discoverability is
  'Master switch. If private, NO identity is discoverable regardless of its own setting. Per-identity control lives on work_identities.discoverability.';