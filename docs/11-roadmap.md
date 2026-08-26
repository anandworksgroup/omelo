# 11 — Roadmap

**Status:** Live
**Owner:** Product

Each phase states what ships, what is explicitly **not** built, and the gate to the next phase.
The non-goals are the important part — they are what stops the specification being quietly
abandoned under delivery pressure.

---

## Phase 0 — Specification · **Complete**

Documents 00-13 frozen.

---

## Phase 1a — Database · **Complete**

Deployed to Supabase `jfyqnlucoraazjkndbvm`, schema `public`.

- 86 tables, RLS on every one
- 11 migrations
- Taxonomy seeded: 34 categories, 92 professions, 27 adaptive attributes, 10 licence types, 20 languages, 14 country policies
- Business rules enforced by triggers, not application code
- Hiring loop verified end to end and rolled back

**Left open on purpose:** embedding dimensionality (`vector(1536)` is a placeholder). Tables are
empty, so fixing it is currently free. It stops being free the moment real data lands.

---

## Phase 1b — User app + Company portal

**Thesis:** a person with no resume and no degree can find and get real work, and a small
employer can hire without an HR department.

Scope: **one country, three to five categories.**

### Recommended launch shape

One metro area in a high-volume market, with categories chosen for density rather than
prestige — for example Delivery, Warehousing, Retail, Food & Restaurant, and Security.

Reasoning:
- Job volume is continuous rather than seasonal, so the marketplace has a pulse from week one.
- Hiring cycles are days, not months, so the loop closes fast enough to learn from.
- Requirements are simple, so matching quality is testable early.
- These are the workers nobody serves well, which is where the product has a real advantage.

Adding Technology later is easy. Starting with Technology and adding Construction later is how
a universal platform quietly becomes a tech job board.

### Ships

| Area | Included |
|---|---|
| Onboarding | Language, country, phone auth, four-question flow, category grid, immediate jobs |
| Work identity | Adaptive profile, skills, experience (incl. informal), education, licences, preferences, availability, pay |
| Resume builder | Question-led, voice input, generated document, user-reviewed |
| Documents | Vault, per-employer shares, revocation |
| Verification | Phone, email, work-email employment, licence (manual review) |
| Discovery | Nearby, search with visible facet interpretation, filters, saved searches, alerts |
| Matching | Gates incl. licence, four-retriever retrieval, deterministic scoring, per-category weights, explanations |
| Applying | Quick apply, full apply with review step, employer questions, staged document requests |
| Applications | The hiring timeline, silence state, expiry, rejection with reason |
| Messaging | Job-anchored conversations, structured actions, block, report |
| Company | Verification, job wizard with live pool feedback, pipeline, candidate review, interviews incl. trial shifts, offers, employees |
| Admin | Taxonomy stewardship, verification queue, reports, fraud, country config |
| Compliance | Export, deletion, transparency surfaces, automated-decision log |

### Explicitly NOT in Phase 1b

- **Talent Search and outreach** — requires worker density and consent rates that do not exist yet
- Career paths and skill gaps — requires taxonomy maturity and transition data
- Company reviews
- Assessments
- ATS integrations
- Multi-region deployment (build the partitioning, run one region)
- Network and feed beyond application and match notifications

### Exit gate

S1-S5 from [00 §7](00-vision-and-scope.md), plus:

- Silent-application rate below 10%
- **Coverage above threshold in every launched category, not on average**
- Median time from signup to first application under 10 minutes
- ≥ 30% of applications from people with no uploaded resume
- Pending-alias backlog stable or declining
- Zero grounding violations in production explanations
- Pre-launch checklist in [10 §7](10-compliance-and-trust.md) complete

The fourth bullet is the honesty check on the whole thesis. If nearly everyone who applies had
a resume, Omelo built a job board.

---

## Phase 2 — Career intelligence and verification depth

**Thesis:** Omelo can tell someone something true about their working future that they did not
already know — including tradespeople, not only professionals.

### Ships

| Area | Included |
|---|---|
| Career | Current position with evidence, career paths, skill gaps with opportunity delta, bridge roles |
| Taxonomy | `profession_transitions` populated from real experience sequences; `profession_skills` refined from live job data |
| Verification | Licence verification via issuing bodies, education verification pilot, identity verification |
| Insights | Skill demand trends, pay ranges by profession and location, eligibility-change notifications |
| Matching | Calibration fitted to observed outcomes; per-category weights tuned on real data |
| Growth | Partner routing for gap closure, including trade certification |

### Explicitly NOT in Phase 2

- Talent Search (still)
- Learning content production
- Predicting hiring outcomes for a specific application
- Pay data beyond what Omelo's own postings support

### Exit gate

- Predicted transitions match observed transitions above threshold
- Gap recommendations produce measurable identity improvement and score movement
- Career paths validated for **at least two non-professional categories**, not only technology
- Workers rate insights as new information, not restatement

---

## Phase 3 — Talent engine

**Thesis:** the marketplace works in reverse without compromising worker trust.

Gated on **worker density and consent rates**, not on employer demand. Employer demand for a
searchable database will arrive long before it is safe to serve, and will be pressed hard.

### Ships

Talent Search with the consent predicate, anonymised results, contact requests, talent pools,
job-anchored outreach with earned quotas, reply-rate tracking, assessments, analytics,
two-sided symmetry surfaces, Career Copilot, and the first independent bias audit.

### Explicitly NOT in Phase 3

- Selling worker data, in any form, under any framing
- Automated rejection rules, however requested
- Bulk untargeted outreach
- Any discoverability default other than `private`

### Exit gate

- Consent opt-in rate healthy without dark patterns
- Recruiter reply rate above threshold; low-reply recruiters demonstrably throttled
- Worker-reported outreach quality positive
- Bias audit published with no unresolved findings

---

## Phase 4 — Multi-country and mobility

Additional countries and categories, migrant-worker mobility surfaces, multi-region deployment
with full residency enforcement, agency multi-company support, ATS integrations, enterprise SSO,
and the career-signal network.

**Not:** immigration advice or filing, a general social feed, payroll or EOR.

---

## Phase 5 — Omelo ID

The work identity as a portable, worker-controlled, verifiable object other systems can consume
under scoped, revocable permissions.

Portability looks like giving away the moat. It is the opposite: an identity people can take
anywhere is one they will invest in fully, and the graph — transitions, verified hires, market
signal, matching — is the actual moat. The identity is the interface; the graph is the product.

---

## What could invalidate this plan

| Risk | Signal | Response |
|---|---|---|
| **Cold start fails** — no jobs, so no workers, so no jobs | Low job volume per category in the launch metro | Buy or seed supply in one category until density is real; narrow further |
| **Small employers won't self-serve** | Signups that never publish a job | Assisted onboarding; phone-based job creation; a sales-light motion |
| **Adaptive profile still feels long** | Drop-off inside profile steps | Cut attributes per profession; defer everything to post-application |
| **Employers reject timeline transparency** | Verified employers churning at pipeline setup | **Hold the line.** Losing employers who require opacity is an expected, acceptable cost. |
| **Universality is nominal** | Coverage strong in one category, weak in the rest | Treat as a Sev-1 product failure, not a backlog item. This is the specific way the whole thesis dies. |
| **Fraud outpaces Trust & Safety** | Rising payment-request reports | Slow employer onboarding before loosening it; verification is the throttle |
| **Taxonomy stewardship does not scale** | Growing pending-alias backlog | Raise automation thresholds; hire stewards; narrow category scope |
| **Match quality plateaus** | Precision flat; application rate uncorrelated with score | Revisit features and per-category calibration; consider learned re-ranking **on top of** deterministic features, never replacing them |

Two rows deserve emphasis.

**Employer pressure to weaken worker-side transparency** is not hypothetical. It is the most
likely form the pressure will take, it will be framed reasonably, and it arrives exactly when
revenue matters most. That is why it is written down now, before anyone is under it.

**Nominal universality** is the quieter failure. It will not announce itself — the averages will
look fine. Only per-category measurement catches it, which is why FR-917 exists.
