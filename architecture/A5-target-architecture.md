# A5 — Target Architecture

**Status:** Adopted · supersedes nothing, extends A1–A4
**Principle:** the 87-table foundation stays the core. Capabilities are built *around* it.

> Omelo = Universal Professional Identity + Global Job Marketplace + Hiring/ATS
> + Skills Graph + Career Intelligence

---

## 1. The one loop that matters

Omelo is measured by one loop, not by feature count.

```
JOB → DISCOVERY → MATCH → APPLY → REVIEW → INTERVIEW → OFFER → HIRE
                                                              │
      BETTER MATCH  ←  BETTER IDENTITY  ←  VERIFIED WORK  ←───┘
```

Every product decision is judged by whether it makes that loop faster, more honest, or
more likely to complete. The last three arrows are what no job board has: a hire made on
Omelo becomes verified work history, which improves the identity, which improves the next
match. The loop compounds.

---

## 2. Layers

```
                                   OMELO
                                     │
        ┌────────────────────────────┼────────────────────────────┐
   WORKER PLATFORM            EMPLOYER PLATFORM            ADMIN PLATFORM
   Flutter (Android/iOS/Web)  Next.js (HR / Recruiter)     Next.js (Operations)
        └────────────────────────────┼────────────────────────────┘
                                     │
                           OMELO PLATFORM API
                 PostgREST + RLS  ·  Edge Functions  ·  RPC
                                     │
     Identity · Jobs · Applications · Recruiting · Messaging · Notifications
                                     │
                           INTELLIGENCE LAYER
               Skills Graph · Matching Engine · Career Engine
                                     │
                           TRUST & VERIFICATION
             Identity · Employment · Skills · Company · Risk
                                     │
                               EVENT SPINE
                        domain_events (append-only)
                                     │
                               DATA LAYER
                  PostgreSQL / Supabase · Storage · Search · Analytics
```

---

## 3. Coverage: what the foundation already provides

The honest finding of this review: **most of the target architecture already exists as
schema.** What is missing is mostly logic and interface, not tables.

| Capability | Existing tables | Schema | Logic | UI |
|---|---|---|---|---|
| Professional identity | `persons`, `work_identities`, `person_professions`, `person_attributes`, `profile_attributes` | ✅ | ✅ adaptive resolver | ❌ |
| Skills graph | `skills`, `skill_relations`, `skill_aliases`, `profession_skills`, `person_skills`, `job_skills` | ✅ | ⚠️ no adjacency use | ❌ |
| Universal job model | `jobs` + 10 requirement tables | ✅ | ✅ | ✅ portal wizard |
| Discovery | `omelo_nearby_jobs` | ✅ | ✅ distance only | ✅ |
| **Matching engine** | `matches`, `weight_profiles` | ✅ | **❌ no scorer** | ❌ |
| Applications | `applications`, `application_events` | ✅ | ✅ | ✅ worker |
| **Pipeline / ATS** | `job_stages`, `application_notes` | ✅ | ⚠️ stage moves only | **❌** |
| Assessments | `assessments` | ✅ | ❌ | ❌ |
| **Interviews** | `interviews`, `interview_interviewers`, `interview_scorecards` | ✅ | ❌ | **❌** |
| **Offers** | `offers` | ✅ | ❌ | **❌** |
| **Hire → verified work** | `employments` → `experiences` + `verifications` | ✅ | ✅ trigger | **❌ unreachable** |
| Messaging | `conversations`, `messages` | ✅ | ❌ | ❌ |
| Talent search / pools | `talent_pools`, `talent_pool_members`, consent predicate | ✅ | ⚠️ predicate only | ❌ |
| Trust & verification | `verifications`, `documents`, `document_shares` | ✅ | ⚠️ | ❌ |
| Risk / fraud | `fraud_signals`, `reports`, `moderation_actions` | ✅ | ❌ | ❌ |
| Notifications | `notifications`, `notification_preferences` | ✅ | ❌ | ❌ |
| Audit | `audit_log`, `automated_decision_log` | ✅ | ⚠️ | ❌ |
| Globalisation | `country_policies`, `locations`, pay period + currency everywhere | ✅ | ✅ pay normaliser | ⚠️ INR-only UI |
| Admin | `platform_admins`, `support_sessions` | ✅ | ⚠️ | ❌ |
| **Event spine** | — | **❌** | ❌ | — |
| Analytics funnel | — (derivable from events) | ⚠️ | ❌ | ❌ |
| Search index | — | ❌ | ❌ | — |

Consequence for planning: the next phases are overwhelmingly **engine + interface** work.
Only three genuinely new structures are needed near-term:

1. `domain_events` — the event spine (§6)
2. Match factor storage — handled inside `matches.feature_vector`, no new table (§5.4)
3. Offer acceptance → employment — a transition function, no new table

---

## 4. The hiring state machine

### 4.1 Worker-visible states

Already enforced by `application_state` and `job_stages.maps_to_state`. The target loop maps
onto them without schema change:

| Target step | `application_state` | Written by |
|---|---|---|
| Apply | `applied` | worker insert |
| Employer review | `viewed` | `omelo_mark_application_viewed()` — cannot be suppressed |
| Shortlist | `shortlisted` | employer stage move |
| Screening | `screening` | employer stage move |
| Assessment | `assessment` | employer stage move |
| Interview | `interview` | employer stage move / interview scheduled |
| Offer | `offer` | `omelo_send_offer()` |
| Hired | `hired` | `omelo_respond_to_offer(accept)` |
| Rejected | `rejected` | `omelo_reject_application()` — reason required |
| Withdrawn | `withdrawn` | worker |
| Declined offer | `declined_by_candidate` | `omelo_respond_to_offer(decline)` |
| Expired | `expired` | scheduled job |

### 4.2 Rules

- **Every transition is auditable.** `application_events` is append-only and written by
  trigger, so no code path can move state silently.
- **Rejection requires a human and a reason.** There is no automated rejection path.
- **Hiring is a two-party act.** An employer cannot mark someone hired. The worker accepts
  an offer, and acceptance is what creates the employment record.
- **Verified work is a consequence, not a claim.** `employments` insert fires
  `omelo_employment_to_experience()`, producing a verified experience the worker never had
  to assert.

---

## 5. Matching Engine v1

### 5.1 Design constraints

1. **Deterministic.** Same inputs, same score. No LLM in the scoring path.
2. **Explainable.** Every score decomposes into factors a person can read.
3. **Configurable.** Weights come from `weight_profiles`, selected by job category. Changing
   a weight is a data change, never a deploy.
4. **Symmetric.** The same computation ranks jobs for a worker and candidates for a job.
5. **Stored.** Scores are persisted with their explanation so Omelo can always answer
   *"why was this recommended?"* and *"why is this candidate ranked here?"*

### 5.2 Gates (pass/fail, before scoring)

A gate failure does not produce a low score — it produces **ineligible**, with a reason.

| Gate | Fails when |
|---|---|
| `job_open` | job is not published |
| `work_authorization` | job country requires authorisation the worker lacks and no sponsorship |
| `required_licence` | job requires a licence type the person does not hold |

### 5.3 Factors

Each factor returns a score in `[0,1]`, a status (`strong` / `partial` / `gap` / `unknown`),
and a human sentence. The weight comes from the job's `weight_profiles` row.

| Factor | Measures |
|---|---|
| `profession_fit` | identity profession = job profession (1.0), same category (0.5) |
| `skill_coverage_required` | fraction of required job skills the person holds |
| `skill_coverage_preferred` | fraction of preferred skills held |
| `skill_depth` | proficiency on matched skills |
| `experience_fit` | experience months vs job minimum; 1.0 if job accepts none |
| `distance_fit` | decays with km beyond the worker's radius |
| `pay_fit` | overlap of normalised monthly pay vs worker minimum |
| `shift_fit` | overlap of job shifts with preferred shifts |
| `availability_fit` | worker availability vs immediate start |
| `work_type_fit` | job work type in worker's accepted types |
| `licence_coverage` | licences held vs licences listed |
| `language_fit` | required job languages held |
| `education_fit` | education level vs minimum, respecting `education_negotiable` |
| `benefit_fit` | job offers the transport / accommodation the worker needs |
| `attribute_fit` | adaptive attribute requirements satisfied |
| `trajectory_fit` | job aligns with a career goal (reserved, weight 0 today) |
| `company_preference` | worker follows the company (reserved, weight 0 today) |

**Unknown is not zero.** If the worker never stated a shift preference, `shift_fit` is
`unknown` and scores neutral (0.5), rather than punishing an incomplete profile. An
almost-empty profile must still be able to match — that is a founding constraint.

### 5.4 Storage decision

The request named `match_results`, `match_factors`, `match_explanations`. The existing
`matches` table already holds `score`, `eligible`, `gate_failures`, `feature_vector` (jsonb),
`weight_profile_id` and `engine_version`. Factors and explanations live inside
`feature_vector`:

```json
{
  "profession_fit": {"score": 1.0, "weight": 0.12, "contribution": 0.12,
                     "status": "strong", "explanation": "Same profession: Cook"},
  "distance_fit":   {"score": 0.62, "weight": 0.14, "contribution": 0.087,
                     "status": "partial", "explanation": "7.7 km away"}
}
```

Why not three tables: a match is always read whole, never factor-by-factor across matches,
and three tables triple the write cost of the most frequent computation in the system. If
factor-level analytics ever need joins, a view over `jsonb_each` provides them without a
migration. **`engine_version` is part of the unique key**, so recomputing under a new
engine never overwrites the explanation a user was already shown.

### 5.5 Evolution

```
v1 Rules + weighted features        ← now
v2 Learning-to-rank on event data   ← needs domain_events volume
v3 Behaviour signals (apply, hire)
v4 AI re-ranking of the top N        ← never replaces the explanation
```

Every later stage re-ranks; none removes the factor explanation. A score Omelo cannot
explain is a score Omelo does not show.

---

## 6. Event spine

Important actions emit a row into `domain_events`:

```
WorkerApplied · ApplicationViewed · CandidateShortlisted · CandidateRejected
InterviewScheduled · InterviewCompleted · OfferSent · OfferAccepted · OfferDeclined
WorkerHired · EmploymentVerified · MatchComputed
```

```
                        domain_events
                             │
        ┌────────────────────┼────────────────────┐
    Analytics            Matching v2          Notifications
    funnel rates         learning-to-rank     push / email / SMS
```

Design:
- **Append-only**, written by triggers so application code cannot forget to emit.
- **Transactional outbox:** the event commits with the state change or not at all.
- Consumers mark progress with their own cursor, so a slow consumer never blocks the loop.

`application_events` remains the per-application audit trail visible to both parties.
`domain_events` is the platform-wide stream. They are deliberately separate: one is a
user-facing record, the other is infrastructure.

---

## 7. Trust layer

Claims are not equally trustworthy, and the UI must never pretend they are.

| Evidence tier | Examples | Shown as |
|---|---|---|
| **Omelo-verified** | Hire through Omelo, employer confirmation | ✓ Verified |
| **Document-verified** | Licence checked against a document | ✓ Document checked |
| **Contact-verified** | Phone OTP, email | ✓ Phone |
| **Self-declared** | Skill added by the worker | no badge — shown plainly |

The matching engine uses the tier: an Omelo-verified experience counts fully, a self-declared
skill counts but is labelled. **Unverified is never presented as suspicious** — most of the
workforce has no documents, and the product must not punish that.

---

## 8. Phased roadmap

| Phase | Scope | Exit test |
|---|---|---|
| **NOW** · Complete the marketplace | Matching v1 · candidate review · pipeline · shortlist/reject with reason · worker application center | Employer can take an applicant from *applied* to *rejected* or *shortlisted*, and the worker sees why and when |
| **NEXT** · Complete employment | Interviews · offers · accept → hire → verified employment · messaging | A job goes from posted to a verified line on the worker's profile with no manual database step |
| **THEN** · Powerful identity | Multiple work identity UI · adaptive profiles · skill evidence · verification centre | A person holds two identities with different pay and privacy, each matched separately |
| **THEN** · Employer intelligence | Talent search · recommendations · pay and supply analytics | Employer finds a consenting worker without waiting for an application |
| **THEN** · Intelligence | Event-trained ranking · AI re-rank · career engine | Ranking measurably beats v1 on hire rate |
| **THEN** · Global | Country rollout beyond India | Second country live with local currency, pay period and legal rules as configuration only |

---

## 9. Not building yet, deliberately

| Not yet | Why |
|---|---|
| Social feed, worker-to-worker networking | Hiring loop first. A feed without a working loop is LinkedIn with fewer users. |
| LLM scoring | Unexplainable scores are unshippable in hiring. AI re-ranks, never decides. |
| Dedicated search cluster | Postgres + trigram + PostGIS is sufficient until measured otherwise. |
| Automated rejection | Never. |
