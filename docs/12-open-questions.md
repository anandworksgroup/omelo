# 12 — Open Questions

**Status:** Live — the only document expected to change frequently.

Each question has an owner and a gate. **Blocking** questions must close before the work they
gate begins.

---

## Blocking — must close before application code

### Q1 — Launch country, city, and categories

**Owner:** Product · **Needed by:** Phase 1b kickoff

Everything downstream depends on it: which locations to seed, which licence types matter, which
country policy applies, which categories to tune weight profiles for, and which languages to
localise first.

**Recommendation:** one metro in a high-volume market, with **Delivery, Warehousing, Retail,
Food & Restaurant, and Security**. Continuous hiring, cycles measured in days, simple
requirements, and the workers nobody serves well.

Adding Technology later is easy. Starting with Technology is how this becomes a tech job board.

**Needed:** one country, one metro, three to five categories, named.

---

### Q2 — Embedding model and dimensionality

**Owner:** Engineering · **Needed by:** before any real data lands — **currently free to change**

`vector(1536)` is a placeholder on `persons`, `jobs`, `skills`, and `professions`. Changing
dimensionality after data exists requires re-embedding everything.

Decide: provider, model, dimensionality, **multilingual capability (required — job content will
not be English)**, regional endpoint availability for residency, and cost per million tokens at
projected volume.

Note that Omelo's semantic retrieval must work on short, informal, multilingual text
("delivery boy needed, own bike"), not only well-formed English job descriptions. Evaluate on
that, not on a benchmark of clean corporate postings.

---

### Q3 — Location data source

**Owner:** Engineering · **Needed by:** before seeding

`locations` is empty. Geospatial discovery is a Phase 1b P0 (FR-908) and cannot ship without a
gazetteer covering the launch country down to district or neighbourhood level, with
coordinates.

Options: an open geographic dataset, a commercial geocoding provider, or a government dataset
for the launch country. Licence terms for commercial use and redistribution must be checked.

**Blocking because** the entire nearby-jobs experience — the primary discovery mode for the
launch categories — depends on it.

---

### Q4 — Verification provider for licences and identity

**Owner:** Legal + Engineering · **Needed by:** Phase 1b

Licence verification is the highest-value trust feature for W-C (tradespeople) and W-B, and the
hardest to source. Options per country: issuing-body API, a third-party verification vendor, or
manual document review.

Also required: the second company-verification signal (business registry data or manual review).

**Blocking because** verification gates job posting and talent search. A slow or low-coverage
provider becomes an onboarding bottleneck discovered at the worst moment.

---

### Q5 — Skills taxonomy source and licence

**Owner:** Product + Legal · **Needed by:** before skill seeding

`skills` is empty — professions are seeded, skills are not. Needed: a source covering **trades
and manual work**, not only knowledge work. Most open skills taxonomies are far richer for
software than for masonry.

Check commercial-use, extension, and redistribution terms. Re-seeding after identities exist
means remapping every `person_skill` and `job_skill` edge.

---

### Q6 — Legal entity, jurisdiction, and DPO

**Owner:** Founder + Legal · **Needed by:** before processing any personal data

Establishment jurisdiction, whether a DPO is required, EU representative if applicable, lead
supervisory authority. Determines the compliance configuration in
[10](10-compliance-and-trust.md) and the DPIA scope.

---

## High priority — during Phase 1b

### Q7 — Monetisation model

**Owner:** Product + Founder

Worker side is free. Non-negotiable: charging workers in this market is both a trust failure and
adjacent to the exact fraud pattern Omelo screens for.

Employer side: per-posting, subscription seats, success fee, or talent-search entitlement?

**The model shapes behaviour.** Per-application pricing pushes employers to restrict
applications. Per-hire pricing pushes hiring off-platform — which breaks the verified-employment
loop that is Omelo's compounding advantage. Subscription is the most neutral with respect to
PR-6 and PR-7. Choose the model that does not fight the product.

Also unresolved: E-A, a restaurant hiring one cook, cannot be sold a seat licence. There
probably needs to be a genuinely free tier for very small employers, paid for by volume
employers.

---

### Q8 — Pay normalisation constants per country

**Owner:** Product + Data

F7 in [08 §4.2](08-matching-engine.md) converts between pay periods and needs assumed hours per
week and days per month where a job does not state them. These vary by country and by category.

Wrong constants make hourly and daily-wage jobs rank incorrectly against monthly ones — a
failure that would hit exactly the workers Omelo exists for, and would be invisible in an
aggregate metric.

**Needed:** per-country, per-category defaults, sourced and documented.

---

### Q9 — Match score display granularity

**Owner:** Product + Design

Exact percentage, bands, or both?

**Recommendation:** exact percentage on the worker side, paired with mandatory reasons; bands on
the employer side, to discourage treating a ranking as a measurement and to reinforce that a
human decides.

Additional consideration for this audience: a bare "62%" reads as a personal verdict to someone
already anxious about employability. The reasons are not decoration — they are what make the
number safe to show at all.

**Needed before UI work begins.**

---

### Q10 — Application expiry window

**Owner:** Product

FR-333 requires automatic expiry. Too short insults employers with slow but genuine processes;
too long makes the timeline useless.

**Recommendation:** per-employer, derived from their observed median response time, with a floor
and ceiling, disclosed to the worker up front. A single global window will be wrong in both
directions for most employers — a warehouse decides in two days, a hospital in six weeks.

---

### Q11 — Pay data sourcing

**Owner:** Product + Data

Every pay figure must state its source. Phase 1b can honestly use only Omelo's own postings,
which is thin at launch.

**Recommendation:** posting-derived only, with sample size shown, and no figure below a minimum
sample. Honest absence beats a confident wrong number — and pay is the field users will most
quickly catch us being wrong about.

---

### Q12 — Localisation depth for launch

**Owner:** Product

20 languages are seeded, but seeded is not translated. Which languages ship fully localised in
Phase 1b, including the taxonomy?

Note that `profession_aliases` and `skill_aliases` carry a `locale` column: a worker should be
able to search in their own language and match a job posted in another. That is a
differentiator for W-D and W-B, and it is real work.

---

### Q13 — Fraud screening thresholds

**Owner:** Trust & Safety

`fraud_signals` has severity but no calibrated thresholds. Needed before launch: what triggers
warning, review, rate-limiting, and suspension.

Over-blocking kills employer supply in a marketplace that has none yet. Under-blocking harms
people who cannot absorb the loss. This needs a written, revisitable position rather than
case-by-case judgement.

---

## Medium priority — Phase 2+

### Q14 — Learning partner model
FR-205 routes gaps to closure routes. Affiliate, integrated, or informational? An affiliate
model creates an incentive to overstate gaps, corrupting the most trust-dependent surface in the
product. **Owner:** Product.

### Q15 — Assessment strategy
Build, integrate, or neither? Assessments raise real validity and adverse-impact questions,
particularly for manual work where a trial shift is both more predictive and more honest.
**Owner:** Product.

### Q16 — Company reviews
Deferred at Phase 0. When, and with what moderation and defamation posture? Employer-review
features are valuable to W-B and W-D and legally hazardous everywhere. **Owner:** Product + Legal.

### Q17 — Learned re-ranking
Can a learned model re-rank *on top of* the deterministic score without breaking explainability
or AI Act record-keeping? Possible if it consumes only registry features and its contribution is
itself bounded and explainable. **Owner:** Engineering + Legal.

### Q18 — Network depth
How far can P6 go before it violates PR-1 and becomes a social feed? Needs a written test, not a
judgement call made under growth pressure. **Owner:** Product.

### Q19 — Design system
Build, adopt, or extend? Affects Flutter and Next.js, and WCAG 2.2 AA conformance is far easier
to guarantee from one shared token and component layer. Additional constraint: the user app must
be legible on low-end Android devices and small screens, and usable at large text sizes.
**Owner:** Design.

---

## Closed

| Question | Decision | Recorded in |
|---|---|---|
| Professional network or universal employment platform? | Universal employment platform | [00](00-vision-and-scope.md) |
| Separate schema named `omelodb`? | No — hosted Supabase allows one database; the schema lives in `public` | [`sql/README.md`](../sql/README.md) |
| How does one profile serve every trade? | Adaptive `profile_attributes` resolved by `omelo_profile_schema_for()`; no profession-specific columns | [02 §3](02-domain-model.md) |
| Graph database or relational? | Postgres with edge tables, `pgvector`, and PostGIS | [02](02-domain-model.md) |
| Does the LLM produce match scores? | No. Deterministic only. | [07 §1](07-ai-architecture.md) |
| Talent search opt-in or opt-out? | Opt-in, default `private`, revocable, with an undetectable employer blocklist | [06 §4](06-permissions-and-rbac.md) |
| Can employers hide application progress? | No. Stages map structurally to visible states. | [02 §6](02-domain-model.md) |
| Automated rejection for employers? | Never. Human actor required. | [10 §3](10-compliance-and-trust.md) |
| Gender and age criteria on postings? | Prohibited by default in every country; guarded exception requiring recorded legal basis; never a matching feature | [02 §9](02-domain-model.md) |
| Do documents flow to employers on application? | No. Explicit, revocable, per-employer shares only. | [06 §4.3](06-permissions-and-rbac.md) |
| Is a resume required to apply? | No. Quick apply exists; `requires_resume` defaults to false. | [01 FR-913](01-product-requirements.md) |
| Job aggregation by scraping? | No. ATS integrations, official feeds, direct posting, contracted partners. | [09 §4](09-system-architecture.md) |
