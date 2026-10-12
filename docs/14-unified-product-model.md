# 14 — Unified Product Model

**Status:** Agreed product rule. Implementation waits for R9 verification (§5, step 0).
**Owner:** Product + Engineering
**Repository state reviewed:** `main` at `e40e711` (2026-10-10), migrations up to `82_r10_client_record_needs_the_module`

Omelo has two experiences and one organization model. This document states the rule, records
where the code still departs from it, and sets the order, acceptance criteria and regression
tests for closing the gap. It guides implementation; it is not a reason to pause R9 or to start
the redesign early.

---

## 1. The rule

Omelo is **one User App** and **one Organization Workspace**.

- **User App:** for every individual, whatever their profession. Discover and apply for jobs,
  build a professional profile, network, follow and post, manage interviews and offers, and track
  work, earnings and career growth.
- **Organization Workspace:** for every organization, whatever it needs to do. Public page and
  updates, jobs and hiring, candidates and interviews, team and permissions, clients, staffing
  and workforce, RPO, analytics and billing.

The **organization** is the single business entity. Hiring, recruitment, staffing, workforce
management, client relationships, RPO, billing, the organization page and team management are
capabilities inside that organization. They are not separate products, and they are not
separate organization types that users have to choose between or navigate.

Example: a company starts by publishing jobs and hiring developers. Later it wants to recruit for
its clients, manage contract workers, schedule shifts and invoice clients. It turns those
capabilities on in its existing organization, without creating another organization and without
migrating its data.

### 1.1 One organization model

| Area | Unified approach |
|---|---|
| Organization identity | One organization record and one public page |
| Public presence | About, locations, people, jobs, posts and followers |
| Private operations | Hiring, candidates, interviews, team, clients and workforce |
| Recruitment | Direct hiring, client recruitment, staffing and RPO in the same workspace |
| Financial operations | Worker pay, organization billing and agency fees, as separate secure records |
| Permissions | One consistent role and permission system |
| User identity | A person keeps one personal account and can join multiple organizations |

### 1.2 One workspace navigation

Every organization sees the same areas, in this order, from day one:

1. Overview
2. Organization page
3. Jobs and hiring
4. People and candidates
5. Interviews and scheduling
6. Talent and recruitment
7. Clients and partnerships
8. Workforce and assignments
9. Pay, billing and finance
10. Posts and communications
11. Analytics and reports
12. Team, roles and permissions

What a member can do in an area is decided by **setup** (has the organization set the
capability up?), **permissions** (does this member's role allow the action?) and **business
rules** (has the client confirmed the relationship, has the worker consented?). It is never
decided by whether the organization is labelled a company or an agency. An area that is not set
up yet shows how to set it up; it is not hidden.

An organization may manage direct employees and agency placements at the same time. The
workspace supports both without separate products.

### 1.3 The User App is universal

The User App is for everyone who works, wants work, hires through their personal identity, or
builds a professional network: a software engineer, delivery rider, nurse, recruiter, business
owner or contractor. A person's account is separate from their organization memberships. They can
switch context, and anything done on behalf of an organization requires that organization's
authorization.

---

## 2. Implementation rules

1. **No organization types controlling the product.** Don't build separate company, agency,
   staffing or RPO experiences, and don't let a type field grant, withhold or default a capability.
2. **No duplicate organization records.** One organization uses all capabilities.
3. **One public and one private experience.** The public page represents the organization; the
   private workspace operates it.
4. **One permission system.** Roles and permissions protect sensitive actions without needlessly
   hiding capabilities.
5. **Separate financial concepts.** Worker earnings, client invoices, agency fees and negotiated
   rates stay distinct, access-controlled records.
6. **No automatic disclosure.** Confidential client details, candidate information and private
   employment terms never become visible merely because every module shares one organization.
7. **No forced recreation.** An organization adds capabilities later without starting over.
8. **Preserve the existing implementation.** Extend the current tables, functions and RLS. Don't
   create parallel models. Legacy columns stay where migrations or compatibility need them, but
   they don't drive behavior.

---

## 3. Where the code already follows the rule

Verified at `e40e711`:

- **One sign-up and one onboarding** for every organization (`79_r10_one_onboarding`; the API
  suites create organizations through it).
- **Client-work rules key on the client, not on the organization's type**
  (`77_r10_client_work_not_type`, `78_r10_assignment_offer_follows_client`; invariant 93).
- **The assignment path no longer reads `company_kind`** (`81_r10_stop_reading_kind`).
- **No RLS policy mentions business type** (invariant 92), and **no database function decides
  anything by business type except an explicit allowlist** (invariant 91, see §4.1).
- **Capabilities are a module set on the one organization record** (`company_capabilities`):
  `client_recruitment`, `workforce`, `rpo`, `billing`. Core hiring (page, jobs, candidates,
  interviews, posts, team) is never a capability and comes with every organization (invariant 94).
  Members can't write capabilities directly; they change through Omelo's functions.
- **Client recruitment is a section of the one workspace** (`/dashboard/agency`), no longer a
  separate dashboard for a separate kind of company.
- **Turning a capability on discloses nothing.** A client relationship still needs the client's
  confirmation, and representing a worker still needs the worker's consent
  (`82_r10_client_record_needs_the_module`, `candidate_consents`).

---

## 4. Gaps

### 4.1 Organization type still sets capability defaults

When an organization has no explicit `company_capabilities` row, its `organization_type` decides:

| Capability | On by default for |
|---|---|
| `client_recruitment` | `recruitment_agency`, `staffing_agency`, `rpo_provider`, `workforce_provider` |
| `workforce` | `staffing_agency`, `workforce_provider` |
| `rpo` | `rpo_provider` |
| `billing` | every type except `employer` |

This logic exists twice, and both copies must change together:

- **Database:** `omelo_private.omelo_has_capability`, last defined in
  `77_r10_client_work_not_type`. Invariant 91 currently allowlists it because it "reads the type
  as a DEFAULT, never as a refusal". Under this rule a default is a decision, so the allowlist
  entry goes.
- **Portal:** `apps/company_portal/src/app/dashboard/layout.tsx` (`byType`, mirroring the database)
  and `apps/company_portal/src/app/dashboard/agency/layout.tsx` (its own `byType`).

The portal layout also switches a capability on when matching records exist (clients, workforce
requirements, RPO engagements). Keep that behavior only if the database agrees; otherwise the
navigation and the database can disagree about what an organization may do.

**Migration risk.** Organizations of an agency type that never made an explicit choice currently
rely on the default. Removing it without a backfill would silently switch modules off for them.

### 4.2 Capability areas are hidden until turned on

The capabilities screen (`dashboard/company/capabilities.tsx`) and the workspace layout leave an
area out of the navigation until its capability is on. Under §1.2 every area is always in the
navigation; an area that isn't set up shows its setup state instead.

### 4.3 Remaining type-dependent behavior in the apps

| Where | What it does | Kind |
|---|---|---|
| `dashboard/rpo/page.tsx` | Shows the provider side only if the type is in `RPO_PROVIDER_TYPES` (`lib/enterprise.ts`) | **Decision** |
| `dashboard/agency/actions.ts` | Searches only organizations with `company_kind = 'employer'` as possible clients | **Decision**: any organization can be another's client |
| `dashboard/layout.tsx`, `dashboard/agency/layout.tsx` | Capability defaults by type (§4.1) | **Decision** |
| `onboarding/company-form.tsx`, `dashboard/actions.ts` | Ask the user to choose an organization type at sign-up | **Choice the rule removes** |
| `dashboard/organization/page.tsx`, `org-forms.tsx`, `actions.ts` | Show and edit "What kind of organization this is" (`omelo_set_organization_type`) | Description; must not affect behavior |
| `admin/companies/page.tsx` | Labels and filters organizations as Employer or Agency by `company_kind` | Platform admin reporting; must not affect behavior |
| `lib/supabase/server.ts` | Loads `company_kind` into the workspace context as `kind` | No decision use found; remove or keep for display |
| `dashboard/rpo/actions.ts`, `lib/network.ts`, `apps/user_app/lib/data/network.dart` | Return `organization_type` for display (search results, author cards) | Display |

### 4.4 Names that still say company or agency

People see `company` and `agency` in routes and screens (`/dashboard/company`, `/dashboard/agency`,
`agency-views.tsx`), and the portal app is `apps/company_portal`. Rename what users see during the
redesign. Database names (`companies`, `agency_clients`, `company_capabilities`) can stay: renaming
them would duplicate or churn models for no product gain.

---

## 5. Order of work

**Step 0 — Verify R9 first.** Don't assume R9 is complete because R10 migrations exist. Against
the current code:

| Check | How | Pass |
|---|---|---|
| Database invariants | Run `sql/verify-invariants.sql` against the project database | Every row `OK`, including R9-001 … R9-008 (83–90) |
| R9 end to end | `python tests/api/network_e2e.py` (live API, publishable key, creates `probe.*` accounts) | No `FAIL` lines |
| Other end-to-end suites | Every suite in `tests/api/`, as its docstring says: most run as `python tests/api/<suite>_e2e.py`; `global`, `organization`, `recruitment`, `staffing` and `talent` need `setup` and then `run` | No `FAIL` lines |
| User App | In `apps/user_app`: `flutter analyze`, `flutter test`, `flutter build web --release` (as CI) | Clean |
| Portal | In `apps/company_portal`: `npm run lint`, `npm run build` (as CI) | Clean |
| Edge Functions | The `deno test` / `deno check` commands in `.github/workflows/ci.yml` | Clean |

CI runs the last three on every push. The invariants and end-to-end suites need the live
Supabase project and are run by hand; record the date, commit and result when they are.

**Step 1 — Remove type-based capability defaults** (database and portal together, §4.1).

**Step 2 — One workspace navigation** (§1.2, §4.2).

**Step 3 — Remove the remaining type-dependent behavior** (§4.3).

**Step 4 — Redesign last.** Unify the User App, the public organization page and the private
Organization Workspace, including the naming in §4.4, without duplicating models or weakening
security.

Steps 1–3 are small, backend-led and testable on their own. Step 4 is the UI/UX redesign.

---

## 6. Acceptance criteria

### Step 1 — capability defaults

- `omelo_has_capability` reads only `company_capabilities`. No row means off. It no longer
  mentions `organization_type` or `company_kind`.
- A migration first writes an explicit `company_capabilities` row for every existing
  organization whose effective state comes from the default, so **no live organization gains or
  loses a capability** in the change. The migration reports how many rows it wrote.
- `omelo_has_capability` is removed from invariant 91's allowlist, and 91 passes.
- The portal reads capability state from the database (one source), not from its own copy of the
  rule. `byType` is gone from both layouts.

### Step 2 — one workspace

- Every organization's navigation lists the same twelve areas (§1.2) in the same order.
- An area whose capability isn't set up shows a setup screen; a member without the permission to
  set it up sees who can.
- Turning a capability on still discloses nothing (§2, rule 6); the client-confirmation and
  worker-consent rules are unchanged.

### Step 3 — legacy behavior

- No code path in either app decides what an organization can see or do from `organization_type`
  or `company_kind`. Remaining reads are labelled display-only.
- Any organization can provide RPO when its `rpo` capability is on and the member's role allows it.
- Any organization can be another organization's client.
- Sign-up doesn't ask for an organization type. If the type is kept as a public descriptor, it
  is optional, can be set later, and changes nothing.

### Step 4 — redesign

- One User App and one Organization Workspace; one public organization page.
- People see no "company" versus "agency" split in routes, labels or navigation.
- No new organization, capability or permission tables that duplicate existing ones.
- Every existing invariant and end-to-end suite still passes.

---

## 7. Regression tests to add

**Database (`sql/verify-invariants.sql`):**

- *Capabilities never come from business type.* `omelo_has_capability`'s source doesn't mention
  `organization_type` or `company_kind` (enforced by dropping its allowlist entry in invariant 91).
- *No organization relies on an implicit capability.* For every organization, the effective
  capability set equals its explicit `company_capabilities` rows.

**End to end (`tests/api/`):**

- *Same product for every type.* Create one organization of each legacy `organization_type`
  through the one sign-up. Assert all five have the same capabilities (none on) and the same
  allowed actions for an owner.
- *Add a capability later.* An organization created as `employer` hires directly, then turns on
  `client_recruitment`, `workforce`, `rpo` and `billing`. It gains each workflow without a new
  organization, and its jobs, candidates and team are unchanged.
- *Turning a capability on discloses nothing.* Before the client confirms, the provider can't
  read the client's private data; before the worker consents, the provider can't represent them.
- *Financial records stay separate.* A workforce member sees their own earnings, not the client
  invoice or the agency fee; a client sees its invoice, not the worker's pay rate or the agency's
  margin.
- *Changing the type changes nothing.* Change an organization's `organization_type` and assert
  its capabilities, navigation data and permitted actions are identical before and after.

**Portal and User App:**

- The workspace navigation renders the same twelve areas for organizations of every legacy type.
- The RPO provider view and the client search work for an organization created as `employer`.

---

## 8. Decisions still owed

- Keep `organization_type` as an optional public descriptor ("Recruitment agency" on the
  organization page), or retire it? Either is consistent with this rule as long as it changes
  nothing (§6, step 3).
- Should the existing-records rule in the portal layout (§4.1) become a database rule, or be
  dropped in favour of explicit setup?
