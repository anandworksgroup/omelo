# Omelo Database

**[`supabase/migrations/`](../supabase/migrations) is the source of truth.** It holds every
migration exactly as it was applied to the live project (md5-verified against
`supabase_migrations.schema_migrations`), in version order, so `supabase db push` rebuilds the
database on a new project. See [DEPLOYMENT.md](../DEPLOYMENT.md).

[`annotated/`](annotated) keeps the commented source of migrations 24–33 (why each guard
exists, what was exploited). Their statements are the same as the canonical files; read them
for the reasoning, apply the canonical ones.

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
| 11 | `omelo_11_lock_down_function_surface` | Function-surface hardening. **Over-revoked** — see migration 19 |
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
> working. RLS now functions for real users, and no predicate is reachable from a client.
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

Thirty-one functions are reachable over PostgREST. Every `SECURITY DEFINER` one authorises
the caller as its first statement; the hiring functions are the **only** way application,
interview, offer and employment state can change. Everything else is an internal predicate or a trigger body, with `EXECUTE` revoked
and the predicates moved out of the exposed schema entirely.

| Function | Roles | Purpose |
|---|---|---|
| `omelo_nearby_jobs(lat, lng, radius_km, category_id, work_types, limit)` | `anon`, `authenticated` | Distance-sorted job discovery. `SECURITY INVOKER` — RLS governs results. |
| `omelo_profile_schema_for(work_identity_id)` | `authenticated` | Returns the adaptive profile fields for **one work identity**. Defaults to the caller's primary identity. Self-only. |
| `omelo_mark_application_viewed(application_id)` | `authenticated` | The only path to opening an application. Writes the honest `viewed` state. Idempotent. |
| `omelo_company_slug(name)` | `authenticated` | URL-safe unique company slug. `SECURITY INVOKER`, reads only publicly readable rows. |
| `omelo_pay_monthly(amount, period, country)` | `anon`, `authenticated` | Pure arithmetic so a daily wage compares fairly against a salary. |
| `omelo_rank_applicants(job_id)` | `authenticated` | Scores every applicant for a job the caller can access; stores explanations. |
| `omelo_my_match(job_id, work_identity_id?)` | `authenticated` | "Why does this job match me?" Self-only, published jobs only. |
| `omelo_recommend_jobs(lat, lng, radius_km, limit, work_identity_id?)` | `authenticated` | Nearby jobs, scored and explained, eligible and best first. |
| `omelo_move_application(application_id, state)` | `authenticated` (employer) | viewed / shortlisted / screening / assessment / interview for open applications. |
| `omelo_reject_application(application_id, reason)` | `authenticated` (employer) | Reason required. Cancels interviews, withdraws offers, notifies the worker. |
| `omelo_withdraw_application(application_id, reason?)` | `authenticated` (worker) | Also cancels interviews and declines open offers. |
| `omelo_schedule_interview(...)`, `omelo_reschedule_interview`, `omelo_cancel_interview`, `omelo_complete_interview` | `authenticated` (employer; cancel: either party) | Interview lifecycle. Scorecard is written to employer-only `application_notes`. |
| `omelo_confirm_interview(interview_id)` | `authenticated` (worker) | Candidate confirmation. |
| `omelo_send_offer(...)`, `omelo_withdraw_offer(offer_id, reason)` | `authenticated` (employer) | One open offer per application. Terms are frozen once sent. |
| `omelo_view_offer(offer_id)`, `omelo_respond_to_offer(offer_id, accept, reason?)` | `authenticated` (worker) | Accept creates the employment and the verified experience in the same transaction. |
| `omelo_schedule_interview(...)` *(28 signature)* | `authenticated` (hiring team) | Round, format (`omelo_meet`/`phone`/`in_person`), panel, questions, email + notification. Creates the Meet room. |
| `omelo_interview_question_suggestions(job_id, round_kind?)` | `authenticated` | Profession → category → general question bank. |
| `omelo_save_interview_feedback(...)` | `authenticated` (panel, hiring team) | Draft/submit private feedback, competencies, skills demonstrated, per-question answers. |
| `omelo_meet_join(room_name)` | `authenticated` | Called by `meet-token` as the user: `too_early` / `waiting` / `admitted`, with audit and rate limit. |
| `omelo_meet_admit`, `omelo_meet_remove`, `omelo_meet_end` | `authenticated` (panel, hiring team) | Waiting room and host controls. Remove/end are also pushed to the media server by `meet-control`. |
| `omelo_meet_leave`, `omelo_report_meet_abuse` | `authenticated` (participants) | Presence and safety. |
| `omelo_start_conversation(application_id)`, `omelo_send_message(conversation_id, body)`, `omelo_mark_conversation_read(conversation_id)` | `authenticated` (candidate, hiring roles) | Job-context messaging; the only write path to conversations and messages. |
| `omelo_comms_claim`, `omelo_comms_mark` | **`service_role` only** | Used by `comms-dispatch`. Invariant 23 fails if a client can call them. |

### Edge Functions

| Function | JWT | Purpose |
|---|---|---|
| `auth-signup` | no | Email + password signup without confirmation, rate limited per IP. |
| `meet-token` | yes | The only way into an Omelo Meet room. Asks the database (as the user) and mints a 10-minute LiveKit token only when admitted. `503 meet_not_configured` until LiveKit secrets are set. |
| `meet-control` | yes | Remove participant / end interview: database first (authorised, audited), then the media server. |
| `comms-dispatch` | no — takes no input, only sends messages already due, idempotent | Sends queued emails through Resend. Reports `configured:false` until `RESEND_API_KEY` is set. |

Source lives in [`supabase/functions`](../supabase/functions). Secrets (Supabase dashboard → Edge Functions → Secrets): `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `RESEND_API_KEY`, `EMAIL_FROM`, `WORKER_APP_URL`.

Run [`verify-invariants.sql`](verify-invariants.sql) after every migration. It
checks all 20 invariants, each of which corresponds to a bug that actually
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
| 24 | `24_matching_engine_v1` | **Matching Engine v1.** Deterministic, explainable scorer: 3 gates (job open, work authorisation, expired required licence) + 17 factors, weights from `weight_profiles` by job category. *Unknown is not zero* — a missing profile fact scores a neutral 0.5 and is labelled unknown. Score + full explanation stored in `matches.feature_vector` (`engine_version` is in the unique key, so a newer engine never rewrites an explanation someone was shown). Applications are scored at submission. Adds `omelo_rank_applicants`, `omelo_my_match`, `omelo_recommend_jobs`. |
| 25 | `25_hiring_loop_integrity` (+`25b`) | **Security fix + hiring loop.** Seven holes were proven with real logins (below) and closed. Guard triggers are `SECURITY INVOKER` and treat `current_user` as the authority, so a client request is `authenticated` and only the `SECURITY DEFINER` hiring functions can move state. Adds the only paths through the loop: move / reject (reason required) / withdraw, schedule / reschedule / confirm / cancel / complete interview (private scorecard), send / withdraw / view offer, respond to offer. **Accept → hired → employment → verified experience on the identity the worker applied with.** Workers are notified at each step and every transition is attributed in `application_events`. `25b` removed a comparison against the generated `is_archived` column (null in a BEFORE trigger), which had blocked candidate withdrawal. |
| 26 | `26_domain_events` (+`26b`) | **Event spine.** Append-only `domain_events` outbox written in the same transaction: `WorkerApplied`, `ApplicationViewed`, `CandidateShortlisted`, `CandidateRejected`, `InterviewScheduled/Confirmed/Rescheduled/Cancelled/Completed`, `OfferSent/Accepted/Declined/Withdrawn`, `WorkerHired`, `EmploymentVerified`, `JobPublished/Paused/Closed/Expired`. Server-side only (no client privileges). `26b` lets the foreign keys' `ON DELETE SET NULL` through so deleting an account is never blocked. |
| 27 | `27_interview_policy_recursion` | **Fix.** `interviews` and `interview_interviewers` policies referenced each other, so every direct `select` on interviews failed with *infinite recursion detected in policy*. The hiring functions (definer) never hit it; the portal's candidate review page did, as a real employer. Cross-table checks moved to `omelo_private` definer predicates. The e2e test now also reads interviews and offers directly as employer, worker and a rival company. |

| 28 | `28_omelo_meet` (+`28b`) | **Omelo Meet + communications** ([A6](../architecture/A6-omelo-meet.md)). Interviews become rounds (`round_name`, `round_kind`, `meeting_mode`) with a planned process per job (`job_interview_rounds`). Native interview rooms (`interview_rooms`, unguessable `room_name`, 15-min-early → 60-min-late window, waiting room on, **recording impossible by constraint**), presence (`interview_participants`), sessions, in-room chat (`meet_messages`, rate limited), room audit (`meet_events`), abuse reports, profession-specific questions (`interview_question_templates` → `interview_questions`), and **private structured feedback** (`interview_feedback`, `interview_answers`) that candidates have no read path to. Transactional email outbox (`outbound_messages`) written in the same transaction as the action: invitation, next-round, reschedule, cancellation, 24 h + 1 h reminders (re-queued on reschedule), completion, offer. `28b`: scheduling falls back to the job's planned round for format and duration. |
| 29 | `29_interview_question_bank` | Seeds 188 questions: general, software, drivers, nurses, cooks, security, electricians/plumbers, retail, warehouse, reception, teaching, domestic help, accounting, engineering, plus category fallbacks. Resolution: profession → category → general. |
| 30 | `30_meet_schedules` | `pg_cron`: `omelo-comms-dispatch` every minute (calls the `comms-dispatch` Edge Function via `pg_net`), `omelo-meet-housekeeping` every 5 minutes (expires rooms nobody ended). |
| 31 | `31_panel_candidate_access` | **Fix.** A teammate with only the `interviewer` role could join the room but not read the candidate's profile, experience, skills or match — so they needed another app during the call. Access now extends to people named on the panel of a non-cancelled interview with that candidate, only while they are active members of the company, and the match only for that job. Tested, including revocation on deactivation. |
| 32 | `32_job_messaging_and_notifications` | **Security fix + feature.** Any company member (even `viewer`) could open a conversation with *any* person, senders could set `sender_type` to impersonate the other side, and clients could post `action` messages or forge notifications. Conversations are now anchored to an application and written only through `omelo_start_conversation` / `omelo_send_message` / `omelo_mark_conversation_read` (hiring roles only; employers cannot keep messaging a candidate who withdrew; 20 msgs/min). Recipients get an in-app notification; candidates also a throttled email (one per conversation per 30 min). Notifications become an inbox: read, mark read, delete — never create or rewrite. |
| 33 | `33_production_hardening` | Every policy's `auth.uid()` wrapped as `(select auth.uid())` so it is evaluated once per statement (73 policies); an index for every foreign key (105); the Edge Function base URL used by `pg_cron` moved from code to `omelo_private.app_settings`. All three end-to-end suites re-run green afterwards. |
| 34 | `34_rename_meet_message_stamp` | Renamed the meet-chat trigger (`omelo_guard_meet_message` → `omelo_stamp_meet_message`): it is intentionally `SECURITY DEFINER` (stamps the sender name, flood limit) and must not carry the `omelo_guard_*` prefix that invariant 16 requires to be invoker-rights. |
### Holes closed by migration 25

Proven as real users through the publishable key before the fix, and re-run
after it by [`tests/api/hiring_loop_e2e.py`](../tests/api/hiring_loop_e2e.py):

| # | Attack (before) | Result before | After |
|---|---|---|---|
| H1 | Employer `PATCH applications.state = 'hired'` | 200, hired with no offer | 403 |
| H2 | Employer rejects with no reason | 200 | 403 direct; function requires a reason |
| H3 | Employer `POST employments` for any worker | 201 — **forged verified work history** | 403 |
| H4 | Worker inserts `experiences.is_verified = true` / skill `employer_verified` | 201 | 403 |
| H5 | Employer `PATCH companies.is_verified = true` | 200 — forged badge, unlocks talent-search gate | 403 |
| H6 | Candidate `PATCH offers` pay while accepting | allowed by policy | 403 (policy removed) |
| H7 | Either party `POST application_events` | allowed by policy — forged audit trail | 403 (policy removed) |


## Demo accounts (development)

Email confirmation is on and the default SMTP is rate-limited, so these were
created directly in `auth.users`. To enable self-serve signup, turn off
**Confirm email** in Authentication → Providers → Email.

| Role | Email | Password |
|---|---|---|
| Employer (owner of *Sector 18 Kitchens*) | `sarah@zippylogistics.in` | *see `DEMO_ACCOUNTS.local.md`* |
| Worker (Cook, Sector 62 Noida) | `ravi.worker@omelo.dev` | *see `DEMO_ACCOUNTS.local.md`* |

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
