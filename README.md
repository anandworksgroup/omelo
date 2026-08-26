# OMELO

**A universal employment platform.**

Omelo is where a person's work identity, jobs, companies, applications, hiring and career
growth live in one place — for **every** kind of work.

> Omelo must work equally well for a software engineer, a doctor, a teacher, a driver, an
> electrician, a construction worker, a chef, a security guard, a delivery worker, an
> accountant, a factory worker, a student, a freelancer, a domestic worker, a manager, an
> executive, and someone looking for their first job.

Not a professional networking app. Not a white-collar job board with blue-collar roles bolted
on. One platform, one schema, every trade.

---

## Status

| Phase | State |
|---|---|
| **Phase 0 — Specification** | Frozen |
| **Phase 1 — Database** | **Deployed.** 87 tables live on Supabase, RLS on all of them, taxonomy seeded, hiring loop and multi-identity model verified end to end |
| **Phase 1 — Architecture** | **Frozen.** Four documents in [`architecture/`](architecture/) |
| **Phase 1 — Applications** | Not started |

Database: [`sql/README.md`](sql/README.md) · project `jfyqnlucoraazjkndbvm` · schema `public`

---

## Phase 1 architecture

Build against these four. They are the contract between the specification and the code.

| # | Document | Covers |
|---|---|---|
| **A1** | [User App (Flutter)](architecture/A1-user-app.md) | Five tabs, entry, onboarding, discovery, apply, timeline, adaptive profile, identity switcher, complete CTA map |
| **A2** | [Company Portal (Web)](architecture/A2-company-portal.md) | Onboarding, verification, job wizard, pipeline, candidates, talent search, interviews, offers, team, complete CTA map |
| **A3** | [Database](architecture/A3-database.md) · [full table reference](architecture/A3-database-tables.md) | The deployed schema — every table, column, key, enum, index, constraint and relationship |
| **A4** | [Backend & Security](architecture/A4-backend-security.md) | Supabase topology, RLS, roles, storage, Edge Functions, notifications, search, AI matching |

---

## The core model

```
PERSON
  |
  v
WORK IDENTITY  ---- may be almost empty at signup; Omelo builds it progressively
  |
  +-- Skills          +-- Licences
  +-- Experience      +-- Availability
  +-- Education       +-- Preferences
  +-- Documents       +-- Goals
  |
  v
OPPORTUNITY
  |
  v
APPLICATION --> INTERVIEW --> OFFER --> HIRED
                                          |
                                          v
                                     EMPLOYMENT
                                          |
                                          v
                              VERIFIED WORK EXPERIENCE
                                          |
                                          v
                                 NEXT OPPORTUNITY
```

That last loop is the product. A hire made on Omelo becomes verified work history, which makes
the person more employable next time. It is implemented, not aspirational — see
`omelo_employment_to_experience()` in [`sql/README.md`](sql/README.md).

---

## Two applications, one platform

```
                         OMELO
                           |
             +-------------+-------------+
             |                           |
        USER PLATFORM              COMPANY PLATFORM
             |                           |
       Flutter Mobile              Web Dashboard
             |                           |
             +-------------+-------------+
                           |
                    OMELO PLATFORM
                           |
       +-------------------+-------------------+
       |                   |                   |
    Identity             Jobs                Hiring
       |                   |                   |
    Skills              Search             Candidates
    Experience          Matching           Applications
    Education           Discovery          Interviews
    Documents           Alerts             Offers
    Verification        Applications       Employees
       |                   |                   |
       +-------------------+-------------------+
                           |
                    AI / MATCHING
                           |
                     OMELO DATABASE
```

Plus a third surface, [Platform Admin](docs/13-platform-admin.md), which a global marketplace
cannot operate without.

---

## Specification index

| # | Document | What it decides |
|---|---|---|
| 00 | [Vision & Scope](docs/00-vision-and-scope.md) | What Omelo is, principles, glossary, phase gates |
| 01 | [Product Requirements](docs/01-product-requirements.md) | Personas across every collar, numbered requirements, NFRs |
| 02 | [Domain Model](docs/02-domain-model.md) | Work identity, the adaptive profile, category/profession spine |
| 03 | [Database Schema](docs/03-database-schema.md) | The deployed schema, table by table, and what it enforces |
| 04 | [User App Flows](docs/04-user-app-flows.md) | Five tabs, onboarding, discovery, apply, timeline, profile |
| 05 | [Company Portal Flows](docs/05-company-portal-flows.md) | Onboarding, job wizard, pipeline, talent search, offers |
| 06 | [Permissions & RBAC](docs/06-permissions-and-rbac.md) | Roles, matrix, consent layer, RLS enforcement |
| 07 | [AI Architecture](docs/07-ai-architecture.md) | Seven subsystems, guardrails, model routing |
| 08 | [Matching Engine](docs/08-matching-engine.md) | Gates, retrieval, deterministic scoring, explanation |
| 09 | [System Architecture](docs/09-system-architecture.md) | Stack, services, ingestion, residency |
| 10 | [Compliance & Trust](docs/10-compliance-and-trust.md) | GDPR, AI Act, AEDT law, fraud, retention |
| 11 | [Roadmap](docs/11-roadmap.md) | Phases and exit gates |
| 12 | [Open Questions](docs/12-open-questions.md) | Decisions still owed |
| 13 | [Platform Admin](docs/13-platform-admin.md) | The third surface: moderation, taxonomy, fraud, countries |

---

## Five rules that constrain everything

**1. Every person is a talent, not a "professional."**
A 19-year-old looking for their first restaurant job matters exactly as much as a 40-year-old
software architect. Terminology, defaults, and required fields all follow from this.

**2. The profile is adaptive, never one-size-fits-all.**
A driver is asked about vehicle classes. A nurse about specialisations. An engineer about their
stack. Nobody is asked all three. There are **no profession-specific columns** anywhere —
`profile_attributes` declares what applies, `omelo_profile_schema_for()` resolves it.

**2b. A person can hold several kinds of work at once.**
Teacher *and* freelance designer. Driver *and* mechanic. Up to five **work identities** per
person, each with its own profession, pay expectation, availability and — critically — its own
discoverability. One shared set of documents, licences and verifications underneath. See
[A3 §2](architecture/A3-database.md).

**3. Nothing required to participate.**
No degree, no formal employment, no resume, no certifications, no digital literacy assumed. A
person can search, discover and apply with an almost-empty work identity.

**4. The LLM never produces the match score.**
Scores are deterministic, reproducible, and explainable from a stored feature vector. The LLM
extracts, normalises, and explains. It does not decide who is qualified.

**5. Discoverability is opt-in, and employers cannot hide.**
No person appears in talent search without current consent. No employer can invent a
candidate-visible state, suppress a `viewed`, or let an application go silent.

---

## How to change this specification

1. Amend the relevant document. Requirement IDs are permanent — mark superseded ones
   `DEPRECATED`, never renumber.
2. Record the decision and its reasoning in that document's decision log.
3. Schema changes ship as numbered Supabase migrations. No manual production DDL.
