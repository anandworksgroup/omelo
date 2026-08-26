# 08 — The Matching Engine

**Status:** Frozen (Phase 0), revised for universal employment
**Owner:** Engineering + Product

One engine, run in both directions.

```
   Person  --->  ENGINE  --->  ranked Jobs
   Job     --->  ENGINE  --->  ranked Candidates
```

Both directions consume the same features, weights, and code path. If they diverge, the product
becomes incoherent: a person shown 94% by one path and ranked 40th by the other destroys trust
on both sides.

**The universality constraint:** the same engine must rank a delivery job for someone 2 km away
with a two-wheeler licence, and a principal engineer role for someone relocating across a
continent. The features below are chosen so that both work without special cases.

---

## 1. Four stages

```
   +---------------------+
   | 1. GATES            |   Hard pass/fail. Ineligible pairs get no score.
   +----------+----------+
              |
   +----------v----------+
   | 2. RETRIEVAL        |   Millions to hundreds. Recall-oriented.
   +----------+----------+
              |
   +----------v----------+
   | 3. SCORING          |   Deterministic features. Precision-oriented.
   +----------+----------+
              |
   +----------v----------+
   | 4. EXPLANATION      |   From the feature vector. Never post-hoc.
   +---------------------+
```

---

## 2. Stage 1 — Eligibility gates

Binary and non-negotiable. A failed gate means no score is computed at all.

| Gate | Condition | Failure behaviour |
|---|---|---|
| `work_authorization` | Person can work in the job's country, **or** the job declares sponsorship | Shown separately with the reason ([04 §5.4](04-user-app-flows.md)) |
| `required_licence` | Person holds every licence the job marks `required`, with an acceptable class and not expired | Shown with the reason and a route to obtaining it |
| `location_feasibility` | Job is remote, within the person's stated radius, or they are open to relocating | Shown with reason |
| `minimum_working_age` | Where a jurisdiction sets a legal minimum age for the work | Excluded silently |
| `language_minimum` | Meets `required` language levels | Shown with reason |
| `job_active` | `status = 'published'`, not expired | Silent |
| `not_hidden` | Person has not hidden this job or company | Silent |
| `not_blocked` | Neither party has blocked the other | Silent, and undetectable |
| `discoverability` | *(talent direction only)* `omelo_is_discoverable_to()` passes | Silent |
| `already_applied` | No existing application | Shown as "already applied" |

### 2.1 Why licence is a gate but experience is not

A licence gate is a **fact about legality**: a person without an HMV licence cannot lawfully
drive a heavy truck, and ranking them highly wastes everyone's time and can endanger them.

Experience is a **preference dressed as a fact**. Rigid experience gates are the most common
cause of wrongly excluding capable people, and they correlate with age.

The line throughout: **gates are for things that make hiring impossible, not unlikely.**

### 2.2 What is deliberately NOT a gate

| Not a gate | Why |
|---|---|
| Years of experience | Scored, never gated. `accepts_no_experience` exists precisely so employers can opt in to the whole market. |
| Education level | Scored, and only where the employer marked it required. `education_negotiable` defaults to true. |
| Pay expectation | Scored. It is a negotiation input, not a binary. |
| Current profession | Scored via taxonomy distance. Career changers and first-time workers are the target, not noise. |
| Employment gaps | **Not a feature at all.** Gaps correlate with caregiving, illness, and other protected characteristics. |
| Informal or self-employed history | Counts as experience. Discounting it would exclude a large share of the world's real work. |
| Having a resume | Irrelevant. `quick_apply` exists. |

### 2.3 The sponsorship gate

```
if job.country in person.authorized_countries:      PASS
elif job.visa_sponsorship is True:                  PASS
elif job.visa_sponsorship is None:                  PASS, flag 'sponsorship_unknown'
else:                                               FAIL, reason 'no_sponsorship'
```

`NULL` passing is deliberate. Treating unknown as "no" would silently remove migrant workers —
a primary Omelo audience — from most of the market.

### 2.4 The licence gate

```
for each licence L the job marks 'required':
    held = person.licences matching L.type
    if none:                      FAIL 'missing_licence'
    if L.class specified and held.class not acceptable:
                                  FAIL 'licence_class'
    if held.expires_on < today:   FAIL 'licence_expired'
```

Failure is always **shown with a route**: how to obtain the licence, which nearby jobs do not
require it, and how many jobs it would unlock. A licence gate is the most actionable exclusion
in the product — it names something the person can actually change.

---

## 3. Stage 2 — Retrieval

Optimise for **recall**. Anything dropped here is unrecoverable and invisible to everyone.

| Retriever | Method | Contributes |
|---|---|---|
| **Structured** | SQL over `profession_id`, `category_id`, `job_skills`, work type, shift | High-precision core |
| **Geospatial** | PostGIS `ST_DWithin` on `jobs.geo` within the person's radius | **The primary retriever for onsite work** |
| **Semantic** | `pgvector` HNSW over `job_embedding` × `identity_embedding` | Unusual titles, career changers, sparse identities |
| **Lexical** | `pg_trgm` over title and description | Specific terms the others blur |

```
retrieved = structured(300) ∪ geo(300) ∪ semantic(300) ∪ lexical(200)
          |> gates |> dedupe  ->  typically 400-900 pairs to score
```

### 3.1 Geospatial is a retriever, not a filter

For most non-remote work, distance is the dominant factor in whether a person will apply at all,
and a job 40 km away is functionally invisible to someone commuting by bicycle. Retrieving by
distance first — rather than retrieving broadly and filtering — is what makes the "142 jobs
within 10 km" experience possible at interactive latency.

### 3.2 Cold-start retrieval

A person who just signed up may have only a category and a location. Retrieval falls back to
`category + geo + accepts_no_experience`, which is enough to fill a first screen with real,
applicable work. **Nobody sees an empty Discover tab.**

---

## 4. Stage 3 — Scoring

Deterministic. Reproducible. No LLM.

### 4.1 Features

Each yields a value in `[0, 1]`.

| # | Feature | Definition |
|---|---|---|
| F1 | `skill_coverage_required` | Weighted fraction of required job skills evidenced, with partial credit for adjacent skills |
| F2 | `skill_coverage_preferred` | Same, for preferred |
| F3 | `skill_depth` | Proficiency and recency. A skill last used 8 years ago scores below one used this year |
| F4 | `profession_fit` | Taxonomy distance between the person's professions and the job's, plus credit if it is on a declared career path |
| F5 | `experience_fit` | Months vs the job's band. 1.0 inside; asymmetric decay outside — over-qualification penalised far less than under-qualification. **1.0 when `accepts_no_experience`** |
| F6 | `distance_fit` | Actual distance vs the person's stated radius. 1.0 for remote or within radius, decaying beyond, 1.0 if willing to relocate |
| F7 | `pay_fit` | Overlap between expectation and range, **normalised across pay periods**. A `NULL` range yields a neutral 0.5, never a penalty |
| F8 | `shift_fit` | Overlap between the person's workable shifts and the job's |
| F9 | `availability_fit` | Person's availability window vs the job's start date. `is_immediate_start` against `immediate` scores 1.0 |
| F10 | `work_type_fit` | Job's work type against the types the person is seeking |
| F11 | `licence_coverage` | Preferred (non-gating) licences held |
| F12 | `attribute_fit` | Adaptive attribute requirements vs the person's values — vehicle class, trade level, specialisation, tools |
| F13 | `education_fit` | Only if the employer marked it required; experience substitutes where `education_negotiable` |
| F14 | `language_fit` | Proficiency vs requirements, weighted by requirement level |
| F15 | `benefit_fit` | Job benefits against declared needs — accommodation, transport, meals |
| F16 | `trajectory_fit` | Does this advance a declared career goal? Rewards upward moves |
| F17 | `company_preference` | Follows, saved jobs, stated preferences |

**F6, F8, F9, F12, and F15 are the universality features.** Without them the engine silently
ranks blue-collar work badly: distance, shift, immediate availability, vehicle class, and
whether accommodation is provided are frequently *more* decisive than skill overlap.

### 4.2 Pay normalisation

```
normalise(amount, period) -> comparable monthly figure
  hour     * assumed_hours_per_week * 52 / 12   (from job.hours_per_week, else country default)
  day      * assumed_days_per_month             (from job.working_days, else country default)
  week     * 52 / 12
  fortnight* 26 / 12
  month    * 1
  year     / 12
  per_task -> excluded from pay_fit; F7 returns neutral 0.5
```

Assumptions are recorded in the feature vector so the comparison is explainable rather than
magic. ₹700/day and ₹22,000/month become comparable, and the person never has to do that
arithmetic.

### 4.3 Score computation

```
eligible = all(gates)
if not eligible: return (ineligible, gate_failures)   # no score at all

raw   = Σ(wᵢ · Fᵢ) / Σ wᵢ
score = round(100 · calibrate(raw))
```

`calibrate()` maps raw scores onto a distribution where the number means something. Without it
everything clusters between 60 and 85 and "78% match" carries no information. Fitted against
observed outcomes and re-fitted on a schedule.

### 4.4 Weight profiles are per category

Weights are **data, not code** (`weight_profiles.category_id`). This is what stops the engine
from being white-collar shaped.

```json
{
  "name": "delivery_default",
  "category": "delivery",
  "weights": {
    "distance_fit": 0.22,          "availability_fit": 0.14,
    "attribute_fit": 0.16,         "shift_fit": 0.12,
    "pay_fit": 0.12,               "skill_coverage_required": 0.08,
    "work_type_fit": 0.06,         "experience_fit": 0.04,
    "language_fit": 0.04,          "benefit_fit": 0.02,
    "education_fit": 0.00
  }
}
```

```json
{
  "name": "technology_default",
  "category": "technology",
  "weights": {
    "skill_coverage_required": 0.30, "skill_depth": 0.14,
    "experience_fit": 0.13,          "profession_fit": 0.11,
    "skill_coverage_preferred": 0.08,"pay_fit": 0.07,
    "distance_fit": 0.05,            "trajectory_fit": 0.04,
    "language_fit": 0.03,            "education_fit": 0.03,
    "availability_fit": 0.02
  }
}
```

Same engine, same features, different weights. `education_fit` at 0.00 for delivery is a
deliberate, visible, reviewable product position — possible only because weights are data.

### 4.5 Partial credit for adjacent skills

```
coverage(required skill s) =
    1.00  holds s, evidenced
    0.85  holds s, self-declared
    0.60  holds x where skill_relations(x, s) = 'substitutable_for'
    0.40  holds x where skill_relations(x, s) = 'adjacent_to'
    0.25  holds a prerequisite of s
    0.00  otherwise
```

This is what lets Omelo see that a strong Kotlin developer is a credible Swift hire, and that a
mason who has done plastering can do rendering. Exact string matching on skills is the largest
source of false negatives in existing platforms, and false negatives are invisible to everyone
involved.

### 4.6 Features explicitly excluded

Never computed, never stored, never available to a weight profile:

Employment gaps · age or graduation year or any age proxy · name-derived signals · gender ·
photo or any image-derived signal · caste, religion, ethnicity, or nationality beyond declared
work authorisation · school prestige · postcode beyond genuine distance calculation · current
employer prestige · response speed or "eagerness" · the language the resume was written in ·
**anything from `job_legal_restrictions`**

The feature registry is an **allowlist** validated at weight-profile load, so an unreviewed
feature fails loudly rather than shipping quietly.

The last exclusion is load-bearing: where a jurisdiction lawfully permits a gender or age
criterion on a posting, that criterion still never enters a score.

---

## 5. Stage 4 — Explanation

Generated **from the feature vector**, never reconstructed afterwards.

```json
{
  "score": 87, "eligible": true,
  "features": {
    "distance_fit":     { "value": 0.95, "distance_km": 2.4, "radius_km": 10 },
    "attribute_fit":    { "value": 1.0, "matched": ["delivery-vehicle: Two-wheeler"] },
    "availability_fit": { "value": 1.0, "person": "immediate", "job": "immediate" },
    "shift_fit":        { "value": 1.0, "overlap": ["day","evening"] },
    "pay_fit":          { "value": 0.85, "expected_monthly": 28000,
                          "range_monthly": [22000, 30000], "overlap_pct": 85 },
    "experience_fit":   { "value": 1.0, "reason": "accepts_no_experience" },
    "skill_coverage_required": { "value": 0.5,
                          "matched": ["two_wheeler_riding"],
                          "missing": [{"skill":"delivery_app_experience","weight":0.4}] }
  },
  "gate_results": { "required_licence": "pass", "work_authorization": "pass" },
  "engine_version": "2026.1.0", "weight_profile_id": "delivery_default"
}
```

The same object renders the worker's card ([04 §5.3](04-user-app-flows.md)) and the employer's
candidate card ([05 §4](05-company-portal-flows.md)) — which is how two-sided symmetry is
structurally guaranteed rather than maintained by convention.

The LLM receives **only** this vector and taxonomy labels. Never the resume, never the job
description. It therefore cannot introduce a claim the vector does not contain, and every
narrative claim is validated against the vector before display.

---

## 6. The reverse direction

Same engine, plus one gate and one ranking signal.

| Difference | Detail |
|---|---|
| Extra gate | `omelo_is_discoverable_to()` — consent, verification, entitlement, blocklist |
| Extra ranking signal | Responsiveness and stated availability |
| **Never a match feature** | Responsiveness affects **ordering only**, never the displayed score |

A person who replies slowly is not a worse fit for the job. The moment engagement merges into
the score, the number stops being an honest statement about the person.

---

## 7. Computation strategy

| Trigger | Scope | Timing |
|---|---|---|
| Person opens Discover | Their retrieval set | Real-time, < 1.5 s |
| Identity changes | Invalidate cached matches; recompute top N | Async |
| Job published | Score against saved searches and matching goals | Async |
| Recruiter opens talent search | Their retrieval set | Real-time |
| Nightly | Refresh active jobseekers; expire stale rows | Batch |

`matches` rows have a TTL. Any row whose score was **displayed** is retained for the audit
window regardless, because it may need explaining.

**Never build a job that scores every person against every job.**

---

## 8. Quality measurement

| Metric | Why |
|---|---|
| Precision@10 | Does the top of the list deserve to be there |
| Application rate by score band | Do higher scores convert |
| Interview rate by band | Do scores predict employer interest |
| Calibration error | Is "90%" honest |
| **Recall proxy** | Of jobs a person took elsewhere, how many did we retrieve |
| Coverage: % with 5+ matches above threshold | Detects dead marketplaces |
| **Coverage by category** | Whether the engine works for construction and domestic work, or only technology |
| Selection-rate parity | Adverse-impact monitoring |

**Coverage by category is the universality metric.** An overall average of 78% can conceal
technology at 95% and domestic services at 11%. Measure per category or do not claim to be
universal.

---

## 9. Failure modes and guards

| Failure | Guard |
|---|---|
| Cold-start person (empty identity) | Category + geo + `accepts_no_experience` fallback; lower-confidence label; named next actions |
| Cold-start job (thin description) | Low-confidence extraction excludes weak fields from gates |
| Score inflation | Continuous calibration monitoring; a compressed distribution is an alert |
| Popular-job pile-up | Rank-and-diversify at the feed layer |
| Rural or thin geography | Radius expands automatically with the expansion disclosed: "no jobs within 10 km — showing within 40 km" |
| Taxonomy drift | Steward queue SLA; pending-alias rate is monitored |
| Embedding model change | Versioned re-embed with both live during cutover |
| Feature bug | `engine_version` identifies affected users precisely for recomputation |
| Keyword stuffing | Evidence weighting (F3); anomaly detection on skill counts |
| **Category weight neglect** | A category with no tuned weight profile falls back to a generic one and is flagged. An untuned category ranks badly and nobody notices unless it is measured. |

---

## Decision log

| Decision | Rationale |
|---|---|
| One engine, both directions | Divergent scores destroy trust on both sides |
| Licence is a gate; experience is not | A licence is a fact about legality; experience is a preference dressed as a fact |
| Geospatial retrieval, not a geo filter | Distance dominates applying behaviour for most non-remote work |
| Pay normalised across periods with assumptions recorded | ₹700/day and ₹22,000/month must be comparable, and the comparison must be explainable |
| Weight profiles per category | Without this the engine is white-collar shaped no matter what the features are |
| Shift, availability, attribute, and benefit features are first class | Frequently more decisive than skill overlap for the majority of work |
| `job_legal_restrictions` fields are never features | Lawful on a posting in a few places; never acceptable in a score anywhere |
| Coverage measured per category | An overall average hides total failure for entire segments |
| Engagement signals rank but never score | A slow replier is not a worse fit |
