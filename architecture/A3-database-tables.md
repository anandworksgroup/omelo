# A3 Appendix — Complete Table Reference

**Generated from the live database.** Do not hand-edit — regenerate with the query in §1.
Architecture and rationale: [A3-database.md](A3-database.md)

87 tables · schema `public` · project `jfyqnlucoraazjkndbvm`

Key legend: `PK` primary key · `UQ` part of a unique constraint · `NN` NOT NULL ·
`cascade` / `set null` = ON DELETE behaviour.

---

## 1. Generator query

```sql
with fk as (
  select con.conrelid::regclass::text as tbl, a.attname as col,
         con.confrelid::regclass::text || '.' || af.attname as ref,
         case con.confdeltype when 'c' then ' cascade' when 'n' then ' set null' else '' end as del
  from pg_constraint con
  join unnest(con.conkey)  with ordinality as k(attnum, ord) on true
  join unnest(con.confkey) with ordinality as f(attnum, ord) on f.ord = k.ord
  join pg_attribute a  on a.attrelid=con.conrelid  and a.attnum=k.attnum
  join pg_attribute af on af.attrelid=con.confrelid and af.attnum=f.attnum
  where con.contype='f' and con.connamespace='public'::regnamespace),
pk as (select con.conrelid::regclass::text as tbl, a.attname as col
  from pg_constraint con join unnest(con.conkey) k(attnum) on true
  join pg_attribute a on a.attrelid=con.conrelid and a.attnum=k.attnum
  where con.contype='p' and con.connamespace='public'::regnamespace),
uq as (select con.conrelid::regclass::text as tbl, a.attname as col
  from pg_constraint con join unnest(con.conkey) k(attnum) on true
  join pg_attribute a on a.attrelid=con.conrelid and a.attnum=k.attnum
  where con.contype='u' and con.connamespace='public'::regnamespace),
cols as (
  select c.table_name, c.ordinal_position,
    '| `'||c.column_name||'` | `'||
      case when c.data_type='USER-DEFINED' then c.udt_name
           when c.data_type='ARRAY' then ltrim(c.udt_name,'_')||'[]'
           when c.data_type='character' then 'char('||c.character_maximum_length||')'
           when c.data_type='timestamp with time zone' then 'timestamptz'
           when c.data_type='double precision' then 'float8'
           else c.data_type end ||'` | '||
      case when exists(select 1 from pk where pk.tbl=c.table_name and pk.col=c.column_name) then 'PK ' else '' end ||
      case when exists(select 1 from uq where uq.tbl=c.table_name and uq.col=c.column_name) then 'UQ ' else '' end ||
      case when c.is_nullable='NO' then 'NN' else '' end
    ||' | '|| coalesce((select f2.ref||f2.del from fk f2 where f2.tbl=c.table_name and f2.col=c.column_name limit 1),'')
    ||' | '|| coalesce(replace(replace(c.column_default,'|','\|'),'::text',''),'') ||' |' as line
  from information_schema.columns c where c.table_schema='public')
select string_agg(sec, E'\n\n' order by tn) as md from (
  select t.table_name as tn,
    '### `'||t.table_name||'`'||E'\n\n'||
    '| Column | Type | Key | References | Default |'||E'\n'||'|---|---|---|---|---|'||E'\n'||
    (select string_agg(line, E'\n' order by ordinal_position) from cols where cols.table_name=t.table_name) as sec
  from information_schema.tables t
  where t.table_schema='public' and t.table_type='BASE TABLE') s;
```

---

## 2. Tables

### `application_events`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `bigint` | PK NN |  | nextval |
| `application_id` | `uuid` | NN | applications.id cascade |  |
| `event_type` | `application_event_type` | NN |  |  |
| `actor_type` | `actor_type` | NN |  |  |
| `actor_id` | `uuid` |  | persons.id |  |
| `from_state` | `application_state` |  |  |  |
| `to_state` | `application_state` |  |  |  |
| `from_stage_id` | `uuid` |  |  |  |
| `to_stage_id` | `uuid` |  |  |  |
| `reason` | `text` |  |  |  |
| `metadata` | `jsonb` | NN |  | '{}' |
| `occurred_at` | `timestamptz` | NN |  | now() |

### `application_notes`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `application_id` | `uuid` | NN | applications.id cascade |  |
| `company_id` | `uuid` | NN | companies.id cascade |  |
| `author_id` | `uuid` |  | persons.id set null |  |
| `body` | `text` | NN |  |  |
| `created_at` | `timestamptz` | NN |  | now() |

### `applications`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `job_id` | `uuid` | UQ NN | jobs.id cascade |  |
| `person_id` | `uuid` | UQ NN | persons.id cascade |  |
| `company_id` | `uuid` | NN | companies.id cascade |  |
| `stage_id` | `uuid` |  | job_stages.id |  |
| `state` | `application_state` | NN |  | 'applied' |
| `is_archived` | `boolean` |  |  |  |
| `match_score` | `smallint` |  |  |  |
| `cover_note` | `text` |  |  |  |
| `answers` | `jsonb` | NN |  | '[]' |
| `resume_document_id` | `uuid` |  | documents.id set null |  |
| `identity_snapshot` | `jsonb` | NN |  | '{}' |
| `applied_via` | `text` | NN |  | 'omelo' |
| `first_viewed_at` | `timestamptz` |  |  |  |
| `last_activity_at` | `timestamptz` | NN |  | now() |
| `applied_at` | `timestamptz` | NN |  | now() |
| `closed_at` | `timestamptz` |  |  |  |
| `rejection_reason` | `text` |  |  |  |
| `rejected_by` | `uuid` |  | persons.id |  |
| `withdrawal_reason` | `text` |  |  |  |
| `work_identity_id` | `uuid` | NN | work_identities.id |  |

### `assessments`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `application_id` | `uuid` | NN | applications.id cascade |  |
| `job_id` | `uuid` | NN | jobs.id cascade |  |
| `name` | `text` | NN |  |  |
| `kind` | `text` | NN |  | 'custom' |
| `provider` | `text` |  |  |  |
| `external_url` | `text` |  |  |  |
| `sent_at` | `timestamptz` |  |  |  |
| `due_at` | `timestamptz` |  |  |  |
| `completed_at` | `timestamptz` |  |  |  |
| `score` | `numeric` |  |  |  |
| `max_score` | `numeric` |  |  |  |
| `result` | `jsonb` | NN |  | '{}' |
| `created_at` | `timestamptz` | NN |  | now() |

### `audit_log`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `bigint` | PK NN |  | nextval |
| `actor_type` | `actor_type` | NN |  |  |
| `actor_id` | `uuid` |  |  |  |
| `action` | `text` | NN |  |  |
| `subject_type` | `text` | NN |  |  |
| `subject_id` | `uuid` |  |  |  |
| `company_id` | `uuid` |  |  |  |
| `ip_hash` | `text` |  |  |  |
| `user_agent` | `text` |  |  |  |
| `metadata` | `jsonb` | NN |  | '{}' |
| `occurred_at` | `timestamptz` | NN |  | now() |

### `automated_decision_log`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `bigint` | PK NN |  | nextval |
| `person_id` | `uuid` |  | persons.id set null |  |
| `job_id` | `uuid` |  | jobs.id set null |  |
| `company_id` | `uuid` |  | companies.id set null |  |
| `decision_kind` | `text` | NN |  |  |
| `outcome` | `jsonb` | NN |  |  |
| `engine_version` | `text` | NN |  |  |
| `human_reviewed` | `boolean` | NN |  | false |
| `review_requested_at` | `timestamptz` |  |  |  |
| `reviewed_at` | `timestamptz` |  |  |  |
| `occurred_at` | `timestamptz` | NN |  | now() |

### `blocks`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `person_id` | `uuid` | PK NN | persons.id cascade |  |
| `target_type` | `text` | PK NN |  |  |
| `target_id` | `uuid` | PK NN |  |  |
| `reason` | `text` |  |  |  |
| `created_at` | `timestamptz` | NN |  | now() |

### `candidate_invitations`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `company_id` | `uuid` | NN | companies.id cascade |  |
| `job_id` | `uuid` | UQ NN | jobs.id cascade |  |
| `person_id` | `uuid` | UQ NN | persons.id cascade |  |
| `sent_by` | `uuid` |  | persons.id set null |  |
| `message` | `text` |  |  |  |
| `responded_at` | `timestamptz` |  |  |  |
| `response` | `text` |  |  |  |
| `sent_at` | `timestamptz` | NN |  | now() |
| `work_identity_id` | `uuid` |  | work_identities.id set null |  |

### `career_goals`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `person_id` | `uuid` | NN | persons.id cascade |  |
| `profession_id` | `uuid` |  | professions.id |  |
| `goal_text` | `text` |  |  |  |
| `target_countries` | `bpchar[]` | NN |  | '{}' |
| `target_pay_amount` | `numeric` |  |  |  |
| `target_pay_period` | `pay_period` |  |  |  |
| `target_currency` | `char(3)` |  |  |  |
| `priority` | `smallint` | NN |  | 1 |
| `created_at` | `timestamptz` | NN |  | now() |
| `work_identity_id` | `uuid` | NN | work_identities.id cascade |  |

### `companies`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `slug` | `text` | UQ NN |  |  |
| `display_name` | `text` | NN |  |  |
| `legal_name` | `text` |  |  |  |
| `industry_id` | `uuid` |  | industries.id |  |
| `size_band` | `company_size_band` |  |  |  |
| `founded_year` | `smallint` |  |  |  |
| `website` | `text` |  |  |  |
| `logo_url` | `text` |  |  |  |
| `cover_url` | `text` |  |  |  |
| `about` | `text` |  |  |  |
| `culture` | `jsonb` | NN |  | '{}' |
| `media` | `jsonb` | NN |  | '[]' |
| `registration_number` | `text` |  |  |  |
| `tax_id` | `text` |  |  |  |
| `country_code` | `char(2)` |  |  |  |
| `hq_location_id` | `uuid` |  | locations.id |  |
| `is_verified` | `boolean` | NN |  | false |
| `verified_at` | `timestamptz` |  |  |  |
| `verification_method` | `verification_method` |  |  |  |
| `response_rate_pct` | `numeric` |  |  |  |
| `median_response_hours` | `integer` |  |  |  |
| `total_hires` | `integer` | NN |  | 0 |
| `stats_computed_at` | `timestamptz` |  |  |  |
| `created_by` | `uuid` |  | persons.id |  |
| `created_at` | `timestamptz` | NN |  | now() |
| `updated_at` | `timestamptz` | NN |  | now() |
| `deleted_at` | `timestamptz` |  |  |  |

### `company_entitlements`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `company_id` | `uuid` | PK NN | companies.id cascade |  |
| `plan` | `text` | NN |  | 'free' |
| `recruiter_seats` | `smallint` | NN |  | 1 |
| `active_job_slots` | `smallint` | NN |  | 3 |
| `talent_search_enabled` | `boolean` | NN |  | false |
| `talent_search_quota_monthly` | `integer` | NN |  | 0 |
| `outreach_quota_daily` | `integer` | NN |  | 0 |
| `ai_credits_monthly` | `integer` | NN |  | 0 |
| `valid_until` | `date` |  |  |  |
| `updated_at` | `timestamptz` | NN |  | now() |

### `company_invitations`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `company_id` | `uuid` | UQ NN | companies.id cascade |  |
| `email` | `text` | UQ NN |  |  |
| `role` | `company_role` | NN |  |  |
| `token_hash` | `text` | NN |  |  |
| `invited_by` | `uuid` |  | persons.id |  |
| `accepted_at` | `timestamptz` |  |  |  |
| `expires_at` | `timestamptz` | NN |  |  |
| `created_at` | `timestamptz` | NN |  | now() |

### `company_locations`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `company_id` | `uuid` | NN | companies.id cascade |  |
| `location_id` | `uuid` |  | locations.id |  |
| `name` | `text` |  |  |  |
| `address` | `text` |  |  |  |
| `geo` | `geography` |  |  |  |
| `is_hq` | `boolean` | NN |  | false |
| `created_at` | `timestamptz` | NN |  | now() |

### `company_members`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `company_id` | `uuid` | UQ NN | companies.id cascade |  |
| `person_id` | `uuid` | UQ NN | persons.id cascade |  |
| `role` | `company_role` | UQ NN |  |  |
| `title` | `text` |  |  |  |
| `department_id` | `uuid` |  | departments.id |  |
| `is_active` | `boolean` | NN |  | true |
| `invited_by` | `uuid` |  | persons.id |  |
| `joined_at` | `timestamptz` | NN |  | now() |

### `conversations`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `company_id` | `uuid` | UQ NN | companies.id cascade |  |
| `person_id` | `uuid` | UQ NN | persons.id cascade |  |
| `job_id` | `uuid` | UQ | jobs.id set null |  |
| `application_id` | `uuid` |  | applications.id set null |  |
| `initiated_by` | `actor_type` | NN |  | 'candidate' |
| `subject` | `text` |  |  |  |
| `person_archived` | `boolean` | NN |  | false |
| `company_archived` | `boolean` | NN |  | false |
| `last_message_at` | `timestamptz` |  |  |  |
| `created_at` | `timestamptz` | NN |  | now() |

### `country_policies`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `country_code` | `char(2)` | PK NN |  |  |
| `name` | `text` | NN |  |  |
| `default_currency` | `char(3)` | NN |  |  |
| `default_pay_period` | `pay_period` | NN |  | 'month' |
| `salary_disclosure_required` | `boolean` | NN |  | false |
| `phone_auth_preferred` | `boolean` | NN |  | false |
| `gender_criteria_permitted` | `boolean` | NN |  | false |
| `age_criteria_permitted` | `boolean` | NN |  | false |
| `legal_basis_note` | `text` |  |  |  |
| `required_documents` | `document_type[]` | NN |  | '{}' |
| `supported` | `boolean` | NN |  | false |
| `created_at` | `timestamptz` | NN |  | now() |

### `credential_types`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `name` | `text` | UQ NN |  |  |
| `issuer` | `text` | UQ NN |  |  |
| `category_id` | `uuid` |  | job_categories.id |  |
| `verify_url_tpl` | `text` |  |  |  |
| `status` | `taxonomy_status` | NN |  | 'active' |

### `departments`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `company_id` | `uuid` | UQ NN | companies.id cascade |  |
| `name` | `text` | UQ NN |  |  |
| `parent_id` | `uuid` |  | departments.id |  |
| `created_at` | `timestamptz` | NN |  | now() |

### `document_shares`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `document_id` | `uuid` | UQ NN | documents.id cascade |  |
| `person_id` | `uuid` | NN | persons.id cascade |  |
| `company_id` | `uuid` | UQ | companies.id cascade |  |
| `application_id` | `uuid` | UQ |  |  |
| `granted_at` | `timestamptz` | NN |  | now() |
| `expires_at` | `timestamptz` |  |  |  |
| `revoked_at` | `timestamptz` |  |  |  |

### `documents`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `person_id` | `uuid` | NN | persons.id cascade |  |
| `type` | `document_type` | NN |  |  |
| `name` | `text` | NN |  |  |
| `storage_path` | `text` | NN |  |  |
| `mime_type` | `text` |  |  |  |
| `size_bytes` | `bigint` |  |  |  |
| `is_sensitive` | `boolean` | NN |  | true |
| `is_generated` | `boolean` | NN |  | false |
| `expires_on` | `date` |  |  |  |
| `scan_status` | `text` | NN |  | 'pending' |
| `created_at` | `timestamptz` | NN |  | now() |
| `deleted_at` | `timestamptz` |  |  |  |

### `educations`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `person_id` | `uuid` | NN | persons.id cascade |  |
| `institution_id` | `uuid` |  | institutions.id |  |
| `institution_name` | `text` | NN |  |  |
| `level` | `education_level` | NN |  |  |
| `field_of_study` | `text` |  |  |  |
| `started_on` | `date` |  |  |  |
| `ended_on` | `date` |  |  |  |
| `is_ongoing` | `boolean` | NN |  | false |
| `grade` | `text` |  |  |  |
| `is_verified` | `boolean` | NN |  | false |
| `source` | `source_type` | NN |  | 'user' |
| `created_at` | `timestamptz` | NN |  | now() |

### `employments`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `person_id` | `uuid` | NN | persons.id cascade |  |
| `company_id` | `uuid` | NN | companies.id cascade |  |
| `job_id` | `uuid` |  | jobs.id set null |  |
| `application_id` | `uuid` |  | applications.id set null |  |
| `offer_id` | `uuid` |  | offers.id set null |  |
| `profession_id` | `uuid` |  | professions.id |  |
| `title` | `text` | NN |  |  |
| `department_id` | `uuid` |  | departments.id |  |
| `work_type` | `work_type` |  |  |  |
| `workplace_type` | `workplace_type` |  |  |  |
| `location_id` | `uuid` |  | locations.id |  |
| `started_on` | `date` | NN |  |  |
| `ended_on` | `date` |  |  |  |
| `status` | `employment_status` | NN |  | 'active' |
| `end_reason` | `text` |  |  |  |
| `is_omelo_hire` | `boolean` | NN |  | true |
| `created_at` | `timestamptz` | NN |  | now() |
| `updated_at` | `timestamptz` | NN |  | now() |

### `experiences`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `person_id` | `uuid` | NN | persons.id cascade |  |
| `company_id` | `uuid` |  | companies.id set null |  |
| `employer_name` | `text` | NN |  |  |
| `is_self_employed` | `boolean` | NN |  | false |
| `is_informal` | `boolean` | NN |  | false |
| `profession_id` | `uuid` |  | professions.id |  |
| `title` | `text` | NN |  |  |
| `work_type` | `work_type` |  |  |  |
| `workplace_type` | `workplace_type` |  |  |  |
| `location_id` | `uuid` |  | locations.id |  |
| `location_text` | `text` |  |  |  |
| `started_on` | `date` |  |  |  |
| `ended_on` | `date` |  |  |  |
| `is_current` | `boolean` | NN |  | false |
| `months_duration` | `integer` |  |  |  |
| `description` | `text` |  |  |  |
| `responsibilities` | `jsonb` | NN |  | '[]' |
| `pay_amount` | `numeric` |  |  |  |
| `pay_period` | `pay_period` |  |  |  |
| `pay_currency` | `char(3)` |  |  |  |
| `reason_for_leaving` | `text` |  |  |  |
| `is_verified` | `boolean` | NN |  | false |
| `verified_employment_id` | `uuid` |  | employments.id set null |  |
| `source` | `source_type` | NN |  | 'user' |
| `created_at` | `timestamptz` | NN |  | now() |
| `work_identity_id` | `uuid` |  | work_identities.id set null |  |

### `follows`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `person_id` | `uuid` | PK NN | persons.id cascade |  |
| `target_type` | `text` | PK NN |  |  |
| `target_id` | `uuid` | PK NN |  |  |
| `created_at` | `timestamptz` | NN |  | now() |

### `fraud_signals`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `bigint` | PK NN |  | nextval |
| `subject_type` | `text` | NN |  |  |
| `subject_id` | `uuid` | NN |  |  |
| `signal` | `text` | NN |  |  |
| `severity` | `smallint` | NN |  | 1 |
| `detail` | `jsonb` | NN |  | '{}' |
| `detected_at` | `timestamptz` | NN |  | now() |

### `hidden_jobs`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `person_id` | `uuid` | PK NN | persons.id cascade |  |
| `job_id` | `uuid` | PK NN | jobs.id cascade |  |
| `reason` | `text` |  |  |  |
| `created_at` | `timestamptz` | NN |  | now() |

### `industries`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `parent_id` | `uuid` |  | industries.id |  |
| `slug` | `text` | UQ NN |  |  |
| `name` | `text` | NN |  |  |

### `ingestion_runs`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `source_id` | `uuid` | NN | job_sources.id cascade |  |
| `started_at` | `timestamptz` | NN |  | now() |
| `finished_at` | `timestamptz` |  |  |  |
| `jobs_seen` | `integer` | NN |  | 0 |
| `jobs_created` | `integer` | NN |  | 0 |
| `jobs_updated` | `integer` | NN |  | 0 |
| `jobs_closed` | `integer` | NN |  | 0 |
| `errors` | `jsonb` | NN |  | '[]' |

### `institutions`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `name` | `text` | NN |  |  |
| `country_code` | `char(2)` |  |  |  |
| `website` | `text` |  |  |  |
| `status` | `taxonomy_status` | NN |  | 'active' |
| `created_at` | `timestamptz` | NN |  | now() |

### `interview_interviewers`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `interview_id` | `uuid` | PK NN | interviews.id cascade |  |
| `person_id` | `uuid` | PK NN | persons.id cascade |  |
| `is_lead` | `boolean` | NN |  | false |

### `interview_scorecards`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `interview_id` | `uuid` | UQ NN | interviews.id cascade |  |
| `interviewer_id` | `uuid` | UQ NN | persons.id cascade |  |
| `scores` | `jsonb` | NN |  | '{}' |
| `overall_score` | `numeric` |  |  |  |
| `recommendation` | `interview_recommendation` |  |  |  |
| `notes` | `text` |  |  |  |
| `submitted_at` | `timestamptz` | NN |  | now() |

### `interviews`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `application_id` | `uuid` | NN | applications.id cascade |  |
| `job_id` | `uuid` | NN | jobs.id cascade |  |
| `company_id` | `uuid` | NN | companies.id cascade |  |
| `person_id` | `uuid` | NN | persons.id cascade |  |
| `type` | `interview_type` | NN |  |  |
| `status` | `interview_status` | NN |  | 'scheduled' |
| `round` | `smallint` | NN |  | 1 |
| `scheduled_at` | `timestamptz` |  |  |  |
| `duration_minutes` | `smallint` |  |  |  |
| `timezone` | `text` |  |  |  |
| `meeting_url` | `text` |  |  |  |
| `location_text` | `text` |  |  |  |
| `geo` | `geography` |  |  |  |
| `instructions` | `text` |  |  |  |
| `candidate_confirmed_at` | `timestamptz` |  |  |  |
| `completed_at` | `timestamptz` |  |  |  |
| `cancelled_at` | `timestamptz` |  |  |  |
| `cancel_reason` | `text` |  |  |  |
| `created_by` | `uuid` |  | persons.id |  |
| `created_at` | `timestamptz` | NN |  | now() |

### `job_attribute_requirements`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `job_id` | `uuid` | PK NN | jobs.id cascade |  |
| `attribute_id` | `uuid` | PK NN | profile_attributes.id cascade |  |
| `requirement_level` | `requirement_level` | NN |  | 'required' |
| `value_text` | `text` |  |  |  |
| `value_number_min` | `numeric` |  |  |  |
| `value_number_max` | `numeric` |  |  |  |
| `value_bool` | `boolean` |  |  |  |
| `value_json` | `jsonb` |  |  |  |

### `job_benefits`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `job_id` | `uuid` | PK NN | jobs.id cascade |  |
| `benefit_type` | `benefit_type` | PK NN |  |  |
| `detail` | `text` |  |  |  |

### `job_categories`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `slug` | `text` | UQ NN |  |  |
| `name` | `text` | NN |  |  |
| `icon` | `text` |  |  |  |
| `position` | `smallint` | NN |  | 0 |
| `status` | `taxonomy_status` | NN |  | 'active' |
| `created_at` | `timestamptz` | NN |  | now() |

### `job_credentials`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `job_id` | `uuid` | PK NN | jobs.id cascade |  |
| `credential_type_id` | `uuid` | PK NN | credential_types.id |  |
| `requirement_level` | `requirement_level` | NN |  | 'required' |

### `job_documents_required`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `job_id` | `uuid` | PK NN | jobs.id cascade |  |
| `document_type` | `document_type` | PK NN |  |  |
| `is_required` | `boolean` | NN |  | true |
| `request_at_stage` | `text` | NN |  | 'offer' |

### `job_languages`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `job_id` | `uuid` | PK NN | jobs.id cascade |  |
| `language_code` | `char(3)` | PK NN | languages.code |  |
| `min_proficiency` | `language_proficiency` | NN |  | 'conversational' |
| `requirement_level` | `requirement_level` | NN |  | 'required' |

### `job_legal_restrictions`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `job_id` | `uuid` | PK NN | jobs.id cascade |  |
| `gender_requirement` | `text` |  |  |  |
| `min_age` | `smallint` |  |  |  |
| `max_age` | `smallint` |  |  |  |
| `legal_basis` | `text` | NN |  |  |
| `approved_by` | `uuid` |  | persons.id |  |
| `approved_at` | `timestamptz` |  |  |  |
| `created_at` | `timestamptz` | NN |  | now() |

### `job_licenses`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `job_id` | `uuid` | PK NN | jobs.id cascade |  |
| `license_type_id` | `uuid` | PK NN | license_types.id |  |
| `license_class` | `text` |  |  |  |
| `requirement_level` | `requirement_level` | NN |  | 'required' |

### `job_locations`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `job_id` | `uuid` | PK NN | jobs.id cascade |  |
| `location_id` | `uuid` | PK NN | locations.id |  |

### `job_questions`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `job_id` | `uuid` | NN | jobs.id cascade |  |
| `position` | `smallint` | NN |  |  |
| `prompt` | `text` | NN |  |  |
| `answer_type` | `text` | NN |  |  |
| `options` | `jsonb` |  |  |  |
| `is_required` | `boolean` | NN |  | true |
| `is_knockout` | `boolean` | NN |  | false |
| `knockout_expected` | `jsonb` |  |  |  |

### `job_skills`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `job_id` | `uuid` | PK NN | jobs.id cascade |  |
| `skill_id` | `uuid` | PK NN | skills.id |  |
| `requirement_level` | `requirement_level` | NN |  | 'required' |
| `weight` | `numeric` | NN |  | 1.0 |
| `min_months` | `smallint` |  |  |  |

### `job_sources`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `name` | `text` | UQ NN |  |  |
| `kind` | `text` | NN |  |  |
| `is_active` | `boolean` | NN |  | false |
| `terms_url` | `text` |  |  |  |
| `contract_ref` | `text` |  |  |  |
| `last_synced_at` | `timestamptz` |  |  |  |
| `created_at` | `timestamptz` | NN |  | now() |

### `job_stages`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `job_id` | `uuid` | UQ NN | jobs.id cascade |  |
| `name` | `text` | NN |  |  |
| `position` | `smallint` | UQ NN |  |  |
| `maps_to_state` | `application_state` | NN |  |  |
| `is_terminal` | `boolean` | NN |  | false |
| `created_at` | `timestamptz` | NN |  | now() |

### `jobs`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `company_id` | `uuid` | NN | companies.id cascade |  |
| `department_id` | `uuid` |  | departments.id |  |
| `created_by` | `uuid` |  | persons.id |  |
| `title` | `text` | NN |  |  |
| `profession_id` | `uuid` |  | professions.id |  |
| `category_id` | `uuid` |  | job_categories.id |  |
| `profession_source` | `source_type` |  |  | 'employer' |
| `description` | `text` |  |  |  |
| `responsibilities` | `jsonb` | NN |  | '[]' |
| `requirements_text` | `jsonb` | NN |  | '[]' |
| `openings` | `smallint` | NN |  | 1 |
| `workplace_type` | `workplace_type` | NN |  | 'onsite' |
| `location_id` | `uuid` |  | locations.id |  |
| `location_text` | `text` |  |  |  |
| `geo` | `geography` |  |  |  |
| `country_code` | `char(2)` |  |  |  |
| `company_location_id` | `uuid` |  | company_locations.id |  |
| `relocation_support` | `boolean` | NN |  | false |
| `work_type` | `work_type` | NN |  | 'full_time' |
| `shift_types` | `shift_type[]` | NN |  | '{}' |
| `hours_per_week` | `smallint` |  |  |  |
| `working_days` | `smallint` |  |  |  |
| `schedule_note` | `text` |  |  |  |
| `start_date` | `date` |  |  |  |
| `is_immediate_start` | `boolean` | NN |  | false |
| `duration_months` | `smallint` |  |  |  |
| `pay_min` | `numeric` |  |  |  |
| `pay_max` | `numeric` |  |  |  |
| `pay_period` | `pay_period` |  |  |  |
| `pay_currency` | `char(3)` |  |  |  |
| `pay_basis` | `pay_basis` |  |  | 'gross' |
| `pay_negotiable` | `boolean` | NN |  | false |
| `pay_disclosed` | `boolean` |  |  |  |
| `overtime_available` | `boolean` |  |  |  |
| `min_experience_months` | `smallint` |  |  |  |
| `max_experience_months` | `smallint` |  |  |  |
| `accepts_no_experience` | `boolean` | NN |  | false |
| `min_education` | `education_level` |  |  |  |
| `education_negotiable` | `boolean` | NN |  | true |
| `visa_sponsorship` | `boolean` |  |  |  |
| `accepts_non_residents` | `boolean` |  |  |  |
| `physical_requirements` | `jsonb` | NN |  | '[]' |
| `work_environment` | `text` |  |  |  |
| `uniform_required` | `boolean` |  |  |  |
| `own_tools_required` | `boolean` |  |  |  |
| `own_vehicle_required` | `boolean` |  |  |  |
| `application_method` | `text` | NN |  | 'omelo' |
| `external_apply_url` | `text` |  |  |  |
| `contact_phone` | `text` |  |  |  |
| `walk_in_details` | `text` |  |  |  |
| `requires_resume` | `boolean` | NN |  | false |
| `quick_apply_enabled` | `boolean` | NN |  | true |
| `status` | `job_status` | NN |  | 'draft' |
| `content_language` | `char(3)` |  |  |  |
| `published_at` | `timestamptz` |  |  |  |
| `expires_at` | `timestamptz` |  |  |  |
| `closed_at` | `timestamptz` |  |  |  |
| `applicant_count` | `integer` | NN |  | 0 |
| `view_count` | `integer` | NN |  | 0 |
| `source` | `source_type` | NN |  | 'employer' |
| `external_source_id` | `uuid` |  | job_sources.id set null |  |
| `external_id` | `text` |  |  |  |
| `job_embedding` | `vector` |  |  |  |
| `created_at` | `timestamptz` | NN |  | now() |
| `updated_at` | `timestamptz` | NN |  | now() |

### `languages`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `code` | `char(3)` | PK NN |  |  |
| `name` | `text` | NN |  |  |
| `native_name` | `text` |  |  |  |
| `rtl` | `boolean` | NN |  | false |

### `license_types`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `slug` | `text` | UQ NN |  |  |
| `name` | `text` | NN |  |  |
| `country_code` | `char(2)` |  |  |  |
| `issuing_body` | `text` |  |  |  |
| `category_id` | `uuid` |  | job_categories.id |  |
| `class_options` | `text[]` | NN |  | '{}' |
| `verify_url_tpl` | `text` |  |  |  |
| `renewable` | `boolean` | NN |  | true |
| `status` | `taxonomy_status` | NN |  | 'active' |
| `created_at` | `timestamptz` | NN |  | now() |

### `locations`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `parent_id` | `uuid` |  | locations.id |  |
| `kind` | `text` | NN |  |  |
| `name` | `text` | NN |  |  |
| `country_code` | `char(2)` |  |  |  |
| `admin_code` | `text` |  |  |  |
| `latitude` | `float8` |  |  |  |
| `longitude` | `float8` |  |  |  |
| `geo` | `geography` |  |  |  |
| `timezone` | `text` |  |  |  |
| `population` | `integer` |  |  |  |
| `status` | `taxonomy_status` | NN |  | 'active' |
| `created_at` | `timestamptz` | NN |  | now() |

### `matches`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `person_id` | `uuid` | UQ NN | persons.id cascade |  |
| `job_id` | `uuid` | UQ NN | jobs.id cascade |  |
| `score` | `smallint` | NN |  |  |
| `eligible` | `boolean` | NN |  | true |
| `gate_failures` | `text[]` | NN |  | '{}' |
| `feature_vector` | `jsonb` | NN |  |  |
| `weight_profile_id` | `uuid` |  | weight_profiles.id |  |
| `engine_version` | `text` | UQ NN |  |  |
| `computed_at` | `timestamptz` | NN |  | now() |
| `work_identity_id` | `uuid` | NN | work_identities.id cascade |  |

### `messages`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `bigint` | PK NN |  | nextval |
| `conversation_id` | `uuid` | NN | conversations.id cascade |  |
| `sender_person_id` | `uuid` |  | persons.id set null |  |
| `sender_type` | `actor_type` | NN |  |  |
| `kind` | `message_kind` | NN |  | 'text' |
| `body` | `text` |  |  |  |
| `action_type` | `text` |  |  |  |
| `action_payload` | `jsonb` |  |  |  |
| `document_id` | `uuid` |  | documents.id set null |  |
| `read_at` | `timestamptz` |  |  |  |
| `sent_at` | `timestamptz` | NN |  | now() |

### `moderation_actions`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `report_id` | `uuid` |  | reports.id set null |  |
| `subject_type` | `text` | NN |  |  |
| `subject_id` | `uuid` | NN |  |  |
| `action` | `moderation_action` | NN |  |  |
| `reason` | `text` | NN |  |  |
| `actor_id` | `uuid` |  | persons.id set null |  |
| `expires_at` | `timestamptz` |  |  |  |
| `reversed_at` | `timestamptz` |  |  |  |
| `created_at` | `timestamptz` | NN |  | now() |

### `notification_preferences`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `person_id` | `uuid` | PK NN | persons.id cascade |  |
| `push_enabled` | `boolean` | NN |  | true |
| `email_enabled` | `boolean` | NN |  | true |
| `sms_enabled` | `boolean` | NN |  | false |
| `whatsapp_enabled` | `boolean` | NN |  | false |
| `muted_types` | `notification_type[]` | NN |  | '{}' |
| `quiet_hours_start` | `smallint` |  |  |  |
| `quiet_hours_end` | `smallint` |  |  |  |
| `updated_at` | `timestamptz` | NN |  | now() |

### `notifications`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `bigint` | PK NN |  | nextval |
| `person_id` | `uuid` | NN | persons.id cascade |  |
| `type` | `notification_type` | NN |  |  |
| `title` | `text` | NN |  |  |
| `body` | `text` |  |  |  |
| `deeplink` | `text` |  |  |  |
| `entity_type` | `text` |  |  |  |
| `entity_id` | `uuid` |  |  |  |
| `read_at` | `timestamptz` |  |  |  |
| `created_at` | `timestamptz` | NN |  | now() |

### `offers`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `application_id` | `uuid` | NN | applications.id cascade |  |
| `job_id` | `uuid` | NN | jobs.id cascade |  |
| `company_id` | `uuid` | NN | companies.id cascade |  |
| `person_id` | `uuid` | NN | persons.id cascade |  |
| `status` | `offer_status` | NN |  | 'draft' |
| `title` | `text` | NN |  |  |
| `pay_amount` | `numeric` |  |  |  |
| `pay_period` | `pay_period` |  |  |  |
| `pay_currency` | `char(3)` |  |  |  |
| `pay_basis` | `pay_basis` |  |  | 'gross' |
| `work_type` | `work_type` |  |  |  |
| `workplace_type` | `workplace_type` |  |  |  |
| `location_text` | `text` |  |  |  |
| `start_date` | `date` |  |  |  |
| `hours_per_week` | `smallint` |  |  |  |
| `shift_types` | `shift_type[]` | NN |  | '{}' |
| `benefits` | `jsonb` | NN |  | '[]' |
| `conditions` | `text` |  |  |  |
| `contract_document_id` | `uuid` |  | documents.id set null |  |
| `expires_at` | `timestamptz` |  |  |  |
| `sent_at` | `timestamptz` |  |  |  |
| `viewed_at` | `timestamptz` |  |  |  |
| `responded_at` | `timestamptz` |  |  |  |
| `decline_reason` | `text` |  |  |  |
| `created_by` | `uuid` |  | persons.id |  |
| `created_at` | `timestamptz` | NN |  | now() |
| `updated_at` | `timestamptz` | NN |  | now() |

### `person_attributes`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `person_id` | `uuid` | UQ NN | persons.id cascade |  |
| `attribute_id` | `uuid` | UQ NN | profile_attributes.id cascade |  |
| `value_text` | `text` |  |  |  |
| `value_number` | `numeric` |  |  |  |
| `value_bool` | `boolean` |  |  |  |
| `value_date` | `date` |  |  |  |
| `value_json` | `jsonb` |  |  |  |
| `source` | `source_type` | NN |  | 'user' |
| `created_at` | `timestamptz` | NN |  | now() |
| `work_identity_id` | `uuid` | NN | work_identities.id cascade |  |

### `person_credentials`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `person_id` | `uuid` | NN | persons.id cascade |  |
| `credential_type_id` | `uuid` |  | credential_types.id |  |
| `name` | `text` | NN |  |  |
| `issuer` | `text` |  |  |  |
| `credential_number` | `text` |  |  |  |
| `issued_on` | `date` |  |  |  |
| `expires_on` | `date` |  |  |  |
| `verification_url` | `text` |  |  |  |
| `document_id` | `uuid` |  | documents.id set null |  |
| `is_verified` | `boolean` | NN |  | false |
| `created_at` | `timestamptz` | NN |  | now() |

### `person_languages`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `person_id` | `uuid` | PK NN | persons.id cascade |  |
| `language_code` | `char(3)` | PK NN | languages.code |  |
| `proficiency` | `language_proficiency` | NN |  |  |
| `can_read` | `boolean` |  |  |  |
| `can_write` | `boolean` |  |  |  |

### `person_licenses`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `person_id` | `uuid` | NN | persons.id cascade |  |
| `license_type_id` | `uuid` |  | license_types.id |  |
| `name` | `text` | NN |  |  |
| `license_class` | `text` |  |  |  |
| `license_number` | `text` |  |  |  |
| `issuing_body` | `text` |  |  |  |
| `country_code` | `char(2)` |  |  |  |
| `issued_on` | `date` |  |  |  |
| `expires_on` | `date` |  |  |  |
| `document_id` | `uuid` |  | documents.id set null |  |
| `is_verified` | `boolean` | NN |  | false |
| `verification_status` | `verification_status` | NN |  | 'unverified' |
| `created_at` | `timestamptz` | NN |  | now() |

### `person_location_preferences`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `person_id` | `uuid` | NN | persons.id cascade |  |
| `kind` | `text` | NN |  |  |
| `location_id` | `uuid` |  | locations.id |  |
| `country_code` | `char(2)` |  |  |  |
| `radius_km` | `integer` |  |  |  |
| `priority` | `smallint` | NN |  | 1 |
| `created_at` | `timestamptz` | NN |  | now() |
| `work_identity_id` | `uuid` | NN | work_identities.id cascade |  |

### `person_professions`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `person_id` | `uuid` | NN | persons.id cascade |  |
| `profession_id` | `uuid` | PK NN | professions.id |  |
| `relationship` | `text` | NN |  |  |
| `months_experience` | `integer` |  |  |  |
| `priority` | `smallint` | NN |  | 1 |
| `created_at` | `timestamptz` | NN |  | now() |
| `work_identity_id` | `uuid` | PK NN | work_identities.id cascade |  |

### `person_references`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `person_id` | `uuid` | NN | persons.id cascade |  |
| `name` | `text` | NN |  |  |
| `relationship` | `text` |  |  |  |
| `company_name` | `text` |  |  |  |
| `phone` | `text` |  |  |  |
| `email` | `text` |  |  |  |
| `is_verified` | `boolean` | NN |  | false |
| `created_at` | `timestamptz` | NN |  | now() |

### `person_skills`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `person_id` | `uuid` | UQ NN | persons.id cascade |  |
| `skill_id` | `uuid` | UQ NN | skills.id |  |
| `proficiency` | `proficiency_level` |  |  |  |
| `months_used` | `integer` |  |  |  |
| `last_used_on` | `date` |  |  |  |
| `evidence_type` | `evidence_type` | NN |  | 'self_declared' |
| `evidence_refs` | `jsonb` | NN |  | '[]' |
| `is_verified` | `boolean` | NN |  | false |
| `source` | `source_type` | NN |  | 'user' |
| `created_at` | `timestamptz` | NN |  | now() |
| `work_identity_id` | `uuid` |  | work_identities.id set null |  |

### `person_work_preferences`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `person_id` | `uuid` | NN | persons.id cascade |  |
| `seeking` | `boolean` | NN |  | true |
| `work_types` | `work_type[]` | NN |  | '{}' |
| `workplace_types` | `workplace_type[]` | NN |  | '{}' |
| `shift_types` | `shift_type[]` | NN |  | '{}' |
| `availability` | `availability_window` | NN |  | 'immediate' |
| `available_from` | `date` |  |  |  |
| `notice_period_days` | `integer` |  |  |  |
| `max_weekly_hours` | `smallint` |  |  |  |
| `willing_to_relocate` | `boolean` | NN |  | false |
| `willing_to_travel` | `boolean` | NN |  | false |
| `needs_accommodation` | `boolean` | NN |  | false |
| `needs_transport` | `boolean` | NN |  | false |
| `current_pay_amount` | `numeric` |  |  |  |
| `current_pay_period` | `pay_period` |  |  |  |
| `expected_pay_amount` | `numeric` |  |  |  |
| `expected_pay_period` | `pay_period` |  |  |  |
| `minimum_pay_amount` | `numeric` |  |  |  |
| `minimum_pay_period` | `pay_period` |  |  |  |
| `pay_currency` | `char(3)` |  |  |  |
| `pay_basis` | `pay_basis` |  |  | 'gross' |
| `min_outreach_pay_amount` | `numeric` |  |  |  |
| `min_outreach_pay_period` | `pay_period` |  |  |  |
| `updated_at` | `timestamptz` | NN |  | now() |
| `work_identity_id` | `uuid` | PK NN | work_identities.id cascade |  |

### `persons`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN | auth.users.id cascade |  |
| `display_name` | `text` |  |  |  |
| `given_name` | `text` |  |  |  |
| `family_name` | `text` |  |  |  |
| `headline` | `text` |  |  |  |
| `about` | `text` |  |  |  |
| `avatar_url` | `text` |  |  |  |
| `email` | `text` |  |  |  |
| `phone` | `text` |  |  |  |
| `date_of_birth` | `date` |  |  |  |
| `location_id` | `uuid` |  | locations.id |  |
| `location_text` | `text` |  |  |  |
| `geo` | `geography` |  |  |  |
| `country_code` | `char(2)` |  |  |  |
| `timezone` | `text` |  |  |  |
| `highest_education` | `education_level` |  |  |  |
| `locale` | `text` | NN |  | 'en' |
| `discoverability` | `discoverability` | NN |  | 'private' |
| `profile_slug` | `text` | UQ |  |  |
| `onboarding_stage` | `text` | NN |  | 'new' |
| `last_active_at` | `timestamptz` |  |  |  |
| `created_at` | `timestamptz` | NN |  | now() |
| `updated_at` | `timestamptz` | NN |  | now() |
| `deleted_at` | `timestamptz` |  |  |  |

### `platform_admins`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `person_id` | `uuid` | PK NN | persons.id cascade |  |
| `role` | `text` | NN |  |  |
| `granted_by` | `uuid` |  | persons.id set null |  |
| `granted_at` | `timestamptz` | NN |  | now() |
| `expires_at` | `timestamptz` |  |  |  |
| `is_active` | `boolean` | NN |  | true |

### `profession_aliases`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `profession_id` | `uuid` |  | professions.id cascade |  |
| `alias` | `text` | UQ NN |  |  |
| `locale` | `text` | UQ |  |  |
| `status` | `taxonomy_status` | NN |  | 'pending_review' |
| `occurrences` | `integer` | NN |  | 1 |
| `created_at` | `timestamptz` | NN |  | now() |

### `profession_skills`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `profession_id` | `uuid` | PK NN | professions.id cascade |  |
| `skill_id` | `uuid` | PK NN | skills.id cascade |  |
| `importance` | `numeric` | NN |  |  |
| `source` | `source_type` | NN |  | 'admin' |

### `profession_transitions`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `from_profession_id` | `uuid` | PK NN | professions.id cascade |  |
| `to_profession_id` | `uuid` | PK NN | professions.id cascade |  |
| `prior_strength` | `numeric` | NN |  | 0 |
| `observed_count` | `integer` | NN |  | 0 |
| `median_months` | `integer` |  |  |  |
| `median_pay_delta_pct` | `numeric` |  |  |  |
| `last_computed_at` | `timestamptz` |  |  |  |

### `professions`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `category_id` | `uuid` | NN | job_categories.id |  |
| `slug` | `text` | UQ NN |  |  |
| `name` | `text` | NN |  |  |
| `description` | `text` |  |  |  |
| `typical_education_level` | `education_level` |  |  |  |
| `requires_license` | `boolean` | NN |  | false |
| `is_entry_level_friendly` | `boolean` | NN |  | false |
| `typical_work_types` | `work_type[]` | NN |  | '{}' |
| `external_ids` | `jsonb` | NN |  | '{}' |
| `status` | `taxonomy_status` | NN |  | 'active' |
| `merged_into` | `uuid` |  | professions.id |  |
| `embedding` | `vector` |  |  |  |
| `created_at` | `timestamptz` | NN |  | now() |

### `profile_attributes`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `slug` | `text` | UQ NN |  |  |
| `label` | `text` | NN |  |  |
| `help_text` | `text` |  |  |  |
| `data_type` | `attribute_data_type` | NN |  |  |
| `category_id` | `uuid` |  | job_categories.id |  |
| `profession_id` | `uuid` |  | professions.id |  |
| `options` | `jsonb` | NN |  | '[]' |
| `unit` | `text` |  |  |  |
| `is_required` | `boolean` | NN |  | false |
| `is_filterable` | `boolean` | NN |  | true |
| `usable_as_requirement` | `boolean` | NN |  | true |
| `position` | `smallint` | NN |  | 0 |
| `status` | `taxonomy_status` | NN |  | 'active' |
| `created_at` | `timestamptz` | NN |  | now() |

### `profile_views`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `person_id` | `uuid` | NN | persons.id cascade |  |
| `viewer_company_id` | `uuid` |  | companies.id set null |  |
| `viewer_person_id` | `uuid` |  | persons.id set null |  |
| `context_job_id` | `uuid` |  | jobs.id set null |  |
| `viewed_at` | `timestamptz` | NN |  | now() |
| `work_identity_id` | `uuid` |  | work_identities.id set null |  |

### `project_skills`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `project_id` | `uuid` | PK NN | projects.id cascade |  |
| `skill_id` | `uuid` | PK NN | skills.id |  |

### `projects`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `person_id` | `uuid` | NN | persons.id cascade |  |
| `title` | `text` | NN |  |  |
| `role` | `text` |  |  |  |
| `description` | `text` |  |  |  |
| `url` | `text` |  |  |  |
| `media` | `jsonb` | NN |  | '[]' |
| `started_on` | `date` |  |  |  |
| `ended_on` | `date` |  |  |  |
| `created_at` | `timestamptz` | NN |  | now() |
| `work_identity_id` | `uuid` |  | work_identities.id set null |  |

### `reports`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `reporter_id` | `uuid` |  | persons.id set null |  |
| `subject_type` | `text` | NN |  |  |
| `subject_id` | `uuid` | NN |  |  |
| `reason` | `report_reason` | NN |  |  |
| `details` | `text` |  |  |  |
| `status` | `report_status` | NN |  | 'open' |
| `assigned_to` | `uuid` |  | persons.id set null |  |
| `resolution` | `moderation_action` |  |  |  |
| `resolution_note` | `text` |  |  |  |
| `resolved_at` | `timestamptz` |  |  |  |
| `created_at` | `timestamptz` | NN |  | now() |

### `saved_jobs`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `person_id` | `uuid` | PK NN | persons.id cascade |  |
| `job_id` | `uuid` | PK NN | jobs.id cascade |  |
| `created_at` | `timestamptz` | NN |  | now() |

### `saved_searches`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `person_id` | `uuid` | NN | persons.id cascade |  |
| `name` | `text` | NN |  |  |
| `query_text` | `text` |  |  |  |
| `facets` | `jsonb` | NN |  | '{}' |
| `alert_cadence` | `text` | NN |  | 'daily' |
| `last_alerted_at` | `timestamptz` |  |  |  |
| `created_at` | `timestamptz` | NN |  | now() |
| `work_identity_id` | `uuid` |  | work_identities.id cascade |  |

### `skill_aliases`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `skill_id` | `uuid` |  | skills.id cascade |  |
| `alias` | `text` | UQ NN |  |  |
| `locale` | `text` | UQ |  |  |
| `status` | `taxonomy_status` | NN |  | 'pending_review' |
| `occurrences` | `integer` | NN |  | 1 |
| `created_at` | `timestamptz` | NN |  | now() |

### `skill_relations`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `from_skill_id` | `uuid` | PK NN | skills.id cascade |  |
| `to_skill_id` | `uuid` | PK NN | skills.id cascade |  |
| `kind` | `relation_kind` | PK NN |  |  |
| `strength` | `numeric` | NN |  | 0.5 |
| `source` | `source_type` | NN |  | 'admin' |

### `skills`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `slug` | `text` | UQ NN |  |  |
| `name` | `text` | NN |  |  |
| `type` | `skill_type` | NN |  |  |
| `description` | `text` |  |  |  |
| `external_ids` | `jsonb` | NN |  | '{}' |
| `status` | `taxonomy_status` | NN |  | 'active' |
| `merged_into` | `uuid` |  | skills.id |  |
| `embedding` | `vector` |  |  |  |
| `created_at` | `timestamptz` | NN |  | now() |

### `support_sessions`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `admin_id` | `uuid` | NN | persons.id cascade |  |
| `person_id` | `uuid` | NN | persons.id cascade |  |
| `reason` | `text` | NN |  |  |
| `request_ref` | `text` |  |  |  |
| `started_at` | `timestamptz` | NN |  | now() |
| `expires_at` | `timestamptz` | NN |  |  |
| `ended_at` | `timestamptz` |  |  |  |
| `disclosed_at` | `timestamptz` |  |  |  |

### `talent_pool_members`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `pool_id` | `uuid` | PK NN | talent_pools.id cascade |  |
| `person_id` | `uuid` | PK NN | persons.id cascade |  |
| `added_by` | `uuid` |  | persons.id set null |  |
| `note` | `text` |  |  |  |
| `added_at` | `timestamptz` | NN |  | now() |
| `work_identity_id` | `uuid` |  | work_identities.id set null |  |

### `talent_pools`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `company_id` | `uuid` | UQ NN | companies.id cascade |  |
| `name` | `text` | UQ NN |  |  |
| `created_by` | `uuid` |  | persons.id set null |  |
| `created_at` | `timestamptz` | NN |  | now() |

### `verifications`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `subject_type` | `text` | NN |  |  |
| `subject_id` | `uuid` | NN |  |  |
| `person_id` | `uuid` |  | persons.id cascade |  |
| `type` | `verification_type` | NN |  |  |
| `status` | `verification_status` | NN |  | 'pending' |
| `method` | `verification_method` |  |  |  |
| `claim` | `jsonb` | NN |  | '{}' |
| `verified_by` | `uuid` |  |  |  |
| `provider` | `text` |  |  |  |
| `verified_at` | `timestamptz` |  |  |  |
| `expires_at` | `timestamptz` |  |  |  |
| `revoked_at` | `timestamptz` |  |  |  |
| `revoke_reason` | `text` |  |  |  |
| `created_at` | `timestamptz` | NN |  | now() |

### `weight_profiles`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `name` | `text` | UQ NN |  |  |
| `category_id` | `uuid` |  | job_categories.id |  |
| `weights` | `jsonb` | NN |  |  |
| `is_active` | `boolean` | NN |  | true |
| `created_at` | `timestamptz` | NN |  | now() |

### `work_authorizations`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `person_id` | `uuid` | UQ NN | persons.id cascade |  |
| `country_code` | `char(2)` | UQ NN |  |  |
| `status` | `work_auth_status` | NN |  |  |
| `expires_on` | `date` |  |  |  |
| `document_id` | `uuid` |  | documents.id set null |  |
| `requires_sponsorship` | `boolean` |  |  |  |
| `is_verified` | `boolean` | NN |  | false |
| `created_at` | `timestamptz` | NN |  | now() |

### `work_identities`

| Column | Type | Key | References | Default |
|---|---|---|---|---|
| `id` | `uuid` | PK NN |  | gen_random_uuid() |
| `person_id` | `uuid` | UQ NN | persons.id cascade |  |
| `label` | `text` | UQ NN |  |  |
| `profession_id` | `uuid` |  | professions.id |  |
| `category_id` | `uuid` |  | job_categories.id |  |
| `profession_source` | `source_type` | NN |  | 'user' |
| `headline` | `text` |  |  |  |
| `about` | `text` |  |  |  |
| `is_primary` | `boolean` | NN |  | false |
| `status` | `work_identity_status` | NN |  | 'active' |
| `discoverability` | `discoverability` | NN |  | 'private' |
| `total_experience_months` | `integer` |  |  |  |
| `completeness_score` | `smallint` | NN |  | 0 |
| `identity_embedding` | `vector` |  |  |  |
| `created_at` | `timestamptz` | NN |  | now() |
| `updated_at` | `timestamptz` | NN |  | now() |
