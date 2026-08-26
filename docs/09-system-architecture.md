# 09 — System Architecture

**Status:** Frozen (Phase 0)
**Owner:** Engineering

---

## 1. Recommended stack

| Layer | Choice | Rationale |
|---|---|---|
| **Database** | PostgreSQL 15+ with `pgvector`, `pg_trgm` | One store for graph, relational, and vector ([02 §1.2](02-domain-model.md)) |
| **Platform** | Supabase (Postgres, Auth, Storage, Realtime, Edge Functions) | Ships Phase 1 fast; RLS is first-class; no lock-in at the data layer since it is plain Postgres |
| **API** | TypeScript service layer (Node) with explicit response projections | Primary authorisation point ([06 §5](06-permissions-and-rbac.md)); typed contracts shared with clients |
| **Mobile** | Flutter (Android + iOS) | One codebase, both platforms, and the team's existing strength |
| **Employer web** | Next.js (React) | Data-dense desktop application; SSR for public company and job pages |
| **Public pages** | Next.js SSR/ISR | Job and company pages must be crawlable — organic search is a primary acquisition channel |
| **Search / retrieval** | Postgres (structured + `pg_trgm` + `pgvector`) | One store until it demonstrably breaks |
| **Async jobs** | Queue + workers (ingestion, extraction, embeddings, matching, notifications) | Nothing slow belongs in a request path |
| **AI** | Claude API via the service layer | Never called directly from clients |
| **Object storage** | Supabase Storage / S3-compatible, encrypted | Resumes and verification documents |
| **Realtime** | Supabase Realtime | Chat and timeline updates |

### 1.1 On the Supabase choice

Right call for Phase 1-2, with one condition: **the service layer, not the client, is the
authorisation boundary.**

Supabase makes it tempting to query the database directly from Flutter and Next.js with RLS as
the only guard. Do not do that. Entitlements, rate limits, audience-shaped responses, the
consent predicate, and audit logging all live in the service layer. Direct client-to-database
access is acceptable only for genuinely public reads (published job listings, public company
pages) and realtime subscriptions on rows the user already owns.

Everything else goes through the API.

---

## 2. Service decomposition

Start as a modular monolith with hard internal boundaries. Extract services only when a
specific scaling or team constraint forces it. Premature microservices on a schema this
interconnected produces distributed joins and nothing else.

```
                    +------------------+
                    |   API Gateway    |   authn, rate limit, routing
                    +--------+---------+
                             |
   +-------------+-----------+-----------+-------------+
   |             |           |           |             |
Identity      Job         Match      Messaging      Company
Service     Service     Service      Service       Service
   |             |           |           |             |
   +-------------+-----------+-----------+-------------+
                             |
                    +--------v---------+
                    |    PostgreSQL    |
                    +--------+---------+
                             |
   +-------------+-----------+-----------+-------------+
   |             |           |           |             |
Ingestion    Extraction   Embedding   Notification   Analytics
 Workers      Workers      Workers      Workers       Workers
```

| Module | Owns |
|---|---|
| **Identity** | Person, identity edges, verification, preferences, consent |
| **Job** | Jobs, requirements, stages, ingestion reconciliation |
| **Match** | Gates, retrieval, scoring, explanation, cache |
| **Application** | Applications, events, public-state derivation |
| **Messaging** | Conversations, messages, structured actions |
| **Company** | Companies, members, entitlements, billing |
| **Career** | Paths, gaps, insights |
| **Trust** | Verification, screening, reports, audit |

Boundary rule: modules communicate through published interfaces, never by reaching into each
other's tables. When extraction becomes necessary, the seams already exist.

---

## 3. Request paths

### 3.1 Job search (NFR-01: p95 < 400 ms)

```
Client
  -> API: POST /search/jobs
  -> [cached?] facet resolution (natural language -> facets)
  -> retrieval: structured ∪ semantic ∪ lexical      (parallel)
  -> gates
  -> match cache lookup; score misses inline
  -> rank + diversify
  -> project to SearchResultView
  -> Client
```

Budget: facet resolution ≤ 80 ms (cached: ~0), retrieval ≤ 150 ms, scoring ≤ 120 ms,
serialisation ≤ 50 ms.

Facet resolution is the only LLM call in this path, and it is aggressively cached by query
string. A cache miss must not blow the budget — if resolution exceeds its slice, fall back to
lexical interpretation and mark the facets unconfirmed.

### 3.2 Identity extraction (NFR-04: p95 < 30 s)

```
Upload -> Storage (encrypted)
       -> enqueue extraction job
       -> Client shows progress, remains interactive
Worker: parse -> segment -> extract -> resolve -> validate -> draft
       -> notify client via Realtime
Client: review screens -> confirm -> commit to identity
       -> enqueue embedding refresh
       -> enqueue match recomputation
```

Never synchronous. The client stays usable throughout, and a failed extraction degrades to
guided manual entry rather than a dead end.

---

## 4. Job ingestion — the legal and operational core

"Indeed-like coverage" is an **acquisition and legal** problem before it is a technical one.

### 4.1 Permitted sources, in priority order

| Priority | Source | Mechanism | Notes |
|---|---|---|---|
| 1 | **Direct posting** | Employers post natively | Best data quality — structured at source. The strategic goal. |
| 2 | **ATS integrations** | Greenhouse, Lever, Workday, SmartRecruiters, Ashby, Recruitee APIs | Employer authorises; jobs sync; applications can flow back |
| 3 | **Official feeds** | Employer-published XML/JSON feeds, indexing programmes | Standard, permitted, reliable |
| 4 | **Partner aggregators** | Contracted redistribution | Costs money; contract defines what is permitted |

### 4.2 Not permitted

Scraping job boards or career sites without authorisation. Reasons, in order of how quickly
they will hurt:

1. **Terms of service.** Most job boards prohibit it explicitly.
2. **Litigation and blocking.** A predictable, expensive, ongoing fight.
3. **Data quality.** Scraped postings go stale, duplicate, and misrepresent — directly attacking FR-310 and every match score computed from them.
4. **Trust.** A marketplace built on unauthorised copies of other marketplaces has no employer relationship, and therefore no application feedback loop — which means no hiring timeline (PR-4).

**Every entry in `job_sources` requires a `contract_ref` before it is enabled.** A source
without documented authorisation does not get turned on.

### 4.3 Ingestion pipeline

```
Source (feed / API)
   -> fetch (rate-limited, respecting the source's constraints)
   -> normalise to canonical job shape
   -> deduplicate (company + title + location + description fingerprint)
   -> AI-3 job understanding -> structured requirements
   -> resolve company (existing node or create unverified)
   -> resolve profession, skills, location
   -> embed
   -> upsert; close postings absent from the feed
   -> record ingestion_run
```

Reconciliation rule: a job absent from two consecutive successful syncs is marked `expired`.
Stale postings are the most common failure of aggregation products and the fastest way to
lose candidate trust.

### 4.4 The cold-start sequence

Marketplace order of operations for a launch market:

1. **Jobs first, via ATS integrations.** Candidates will not build an identity for an empty marketplace.
2. **Candidates second**, targeting a specific profession family and geography where job density is already real.
3. **Direct posting third**, sold on match quality and pipeline once candidate supply is demonstrable.
4. **Talent search last**, once candidate density justifies it and consent rates are healthy.

Launching talent search into a thin, low-consent candidate pool burns employer trust exactly
once.

---

## 5. Environments

| Environment | Purpose | Data |
|---|---|---|
| Local | Development | Seeded synthetic only |
| Preview | Per-PR | Synthetic only |
| Staging | Integration, load, AI evaluation | Synthetic + anonymised job data. **Never production personal data.** |
| Production (EU) | EU users | EU personal data, EU region |
| Production (default) | Other regions | Per residency map |

Rule: personal data never leaves production. Debugging uses synthetic reproductions, not
copies of user records.

---

## 6. Data residency

NFR-08. EU personal data is processed and stored in an EU region.

| Data | Residency |
|---|---|
| Identity, applications, messages, verification documents | User's region |
| Job postings, company profiles | Global (not personal data) |
| Taxonomy | Global |
| Embeddings derived from personal data | User's region |
| Aggregate analytics | Global, only after aggregation and pseudonymisation |
| AI processing of personal data | Regional endpoint where available; contractual safeguards documented in the DPA |

Design consequence: **regional partitioning is a Phase 1 schema and routing concern**, not a
Phase 4 migration. Retrofitting residency onto a live global database is among the most
expensive corrections available.

---

## 7. Observability

| Layer | Instrumented |
|---|---|
| Request | Latency by endpoint against NFR budgets; error rates |
| Match | Score distribution, calibration drift, coverage, recall proxy |
| AI | Per-subsystem cost, latency, confidence distribution, fallback rate |
| Ingestion | Per-source freshness, dedupe rate, close-detection accuracy |
| Marketplace health | Applications per job, response rate, time-to-first-response, **silent-application rate** |
| Trust | Report volume, fraud detections, verification throughput |
| Consent | Discoverability opt-in rate, block rate, deletion requests |

Alert on marketplace-health regressions with the same seriousness as on error rates. A rising
silent-application rate is an outage of the product's core promise, even while every service
reports healthy.

---

## 8. Scale plan

| Stage | Scale | Action |
|---|---|---|
| Phase 1 | < 1M identities, < 2M jobs | Single Postgres primary + read replicas |
| Phase 2 | Match table growth | Partition `matches` by `computed_at`; TTL eviction |
| Phase 3 | Search latency pressure | Consider a dedicated search index as a **derived** store |
| Phase 3 | Event volume | Partition `application_events` and `audit_log`; archive cold partitions |
| Phase 4 | Multi-region | Regional primaries; global taxonomy replication |
| Phase 4+ | Deep graph traversal | Evaluate a graph engine as a derived store, never as the system of record |

Every step preserves the single-source rule ([02 §1.3](02-domain-model.md)).

---

## 9. Security posture

| Control | Implementation |
|---|---|
| Transport | TLS 1.3 everywhere |
| At rest | AES-256; verification documents separately encrypted with distinct key access |
| Secrets | Managed secret store; no secrets in code or environment files in the repository |
| Authentication | Email/phone with MFA available; MFA **required** for company Owner and Admin roles |
| Session | Short-lived access tokens, rotating refresh, device tracking |
| Authorisation | Service layer primary, RLS secondary ([06 §5](06-permissions-and-rbac.md)) |
| Rate limiting | Per user, per company, per IP; stricter on search, outreach, and application submission |
| File upload | Type validation, size limits, virus scanning, sandboxed parsing |
| Untrusted content | Resumes and job descriptions treated as adversarial input ([07 §9.2](07-ai-architecture.md)) |
| Dependency hygiene | Automated scanning, pinned versions |
| Access review | Quarterly review of every internal role grant |
| Break-glass | Two-person approval, time-boxed, alerted, logged, disclosed |

---

## Decision log

| Decision | Rationale |
|---|---|
| Supabase + Postgres for Phase 1-2 | Fastest path to a correct implementation; plain Postgres means no data-layer lock-in |
| Service layer is the authorisation boundary, not RLS | RLS cannot express entitlements, rate limits, or audience shaping |
| Modular monolith first | The schema is highly interconnected; premature service splits produce distributed joins |
| Flutter mobile, Next.js employer web | Matches team strength; employer tooling is desktop-shaped and needs SEO-capable public pages |
| No scraping | ToS, litigation, data quality, and the missing employer feedback loop that PR-4 depends on |
| Jobs before candidates in cold start | Nobody builds an identity for an empty marketplace |
| Residency partitioning in Phase 1 | Retrofitting regional data separation onto a live global database is prohibitively expensive |
