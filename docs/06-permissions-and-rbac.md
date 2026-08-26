# 06 — Permissions & RBAC

**Status:** Frozen (Phase 0) — **implemented in the live database**
**Owner:** Engineering + Security
**Deployed artifact:** RLS enabled on all 86 tables. See [`sql/README.md`](../sql/README.md).

---

## 1. The permission model

Omelo's authorisation is the intersection of four independent checks. **All four must pass.**

```
        +------------------+
        | 1. IDENTITY      |  Who is the authenticated person?
        +--------+---------+
                 |
        +--------v---------+
        | 2. CONTEXT       |  Acting as themselves, or as a member
        |                  |  of a specific company?
        +--------+---------+
                 |
        +--------v---------+
        | 3. ROLE          |  What does their role in that context permit?
        +--------+---------+
                 |
        +--------v---------+
        | 4. CONSENT       |  Has the data subject permitted this?
        +--------+---------+
                 |
              ALLOW
```

Layer 4 is what distinguishes Omelo from a conventional B2B application. A recruiter with a
valid role and a valid company context still cannot see a candidate who has not consented to
be discoverable, or who has blocked that company. **Consent is not a filter applied to
results; it is a precondition of the query.**

---

## 2. Roles

### 2.1 Person-scope roles

| Role | Granted by | Capability |
|---|---|---|
| **Worker** | Every person, implicitly | Full control of own work identity, applications, documents, conversations, preferences |

Every account is a Worker. Recruiting capability is *additive* via `company_members`
([02 §7](02-domain-model.md)).

### 2.2 Company-scope roles

Matches the `company_role` enum in the live database.

| Role | Scope | Intended holder |
|---|---|---|
| **Owner** | Whole company | Founder / account owner. Exactly one; transferable. |
| **Admin** | Whole company | Everything except ownership transfer and company deletion. |
| **Recruiter** | Assigned jobs | Sourcing, outreach, pipeline movement. |
| **Hiring Manager** | Assigned jobs | Reviews candidates, decides, cannot source broadly. |
| **Interviewer** | Scheduled interviews only | Sees a candidate only from the moment they are scheduled to interview them. |
| **HR** | Whole company | Offers, employees, hiring records. **No talent search.** |
| **Finance** | Billing only | **No candidate data whatsoever.** |
| **Viewer** | Read-only, assigned jobs | Observers who must not act. |
| **Agency Recruiter** | Assigned jobs at a client company | Recruiter capabilities with mandatory client attribution and no cross-client visibility. |

### 2.3 Platform roles

| Role | Capability | Constraint |
|---|---|---|
| **Support** | Scoped, time-limited, consented impersonation | Requires an open user request; every action logged and shown to the user afterwards |
| **Trust & Safety** | Investigate reports, suspend accounts, remove content | Cannot read message content except within a reported thread; access logged |
| **Taxonomy Steward** | Approve/merge skills and professions | No access to personal data |
| **Engineer (prod)** | Break-glass only | Time-boxed, two-person approval, fully logged, alerted |

There is no "platform admin who can see everything." That role does not exist, and no code
path grants it.

---

## 3. Permission matrix

Legend: **F** full · **A** assigned jobs only · **S** scheduled interviews only ·
**O** own records only · **C** consent-gated · **—** none

### 3.1 Company-scope resources

| Resource / Action | Owner | Admin | Recruiter | Hiring Mgr | Interviewer | Billing |
|---|---|---|---|---|---|---|
| Company profile — view | F | F | F | F | F | F |
| Company profile — edit | F | F | — | — | — | — |
| Team — view | F | F | F | F | — | — |
| Team — invite / remove | F | F | — | — | — | — |
| Assign roles | F | F | — | — | — | — |
| Transfer ownership | F | — | — | — | — | — |
| Delete company | F | — | — | — | — | — |
| Job — create | F | F | F | — | — | — |
| Job — edit | F | F | A | — | — | — |
| Job — publish | F | F | A | — | — | — |
| Job — close | F | F | A | A | — | — |
| Application — list | F | F | A | A | — | — |
| Application — view detail | F | F | A | A | S | — |
| Application — move stage | F | F | A | A | — | — |
| Application — reject | F | F | A | A | — | — |
| Internal notes — read | F | F | A | A | S* | — |
| Internal notes — write | F | F | A | A | S* | — |
| Scorecard — submit | F | F | A | A | S | — |
| Message candidate | F | F | A | A | — | — |
| Talent Search — execute | F | F | C | — | — | — |
| Talent Search — outreach | F | F | C | — | — | — |
| Talent pools | F | F | F | A | — | — |
| Analytics — hiring | F | F | A | A | — | — |
| Analytics — adverse impact | F | F | — | — | — | — |
| Billing — view | F | F | — | — | — | F |
| Billing — change plan | F | F | — | — | — | F |
| ATS integration | F | F | — | — | — | — |
| Audit log — read | F | F | — | — | — | — |

`S*` — an Interviewer sees and writes notes only on their own scheduled interviews, and
cannot read other interviewers' scorecards before submitting their own (to prevent anchoring).

### 3.2 Person-scope resources

| Resource / Action | Self | Recruiter (consent-gated) | Other person | Public |
|---|---|---|---|---|
| Identity — full | F | C | — | — |
| Identity — public projection | F | C | Per visibility | Per visibility |
| Contact details | F | C, after contact accepted | — | — |
| Work authorisation | F | C, in application or search context | — | — |
| Salary expectations | F | C, if candidate exposed it | — | — |
| Applications | O | Only to the receiving company | — | — |
| Conversations | O | Own company's threads | — | — |
| Saved jobs / searches | O | — | — | — |
| Blocklist | O | **Never visible to blocked party** | — | — |
| Profile views received | O | — | — | — |
| Career intelligence | O | — | — | — |
| Match feature vectors | O | Own company's jobs only | — | — |

The blocklist row is critical: a blocked employer must not be able to detect that they were
blocked. Blocking produces absence, never a signal.

---

## 4. The consent layer in detail

### 4.1 Discoverability states

| State | In Talent Search | Profile visible to | Default |
|---|---|---|---|
| `private` | Never | Only companies they applied to | **Yes** |
| `discoverable` | Yes, subject to preferences and blocklist | Verified companies matching their preferences | No |
| `public` | Yes | Anyone with the profile link | No |

`private` is the default. Discoverability is an explicit, revocable, granular decision.

### 4.2 The consent predicate

Implemented once, as `omelo_is_discoverable_to(person_id, company_id)`, and used by every
talent surface — never re-implemented per feature.

```
A person P is visible to company C for job J when ALL hold:

  1. P.discoverability != 'private'
  2. P.deleted_at IS NULL
  3. C.is_verified = true
  4. C has an active talent-search entitlement
  5. NOT EXISTS (block: P blocks C)
  6. NOT EXISTS (block: P blocks the querying recruiter)
  7. J pay >= P.min_outreach_pay      (normalised across pay periods; or no floor set)
  8. J.profession_id IN P.outreach_professions  (or no restriction set)
```

Conditions 1-6 are enforced inside the deployed function. Conditions 7-8 are applied by the
talent-search service layer, because they need pay-period normalisation.

All of them are **query predicates, not post-filters**. A post-filter leaks existence through
result counts, pagination behaviour, and timing.

### 4.3 Documents are outside the grant entirely

Receiving an application grants access to the work identity, **not to documents**. Every
document view requires a live, unrevoked `document_shares` row naming that company. The RLS
policy on `documents` contains no path from "has an application" to "can read the identity
document". Revocation is immediate.

This matters more on a universal platform than a white-collar one: the people most likely to be
asked for a passport scan by a fraudulent employer are the least able to absorb the harm.

### 4.4 Applying grants a scoped exception

When a person applies to a job, they grant that company access to their work identity **for
that application's context only**. This grant:

- Does not make them appear in Talent Search.
- Does not extend to other jobs at the same company.
- Does not survive withdrawal — after withdrawal the company retains only the immutable snapshot for its legal hiring record, not live identity access.

---

## 5. Enforcement architecture — defence in depth

```
   Client            (never trusted; UI hiding is not enforcement)
     |
   API / Service layer   <-- PRIMARY enforcement
     |                        - role resolution from active context
     |                        - consent predicate
     |                        - entitlement checks
     |                        - explicit response schemas per audience
     |
   Database RLS          <-- LAST LINE OF DEFENCE
     |                        - catches service-layer bugs
     |                        - catches direct/console access
     |
   Audit log             <-- DETECTION
```

### 5.1 Primary enforcement is the service layer

RLS alone cannot express entitlements, rate limits, or audience-specific response shaping.
The service layer owns authorisation; RLS exists so that a service-layer mistake is contained
rather than catastrophic.

### 5.2 Response schemas per audience

Every entity has explicitly defined projections — for example `PersonIdentity` renders as
`SelfView`, `RecruiterView`, `PublicView`, or `AnonymisedSearchView`. A handler returns a
named projection; it never returns a database row and trusts a serializer to omit fields.

This is how FR-405 (name hidden until contact accepted) and the internal-notes separation in
[05 §6.1](05-company-portal-flows.md) are structurally guaranteed.

### 5.3 RLS strategy

- Enabled on **every** table containing personal data.
- Person-owned tables: `person_id = auth.uid()`.
- Company-scoped tables: membership via a `SECURITY DEFINER` helper function, so the policy is one indexed lookup rather than a correlated subquery.
- Taxonomy tables: readable by all authenticated users; writable only by the steward service role.
- Append-only tables (`application_events`, `audit_log`): insert-only for application roles; no update or delete policy exists at all.

See [`sql/policies.sql`](../sql/policies.sql).

---

## 6. Auditing

Written to `audit_log` for every one of these (NFR-10):

| Category | Examples |
|---|---|
| Access to personal data | Profile view, application detail view, talent-search execution, export |
| Permission changes | Role grant/revoke, invitation, ownership transfer |
| Hiring decisions | Stage change, rejection, offer |
| Consent changes | Discoverability change, block added/removed, deletion request |
| Verification | Granted, expired, revoked |
| Automated decisions | Every ranking shown, to `automated_decision_log` |
| Privileged access | Support impersonation, T&S action, break-glass |

Audit entries are append-only and retained per the schedule in
[10](10-compliance-and-trust.md). Candidates can see the subset that concerns them: who viewed
their profile, which companies searched and matched them, and every privileged access to
their account.

---

## 7. Failure modes this design specifically prevents

| Failure mode | Prevention |
|---|---|
| Recruiter finds a candidate who never opted in | Consent is a query predicate, and RLS blocks it independently |
| Candidate's current employer discovers they are looking | Blocklist anti-join at query time; blocking produces absence, not a signal |
| Internal note leaks to a candidate | Separate permission class and explicit response projections |
| Billing user browses candidates | No candidate-data grant exists for the Billing role at any layer |
| Interviewer browses the whole pipeline | Scheduled-interview scoping, enforced in the service layer and RLS |
| Agency recruiter cross-contaminates clients | Company context required on every query; no global recruiter grant |
| Support agent reads accounts casually | Impersonation requires an open request, is time-boxed, and is disclosed to the user |
| A service-layer bug exposes a table | RLS denies by default |
| Deleted account persists in search | Deletion pipeline confirms purge in every derived store before completing |
| A person's recruiter role reveals their own candidate activity | Context isolation rule ([02 §7](02-domain-model.md)) |

---

## Decision log

| Decision | Rationale |
|---|---|
| Consent is a fourth, independent authorisation layer | Role-based access alone permits exactly the harvesting behaviour that destroys candidate trust |
| Discoverability defaults to `private` | Opt-out consent for a talent database is not meaningful consent |
| Blocking produces absence, never a signal | A detectable block endangers the employed candidate it exists to protect |
| Service layer primary, RLS secondary | RLS cannot express entitlements or audience shaping; it is containment, not the model |
| No universal platform admin role | If the role exists, it will be used, and it will eventually be compromised |
| Interviewers cannot read peer scorecards pre-submission | Anchoring degrades evaluation quality and creates a defensibility problem |
