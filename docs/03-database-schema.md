# 03 — Database Schema

**Status:** **Deployed.** This describes the live database, not a proposal.
**Operational detail:** [`sql/README.md`](../sql/README.md)

| | |
|---|---|
| Project | `jfyqnlucoraazjkndbvm` (`ap-southeast-1`) |
| Postgres | 17.6 |
| Schema | `public` |
| Tables | 86 — RLS enabled on every one |
| Migrations | 11 |
| Seeded | 34 categories, 92 professions, 27 adaptive attributes, 10 licence types, 20 languages, 14 country policies |

---

## 1. Table groups

| Group | Tables | Role |
|---|---|---|
| **Taxonomy** | `locations`, `country_policies`, `job_categories`, `professions`, `profession_aliases`, `profession_transitions`, `profession_skills`, `skills`, `skill_aliases`, `skill_relations`, `license_types`, `credential_types`, `institutions`, `industries`, `languages`, `profile_attributes` | Curated backbone. Every score depends on its quality. |
| **Work identity** | `persons`, `person_work_preferences`, `person_location_preferences`, `person_professions`, `person_skills`, `person_attributes`, `experiences`, `educations`, `person_licenses`, `person_credentials`, `projects`, `project_skills`, `person_languages`, `work_authorizations`, `person_references`, `career_goals` | What a person can do |
| **Documents & trust** | `documents`, `document_shares`, `verifications` | Consent-gated evidence |
| **Company** | `companies`, `company_locations`, `departments`, `company_members`, `company_invitations`, `company_entitlements` | Employer identity and access |
| **Jobs** | `jobs`, `job_skills`, `job_languages`, `job_licenses`, `job_credentials`, `job_attribute_requirements`, `job_documents_required`, `job_benefits`, `job_locations`, `job_stages`, `job_questions`, `job_legal_restrictions` | Demand side |
| **Hiring** | `applications`, `application_events`, `application_notes`, `interviews`, `interview_interviewers`, `interview_scorecards`, `assessments`, `offers`, `employments` | The hiring relationship, end to end |
| **Matching** | `matches`, `weight_profiles` | Materialised, versioned, explainable |
| **Messaging** | `conversations`, `messages`, `notifications`, `notification_preferences` | Direct hiring chat |
| **Edges** | `follows`, `blocks`, `saved_jobs`, `hidden_jobs`, `saved_searches`, `profile_views`, `talent_pools`, `talent_pool_members`, `candidate_invitations` | Consent and preference |
| **Platform** | `reports`, `moderation_actions`, `fraud_signals`, `platform_admins`, `support_sessions`, `audit_log`, `automated_decision_log` | Trust, safety, accountability |
| **Ingestion** | `job_sources`, `ingestion_runs` | Where external jobs legally come from |
| **RLS support** | `job_assignments`-equivalent scoping via `company_members` + `interview_interviewers` | Access scoping |

---

## 2. What the database enforces without application help

Policies that live only in code get broken. These are structural.

| Rule | Mechanism |
|---|---|
| Employers cannot invent or hide candidate-visible states | `job_stages.maps_to_state` is `not null`; `omelo_sync_application_state()` derives `applications.state` on every stage move |
| Application history is immutable | `omelo_log_application_event()` appends; `UPDATE`/`DELETE` revoked; no RLS policy exists for them |
| An Omelo hire becomes verified work history | `omelo_employment_to_experience()` on insert into `employments` |
| `viewed` cannot be suppressed | `omelo_mark_application_viewed()` is the only granted path to opening an application |
| Gender/age criteria prohibited by default | `omelo_check_legal_restriction()` raises unless `country_policies` permits it for that country |
| Sponsorship is never guessed | `jobs.visa_sponsorship` nullable, no default; `NULL` = unknown |
| Money is never a bare number | `CHECK (pay_min is null or (pay_currency is not null and pay_period is not null))` |
| Sensitive documents are never auto-shared | `documents` RLS reaches employers only via a live `document_shares` row |
| Blocking is undetectable | `blocks` has an owner-only read policy; enforcement is inside `omelo_is_discoverable_to()` |
| Talent search needs consent + verification + entitlement | All three are conditions of `omelo_is_discoverable_to()` |
| Taxonomy cannot be polluted | Write privileges revoked from `anon`/`authenticated` on all taxonomy tables |
| Scores are reproducible | `matches.feature_vector` and `engine_version` are `not null`; unique key includes the version |

---

## 3. Key modelling notes

### 3.1 `persons.id` references `auth.users(id)`

One identity, no mapping table, and RLS compares directly against `auth.uid()`. A trigger on
`auth.users` creates the person, work preferences, and notification preferences on signup, so a
new user can search and browse immediately with an empty identity.

### 3.2 Raw values persist beside resolved IDs

`experiences.employer_name`, `educations.institution_name`, `person_licenses.name` all keep what
the user actually wrote next to the resolved foreign key. Resolution is probabilistic and
improves over time; a better resolver can re-run over history, and a mis-resolution never
destroys the user's own words.

### 3.3 Geography is first class

`persons.geo`, `jobs.geo`, `company_locations.geo`, and `interviews.geo` are
`geography(Point,4326)` with GIST indexes. `omelo_nearby_jobs()` returns distance-sorted
results.

This is not a nicety. For most non-remote work, *"how far is it"* outranks every other filter,
and a platform that treats location as a text filter is unusable for the majority of jobs.

**Verified:** a worker at 28.54, 77.23 found a Saket job at 2.2 km.

### 3.4 The adaptive attribute system

`profile_attributes` declares fields scoped `universal`, `category`, or `profession`.
`person_attributes` holds values. `job_attribute_requirements` reuses the same definitions as
job requirements. `omelo_profile_schema_for()` resolves what to render.

Consequence: **no profession-specific columns exist in any person table**, and adding a
profession or a field is a data insert rather than a migration.

### 3.5 Embeddings live in-row

`persons.identity_embedding`, `jobs.job_embedding`, `skills.embedding`,
`professions.embedding` are `vector(1536)` with HNSW cosine indexes, so semantic retrieval and
relational filtering happen in one query rather than two systems reconciled in application code.

> **Open:** 1536 is a placeholder pending the model decision (Q3 in
> [12](12-open-questions.md)). Fix it before any real data lands — changing dimensionality
> later requires a full re-embed. The tables are empty today, so this is currently free.

### 3.6 `matches` is a cache with a contract

Rows may be recomputed freely **except** that any score displayed to a user is retained for the
audit window. The unique key `(person_id, job_id, engine_version)` means a new engine version
writes new rows rather than overwriting history.

**Do not build a job that scores every person against every job.** Matches are materialised only
for pairs surviving retrieval, with TTL eviction.

### 3.7 The stale-application index

```sql
create index applications_stale_idx on applications (last_activity_at)
  where state in ('applied','viewed','shortlisted','screening','assessment','interview','offer');
```

Exists solely to serve the background job that finds applications going silent and expires them
with notice. PR-6 has an index behind it.

---

## 4. Client-callable functions

Only three are reachable over PostgREST. Everything else is an internal predicate or trigger
body with `EXECUTE` revoked.

| Function | Roles | Notes |
|---|---|---|
| `omelo_nearby_jobs(...)` | `anon`, `authenticated` | `SECURITY INVOKER`; RLS governs results |
| `omelo_profile_schema_for()` | `authenticated` | Self-only; raises if asked for another person |
| `omelo_mark_application_viewed(id)` | `authenticated` | Checks `omelo_can_access_job()`, writes state + profile view |

Internal predicates — `omelo_is_company_member`, `omelo_has_company_role`,
`omelo_can_access_job`, `omelo_is_discoverable_to`, `omelo_has_application_from`,
`omelo_is_interviewer_for`, `omelo_is_platform_admin` — are `SECURITY DEFINER` and callable by
nobody except RLS policies.

---

## 5. Scale plan

| Stage | Action |
|---|---|
| Phase 1 | Single primary + read replicas |
| Match growth | Partition `matches` by `computed_at`; TTL eviction |
| Event volume | Partition `application_events` and `audit_log` by month; archive cold partitions |
| Search pressure | Add a dedicated search index as a **derived** store |
| Multi-region | Regional primaries; global taxonomy replication |

Tables that will need partitioning already carry the partition key as a column. Retrofitting one
onto a live 100M-row table is a weekend nobody wants.

---

## 6. What is deliberately absent

| Absent | Why |
|---|---|
| Any column for race, ethnicity, gender, religion, disability, health, marital status, caste, or photo requirement | Never collected. Absence is a stronger guarantee than policy, and it means no scoring feature can ever reference them. |
| A `resumes` table as the primary record | A resume is a rendering of the work identity, not the identity |
| Profession-specific columns | `profile_attributes` instead |
| A mutable `status` column on applications | Events append; state derives |
| Free-text `skills text[]` anywhere | Violates modelling rule 2 |
| Company reviews | Deferred; moderation and defamation exposure need deliberate design |

`persons.date_of_birth` exists but is documented as collected only where a jurisdiction legally
requires age verification for a role, and is **never** a matching feature.

---

## 7. Migration discipline

1. Every change is a numbered Supabase migration. No manual production DDL.
2. Enum values are added, never removed or reordered.
3. Changes to `matches`, `application_events`, or `audit_log` require a backfill plan.
4. Changing the embedding model requires a versioned re-embed with both columns live.
5. Run `get_advisors` after every DDL change. Current state: 4 warnings, two of which are
   intentionally-granted RPCs that self-check authorisation, one is a Supabase platform object.

---

## Decision log

| Decision | Rationale |
|---|---|
| `public` schema, not a schema named `omelodb` | Hosted Supabase allows one database; `public` is what Auth, RLS, PostgREST, and Realtime expect |
| `persons.id` = `auth.users.id` | Removes a mapping table; makes RLS trivial |
| PostGIS from day one | Distance is the primary filter for most non-remote work |
| Adaptive attributes over per-profession tables | Adding a profession is data, not a migration |
| Raw strings kept beside resolved FKs | Resolution improves over time; never destroy user input |
| Business rules as triggers, not application code | Transparency guarantees that live only in code get broken |
| Protected attributes have no column anywhere | Absence is stronger than policy |
