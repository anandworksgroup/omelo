# 02 — Domain Model

**Status:** Frozen (Phase 0), implemented in the live database
**Owner:** Engineering + Product

---

## 1. The spine

```
PERSON
  |
  v
WORK IDENTITY
  |
  +-- Skills          +-- Licences
  +-- Experience      +-- Availability
  +-- Education       +-- Preferences
  +-- Documents       +-- Goals
  |
  v
OPPORTUNITY (Job)
  |
  v
APPLICATION -> INTERVIEW -> OFFER -> HIRED -> EMPLOYMENT -> VERIFIED EXPERIENCE
                                                                    |
                                                                    v
                                                           NEXT OPPORTUNITY
```

Two properties matter more than anything else in this model:

1. **A work identity may be almost empty and still be valid.** Nothing is required to
   participate. Omelo builds the identity progressively as the person uses the platform.
2. **The loop closes.** A hire made on Omelo writes verified work history back onto the
   identity, which improves the person's next opportunity. This is the only mechanism in the
   product that compounds.

---

## 2. Category → Profession: the universal spine

Every kind of work sits in the same two-level tree. There is no separate "blue-collar section."

```
Construction                      Healthcare                  Technology
  |- General Labourer               |- Doctor                    |- Software Engineer
  |- Mason                          |- Nurse                     |- Mobile Developer
  |- Carpenter                      |- Caregiver                 |- Data Analyst
  |- Electrician                    |- Pharmacist                |- IT Support
  |- Plumber                        |- Lab Technician            |- Network Engineer
  |- Welder                         |- Ward Attendant
  |- Painter
  |- Site Supervisor
  |- Civil Engineer
  |- Heavy Equipment Operator
```

`Electrician` and `Software Engineer` are siblings in the same structure, with the same field
types and the same treatment throughout the product.

**Seeded:** 34 categories, 92 professions.

Each profession carries the metadata that lets onboarding adapt:

| Field | Why it exists |
|---|---|
| `typical_education_level` | Sets a sensible default; never a gate |
| `requires_license` | Prompts for the licence up front — for a driver or nurse, this *is* employability |
| `is_entry_level_friendly` | Lets a first-time jobseeker be shown work that will actually take them |
| `typical_work_types` | A mason is `daily_wage` and `contract`; an accountant is not |

### 2.1 Titles are noise, professions are signal

Every job and every experience stores **both** the free-text title as written **and** a
resolved `profession_id`. Neither replaces the other: the raw string is what the user actually
said and must never be destroyed; the resolved ID is what matching reasons about.

Unrecognised titles land in `profession_aliases` with `status = 'pending_review'` and an
occurrence counter. **Users never create professions.** An uncurated taxonomy degrades within
months and takes every downstream score with it.

---

## 3. The adaptive profile — the central mechanism

This is what makes one product serve every trade.

### 3.1 The problem

A driver needs to record vehicle classes, routes, and night-driving willingness. A nurse needs
specialisation and clinical setting. A mason needs trade level and whether they own tools. A
software engineer needs a portfolio link.

The two obvious solutions are both wrong:

- **One giant profile with every field** — unusable. A cook scrolls past clinical specialisations.
- **A table per profession** — unmaintainable. Adding a profession becomes a migration.

### 3.2 The solution

```
profile_attributes                     -- declares WHAT fields exist and WHO sees them
    scope: universal | category | profession
    type:  text, number, boolean, single_select, multi_select, date, years, file

person_attributes                      -- the person's VALUES

job_attribute_requirements             -- the same attributes used as job requirements

omelo_profile_schema_for()             -- resolves which fields THIS person should see
```

**There are no profession-specific columns anywhere in the person tables.** Adding a
profession, or a new field for an existing one, is a data insert.

### 3.3 Verified behaviour

For a person seeking `Delivery Executive`, `omelo_profile_schema_for()` returns exactly:

```
delivery-vehicle        (category: Delivery)     "What do you deliver with?"
smartphone-available    (category: Delivery)     "Do you have a smartphone?"
has-smartphone          (universal)
can-travel-daily-km     (universal)
first-job               (universal)
```

Not vehicle licence classes. Not clinical specialisations. Not a portfolio URL. Five questions,
all of which matter to that person, none of which do not.

### 3.4 Attributes are symmetric

The same attribute definition drives the profile field *and* the job requirement. An employer
posting a delivery job selects "must have own two-wheeler" from the same vocabulary the worker
answered with. That symmetry is what makes matching on these fields possible at all.

---

## 4. Work identity: what makes it universal

| Design choice | What it enables |
|---|---|
| `experiences.company_id` is **nullable**, `employer_name` is free text | Self-employed, informal, family-business, and daily-wage work are valid history. Requiring a registered employer would leave a large share of the world with no recordable work history at all. |
| `is_self_employed`, `is_informal` flags | Informal work is labelled honestly rather than disguised as formal employment |
| `education_level` includes `none` and `vocational` | Nobody has to misrepresent themselves to complete a profile |
| `person_licenses` is a first-class table | A driving licence, trade licence, or nursing registration is the employability gate, not a nice-to-have |
| `person_professions` allows multiple, typed relationships | A person can be `experienced` in one profession, `seeking` another, and hold a third as a `goal` — very common |
| Pay is `(amount, period, currency, basis)` everywhere | ₹700/day and €85,000/year are both expressible and comparable |
| `availability_window` from `immediate` to `within_90_days` | "I can start tomorrow" is the single most important fact for shift and daily work |
| `language_proficiency` in plain words | "Conversational Hindi" is meaningful to a supervisor; "B1" is not |

---

## 5. The universal job model

Every job answers the same twelve questions. Only the answers differ.

| Question | Fields |
|---|---|
| **What work?** | `title`, `profession_id`, `category_id`, `description`, `responsibilities`, `openings` |
| **Where?** | `workplace_type`, `location_id`, `geo`, `country_code`, `relocation_support` |
| **When?** | `work_type`, `shift_types`, `hours_per_week`, `working_days`, `start_date`, `duration_months` |
| **How much?** | `pay_min/max`, `pay_period`, `pay_currency`, `pay_basis`, `pay_negotiable`, `overtime_available` |
| **What skills?** | `job_skills` with requirement level and weight |
| **What experience?** | `min/max_experience_months`, `accepts_no_experience` |
| **What qualifications?** | `min_education`, `job_licenses`, `job_credentials` |
| **What documents?** | `job_documents_required`, each with the stage at which it is requested |
| **What language?** | `job_languages` with minimum proficiency |
| **What benefits?** | `job_benefits` — accommodation, transport, meals, insurance, flights |
| **What conditions?** | `physical_requirements`, `uniform_required`, `own_tools_required`, `own_vehicle_required` |
| **Who / how to apply?** | `company_id`, `application_method`, `quick_apply_enabled`, `requires_resume` |

A cook's job and a cardiologist's job are the same row shape.

### 5.1 Two fields that carry disproportionate weight

**`visa_sponsorship` is nullable with no default.** `NULL` means *unknown* and renders as
unknown. Inferring "no" from silence would silently remove migrant workers — a primary Omelo
audience — from most of the market.

**`job_documents_required.request_at_stage` defaults to `offer`.** Demanding a passport scan to
apply for a shift is both a privacy failure and a well-known fraud pattern.

---

## 6. The application: two layers, one truth

The employer's pipeline and the worker's timeline are **different things**. Conflating them is
the standard industry mistake and the reason applications disappear into silence.

| Layer | Owner | Mutability |
|---|---|---|
| `applications.stage_id` | Employer, fully configurable | Employer moves it |
| `applications.state` | System | **Derived**, never set directly by the employer |

Every `job_stages` row declares `maps_to_state`. `omelo_sync_application_state()` recomputes
the visible state on every stage move. The employer names and orders their stages freely:

```
Google's pipeline                A restaurant's pipeline
------------------------         ------------------------
New            -> applied        New          -> applied
Recruiter Screen -> screening    Phone Call   -> screening
Take-home      -> screening      Trial Shift  -> interview
Tech Interview -> interview      Manager      -> interview
System Design  -> interview      Hire         -> hired
Final / Onsite -> final_interview
Offer Approval -> offer
Hired          -> hired
```

Both are real, both are supported, and neither can hide movement from the candidate.

**Verified:** moving an application to a stage named "Trial Shift" produced candidate state
`interview` and two immutable event rows, with no application code involved.

### 6.1 Invariants

- `viewed` is written by `omelo_mark_application_viewed()`, the only path to opening an application. It cannot be suppressed.
- Every transition appends to `application_events`. `UPDATE` and `DELETE` are revoked; no RLS policy exists for them. Append-only by absence.
- No silent termination. Inactive applications transition to `expired` with notice.
- `withdrawn` is available to the worker from any non-terminal state.

---

## 7. The hiring loop

```
offers.status = 'accepted'
        |
        v
   employments row
        |
        +--> experiences row     (is_verified = true, source = 'employer')
        |
        +--> verifications row   (type = 'employment', method = 'employer_confirmation')
```

Implemented as `omelo_employment_to_experience()`, a trigger on `employments`.

**Why this matters strategically.** It is the only feature that makes a worker's Omelo identity
strictly better than their identity anywhere else, and it gets better every time they are hired
through the platform. It is also the reason an employer benefits from completing a hire *on*
Omelo rather than taking the conversation off-platform.

---

## 8. Consent and the document vault

Two mechanisms that a universal platform needs more than a white-collar one does, because the
users are more exposed.

**Documents.** Receiving an application grants an employer **nothing**. Access to any document
requires a live, unrevoked `document_shares` row naming that company. Revocation is immediate.
The RLS policy on `documents` has no path from "has an application" to "can read the passport
scan."

**Blocking.** `blocks` is enforced inside `omelo_is_discoverable_to()`, as a condition of the
query rather than a filter on results. Only the owner can read the table. A blocked employer
gets absence, never a signal — which is what lets an employed person look for work without
their current employer finding them.

---

## 9. Legally restricted criteria

Gender and age criteria in job postings are unlawful in most of the world and lawful, sometimes
mandatory, in a few. A universal platform cannot pretend either fact away.

`job_legal_restrictions` is an **exception table**:

- Default posture is prohibited.
- `omelo_check_legal_restriction()` raises unless `country_policies` explicitly permits it for that country.
- Enabling it requires a recorded `legal_basis` and an approver.
- **These fields are never usable as matching features.**

This is the most legally dangerous element in the product. It is modelled as a guarded
exception precisely so nobody can reach for it casually.

---

## 10. Modelling rules

1. Never store a title as a profession. Store both.
2. Never store a skill as a string. Always an edge to a canonical `skills` row.
3. Never store money as a bare number. Always amount + currency + period + basis.
4. Never store a country as free text. Always a code or `locations` reference.
5. Never overwrite application state. Append an event; derive the state.
6. Never add a profession-specific column. Declare a `profile_attribute`.
7. Never let a derived store become authoritative. Postgres is the system of record.
8. Every inferred value carries confidence and is user-correctable; corrections are retained.
9. Unknown means unknown. Never "no."

---

## Decision log

| Decision | Rationale |
|---|---|
| Category → Profession as one universal tree | An electrician and an engineer are the same kind of object; separate hierarchies would fork the whole product |
| Adaptive attributes rather than per-profession tables | Adding a profession is data, not a migration |
| Attributes shared between profile and job requirements | Symmetry is what makes matching on them possible |
| `experiences.company_id` nullable | Informal and self-employed work is real work |
| Licences as a first-class table | For a large share of the workforce, the licence is employability |
| Stage → state mapping enforced by trigger | Makes application transparency structural, not a policy someone must remember |
| Hire writes verified experience automatically | The only compounding mechanism in the product |
| Documents require explicit per-employer shares | Receiving an application must never imply access to identity documents |
| Gender/age as a guarded exception, prohibited by default | Unlawful nearly everywhere; must be hard to reach and impossible to use for matching |
