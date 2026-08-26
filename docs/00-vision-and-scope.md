# 00 — Vision & Scope

**Status:** Frozen (Phase 0), revised for the universal employment model
**Owner:** Product

---

## 1. The definition

> Omelo is a **universal employment platform**: where a person's work identity, jobs,
> companies, applications, hiring, and career growth live in one place — for every kind of
> work.

Not *"a professional network."*
Not *"search for a job."*
But *"build your work identity, find work, and get hired"* — whoever you are.

### 1.1 The test every decision must pass

Any feature, field, screen, or default must work for all of these people:

software engineer · doctor · teacher · driver · electrician · construction worker · chef ·
security guard · delivery worker · accountant · factory worker · student · freelancer ·
domestic worker · manager · executive · **someone looking for their first job**

If a design only works for the top of that list, it is wrong. This is not an inclusivity
gesture — it is the market. The overwhelming majority of the world's workers are not
white-collar, and every existing platform serves them badly or not at all.

---

## 2. What Omelo takes from existing platforms

| Platform | Structural advantage absorbed | Omelo expression |
|---|---|---|
| LinkedIn | A persistent identity that outlives one job search | **Work Identity** |
| Indeed | Breadth of coverage; the search habit | **Discover** |
| SEEK | A real two-sided marketplace, not a directory | **Employer / Worker marketplace** |
| Naukri | Recruiter-first database built for volume hiring | **Talent Search** |
| BOSS Zhipin | Direct conversation as the primary primitive | **Direct hiring chat** |
| StepStone / EU boards | Regional and regulatory specialisation | **Country-aware engine** |
| Computrabajo | Multi-country reach in emerging markets | **Multi-country marketplace** |

**But the synthesis goes further than all of them.** Every platform above is shaped for
salaried, formally-documented, office-adjacent work. Omelo's structural bet is that the same
underlying object — a **work identity** — describes a warehouse packer and a cardiologist, and
that the difference between them is *data*, not a different product.

---

## 3. The core differentiator

| | Existing platforms | Omelo |
|---|---|---|
| Identity | You write a resume. No resume, no participation. | A structured work identity that can start almost empty and grow |
| Profile shape | One template, white-collar shaped | **Adaptive** — the fields follow the work |
| Entry requirement | Degree, employment history, digital fluency assumed | None required |
| Search | Keyword over job text | Compatibility over a work graph, distance-aware |
| Application | Submit, then silence | Submit, then a visible, honest timeline |
| After hiring | You disappear from the platform | Hire becomes **verified work history** |
| Growth | Not addressed | Career paths and skill gaps for trades as well as professions |

Row 2 and row 6 are the ones nobody else has.

---

## 4. Design principles

Tie-breakers, in priority order.

**PR-1 — Every person is a talent.**
Terminology, defaults, ordering, and required fields treat a first-time jobseeker as a
first-class user, not an edge case.

**PR-2 — The profile adapts to the work.**
Never ask a driver about clinical specialisations. Never ask a nurse about vehicle classes.
Never ask anyone for a field their work does not use.

**PR-3 — Nothing is required to participate.**
No degree, no resume, no formal employment, no certifications, no digital literacy assumed.
Requirements are the fastest way to exclude the people who most need the platform.

**PR-4 — Structure over prose.**
Free text is accepted, then normalised into typed entities — always with user confirmation.

**PR-5 — Explainability is a feature.**
Every score, ranking, and recommendation is shown with the reasons that produced it.

**PR-6 — No black-hole applications.**
Every application has a visible, honest state. "No response yet" is a displayed state with
elapsed time. Silence is a product bug.

**PR-7 — Two-sided symmetry.**
Every employer capability has a worker-side counterpart. Recruiters see match reasons; so do
candidates. Recruiters rate candidates; candidates see employer response rates.

**PR-8 — The worker owns the identity.**
Export, correct, restrict, and delete are first-class features. Sensitive documents are never
auto-shared.

**PR-9 — Global by construction.**
Country, currency, pay period, language, work authorisation, and legal policy are modelled
from day one as configuration.

**PR-10 — Deterministic core, AI edge.**
Money, eligibility, permissions, and scores are deterministic code. AI extracts, normalises,
explains, and converses.

---

## 5. What "universal" changes in practice

Concrete consequences, so this stays a design constraint rather than a slogan.

| White-collar assumption | Omelo instead |
|---|---|
| Pay is annual | `pay_period` spans hour, day, week, fortnight, month, year, per-task |
| Everyone has a degree | `education_level` includes `none` and `vocational` |
| Experience means formal employment | `experiences` allows self-employed and informal work with no company record |
| Skills are technical | `skill_type` includes `trade`, `equipment`, `physical`, `safety` |
| Certifications are professional | **Licences are first class** — driving, trade, medical, security |
| Location means a city filter | Geo point + distance. "2.4 km away" is a primary discovery mode |
| Schedule is 9-to-5 | `shift_type` spans day, evening, night, rotating, split, on-call, weekend |
| Benefits are equity and healthcare | **Accommodation, transport, meals, flight tickets** — decisive for migrant and shift work |
| Applying means uploading a resume | `quick_apply` exists; `requires_resume` defaults to false |
| Language proficiency is CEFR | Plain levels: basic, conversational, professional, fluent, native |
| Work type is full-time or contract | Adds gig, seasonal, apprenticeship, daily wage, volunteer |

Every row above is implemented in the deployed schema.

---

## 6. Explicitly out of scope

| Not building | Why |
|---|---|
| A general social feed | PR-1. Career signal only. No general-interest posting. |
| Payroll, EOR, or immigration filing | Regulated and capital-intensive. Partner instead. |
| Learning content production | We identify gaps and route to partners; we do not author courses. |
| Scraped job aggregation | Legal risk, data quality, and no employer feedback loop — which PR-6 depends on. |
| Company reviews | Deferred. Moderation and defamation exposure need deliberate design, not a v1 bolt-on. |
| Full enterprise ATS replacement | Integrate first. Revisit later. |

---

## 7. Success definition for Phase 1

- **S1** — A person with no resume and no degree completes a usable work identity in under 6 minutes and receives relevant matches immediately.
- **S2** — A person with a resume completes identity creation in under 12 minutes, confirming ≥ 85% of extracted fields without editing.
- **S3** — ≥ 40% of applications receive an employer action within 7 days, and 100% display a truthful current state.
- **S4** — An employer goes from "create job" to "first qualified conversation" in under 48 hours.
- **S5** — Hires made on Omelo produce verified work history on the worker's identity without either side doing extra work.

S1 is listed first deliberately. If Omelo only works for people who already have a resume, it
is a job board.

---

## 8. Glossary

| Term | Meaning |
|---|---|
| **Person** | A human account. May be a worker, a recruiter, or both. |
| **Work Identity** | The structured record of what a person can do. May be nearly empty. A resume is one *rendering* of it. |
| **Category** | Top-level work grouping (Construction, Healthcare, Technology). 34 seeded. |
| **Profession** | A specific kind of work within a category (Electrician, Nurse, Delivery Executive). 92 seeded. |
| **Adaptive Profile** | The set of fields shown to a person, resolved from the work they seek. |
| **Profile Attribute** | A declared, typed field scoped to a category or profession. |
| **Licence** | A legal permit to perform work. The primary employability gate for hundreds of millions. |
| **Job** | A posted opening, answering the same twelve questions regardless of the work. |
| **Application** | The person-job relationship, carrying a candidate-visible state. |
| **Stage** | An employer's own pipeline step. Always maps to a candidate-visible state. |
| **Match Score** | A deterministic 0-100 value from graph features. Never LLM-generated. |
| **Eligibility Gate** | A hard pass/fail condition, e.g. work authorisation or a required licence. |
| **Discoverability** | Opt-in state controlling appearance in Talent Search. Defaults to `private`. |
| **Employment** | A hire recorded on Omelo, which becomes verified experience. |
| **Document Share** | Explicit, revocable, per-employer consent to view one document. |

---

## 9. Phase boundaries

| Phase | Name | Exit gate |
|---|---|---|
| **0** | Specification | Approved |
| **1a** | Database | **Deployed** |
| **1b** | User app + Company portal | S1-S5 met in one launch market |
| **2** | Career intelligence | Path and gap models validated against real transition data |
| **3** | Talent engine | Consent rates and recruiter reply rates healthy |
| **4** | Global mobility + Network | Multi-country operation with residency compliance |
| **5** | Omelo ID | Portable work identity adopted externally |

---

## Decision log

| Decision | Rationale |
|---|---|
| Universal employment platform, not professional networking | The majority of the world's workers are not white-collar and are served badly everywhere |
| Adaptive profile via declared attributes, not per-profession tables | One schema serves every trade; adding a profession is data, not a migration |
| Nothing required to participate | Requirements exclude precisely the people who most need the platform |
| Licences are first class, not a certification subtype | For drivers, nurses, electricians, and guards the licence *is* employability |
| Geo distance is a primary discovery mode | For most non-remote work, "how far is it" outranks every other filter |
| Accommodation, transport, and meals modelled as benefits | Decisive for migrant and shift work, absent from every white-collar schema |
| Hire creates verified experience automatically | The loop that compounds — and the reason to hire *through* Omelo rather than around it |
| Company reviews deferred | Moderation and defamation exposure need deliberate design |
