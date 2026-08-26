# 13 — Platform Admin

**Status:** Frozen (Phase 0)
**Owner:** Operations + Trust & Safety

The third surface. A global employment marketplace cannot operate without it, and building it
late means operating blind through the period when trust is most fragile.

---

## 1. Why this is not optional

Omelo will carry, from early on:

- fraudulent job postings targeting people with the least ability to absorb a loss
- fake companies harvesting identity documents
- a taxonomy accumulating unrecognised professions and skills faster than it can absorb them
- verification requests requiring human judgement
- harassment and discrimination reports
- country-by-country legal configuration
- automated-decision review requests

Every one needs tooling with an audit trail. Handling them by direct database access is how a
platform ends up with an unlogged superuser and no answer when a regulator asks who saw what.

---

## 2. Structure

```
Admin Portal
  |
  +-- Overview          platform health, queues, alerts
  +-- Users             search, investigate, support access
  +-- Companies         verification queue, standing
  +-- Jobs              moderation, fraud review
  +-- Applications      dispute investigation
  +-- Reports           the Trust & Safety queue
  +-- Moderation        actions taken and reversals
  +-- Fraud             signals, patterns, blocked entities
  +-- Verification      requests needing human review
  +-- Taxonomy          professions, skills, aliases, licences
  +-- Countries         per-country policy and legal basis
  +-- AI                model versions, quality, cost, incidents
  +-- Automated decisions   human-review requests
  +-- Billing           plans, entitlements, disputes
  +-- Support           tickets and scoped impersonation
  +-- Analytics         marketplace health
```

---

## 3. Admin roles

There is **no universal superadmin who can see everything.** If the role exists it will be used
routinely, and eventually compromised.

| Role | Can | Cannot |
|---|---|---|
| **Support** | Scoped, time-boxed, consented impersonation to resolve an open request | Browse users without an open request |
| **Trust & Safety** | Investigate reports, suspend accounts, remove content | Read message content outside a reported thread |
| **Taxonomy Steward** | Approve, merge, deprecate professions and skills | Access any personal data |
| **Analyst** | Aggregate analytics | Access individual records |
| **Superadmin** | Grant roles, configure countries, break-glass | Act unlogged — every action is audited and alerted |

Backed by `platform_admins`, with `expires_at` so elevated access lapses by default rather than
by someone remembering to revoke it.

---

## 4. Support access is consented, scoped, and disclosed

`support_sessions` requires:

| Field | Purpose |
|---|---|
| `reason` | Why access is needed |
| `request_ref` | The user's open ticket — no ticket, no access |
| `expires_at` | Time-boxed, mandatory |
| `disclosed_at` | When the user was told |

The user sees every support session on their own account (`support_sessions` has a
subject-read RLS policy). Support cannot browse; support can only respond.

---

## 5. Taxonomy stewardship

The highest-volume ongoing admin workload, and the one whose neglect silently degrades every
match score in the product.

```
PENDING PROFESSION ALIASES               ordered by occurrences

  "delivery boy"              1,847    -> Delivery Executive     [merge]
  "site electrician"            892    -> Electrician            [merge]
  "househelp"                   654    -> Domestic Helper        [merge]
  "JCB operator"                412    -> Heavy Equipment Op.    [merge]
  "field boy"                   287    -> ?                      [new] [reject]
```

Actions: **approve as new** · **merge into existing** · **mark as alias** · **reject**.

### 5.1 Rules

1. Users never create professions or skills. Unrecognised input becomes a pending alias with an occurrence counter; the person is never blocked.
2. The queue is ordered by occurrence, so real market vocabulary surfaces fast and noise sinks.
3. A merge writes `merged_into` and rewrites affected edges as a background migration. No person or job silently loses a skill.
4. **Pending-alias backlog is a monitored platform metric.** A growing backlog is a quality incident, not a chore.

### 5.2 Terminology note

"delivery boy" and "househelp" are real market vocabulary and must be *recognised* as aliases so
those people find work. They must never become canonical labels in Omelo's own interface. The
alias system exists precisely to separate what people type from what the product says.

---

## 6. Verification queue

```
VERIFICATION REQUESTS                              47 pending

  Identity      12    avg wait 4h
  Licence       18    avg wait 6h
  Education      9    avg wait 2 days
  Employment     8    avg wait 1 day
```

Rules:
- Every decision records method, verifier, claim, and expiry.
- **Documents are deleted immediately after the decision.** Only the verified claim persists. This is the highest-risk data Omelo touches and the easiest to over-retain.
- Rejections are appealable to a different reviewer.
- Verification expires and requires renewal — a licence valid in 2026 is not evidence in 2031.

---

## 7. Fraud and moderation

### 7.1 The queue

```
REPORTS                                            23 open

  Payment request        7   ESCALATED   avg 1.2h
  Fake company           4   ESCALATED   avg 3h
  Harassment             3   ESCALATED   avg 0.8h
  Misleading job         6                avg 8h
  Spam                   3                avg 12h
```

SLAs: harassment and payment-request reports within 4 hours; everything else within 24.

### 7.2 Automated fraud signals

`fraud_signals` accumulates detections with severity, feeding the queue and posting limits.

| Pattern | Action |
|---|---|
| Payment requested from a candidate | Block posting, suspend, warn affected candidates |
| Bank details or identity documents collected during hiring | Block, investigate |
| Identity documents requested at apply stage | Flag for review |
| Early redirection to external messaging apps | Warn candidate, flag |
| Pay far outside the market band for that profession and location | Manual review before publication |
| New company posting at high volume | Rate limit, manual review |
| Duplicated job description | Dedupe, investigate |
| Reshipping, money-mule, package-forwarding roles | Block category |

**Warning affected candidates is part of the action, not an afterthought.** A fraudulent posting
taken down after 200 people applied has still harmed 200 people who deserve to be told.

### 7.3 The asymmetry

Employer-side enforcement is **preventive**; candidate-side enforcement is **corrective**.
Employers hold the power in this market, and a false accusation against a worker damages them
far more than a false accusation against a company damages the company.

---

## 8. Country configuration

`country_policies` is where internationalisation lives as configuration rather than code.

```
COUNTRY: India (IN)                              Supported

  Currency                 INR
  Default pay period       month
  Phone auth preferred     Yes
  Salary disclosure        Not required
  Gender criteria          PROHIBITED
  Age criteria             PROHIBITED
  Required documents       -

  Changing a prohibition requires a recorded legal basis
  and superadmin approval. All changes are audited.
```

Gender and age criteria default to prohibited in every country. Enabling either requires a
written legal basis, and `omelo_check_legal_restriction()` refuses the posting until it is
recorded. This is the most legally dangerous switch in the product and is deliberately
awkward to reach.

Adding a market is: seed locations, set policy, seed country-specific licence types, review
professions for local relevance, get legal sign-off. **Configuration plus legal review, not an
engineering project.**

---

## 9. Automated decision review

Backed by `automated_decision_log`.

```
HUMAN REVIEW REQUESTS                              6 pending

  Person requested review of a ranking      2 days ago
  Job: Site Electrician - Metro Constructions
  Score: 62   Engine: 2026.1.0

  [ view feature vector ]  [ recompute ]  [ respond ]
```

Because `feature_vector` and `engine_version` are stored, a reviewer can see exactly which
inputs produced the score and reproduce it — even after the engine has changed. This is what
makes the right to human review real rather than a policy statement.

---

## 10. AI operations

| View | Purpose |
|---|---|
| Model versions | What is deployed per subsystem, with `prompt_version` |
| Quality | Extraction accuracy, resolution accuracy, grounding violations (target: zero) |
| Cost | Per-subsystem spend against budget |
| Fallback rate | How often the deterministic path is being used |
| Incidents | Injection attempts, anomalous outputs, refusal failures |

Silent model swaps are prohibited. A model change is a deployment with the same rigour as a
schema migration: evaluation against a held-out set, documented comparison, staged rollout,
rollback capability.

---

## 11. Marketplace health

The dashboard that matters most, and the one that reports problems no error rate will catch.

| Metric | Why |
|---|---|
| **Silent-application rate** | The direct measure of PR-6. A rise is an outage of the core promise. |
| Employer response rate and median time | |
| Applications per job | Detects both dead jobs and pile-ups |
| Coverage: % of active jobseekers with 5+ matches | Detects dead marketplaces by segment |
| **Coverage by category** | Whether Omelo actually works for construction and domestic work, or only for technology |
| Consent opt-in rate | Talent-search viability |
| Pending-alias backlog | Taxonomy health |
| Verification throughput | |
| Fraud detection and report rates | |

**Coverage by category is the universality metric.** If technology coverage is 90% and domestic
services is 12%, Omelo is a tech job board wearing a universal platform's clothes, and no
overall average will reveal it.

---

## 12. Admin invariants

1. No universal superadmin. No role sees everything.
2. Every admin action writes to `audit_log` with actor, subject, and timestamp.
3. Support access requires an open user request, is time-boxed, and is disclosed to the user.
4. Trust & Safety reads message content only inside a reported thread.
5. Verification documents are deleted immediately after the decision.
6. Users never write to the taxonomy; stewards do.
7. Country prohibitions can only be lifted with a recorded legal basis and superadmin approval.
8. Break-glass database access requires two-person approval and raises an alert.
9. Every automated decision that affected a person is reviewable by a human.
10. Taking down a fraudulent posting includes warning the people who applied to it.
