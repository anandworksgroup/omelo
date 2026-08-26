# 01 — Product Requirements

**Status:** Frozen (Phase 0), revised for the universal employment model
**Owner:** Product

Requirement IDs are stable and permanent. Never renumber. To retire one, mark it
`DEPRECATED` and add the superseding ID.

Priority key: **P0** = Phase 1 launch blocker · **P1** = Phase 1 desirable ·
**P2** = Phase 2 · **P3** = Phase 3+

---

## 1. Personas

> **Read W-A through W-D first.** They are the majority of the world's workers and the segment
> every existing platform serves badly. Any design that works only for W-E through W-I is a
> job board, not a universal employment platform.

### 1.1 Worker personas

| ID | Persona | Defining need | Why they churn |
|---|---|---|---|
| **W-A** | *The First-Time Worker* — 17-22, no experience, no resume, often no degree | To be shown work that will actually take someone with nothing yet | Every listing demands experience they cannot have; no way to express what they *can* do |
| **W-B** | *The Local Shift Worker* — delivery, warehouse, retail, cleaning, security | Work near home, starting soon, at a stated wage | Distance hidden until too late; pay not shown; applications vanish; no reply |
| **W-C** | *The Licensed Tradesperson* — electrician, plumber, driver, nurse, welder | Their licence recognised as the qualification it is | Platforms treat a trade licence as a footnote and rank them by keyword overlap |
| **W-D** | *The Migrant Worker* — seeking work in the Gulf, Europe, or another region | Knowing which employers actually sponsor, and whether accommodation is provided | Cannot tell sponsorship from silence; agencies charge fees; documents demanded up front |
| **W-E** | *The Informal Worker* — years of real work, none of it documented | Having self-employed and informal work count as experience | Profiles that require a registered employer leave them with an empty history |
| **W-F** | *The Employed Passive Worker* — has a job, open to a better one | To be found without their current employer noticing | Any platform where "open to work" leaks to their manager |
| **W-G** | *The Career Switcher* — moving from one kind of work to another | The concrete gap between here and there | Generic advice, no evidence, no route |
| **W-H** | *The Professional* — engineer, accountant, doctor, teacher | Precision over volume; relevant, senior-appropriate matches | Recruiter spam far below their level |
| **W-I** | *The Returner* — out of work for caregiving, illness, or migration | Not being penalised for a gap | Platforms that treat gaps as a negative signal |

Design consequences, stated so they are not lost:

- **W-A** requires `accepts_no_experience` as a first-class filter and `is_entry_level_friendly` on professions.
- **W-B** requires geospatial retrieval, mandatory pay display with period, and the hiring timeline.
- **W-C** requires licences as a gate and a first-class profile section.
- **W-D** requires `visa_sponsorship` to mean unknown when unknown, and accommodation/transport/flights as modelled benefits.
- **W-E** requires `experiences.company_id` to be nullable.
- **W-F** requires the employer blocklist to be undetectable.
- **W-I** requires employment gaps to be excluded from the feature set entirely.

### 1.2 Employer personas

| ID | Persona | Defining need | Why they churn |
|---|---|---|---|
| **E-A** | *The Small Local Employer* — restaurant, shop, workshop, clinic hiring 1-3 people | A live job in under ten minutes, with no org chart to model | Enterprise onboarding friction; forms that assume an HR department |
| **E-B** | *The High-Volume Operator* — logistics, retail, security, manufacturing hiring continuously | Fast throughput from application to trial shift to hire | Tools built around slow, individually-considered white-collar hiring |
| **E-C** | *In-house Recruiter* at a 50-5,000 person company | Qualified pipeline without paying per unqualified applicant | Volume of irrelevant applications; no route to passive talent |
| **E-D** | *Hiring Manager* | A short, credible shortlist | Being handed 300 resumes |
| **E-E** | *Talent Sourcer* | Search and outreach at scale, with real reply rates | Databases full of stale or non-consenting profiles |
| **E-F** | *Agency Recruiter* across several clients | Multi-company scoping and attribution | Tools assuming one employer per account |

**E-A and E-B are the ones most easily designed out.** Every mandatory field added for E-C's
benefit is a step E-A must complete before hiring a cook.

### 1.3 Internal personas

| ID | Persona | Need |
|---|---|---|
| **I-A** | Trust & Safety reviewer | Investigate fraud, fake companies, harassment; act with an audit trail |
| **I-B** | Taxonomy steward | Approve, merge, and deprecate professions and skills; keep the taxonomy clean |
| **I-C** | Support agent | Assist via scoped, logged, consent-bounded access |
| **I-D** | Verification reviewer | Check licences, identity, and education, then delete the documents |

---

## 1.5 Universal participation requirements

These override any conflicting requirement elsewhere in this document. They exist because the
easiest way to build a job board by accident is to add one reasonable-sounding mandatory field
at a time.

| ID | Requirement | Priority |
|---|---|---|
| FR-901 | A person can search, browse, and view full job details **without an account**. | P0 |
| FR-902 | A person can create an account and reach relevant jobs in **four questions**: what work, where, what kind, how much experience. | P0 |
| FR-903 | **No field anywhere is mandatory to complete a work identity.** Every step offers Skip. `None` is a valid answer everywhere and never a validation error. | P0 |
| FR-904 | A person with no resume, no degree, and no formal employment can complete a usable profile and apply. | P0 |
| FR-905 | The profile is **adaptive**: fields shown are resolved from the work sought, via `omelo_profile_schema_for()`. No person is shown a field their work does not use. | P0 |
| FR-906 | Adding a profession, or a field for one, is a data operation. **No schema migration, no code change.** | P0 |
| FR-907 | Every monetary amount is displayed with its period. Comparison across periods is Omelo's job, never the user's. | P0 |
| FR-908 | Distance is shown on every onsite job and is the default sort for location-based discovery. | P0 |
| FR-909 | Licences are a first-class profile section and a hard matching gate, with the route to obtaining a missing one always shown. | P0 |
| FR-910 | Language selection precedes authentication. Phone-first auth is available wherever `country_policies.phone_auth_preferred`. | P0 |
| FR-911 | Voice input is available on every free-text profile field. | P1 |
| FR-912 | Approximate answers are accepted where precision is not needed ("about 2 years"). | P0 |
| FR-913 | Quick apply exists: for jobs with `quick_apply_enabled` and `requires_resume = false`, applying is confirm-and-submit. | P0 |
| FR-914 | Identity documents are requested at the stage the employer declared, defaulting to **offer**, never at apply time. | P0 |
| FR-915 | Gender and age criteria are prohibited by default in every country and require a recorded legal basis to enable. They are **never** matching features or user-facing filters. | P0 |
| FR-916 | Informal and self-employed work counts as experience, recorded honestly with `is_informal` / `is_self_employed`. | P0 |
| FR-917 | Match coverage is measured **per category**. An overall average that hides a failing category is not an acceptable measure. | P0 |
| FR-918 | Trial shifts and walk-in interviews are first-class interview types. | P1 |
| FR-919 | Notifications support SMS and WhatsApp, not push and email alone. | P1 |
| FR-920 | Every notification carries a deep link. Nothing is a dead end. | P0 |

---

## 2. P1 — Work Identity

The foundation. A person does not create a resume. They create an **Omelo Work
Identity**: a structured, typed, partly verified record that many artifacts (resume, profile,
application) are rendered *from*.

### 2.1 Identity composition

| ID | Requirement | Priority |
|---|---|---|
| FR-101 | A Person has exactly one Professional Identity, containing: headline, current profession, summary, skills, experience, education, projects, certifications, languages, work authorisation, preferences, and target career. | P0 |
| FR-102 | Every experience entry is typed: company (linked to a Company node where resolvable), profession (linked to the taxonomy), title as written, start/end, employment type, location, remote mode, and achievements. | P0 |
| FR-103 | Every skill on an identity resolves to a canonical Skill node, and carries: proficiency, years of use, last used, and evidence links (which experiences/projects/credentials support it). | P0 |
| FR-104 | Skills a user cannot evidence are marked `self-declared`; skills backed by experience, project, credential, or assessment are marked `evidenced`. The distinction is visible to both sides. | P0 |
| FR-105 | Education entries link to an Institution node, with degree, field of study, and dates. | P0 |
| FR-106 | Projects carry title, description, role, skills used, links, and optional media. | P1 |
| FR-107 | Certifications link to an Issuer, with credential ID, issue/expiry date, and verification URL where the issuer supports it. | P1 |
| FR-108 | Languages carry a CEFR-style proficiency level per language. | P0 |
| FR-109 | Work authorisation is modelled per country as an explicit status (citizen, permanent resident, work permit held, requires sponsorship, no right to work), with optional expiry. | P0 |
| FR-110 | Identity completeness is scored and displayed, with the specific next action that raises it most. | P1 |

### 2.2 Identity creation and import

| ID | Requirement | Priority |
|---|---|---|
| FR-120 | A candidate can create an identity by uploading a resume (PDF/DOCX). The system extracts structured fields and presents them for confirmation. | P0 |
| FR-121 | **No extracted field is committed to the identity without explicit user confirmation.** Extraction confidence is shown per field; low-confidence fields are highlighted first. | P0 |
| FR-122 | A candidate can create an identity manually, guided step by step, without any upload. | P0 |
| FR-123 | Import from a LinkedIn data export archive is supported, subject to the same confirmation rule. | P1 |
| FR-124 | Identity creation is resumable; partial state persists across sessions and devices. | P0 |
| FR-125 | Target completion time for a resume-based identity is under 12 minutes (success metric S1). | P0 |

### 2.3 Verification

| ID | Requirement | Priority |
|---|---|---|
| FR-130 | Education can be verified via institution partnership or document review, producing a `verified` badge with method and date. | P2 |
| FR-131 | Employment can be verified via work-email domain confirmation, employer confirmation, or document review. | P1 |
| FR-132 | Certifications can be verified via issuer API or verification URL check. | P2 |
| FR-133 | Every verification records: method, verifier, timestamp, and expiry. Verifications expire and require renewal. | P1 |
| FR-134 | A verified badge never implies more than what was checked. Hovering a badge states exactly what was verified and how. | P0 |
| FR-135 | Unverified is the default and is never presented as suspicious. | P0 |

### 2.4 Rendering and portability

| ID | Requirement | Priority |
|---|---|---|
| FR-140 | Omelo generates a role-appropriate resume (PDF) from the identity, tailored to a specific job or profession, without the candidate rewriting anything. | P1 |
| FR-141 | The candidate reviews and edits any generated document before it is sent. Generated content is never transmitted unreviewed. | P0 |
| FR-142 | A candidate can export their complete identity as structured JSON at any time. | P0 |
| FR-143 | A candidate has a public profile URL whose visibility they control (private / link-only / public). | P1 |
| FR-144 | **Omelo ID** — the identity is addressable as a portable object other systems can consume, subject to candidate-granted scopes. | P3 |

---

## 3. P2 — Career Intelligence

Where Omelo becomes larger than a job board. See [07](07-ai-architecture.md) for how these
are computed.

| ID | Requirement | Priority |
|---|---|---|
| FR-201 | Omelo infers the candidate's current profession and career level from their identity, and shows it with the evidence that produced it. The candidate can correct it, and the correction is retained. | P0 |
| FR-202 | Omelo presents plausible next professions from the current one, each with: rationale, typical time-to-transition, salary delta, and how many people have made that move. | P2 |
| FR-203 | A candidate can declare one or more **target careers**. Targets drive job recommendations, gap analysis, and feed content. | P0 |
| FR-204 | For any (current identity, target profession) pair, Omelo computes a **skill gap**: skills already held, skills partially evidenced, and skills missing, ranked by impact on match scores. | P2 |
| FR-205 | Each gap item links to concrete closure routes: roles that build it, projects, certifications, or partner learning content. | P2 |
| FR-206 | Omelo shows **bridge roles** — intermediate professions that make a distant target reachable. | P2 |
| FR-207 | Market signal per skill and profession: demand trend, salary range by country, and volume of open roles. | P2 |
| FR-208 | An "opportunity delta" statement: how many additional jobs a candidate would match if a specific gap were closed. | P2 |
| FR-209 | Career Intelligence outputs are always shown with their basis and their uncertainty. No unsourced advice. | P0 |
| FR-210 | **Career Copilot** — a conversational interface grounded strictly in the candidate's own graph and live market data, with citations to the underlying records. | P3 |

### 3.1 Global career mobility

| ID | Requirement | Priority |
|---|---|---|
| FR-220 | A candidate can specify target countries; Omelo returns a mobility assessment per country: compatible job volume, salary range for their profession, language requirement, and sponsorship availability signal. | P2 |
| FR-221 | Sponsorship availability is derived from employer-declared data on jobs, never inferred or guessed. Where unknown, it is displayed as unknown. | P0 |
| FR-222 | Omelo never presents immigration guidance as legal advice, and states this at every mobility surface. | P0 |
| FR-223 | Salary figures state their source, currency, period, gross/net basis, and collection date. | P0 |

---

## 4. P3 — Job Marketplace

Not "search jobs" — **discover opportunities**.

### 4.1 Discovery

| ID | Requirement | Priority |
|---|---|---|
| FR-301 | A candidate can search in natural language ("software engineer in Germany with visa sponsorship") and the system resolves it into structured facets: profession, location, seniority, salary, remote mode, sponsorship, language, industry, company. | P0 |
| FR-302 | Resolved facets are shown as editable chips. The user can always see and correct how their query was interpreted. | P0 |
| FR-303 | Classic faceted search and filtering is available without any natural-language step. | P0 |
| FR-304 | Every job result carries a **match score** and, on expansion, the reasons for it. | P0 |
| FR-305 | Each result shows **why you match** (satisfied criteria) and **skill gap** (unmet criteria) explicitly. | P0 |
| FR-306 | Results can be sorted by match, recency, or salary; the active sort is always visible. | P0 |
| FR-307 | A personalised recommendation feed exists independent of search, driven by identity, targets, and behaviour. | P1 |
| FR-308 | Saved searches with configurable alert cadence (instant / daily / weekly / off). | P1 |
| FR-309 | Jobs can be saved, hidden, and marked "not interested" with a reason; reasons feed back into ranking. | P1 |
| FR-310 | Every job displays a freshness state and is removed or marked expired when the source indicates closure. | P0 |
| FR-311 | Jobs display salary where available. Where the posting jurisdiction mandates pay transparency, salary is required before the job can be published in that jurisdiction. | P0 |

### 4.2 Applying

| ID | Requirement | Priority |
|---|---|---|
| FR-320 | One-tap apply using the Omelo identity, with a preview of exactly what the employer will receive. | P0 |
| FR-321 | Employers may require additional structured questions; these are answered inside Omelo, never via redirect, for natively posted jobs. | P0 |
| FR-322 | For jobs originating in an external ATS, Omelo either submits via integration or hands off cleanly, and clearly labels which is happening. | P0 |
| FR-323 | Candidates can attach a tailored cover note, optionally AI-drafted from the identity and job, always user-reviewed (FR-141). | P1 |
| FR-324 | Application rate limiting protects both sides from spray-and-pray behaviour; limits are transparent and explained. | P1 |

### 4.3 Application transparency — the hiring timeline

Direct answer to PR-4.

| ID | Requirement | Priority |
|---|---|---|
| FR-330 | Every application exposes a candidate-visible timeline with these states: `submitted`, `viewed`, `contacted`, `screening`, `interview`, `final_interview`, `offer`, `hired`, `rejected`, `withdrawn`, `expired`. | P0 |
| FR-331 | `viewed` is set automatically and truthfully when a recruiter opens the application. It cannot be faked or suppressed by the employer. | P0 |
| FR-332 | If no state change occurs within a configured window, the timeline displays elapsed time and sets expectation ("Most responses for this employer arrive within N days"). | P0 |
| FR-333 | Rejection is always communicated. An application may not silently terminate; expiry after a defined period auto-transitions to `expired` with notice to the candidate. | P0 |
| FR-334 | Employer response-rate and time-to-response statistics are computed and shown on the company profile. | P1 |
| FR-335 | Candidates can withdraw at any state, with an optional reason. | P0 |
| FR-336 | Candidates see aggregate context where available: number of applicants, and their relative position band. Exact rankings of other candidates are never exposed. | P2 |

---

## 5. P4 — Talent / Recruiting

The reverse direction of the same engine.

| ID | Requirement | Priority |
|---|---|---|
| FR-401 | For any job, Omelo produces a ranked list of compatible candidates, restricted to candidates whose discoverability permits it. | P1 |
| FR-402 | Every candidate result carries a match score and its reasons, symmetric to the candidate-side view (PR-5). | P1 |
| FR-403 | Recruiters can search talent by structured criteria: profession, skills, experience band, location, work authorisation, language, availability, salary expectation. | P1 |
| FR-404 | **Talent Search only returns candidates who have opted into discoverability, and never returns a candidate to an employer they have blocked.** | P0 |
| FR-405 | Candidate identities in search results are shown at the disclosure level the candidate chose (e.g. name hidden until the candidate accepts contact). | P1 |
| FR-406 | Recruiters can save candidates to talent pools, scoped to their company. | P1 |
| FR-407 | Outreach is rate-limited per recruiter and per candidate. Candidates set their contact preferences, including "only for roles above salary X" and "only for target professions". | P0 |
| FR-408 | Outreach messages must reference a specific job. Untargeted bulk messaging is not supported. | P0 |
| FR-409 | Candidates see who viewed their profile and from which company, subject to recruiter-side visibility settings that are themselves disclosed. | P1 |
| FR-410 | Recruiter reply-rate is tracked and surfaced to candidates deciding whether to engage (PR-5). | P2 |

### 5.1 Direct hiring chat

The BOSS Zhipin primitive, made professional.

| ID | Requirement | Priority |
|---|---|---|
| FR-420 | A conversation exists between a Person and a Company, always anchored to a job context. | P0 |
| FR-421 | Either side can initiate: a candidate can message about a job they applied to; a recruiter can message a discoverable candidate about a specific job. | P1 |
| FR-422 | Conversations carry structured actions inline: *schedule interview*, *share portfolio*, *request availability*, *send assessment*, *withdraw application*, *decline*. | P1 |
| FR-423 | Messages are typed and auditable. Attachments are permission-scoped and virus-scanned. | P0 |
| FR-424 | Candidates can block a company or an individual recruiter, permanently and unilaterally. | P0 |
| FR-425 | Report-and-review flow for harassment, discriminatory language, and fee-demanding scams, with T&S tooling behind it. | P0 |
| FR-426 | Chat is not a general messaging product. There is no cross-company DM, no group chat, no friend-based messaging in Phase 1-3. | P0 |
| FR-427 | Read receipts and typing state are symmetric or absent. Never one-sided in the employer's favour. | P0 |

---

## 6. P5 — Company / Employer

| ID | Requirement | Priority |
|---|---|---|
| FR-501 | A Company Identity contains: legal and display name, industry, size band, founded year, locations, description, benefits, culture, media, and links. | P0 |
| FR-502 | Company claiming requires domain-verified work email plus a secondary check before the company can post jobs or search talent. | P0 |
| FR-503 | Companies have members with roles: Owner, Admin, Recruiter, Hiring Manager, Interviewer, Billing. See [06](06-permissions-and-rbac.md). | P0 |
| FR-504 | Agency recruiters can operate across multiple companies with per-company scoping and explicit client attribution. | P2 |
| FR-505 | Job creation captures structured requirements — profession, required and preferred skills with weights, experience band, education, languages, location and remote mode, salary range, employment type, and **sponsorship availability** — not just prose. | P0 |
| FR-506 | The job editor previews the expected candidate pool live as requirements change, so employers can see the cost of an unnecessary requirement. | P1 |
| FR-507 | Omelo flags requirements likely to be discriminatory or unlawful in the posting jurisdiction (age, gender, marital status, photo requirements, nationality where prohibited) and blocks publication of clear violations. | P0 |
| FR-508 | Hiring pipeline: stages are configurable per job; candidates move through stages; every transition is logged with actor and timestamp. | P0 |
| FR-509 | Every employer stage transition maps to a candidate-visible timeline state (FR-330). Internal sub-stages may exist but must map to a public state. | P0 |
| FR-510 | Interview scheduling with calendar integration and timezone-correct proposals. | P2 |
| FR-511 | Structured assessments and scorecards, per stage, per interviewer. | P2 |
| FR-512 | Company analytics: funnel conversion, source effectiveness, time-to-hire, response times, and adverse-impact monitoring. | P2 |
| FR-513 | Billing and entitlements: seats, job slots, talent-search quota, with hard enforcement at the service layer. | P1 |
| FR-514 | **A rejection decision requires a human actor.** The system may rank and may recommend, but may not auto-reject. | P0 |

---

## 7. P6 — Omelo Network

Deliberately not the centre of the product. Career signal, not a social feed (PR-7).

| ID | Requirement | Priority |
|---|---|---|
| FR-601 | A candidate can follow companies, professions, and skills. Following drives feed content and alerts. | P2 |
| FR-602 | Connections between people exist but grant no special data access beyond what visibility settings already allow. | P3 |
| FR-603 | The feed is composed of career-relevant signal only. Canonical item types: role changes among followed people, hiring activity at followed companies, market movement on tracked skills, new eligibility ("you now match N more jobs"), and application events. | P2 |
| FR-604 | Every feed item states why it was shown and can be muted at the source. | P2 |
| FR-605 | No general-purpose posting, resharing, or reactions in Phase 1-3. | P0 |
| FR-606 | Company pages surface real hiring behaviour: response rate, median time to first response, and hiring volume by profession. | P2 |

---

## 8. Cross-cutting requirements

### 8.1 Trust, safety, integrity

| ID | Requirement | Priority |
|---|---|---|
| FR-701 | Job postings are screened for fraud patterns: fee requests, payment-details collection, off-platform redirection to messaging apps, and impossible compensation. | P0 |
| FR-702 | Omelo never asks a candidate for payment to apply, and displays a persistent warning that no legitimate employer will request payment or financial details during hiring. | P0 |
| FR-703 | Company verification state is displayed on every job. Unverified companies have reduced reach and stricter posting limits. | P0 |
| FR-704 | All identity documents submitted for verification are encrypted at rest, access-logged, and deleted after the retention period. | P0 |
| FR-705 | Duplicate and reposted jobs are detected and collapsed. | P1 |

### 8.2 Candidate data rights

| ID | Requirement | Priority |
|---|---|---|
| FR-710 | Self-service export of all personal data in a machine-readable format. | P0 |
| FR-711 | Self-service account deletion with a defined grace period, propagating to derived stores including embeddings and search indexes. | P0 |
| FR-712 | Per-field visibility control on the identity. | P1 |
| FR-713 | **Employer blocklist** — a candidate can name companies that must never see them in Talent Search or the feed. Enforced at query time, not by post-filtering the UI. | P0 |
| FR-714 | A clear, plain-language explanation of how matching uses their data, reachable from every match score. | P0 |
| FR-715 | The right to request human review of any automated ranking that affected them. | P0 |

### 8.3 Internationalisation

| ID | Requirement | Priority |
|---|---|---|
| FR-720 | All user-visible strings are externalised for localisation from the first commit. | P0 |
| FR-721 | Money is always stored with an explicit currency and period; never as a bare number. | P0 |
| FR-722 | Dates and times are stored in UTC and rendered in the viewer's timezone. | P0 |
| FR-723 | Names, addresses, and phone numbers use internationally valid formats; no assumptions about given/family name ordering. | P0 |
| FR-724 | Job content language is recorded; search respects language preference. | P1 |
| FR-725 | Country-specific field requirements are configuration, not code branches. | P1 |

---

## 9. Non-functional requirements

| ID | Requirement | Target |
|---|---|---|
| NFR-01 | Job search latency, p95 | < 400 ms server-side |
| NFR-02 | Match score computation for a candidate's top 50 jobs, p95 | < 1.5 s |
| NFR-03 | Feed and recommendation load, p95 | < 800 ms |
| NFR-04 | Resume extraction turnaround, p95 | < 30 s |
| NFR-05 | Mobile cold start to interactive | < 2.5 s on a mid-tier Android device |
| NFR-06 | Availability, core read paths | 99.9% monthly |
| NFR-07 | Chat message delivery, p95 | < 1 s |
| NFR-08 | Data residency | EU personal data processed and stored in EU region |
| NFR-09 | Encryption | TLS 1.3 in transit; AES-256 at rest; verification documents separately encrypted |
| NFR-10 | Auditability | Every permission-relevant and score-relevant action written to an append-only audit log with actor, subject, timestamp |
| NFR-11 | Match reproducibility | Any historical score reproducible from stored feature vectors and model version |
| NFR-12 | Accessibility | WCAG 2.2 AA on web and mobile |
| NFR-13 | Scale target, Phase 1 | 1M identities, 2M active jobs, 50M edges, without architectural change |
| NFR-14 | Backup and recovery | RPO 15 min, RTO 4 h |
| NFR-15 | AI cost ceiling | Per-identity AI processing cost tracked and capped; matching must degrade gracefully to the deterministic path if AI services are unavailable |

---

## 10. Requirement dependency notes

- FR-330 (timeline) depends on FR-509 (employer stage mapping). Shipping one without the other produces a dishonest timeline — **ship together or not at all**.
- FR-401 (talent recommendations) depends on FR-404 and FR-713. Discoverability and blocklist enforcement precede any talent surface.
- FR-204 (skill gap) depends on a populated profession-skill taxonomy. Phase 2 cannot begin until the taxonomy from [02](02-domain-model.md) is seeded and stewarded.
- FR-311 (salary transparency) depends on per-jurisdiction configuration in FR-725.
