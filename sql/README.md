# Omelo Database

**The live schema is the source of truth.** It is deployed to Supabase, not maintained as
loose SQL files in this folder.

| | |
|---|---|
| **Project ref** | `jfyqnlucoraazjkndbvm` |
| **URL** | `https://jfyqnlucoraazjkndbvm.supabase.co` |
| **Region** | `ap-southeast-1` |
| **Postgres** | 17.6 |
| **Schema** | `public` |
| **Tables** | 87, RLS enabled on all of them |
| **Extensions** | `pgcrypto`, `pg_trgm`, `unaccent`, `vector`, `postgis`, `moddatetime` (all in `extensions`) |

> **On the name `omelodb`:** hosted Supabase gives one database (`postgres`) per project and
> does not allow creating additional databases. The Omelo schema therefore lives in `public`,
> which is what Supabase Auth, RLS, PostgREST, and Realtime expect. A schema literally named
> `omelodb` would require extra API exposure config for no functional benefit.

---

## Applied migrations

| # | Migration | Contents |
|---|---|---|
| 01 | `omelo_01_extensions_and_enums` | Extensions and ~35 enums covering every work shape, not just salaried office work |
| 02 | `omelo_02_taxonomy` | Locations, country policies, job categories, professions, skills, licences, **adaptive `profile_attributes`** |
| 03 | `omelo_03_person_work_identity` | Person, work preferences, skills, experience, education, licences, documents, verification |
| 04 | `omelo_04_company` | Companies, locations, departments, members, entitlements |
| 05 | `omelo_05_jobs` | The universal job model, requirements, benefits, stages, legal-restriction guard, ingestion |
| 06 | `omelo_06_applications_hiring_loop` | Applications, events, interviews, scorecards, assessments, offers, **employments**, matches |
| 07 | `omelo_07_messaging_trust_platform` | Conversations, internal notes, consent edges, notifications, reports, admin, audit |
| 08 | `omelo_08_rls_policies` | Helper predicates and RLS on every table |
| 09 | `omelo_09_seed_taxonomy` | 34 categories, 92 professions, 27 adaptive attributes, 10 licence types, 20 languages, 14 country policies |
| 10 | `omelo_10_auth_functions_grants` | Signup trigger, adaptive profile resolver, nearby-jobs search, grants |
| 11 | `omelo_11_lock_down_function_surface` | Function-surface hardening; only three RPCs reachable from a client |
| 12 | `omelo_12_work_identities` | **Multiple work identities per person.** `work_identities` table, identity-scoping across 11 tables, owner and cap guards, removal of the duplicated identity columns from `persons` |
| 13 | `omelo_13_work_identity_functions_and_rls` | Two-level consent (`omelo_is_identity_discoverable_to`), per-identity adaptive profile resolver, signup creates a default identity, RLS on `work_identities` |
| 14 | `omelo_14_revoke_rls_auto_enable` | Removed `rls_auto_enable()` from the client-reachable API surface |
| 15 | `omelo_15_geo_sync_and_locations_in_ncr` | `omelo_sync_geo()` trigger; Delhi NCR gazetteer — 1 country, 3 regions, 6 cities, 43 areas, all with `geo` |
| 16 | `omelo_16_seed_skills` | 118 skills weighted to trades and manual work; 200+ `profession_skills` links |
| 17 | `omelo_17_seed_weight_profiles` | 11 match weight profiles, each validated to sum to exactly 1.0000 by trigger |
| 18 | `omelo_18_nearby_jobs_v2_and_pay_normalisation` | `omelo_pay_monthly()`; richer `omelo_nearby_jobs` with search, filters, benefits, hidden/blocked gates |
| **19** | **`omelo_19_fix_rls_predicate_execution`** | **Critical fix.** Moved the 8 RLS predicates to schema `omelo_private` and granted EXECUTE to `anon`/`authenticated` |
| 20 | `omelo_20_pin_pay_monthly_search_path` | Pinned `search_path` on the pay normaliser |

> ### Migration 19 — why it mattered
>
> Migration 11 revoked `EXECUTE` on the RLS helper predicates from `anon` **and**
> `authenticated`. RLS policies invoke those helpers *as the calling role*, so every policy
> on ~40 tables failed with `permission denied for function omelo_is_company_member` for
> every real user. It went undetected because all prior testing ran as `service_role`, which
> bypasses RLS entirely.
>
> The fix moves the predicates into `omelo_private`, a schema PostgREST does not expose.
> Policies reference functions by OID, so `ALTER FUNCTION ... SET SCHEMA` keeps every policy
> working. RLS now functions for real users, and the client-callable RPC surface is still
> exactly three.
>
> **Lesson for every future migration: verify with an `anon`/`authenticated` key, never only
> through the service role.**

---

## Pulling the schema locally

Install the Supabase CLI, then:

```bash
supabase link --project-ref jfyqnlucoraazjkndbvm
```

```bash
supabase db pull
```

That writes the full DDL into `supabase/migrations/`. Do this before writing application code
so the local project and the remote database share one migration history.

Generate typed clients:

```bash
supabase gen types typescript --project-id jfyqnlucoraazjkndbvm > src/types/database.ts
```

---

## Client-callable functions

Only three functions are reachable over PostgREST. Everything else is an internal predicate
or a trigger body, with `EXECUTE` revoked.

| Function | Roles | Purpose |
|---|---|---|
| `omelo_nearby_jobs(lat, lng, radius_km, category_id, work_types, limit)` | `anon`, `authenticated` | Distance-sorted job discovery. `SECURITY INVOKER` — RLS governs results. |
| `omelo_profile_schema_for(work_identity_id)` | `authenticated` | Returns the adaptive profile fields for **one work identity**. Defaults to the caller's primary identity. Self-only. |
| `omelo_mark_application_viewed(application_id)` | `authenticated` | The only path to opening an application. Writes the honest `viewed` state. Idempotent. |
| `omelo_company_slug(name)` | `authenticated` | URL-safe unique company slug. `SECURITY INVOKER`, reads only publicly readable rows. |
| `omelo_pay_monthly(amount, period, country)` | `anon`, `authenticated` | Pure arithmetic so a daily wage compares fairly against a salary. |

Run [`verify-invariants.sql`](verify-invariants.sql) after every migration. It
checks all 14 invariants, each of which corresponds to a bug that actually
shipped. **Structural checks are not enough** — the RLS bug below passed every
one of them while being completely broken for real users, so always also test
with an `anon` / `authenticated` key.

---

## Invariants the database enforces by itself

These are not conventions the application must remember. They are structural.

| Invariant | Mechanism |
|---|---|
| Employers cannot invent or hide candidate-visible states | `job_stages.maps_to_state` is `not null`; `omelo_sync_application_state()` derives `applications.state` from it on every stage move |
| Application history is immutable | `omelo_log_application_event()` appends; `UPDATE`/`DELETE` revoked on `application_events` and no RLS policy exists for them |
| An Omelo hire becomes verified work history | `omelo_employment_to_experience()` writes a verified `experiences` row plus a `verifications` record on insert into `employments` |
| Gender and age criteria are prohibited by default | `omelo_check_legal_restriction()` raises unless `country_policies` explicitly permits them for that country |
| Sponsorship is never guessed | `jobs.visa_sponsorship` is nullable with no default; `NULL` means unknown |
| Sensitive documents are never auto-shared | Employers reach `documents` only through a live, unrevoked `document_shares` row — receiving an application grants nothing |
| Blocking produces absence, not a signal | `blocks` has an owner-only read policy; enforcement happens inside `omelo_is_discoverable_to()` |
| Talent search requires consent **and** verification **and** entitlement | All three are conditions inside `omelo_is_discoverable_to()` |
| Taxonomy cannot be polluted by users | `INSERT`/`UPDATE`/`DELETE` revoked from `anon` and `authenticated` on all taxonomy tables; new terms land in `*_aliases` as `pending_review` |
| Money is never a bare number | Every pay column is paired with currency, period, and basis, with `CHECK` constraints |

---

## Verified end to end

A full loop was executed against the live database and rolled back:

```
Employer creates stages: New -> Phone Call -> Trial Shift -> Hire
Worker (no resume, no degree) applies via quick_apply
Employer moves to "Trial Shift"     -> candidate state derived to 'interview'
                                    -> 2 immutable events logged
Employer hires                      -> 1 verified experience created
                                    -> 1 employment verification created
omelo_nearby_jobs(28.54, 77.23, 10) -> found the job at 2.2 km
omelo_profile_schema_for()          -> returned 5 fields for a delivery worker:
                                       delivery-vehicle, smartphone-available,
                                       has-smartphone, can-travel-daily-km, first-job
                                       (no vehicle-classes, no clinical-specialisation)
```

The last line is the adaptive profile working: a delivery worker is asked what they deliver
with, never about clinical specialisations or driving licence classes for heavy vehicles.

---

## `_superseded/`

`_superseded/schema.sql` and `_superseded/policies.sql` are the earlier Phase-0 draft written
against the white-collar-only model. They are kept for reference only. **Do not implement
against them** — they lack the category/profession spine, the adaptive attribute system,
licences, shifts, pay periods, benefits, offers, employments, and the admin surface.

| 21 | `omelo_21_company_bootstrap` | **Fix.** Founder is auto-made `owner` on company insert, plus free-tier entitlements. Without it, `company_members_manage` required an owner role to create the first owner — nobody could ever own a company they created. Adds `omelo_company_slug()`. |
| 22 | `omelo_22_jobs_geo_from_location` | **Fix.** `jobs.geo` derived from `company_location_id` / `location_id`. A portal-posted job had no way to send PostGIS geography over PostgREST, so `geo` was NULL and `omelo_nearby_jobs` silently never returned it. Adds a publish guard: an on-site job cannot be published without a location. |

## Verified as a real authenticated user

Both fixes were found by testing with an actual signed-in JWT rather than `service_role`:

```
sign in                     -> 200
read own person row         -> 1 row
read other person rows      -> 0 rows        (RLS holds)
create company              -> 201
  auto owner membership     -> ['owner']
  auto entitlements         -> free, 3 job slots, talent_search DISABLED
create job as draft         -> 201
  geo derived from location -> present, country IN
  draft visible to anon     -> 0 rows        (correctly hidden)
publish job                 -> published_at + expires_at set automatically
anonymous worker discovery  -> FINDS IT: "Cook - Test Kitchen" 0km,
                               16000-24000/month, no-experience, meals
```

The employer -> job -> worker loop is proven end to end against RLS.

| 23 | `omelo_23_protect_application_immutables` | **Fix.** Employers could `PATCH first_viewed_at` back to `NULL` and erase the fact they had opened an application — breaking FR-331, the promise `viewed` cannot be suppressed. RLS has no column-level rules, so a trigger now makes `first_viewed_at` monotonic and `job_id`/`person_id`/`company_id`/`work_identity_id`/`applied_at`/`identity_snapshot` immutable after submission. Also made `omelo_mark_application_viewed()` idempotent. |

## Demo accounts (development)

Email confirmation is on and the default SMTP is rate-limited, so these were
created directly in `auth.users`. To enable self-serve signup, turn off
**Confirm email** in Authentication → Providers → Email.

| Role | Email | Password |
|---|---|---|
| Employer (owner of *Sector 18 Kitchens*) | `sarah@zippylogistics.in` | `OmeloDemo2026!` |
| Worker (Cook, Sector 62 Noida) | `ravi.worker@omelo.dev` | `OmeloWorker2026!` |

**Worker phone OTP is not available** — the Supabase phone provider is disabled
and needs an SMS provider (Twilio) configured. Both apps use email + password
until then; swapping the worker app to OTP is a change in
`lib/data/auth_repository.dart` only.

## Edge Functions

| Function | verify_jwt | Purpose |
|---|---|---|
| `auth-signup` | **off** | Creates an already-confirmed user so sign-up needs no email confirmation. The caller is by definition unauthenticated, so JWT verification is off and the function validates input and rate limits itself (10 accounts per IP per hour, tracked in `audit_log`). |

Both apps call `auth-signup` and then sign in normally with the publishable
key. The service role key exists only inside the function's environment and
never reaches a browser bundle or an APK.

> **Trade-off, stated plainly:** nobody proves they own their email address.
> That is deliberate for now — it removes the SMTP rate limit that made
> self-serve sign-up unusable. Before launch, either turn confirmation back on
> or move workers to phone OTP, because password reset is not trustworthy
> without a verified address.
