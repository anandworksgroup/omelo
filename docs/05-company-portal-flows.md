# 05 — Company Portal Flows (Web)

**Status:** Frozen (Phase 0)
**Owner:** Product + Design

Desktop-first web. Recruiters and hiring teams work with large candidate datasets, and that
work does not fit a phone. Employer mobile is limited to notifications, messages, and candidate
review.

**The constraint that shapes everything:** the same portal must serve a multinational hiring
200 engineers and a restaurant hiring one cook. Every step that is mandatory for the
multinational must be skippable for the restaurant.

---

## 1. Navigation

```
+----------------------------------------------------------+
| OMELO for Employers        [Company v]      [User v]      |
+------------+---------------------------------------------+
| Dashboard  |                                             |
| Jobs       |                                             |
| Candidates |                                             |
| Talent     |                                             |
| Search     |                                             |
| Applications                                             |
| Interviews |                                             |
| Messages   |                                             |
| Offers     |                                             |
| Employees  |                                             |
| Team       |                                             |
| Company    |                                             |
| Analytics  |                                             |
| Verification                                             |
| Billing    |                                             |
+------------+---------------------------------------------+
```

`[Company v]` is the context switcher for agency recruiters working several clients. Every
permission check evaluates against the **active company context**, never the person globally.

---

## 2. Company onboarding

```
Create company account
      |
Email / phone verification
      |
Company information
      |
Industry  ->  Size  ->  Website  ->  Locations
      |
Legal details            <-- registration number, tax ID
      |
Company verification
      |
      +-- Verified   -> full access: post jobs, search talent
      +-- Pending    -> limited: draft jobs, reviewed publishing, NO talent search
      +-- Rejected   -> appeal path
      |
Create company profile
      |
Invite team              <-- skippable
      |
Dashboard
```

### 2.1 Verification requires two independent signals

| Signal | Examples |
|---|---|
| Domain control | Work email at the company domain, plus a DNS TXT record or well-known file |
| Corporate existence | Registration number checked against a registry, an existing ATS integration, or manual review |

### 2.2 Talent search is never available before verification

No exceptions, no growth experiments. An unverified account with talent-search access is a
data-harvesting vector, and the people harvested are the least able to defend themselves.

Job posting *may* proceed in a limited, reviewed form during verification. Talent search may not.

Unverified companies get: reduced distribution, a visible "unverified" badge on every job,
capped active postings, and manual review before publication.

### 2.3 A restaurant must reach a live job in under ten minutes

Departments, multi-location, legal entity detail, and team invitations are all optional. If a
one-person business has to model an org chart before posting a cook role, Omelo has failed the
larger half of the market.

---

## 3. Create job — guided wizard

```
1 Basics -> 2 Description -> 3 Requirements -> 4 Location
   -> 5 Pay & Benefits -> 6 Schedule -> 7 Conditions -> 8 Review
```

### 3.1 Step 1 — Basics

```
  Job title        [ Delivery Executive                    ]
  Profession       [ Delivery Executive        v ]  matched
  Category         Delivery                          [ change ]
  Department       [ optional                  v ]
  Openings         [ 5 ]
```

Profession is matched from the title and always correctable. Category follows from profession.
Department is optional and hidden entirely for companies that have none.

### 3.2 Step 3 — Requirements, with live pool feedback

Show employers the cost of every requirement **as they add it**.

```
  REQUIREMENTS

  Skills                              Weight
    Two-wheeler riding        [====----] required   [x]
    Area knowledge            [==------] preferred  [x]
    + add

  Experience   ( ) Required [ 1 ] to [ 3 ] years
               (o) No experience needed

  Education    [ No formal education required   v ]

  Licences     [ Driving Licence (India) - MCWG or LMV ]  required
               + add

  Languages    [ Hindi - Conversational ]  required
               [ English - Basic ]         preferred

  ----------------------------------------------------------
  MATCHING CANDIDATES NEARBY                          1,847
  ----------------------------------------------------------
  Requiring 1-3 years experience would exclude 2,310
  candidates who match everything else.
    [ switch to "no experience needed" ]   [ keep ]

  Requiring English excludes 890 candidates.
    [ move to preferred ]   [ keep ]
```

Most bad hiring outcomes begin with a requirement nobody costed. Pricing each one live converts
an unexamined habit into an explicit decision — and it improves Omelo's match quality, because
over-specified jobs produce empty funnels and churned employers.

### 3.3 Step 5 — Pay and benefits

```
  PAY

  Range     [ 22,000 ] to [ 30,000 ]  [ INR ]  per [ month v ]
            (o) Gross   ( ) Net
            [ ] Negotiable      [ ] Overtime available

  Jobs that show pay get 4x more qualified applications.

  BENEFITS

  [x] Transport allowance   [ ] Accommodation    [ ] Meals
  [x] Health insurance      [ ] Flight tickets   [ ] Visa sponsorship
  [ ] Overtime pay          [ ] Uniform          [ ] Equipment
  [ ] Paid leave            [ ] Training         [ ] Tips
```

The period selector is not optional. Accommodation, transport, and meals are given equal
prominence to insurance because for migrant and shift work they are frequently the deciding
factor.

Where `country_policies.salary_disclosure_required` is true, publication is blocked until pay
is provided.

### 3.4 Step 6 — Schedule

```
  Work type      [ Full-time  v ]
  Shifts         [x] Day  [x] Evening  [ ] Night  [ ] Rotating  [ ] Weekend
  Hours per week [ 48 ]        Working days [ 6 ]
  Start date     (o) Immediate  ( ) [ date ]
  Duration       [ ongoing ]   <-- shown only for contract/temporary/seasonal
```

### 3.5 Step 4 — Location and work authorisation

```
  Workplace     ( ) Onsite  ( ) Hybrid  ( ) Remote  (o) Field based

  Location      [ Saket, New Delhi                    ]
                Pin on map: candidates see distance from home

  Visa sponsorship for this role
    ( ) Yes, we sponsor
    ( ) No, must already have the right to work
    (o) Not sure yet

  "Not sure yet" shows candidates "Unknown" rather than a guess.
  Roles with a clear answer get 3x more qualified applications.
```

"Not sure yet" maps to `NULL` and renders as *Unknown* everywhere. Omelo never infers
sponsorship.

### 3.6 Step 7 — Conditions and documents

```
  Requirements of the work
    [ ] Uniform required     [x] Own vehicle required
    [ ] Own tools required   [ ] Physically demanding

  Documents you will need
                                    Requested at
    Driving licence     [x]         [ Offer stage    v ]
    Government ID       [x]         [ Offer stage    v ]
    Police clearance    [ ]         [ Offer stage    v ]

  Asking for identity documents before offer stage sharply
  reduces applications and is a common fraud signal. We
  default to offer stage.
```

### 3.7 Step 8 — Pipeline and compliance review

```
  YOUR HIRING PIPELINE

  Your stage name         Candidate sees
  --------------------    ------------------
  New                     Applied
  Phone Call              Screening
  Trial Shift             Interview
  Hire                    Hired
  Not moving forward      Rejected

  [ + add stage ]

  Name your stages however you like. Candidates always see
  honest progress - you can't hide movement, and we don't
  let applications go silent.
```

The right column is not free text; each stage picks from the fixed state list. The closing
sentence is deliberately direct: this is a stated product value, not a hidden limitation.

**Pre-publication compliance checks:**

| Check | Action |
|---|---|
| Gender, age, marital status, photo, or nationality criteria where prohibited | **Block.** Explain, cite the rule, offer a compliant rewrite. |
| Missing pay where the jurisdiction mandates disclosure | **Block** until provided |
| Identity documents requested at apply stage | Warn strongly; flag for review |
| Exclusionary or discriminatory language | Warn with a suggested alternative |
| Unpaid work where prohibited | Block |
| Requirements far above the stated level | Warn — the most common cause of a dead funnel |

Blocked publications are logged; repeated attempts escalate to Trust & Safety.

### 3.8 AI-assisted job description

```
  [ Generate with Omelo AI ]

  Tell us in one line what you need:
  "Need someone to manage our warehouse in Dubai"

  Omelo drafts: title, responsibilities, requirements,
  skills, shift pattern, benefits, screening questions.

  You review and edit everything before publishing.
```

The draft is never published unreviewed. Extraction cannot write a match score, so even a
prompt-injected job description can only produce text a human then edits.

---

## 4. Candidate review

```
DELIVERY EXECUTIVE - Saket          New (24)  Screening (8)
                                    Trial Shift (3)  Hire (0)

+------------------------------------------------------------+
| 94%  Anand Singh                                           |
|      Delivery Executive  |  2 years  |  Saket  |  2.4 km   |
|      Available immediately                                 |
|                                                            |
|      Strong on   Two-wheeler riding, area knowledge,       |
|                  Hindi (fluent)                            |
|      Gap         No prior delivery-app experience          |
|                                                            |
|      Verified    Phone  Driving licence (MCWG, LMV)        |
|                  Employment (1 of 2)                       |
|                                                            |
|      [ Message ]  [ Move to Phone Call ]  [ Not moving forward ] |
+------------------------------------------------------------+
```

Symmetry rules:
- Match reasons are shown in the same structure the candidate sees.
- Opening this card calls `omelo_mark_application_viewed()`, writing `viewed` and a profile-view record. **This cannot be disabled.**
- Documents are visible only where the candidate granted a share. Everything else shows as "not shared."

### 4.1 Rejection requires a human and prompts for a reason

```
  Not moving forward - Anand Singh

  Reason (shared with the candidate)
    ( ) Skills or experience gap
    ( ) Missing required licence
    ( ) Role filled
    ( ) Location or availability
    ( ) Work authorisation
    ( ) Other  [_________________]

  [ ] Add to talent pool for future roles

  Employers who give a reason get 2.4x higher acceptance
  on future outreach to the same candidates.

  [ Cancel ]                        [ Send decision ]
```

There is no bulk-reject-without-reason path and no automated rejection rule builder. The system
ranks; a human decides.

---

## 5. Talent Search

Verified companies with the entitlement only.

```
TALENT SEARCH

  Profession    [ Electrician ]
  Skills        [Industrial wiring] [+]
  Experience    [ 3 ] + years
  Location      [ Dubai ]   within [ 25 km ]   [x] open to relocation
  Licence       [x] Must hold a valid electrician licence
  Availability  [ Within 30 days ]
  Languages     [ English - Conversational ]
  Work auth     [x] include candidates needing sponsorship

  312 candidates
  ----------------------------------------------------------
  94%  Electrician  |  4 years  |  Dubai  |  Available now
       Verified licence  |  Verified employment
       Industrial wiring, panel installation, safety
       [ Request contact ]

  312 of 1,890 profiles matching your criteria have opted in
  to be found. The rest have not.
```

### 5.1 Four hard rules

1. **Opt-in only.** `discoverability <> 'private'` is a query predicate inside `omelo_is_discoverable_to()`, not a display filter.
2. **Blocklist is an anti-join.** Blocked employers get zero rows, never a hidden row.
3. **Preferences are respected before results are shown.** A candidate's pay floor and target professions filter results the employer never sees.
4. **The denominator is honest.** Telling employers how many profiles were excluded by consent prices consent correctly and prevents the assumption that the database is the market.

### 5.2 Outreach

- Every message must attach to a specific job.
- Per-recruiter daily quota, per-candidate cooldown.
- Templates allowed; a template with no job-specific content is rejected.
- Reply rate is tracked and surfaced to candidates.

**Low reply rates reduce outreach quota.** Outreach capacity is earned by behaviour, not
purchased.

---

## 6. Applications and pipeline

Kanban and list views over the employer's own stages.

| Action | Effect | Audit |
|---|---|---|
| Move stage | `applications.state` recomputed from `maps_to_state`; candidate notified | `stage_changed` |
| Message | Job-anchored conversation | `message_sent` |
| Request document | Creates a consent request the candidate must approve | `document_requested` |
| Schedule interview | Timezone-correct; supports trial shifts and walk-ins | `interview_scheduled` |
| Send assessment | Native or partner | `assessment_sent` |
| Internal note | **Never** visible to the candidate | `note_added` |
| Scorecard | Per-interviewer, structured | `note_added` |
| Extend offer | Structured: pay, period, start date, shifts, benefits | `offer_extended` |
| Decision | Requires human actor and reason | `decision_made` |

### 6.1 Internal notes are structurally separate

`application_notes` is a different table from `messages`, with a different permission class.
No candidate-facing query path reaches it. One leaked internal note is a catastrophic trust
event, so the separation is structural rather than a styling convention.

---

## 7. Interviews

```
Interviews
  +-- Upcoming  |  Today  |  Completed  |  Cancelled  |  No-show
```

Interview types cover the full range of hiring reality: `phone`, `video`, `in_person`, `group`,
`walk_in`, `trial_shift`, `practical_test`, `assessment_centre`, `panel`.

A **trial shift** and a **walk-in** are first-class interview types. They are how an enormous
share of the world is actually hired, and treating them as second-class is how a platform
becomes irrelevant to the businesses doing that hiring.

### 7.1 Scorecard

```
  Anand Singh - Trial Shift

  Punctuality           4/5
  Riding / handling     5/5
  Customer interaction  4/5
  Following process     4/5
  Overall               4.3/5

  Recommendation   ( ) Reject   ( ) Hold   (o) Advance

  Notes  [ ................................. ]
```

Interviewers cannot read peer scorecards before submitting their own. Anchoring degrades
evaluation quality and creates a defensibility problem.

---

## 8. Offers

```
Create offer
  |
Pay (amount + period + currency + gross/net)
  |
Benefits
  |
Start date  |  Hours  |  Shifts
  |
Conditions  |  Contract document
  |
Send
  |
Candidate: [ Review ] [ Accept ] [ Decline ] [ Ask a question ]
  |
Accepted -> HIRED
```

---

## 9. Employees — closing the loop

Accepting an offer creates an `employments` row, and the candidate does not disappear.

```
EMPLOYEES

  Anand Singh      Delivery Executive     Started 1 Sep     Active
  Priya Sharma     Warehouse Supervisor   Started 12 Aug    Active
```

That row automatically writes verified work experience onto the person's Omelo identity, plus
an employment verification record. Neither side does extra work.

```
Job -> Application -> Interview -> Offer -> Hire
                                              |
                                         Employment
                                              |
                                        Verification
                                              |
                                        Work Identity
                                              |
                                    Next Opportunity
```

**Why an employer should care:** a verified hire record is what makes Omelo's talent pool
better than a resume pile, and it is the reason to complete a hire on the platform rather than
taking it off-platform at the first phone call.

---

## 10. Team and permissions

```
TEAM

  Person          Role             Scope            Status
  -------------   --------------   --------------   ------
  Sarah Chen      Admin            All              Active
  Marco Silva     Recruiter        3 jobs           Active
  Yuki Tanaka     Hiring Manager   1 job            Active
  Priya N.        Interviewer      Scheduled only   Active
  HR Team         HR               All              Active
  Finance         Billing          None             Active

  [ Invite ]
```

Scoping rules:
- Hiring Managers see only assigned jobs.
- Interviewers see a candidate only from the moment they are scheduled to interview them.
- **Billing sees no candidate data at all.**
- Agency recruiters are scoped per client with no cross-client visibility.

Full matrix: [06 — Permissions & RBAC](06-permissions-and-rbac.md).

---

## 11. Analytics

| View | Purpose |
|---|---|
| Funnel by job | Where candidates are lost |
| Time to hire | Median and distribution per profession |
| **Response behaviour** | Your response rate and median time — the numbers candidates see |
| Requirement cost | How each requirement narrowed the pool, and what it produced |
| Source effectiveness | Which discovery paths produce hires |
| Adverse-impact monitoring | Aggregate selection-rate disparities, where lawful |

Adverse-impact monitoring runs on aggregate, voluntarily-provided data held in an
access-isolated store the matching engine cannot read. Phase 3+, with legal sign-off as a
prerequisite.

---

## 12. Billing

Entitlements enforced at the **service layer**, never the UI alone, and backed by
`company_entitlements`.

| Entitlement | Enforcement point |
|---|---|
| Recruiter seats | Invitation and login |
| Active job slots | Publication |
| Talent search | Query execution |
| Outreach quota | Message send |
| AI credits | Generation request |

Monetisation is not the first development priority, but the architecture accommodates it now
because retrofitting entitlement checks across a live product is far more expensive than
building them in.

---

## 13. Employer-flow invariants

1. Talent search is unreachable without verification.
2. Every employer stage maps to a candidate-visible state.
3. `viewed` is written by the system and cannot be suppressed.
4. Rejection requires a human actor and prompts for a reason.
5. Internal notes and candidate-visible content are structurally separated.
6. Every requirement shows its cost in candidates.
7. Sponsorship is declared or unknown, never inferred.
8. Documents are visible only where the candidate granted a share.
9. Every pipeline action writes an immutable audit event.
10. A one-person business can post a job without modelling an org chart.
