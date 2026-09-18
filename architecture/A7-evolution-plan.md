# A7 — Omelo Evolution Plan (master roadmap)

> **The ultimate metric:** how reliably Omelo connects the right person with the right
> work and turns that connection into successful employment. Not feature count.

This is the frozen long-term direction. It is executed as **release gates**, not as
twelve parallel phases. Each release ships, is measured, and passes its gate before
the next begins.

---

## 1. Rules that apply to every release

### 1.1 Extend, don't rewrite

The foundation is **100 tables** (was 87 at Phase 1) with RLS on every table, 27
enforced invariants and three end-to-end suites. For every new capability:

```
Existing table?            → extend it
Existing domain absorbs it? → extend the domain
Otherwise                  → new table (and say why in the migration header)
```

Many later phases already have foundation tables that are **present but unused** —
they are extended, not duplicated (see §3).

### 1.2 Every migration ships with

| Item | How it is enforced today |
|---|---|
| Schema, FKs, constraints | reviewed in the migration; FK indexes are checked by the performance advisor |
| **Indexes** | every FK indexed (migration 33 pattern) |
| **RLS + policies** | invariant 3 (RLS on every table); policies use `(select auth.uid())` (invariant 27) |
| **Sensitive writes through functions** | guard triggers + `SECURITY DEFINER` functions (A5 / migration 25 pattern); invariant 4 enumerates the client-callable surface |
| **Audit event** | `domain_events` (and `application_events` where candidate-visible) |
| **Tests** | an end-to-end suite in `tests/api/` run **as real users**, including the abuse cases |
| **Invariants** | new rows in `sql/verify-invariants.sql` for every new guarantee |
| **Rollback strategy** | stated in the migration header: additive changes are forward-only; destructive changes ship as expand → migrate → contract across two releases |

A migration is not done until `verify-invariants.sql` is all OK and the suites pass.

### 1.3 Request path for sensitive actions

```
UI → service action → backend function (authorise) → database (guards) → event → notification → analytics
```

Never `Flutter → direct table write` for hiring, trust, money, consent or representation.
Reads may go directly through RLS.

### 1.4 Universality test

Every capability must make sense for all six reference workers before it ships:
**delivery driver · electrician · nurse · cook · retail associate · software engineer.**
Profession-specific behaviour comes from data (taxonomy, `profile_attributes`, question
bank, weight profiles), never from code branches.

---

## 2. Release gates

| Release | Phases | Theme | Gate to pass |
|---|---|---|---|
| **R1 Production** | 0 | Launchable | Launch checklist in DEPLOYMENT.md complete; monitoring live; real-device test signed off |
| **R2 Identity** | 1, (8 foundation) | Universal Professional Identity | A worker can hold several identities, each with adaptive fields, visibility and evidence; employers see only what each identity allows |
| **R3 Marketplace** | 2, 3 | Measured matching + two-sided discovery | Funnel measured end to end; talent search with consent; invite-to-apply loop closed |
| **R4 Recruitment** | 4 | Recruiters + agencies | Submission requires candidate consent; no permanent "ownership" of a person |
| **R5 Workforce** | 5 | Staffing | Assignment → shift → attendance → timesheet → approval works for hourly/daily/shift work |
| **R6 Global** | 6 | Multi-country | Pay, authorisation, sponsorship, relocation correct across ≥ 2 countries |
| **R7 Intelligence** | 9, 10, (7 extensions) | Career + employer intelligence | Recommendations measurably lift match → hire |
| **R8 Enterprise** | 11, 12 | Enterprise / RPO / network | Approvals, business units, API access, audit-grade reporting |

Omelo Meet 2.0 (Phase 7) and Assessments/Verification (Phase 8) are threaded through
R2, R3 and R7 rather than being standalone releases — most of Meet 2.0 already exists.

---

## 3. Phase-by-phase: what exists, what to extend, what is new

Legend: **✓ built** · **◐ foundation exists, not wired** · **○ not started**

### Phase 0 — Production hardening (R1)

| Area | State | Plan |
|---|---|---|
| RLS audit, function authorisation audit | ✓ | invariants 1–27; exploit suites in `tests/api/` |
| Rate limiting | ◐ | signup, meet join, chat, messaging, abuse reports are limited. Extend to apply, invitations, search |
| Security headers, input validation | ✓ | portal headers; DB check constraints + function validation |
| CI + secret scanning | ✓ | `.github/workflows/ci.yml`. **Add:** GitHub secret scanning + push protection (repo setting) |
| Demo credential rotation | ○ | **Owner action** — old commits in a public repo contain demo passwords (see §6) |
| Leaked-password protection, backups/PITR, restore test, staging project | ○ | Supabase dashboard / plan — owner action |
| **Auth** | ◐ | email+password ✓. Build: password recovery, email verification (progressive), phone OTP (needs SMS provider), session/device list, account deletion (GDPR-grade, uses existing cascades + `domain_events` FK set-null), account recovery |
| **Observability** | ◐ | `domain_events`, `meet_events`, `outbound_messages`, `net._http_response` exist. Build: error tracking (Sentry or equivalent in both apps + functions), function failure / email failure / Meet failure dashboards from existing tables, funnel views (§5) |

### Phase 1 — Universal Professional Identity (R2)

| Capability | State | Existing foundation |
|---|---|---|
| Multiple work identities | ◐ | `work_identities` (≤5/person, primary, per-identity discoverability, guard + single-primary triggers), identity-scoped `person_skills`, `experiences`, `person_attributes`, `person_professions`, `person_work_preferences`, `person_location_preferences`, `career_goals` |
| Adaptive profile by profession | ◐ | `profile_attributes` (27 attributes) + `omelo_profile_schema_for()` resolver |
| Visibility levels | ◐ | `discoverability` enum on persons + identities, `omelo_is_identity_discoverable_to()` |
| Verification foundation | ◐ | `verifications`, `documents`, `document_shares`, trust-field guards (migration 25) |
| **To build** | ○ | Identity switcher + per-identity editor in the worker app; adaptive form rendered from `omelo_profile_schema_for`; visibility settings UI (Public / Employer / Recruiter / Only when matched / Private — extend the enum with `recruiter` and `matched_only`); evidence display |

### Phase 2 — Marketplace intelligence (R3)

| Capability | State | Existing foundation |
|---|---|---|
| Gates → 17 factors → weight profile → rank → explanation | ✓ | `omelo_score_match`, `matches.feature_vector`, 11 `weight_profiles` |
| Funnel tracking | ◐ | `domain_events` has apply → hire. **Missing:** `JobImpression`, `JobViewed` (and `jobs.view_count` is unmaintained) |
| **Plan** | ○ | Do **not** add `match_results / match_factors / match_explanations` tables — `matches` + `feature_vector` already store all three, versioned by `engine_version`. Add only `match_events` (impression / view / click / apply attributed to a match + rank + surface), and materialised `matching_metrics` views computed from `match_events` + `domain_events`. Offline evaluation: replay a new engine version against historical outcomes before switching |

### Phase 3 — Talent search (R3)

| Capability | State | Existing foundation |
|---|---|---|
| Consent-gated discovery | ◐ | `omelo_is_discoverable_to`, `omelo_is_identity_discoverable_to`, `persons_via_consent` / `work_identities_via_consent` policies |
| Entitlement gate | ◐ | `company_entitlements.talent_search_enabled`, `talent_search_quota_monthly`, `outreach_quota_daily` (employers cannot self-grant — probed) |
| Talent pools | ◐ | `talent_pools`, `talent_pool_members` |
| Invite to apply | ◐ | `candidate_invitations` |
| Profile views | ◐ | `profile_views` |
| **To build** | ○ | `omelo_search_talent(...)` (the reverse scorer — same engine, symmetric), invitation send/respond functions + notifications, worker controls for employer / recruiter / direct-invitation consent, portal Talent Search + Pools pages |

### Phase 4 — Recruiter + agency (R4)

| Capability | State | Plan |
|---|---|---|
| Agency as an organisation | ○ | Extend `companies` with `kind` (`employer` / `agency`), reuse `company_members` (add roles `sourcer`, `coordinator`) |
| Clients, agreements, job orders | ○ | New: `agency_clients` (agency ↔ client company), `hiring_agreements` (terms, fee model), job orders = `jobs` with `represented_company_id` + `agency_id` (a job the agency works on for a client) |
| Submissions | ○ | New: `candidate_submissions` (agency, client, job, identity, **consent record**, status). Client review reuses `applications` once accepted |
| Representation consent | ○ | New: `representation_consents` (person, agency, scope, expiry, revocable). **A recruiter can never permanently own a person**: consent expires and is revocable; duplicate-submission rule is "first consented submission wins for that job only" |
| Placements | ◐ | `employments` + `offers` already model the hire; add `placement_fee` fields on the agreement, not a new hire table |

### Phase 5 — Staffing + workforce (R5)

| Capability | State | Plan |
|---|---|---|
| Work types (permanent … gig, apprenticeship) | ✓ | `work_type`, `pay_period` enums, `omelo_pay_monthly` normalisation |
| Assignments, shifts, attendance, timesheets | ○ | New: `assignments` (employment-like, time-bound, client + agency), `shifts`, `shift_assignments`, `attendance_events` (check-in/out, geo-verified optional), `timesheets` + `timesheet_entries`, `timesheet_approvals`. Billing/payments are integrations, not tables, until a provider is chosen |
| Bulk hiring | ◐ | `jobs.openings`, ranking, pipeline. Add bulk actions (shortlist top N, batch interview slots via Omelo Meet `group`/`walk_in`) and funnel views |

### Phase 6 — Global employment (R6)

| Capability | State | Existing foundation |
|---|---|---|
| Country rules, currency, pay normalisation | ◐ | `country_policies` (14), `locations` hierarchy + timezone, `omelo_pay_monthly(amount, period, country)` |
| Work authorisation, sponsorship, relocation | ◐ | `work_authorizations` (trust-guarded), `jobs.visa_sponsorship`, `accepts_non_residents`, `relocation_support`, work-authorisation **gate** in the matcher |
| Legal restrictions | ◐ | `job_legal_restrictions`, `omelo_check_legal_restriction()` |
| **To build** | ○ | FX reference table for cross-currency comparison, multi-country onboarding, **authoritative-source links** for immigration info (government URLs per country in `country_policies`), clearly labelled "information, not legal advice" |

### Phase 7 — Omelo Meet 2.0 (threaded)

| Capability | State |
|---|---|
| Waiting room, video, audio, chat, host controls, problem reporting, hiring context side panel, rounds, private scorecards, emails | ✓ (video goes live when LiveKit keys are set) |
| Connection-quality indicators, reconnect telemetry | ○ R1 (observability) |
| Group / walk-in / panel sessions for bulk hiring | ○ R5 |
| Recording | ○ **Only after** consent → recording → retention → deletion → access-audit design. Constraint `recording_enabled = false` stays until then (invariant 21) |

### Phase 8 — Assessments + verification (R2 foundation → R7)

| Capability | State | Existing foundation |
|---|---|---|
| Assessments | ◐ | `assessments` table (unused), `evidence_type` enum includes `assessment` (guarded — workers cannot self-set) |
| Verification types | ◐ | `verifications` (identity, phone, email, address, education, employment, license, certificate, right_to_work, background_check, reference) |
| Evidence model | ◐ | `person_skills.evidence_type` + `evidence_refs`, verified employment → verified experience ✓ |
| **To build** | ○ | Profession-specific assessment bank (reuse the question-bank pattern from migration 29), assessment attempts + scoring, evidence summary per skill ("6 years · projects · assessment · verified employment"), document verification workflow for admins |

### Phase 9 — Career intelligence (R7)

Existing: `career_goals`, `profession_transitions`, `profession_skills`, `skill_relations`
(adjacent / prerequisite / substitutable / specialisation), `trajectory_fit` factor (weight 0
today). Build: gap analysis (target profession skills − identity skills, via
`skill_relations`), path suggestions from `profession_transitions` weighted by real hire
outcomes, "suitable jobs now" and interview preparation from the question bank.

### Phase 10 — Employer intelligence (R7)

Existing: pay benchmark + matching-worker count in the job form, `companies.response_rate_pct`,
`median_response_hours`, `total_hires` (Omelo-computed, employer cannot write). Build: job
health ("pay below local median", "requirements unusually restrictive", "limited supply
within radius") computed from the same matcher run in reverse over discoverable
identities; hiring funnel and time-to-X per job (§5).

### Phase 11 — Enterprise / RPO (R8)

Existing: `departments` (with parent), `company_locations`, `company_members` roles,
`company_entitlements`, `automated_decision_log`. Build: business units (departments
tree), requisition + approval workflow (`requisitions`, `approval_steps`), SSO, API keys
and webhooks off `domain_events`, RPO = agency model (R4) operating on behalf of one
enterprise.

### Phase 12 — Global Omelo Employment Network

The closed loop already exists in miniature:
**match → hire → verified employment → stronger identity → better next match.**
R2–R8 widen each arc of it.

### Admin (cross-cutting, starts in R1)

Existing: `platform_admins`, `reports`, `moderation_actions`, `fraud_signals`,
`support_sessions`, `audit_log`, `meet_abuse_reports`, `omelo_is_platform_admin()`.
Build an admin portal incrementally: Trust & Safety queue (reports, abuse reports, fraud
signals) in R1; verification review in R2; taxonomy (skills, professions) in R2; matching
metrics in R3.

---

## 4. Event catalogue

`domain_events` is the nervous system. Consumers: analytics, notifications, matching,
recommendations, audit, intelligence.

| Event | State | Emitted from |
|---|---|---|
| WorkerApplied, ApplicationViewed, CandidateShortlisted, CandidateRejected, ApplicationWithdrawn, ApplicationStageChanged | ✓ | `application_events` trigger |
| InterviewScheduled / Confirmed / Rescheduled / Cancelled / Completed | ✓ | hiring functions |
| MeetStarted, MeetEnded, InterviewFeedbackSubmitted, MeetAbuseReported | ✓ | Meet functions |
| OfferSent, OfferAccepted, OfferDeclined, OfferWithdrawn, WorkerHired, EmploymentVerified | ✓ | offer functions, employment trigger |
| JobPublished, JobPaused, JobClosed, JobExpired | ✓ | jobs trigger |
| WorkerRegistered, IdentityCreated, ProfileUpdated, SkillAdded, JobCreated | ○ R1/R2 | signup trigger, identity/profile triggers |
| JobImpression, JobViewed, InterviewJoined | ○ R3 | `match_events`, Meet join |
| TalentSearched, CandidateInvited, InvitationAccepted | ○ R3 | talent search functions |
| CandidateSubmitted, RepresentationGranted/Revoked, PlacementMade | ○ R4 | agency functions |
| ShiftAssigned, AttendanceRecorded, TimesheetApproved | ○ R5 | workforce functions |

`OfferCreated` from the proposed list maps to the existing `OfferSent` (offers are created
and sent atomically; drafts are not events).

---

## 5. KPIs (first-class, defined once)

All computed from `domain_events`, `match_events` (R3) and existing tables — as SQL views in
`omelo_private`, surfaced in the admin and employer dashboards.

| Group | KPI | Definition |
|---|---|---|
| Marketplace | Active workers / employers / jobs | distinct actors with an event in the last 30 days; jobs `published` |
| | Job fill rate | jobs with ≥ 1 `WorkerHired` ÷ jobs closed or expired |
| Matching | Match → Apply | applications ÷ distinct (identity, job) shown (needs `JobImpression`, R3) |
| | Apply → Shortlist → Interview → Offer → Hire | stage transitions from `domain_events`, per job, per category, per engine version |
| Hiring | Time to shortlist / interview / offer / hire | median of (first event − `WorkerApplied`) |
| | Offer acceptance | `OfferAccepted` ÷ (`OfferAccepted` + `OfferDeclined`) |
| Worker | Profile completion, verified identity/skills | `work_identities.completeness_score`, `verifications` |
| Employer | Candidate response | `companies.response_rate_pct` / `median_response_hours` (Omelo-computed) |
| | Interview → hire conversion, repeat hiring | per company from `domain_events` |

---

## 6. Release 1 — concrete scope

### Owner actions (cannot be done from code)

1. **Demo credentials:** the repo is public and commits before `8e0cc53` contain dev demo
   passwords. Rotate them (Supabase → Auth → Users) or make the repo private. History
   rewriting is optional once rotated.
2. GitHub: enable **secret scanning + push protection**.
3. Supabase: **leaked-password protection**, **PITR/backups** (paid plan), a **staging
   project** separate from production, then a **restore test**.
4. Accounts for providers: LiveKit, Resend (+ verified domain), SMS/OTP provider (for phone
   OTP), error tracking (e.g. Sentry).
5. Real-device test: Android, iOS, web — two-person Omelo Meet call.

### Build (can be done now)

| Item | Approach |
|---|---|
| Password recovery | Supabase recovery flow in both apps (email via Resend once configured) |
| Progressive email verification | keep pre-confirmed signup; add "verify your email" that writes `verifications(type=email)`; require it only for trust-sensitive actions (e.g. accepting an offer, talent-search discoverability) |
| Phone OTP | UI + flow behind a feature flag until an SMS provider is configured |
| Sessions / devices | list and revoke sessions (Supabase auth sessions via an Edge Function) |
| Account deletion | `omelo_request_account_deletion()` → grace period → Edge Function deletes the auth user (cascades already safe; events keep a nulled person) |
| Rate limits | apply, invitation, search |
| Observability | error tracking SDK hooks in both apps + functions (DSN from env, no-op without it); `omelo_private` views for function failures (`net._http_response`), email failures (`outbound_messages`), Meet failures (`meet_events`), hiring funnel (`domain_events`); an admin **System health** page |
| Missing events | `WorkerRegistered`, `IdentityCreated`, `ProfileUpdated`, `SkillAdded`, `JobCreated`, `InterviewJoined` |

**Gate:** DEPLOYMENT.md checklist fully ticked + the items above tested as real users.

### Release 1 status (code complete — owner actions pending)

| Item | State |
|---|---|
| Password recovery (portal + worker app, web + mobile deep link) | ✓ built; needs custom SMTP + redirect URLs |
| Progressive email verification (hashed OTP), phone OTP behind a flag | ✓ |
| Optional "verified email to accept offers" | ✓ flag, default off |
| Sessions / devices, sign out elsewhere | ✓ |
| Account deletion (14-day grace, daily job) — FKs fixed so deletion can never be blocked | ✓ |
| Application rate limit (30/h, 100/day) | ✓ |
| Missing events (WorkerRegistered, IdentityCreated, ProfileUpdated, SkillAdded, JobCreated, InterviewJoined, EmailVerified, account events) | ✓ |
| Admin System health + KPIs (cohort funnel) | ✓ `/admin` in the portal |
| Error tracking (Sentry, no-op without DSN) in both apps | ✓ |
| Outbox retention | ✓ |
| Owner actions (§6) | ○ |
