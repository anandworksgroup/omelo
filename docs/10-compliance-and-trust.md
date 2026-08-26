# 10 — Compliance & Trust

**Status:** Frozen (Phase 0)
**Owner:** Legal + Engineering + Trust & Safety

> **This document describes design obligations, not legal advice.** Every regulatory position
> below requires review and sign-off by qualified counsel in each operating jurisdiction
> before launch. Its purpose is to ensure the architecture can *satisfy* those obligations,
> because several of them cannot be retrofitted.

---

## 1. Why this document exists at Phase 0

Omelo operates in two of the most heavily regulated categories of software simultaneously:

1. **Personal data at scale**, across jurisdictions, including career and employment history.
2. **Automated decision support in employment** — explicitly designated high-risk in the EU and separately regulated in several US jurisdictions.

Three obligations in particular are **structurally impossible to add later**:

| Obligation | Why it cannot be retrofitted |
|---|---|
| Score reproducibility and explainability | Requires storing the feature vector and engine version *at the time the score was shown*. Historical scores cannot be reconstructed after the fact. |
| Absence of protected attributes | Once collected, they exist in backups, logs, derived stores, and model training data. Never collecting them is the only clean guarantee. |
| Data residency | Regional separation of a live global database is a multi-quarter migration with a long tail of derived stores. |

This is the entire reason the specification freeze precedes implementation.

---

## 2. Regulatory landscape

Positions below are **design assumptions** pending legal review.

### 2.1 GDPR / UK GDPR — EU and UK

| Obligation | Omelo implementation |
|---|---|
| Lawful basis | Candidate data: consent + contract performance. Employer data: contract. Marketing: separate consent. |
| Purpose limitation | Identity data used for matching, career intelligence, and applications the user initiates. **Never sold, never used for unrelated advertising.** |
| Data minimisation | No protected attributes ([03 §6](03-database-schema.md)). No collection without a stated product purpose. |
| Right of access | Self-service export, no ticket (FR-710) |
| Right to rectification | Every inferred field is user-correctable (FR-201) |
| Right to erasure | Self-service deletion propagating to all derived stores (FR-711) |
| Right to portability | Structured JSON export (FR-142) |
| **Art. 22 — automated decisions** | See §3 below |
| Transparency | Plain-language explanation of matching, reachable from every score (FR-714) |
| DPIA | Required before launch. Recruitment matching at scale meets the threshold. |
| Breach notification | 72-hour process, documented, rehearsed |
| Processor agreements | DPAs with every subprocessor, including AI providers |

### 2.2 EU AI Act

AI systems used in employment — recruitment, candidate filtering, and evaluation — fall within
the Act's high-risk category. Design assumptions:

| Obligation | Omelo implementation |
|---|---|
| Risk management | Documented, maintained, reviewed on every engine change |
| Data governance | Taxonomy stewardship; documented training and evaluation data ([07 §11](07-ai-architecture.md)) |
| Technical documentation | This specification set plus per-release engine documentation |
| **Record-keeping** | `matches.feature_vector`, `engine_version`, `automated_decision_log` |
| **Transparency to users** | Candidates are told when automated ranking is used, and how |
| **Human oversight** | Rejection requires a human actor (FR-514); ranking never auto-rejects |
| Accuracy and robustness | Calibration monitoring; adversarial testing in CI |
| Post-market monitoring | Marketplace-health and adverse-impact metrics |

The deterministic-score rule ([07 §1](07-ai-architecture.md)) is what makes record-keeping and
transparency achievable at all. A non-deterministic scorer cannot produce a reproducible record.

### 2.3 NYC Local Law 144 (and similar AEDT regimes)

Jurisdictions including New York City regulate automated employment decision tools, typically
requiring independent bias auditing and candidate notice.

| Obligation | Omelo implementation |
|---|---|
| Annual independent bias audit | Feature registry, weight profiles, and outcome data are all exportable for audit — by design |
| Public audit summary | Published |
| Candidate notice | Disclosed before use, with the criteria considered |
| Alternative process | Human review available on request (FR-715) |

The feature allowlist ([08 §4.5](08-matching-engine.md)) is what makes an audit tractable: an
auditor can enumerate every input to every score.

### 2.4 Other jurisdictions

| Jurisdiction | Key obligations | Design implication |
|---|---|---|
| **India (DPDP Act)** | Consent notice, data principal rights, breach notice | Consent management; localisation configurable |
| **Australia (Privacy Act)** | APPs, notifiable breaches | Standard controls |
| **Brazil (LGPD)** | GDPR-like rights | Same machinery as GDPR |
| **Canada (PIPEDA)** | Consent, access, accuracy | Same machinery |
| **US states (CCPA/CPRA and successors)** | Access, deletion, opt-out of sale/sharing | We do not sell personal data; a global opt-out signal is honoured |
| **Pay transparency** (EU directive, several US states, others) | Salary disclosure in postings | FR-311, enforced per jurisdiction at publication |
| **Non-discrimination law** (broadly) | Prohibited criteria in postings and selection | FR-507 pre-publication screening |

Country-specific rules are **configuration**, not code branches (FR-725). A new market is a
configuration exercise plus legal review, not an engineering project.

---

## 3. Automated decision-making — the central position

GDPR Art. 22 restricts decisions based *solely* on automated processing that produce legal or
similarly significant effects. Employment decisions plainly qualify.

**Omelo's position:**

| Omelo does | Omelo does not |
|---|---|
| Rank and recommend | Reject candidates automatically |
| Apply factual eligibility gates (right to work, explicit knockout answers) | Apply preference-based automated exclusions |
| Explain every score | Present opaque scores |
| Log every automated ranking shown | Discard the basis of a ranking |
| Provide human review on request | Make ranking the final word |
| Require a human actor for every rejection (FR-514) | Offer employers automated rejection rules |

Employers will ask for automated rejection rules. The answer is no, and the reason is
substantive, not merely legal: an automated rejection rule converts every scoring bug into a
silent, unappealable, undetectable harm — the exact failure mode this architecture exists to
prevent.

### 3.1 Candidate-facing transparency

At every score, one tap away:

```
How this match was calculated

  Your match: 96%

  What we compared
    Required skills          5 of 6 matched          weight: high
    Experience               4 yrs, role asks 3-7    weight: high
    Occupation fit           adjacent role           weight: medium
    Location                 you're open to moving   weight: medium
    Compensation             85% range overlap       weight: low

  What we never use
    Age, gender, ethnicity, religion, marital status,
    photo, name, employment gaps, or your school's ranking.

  This score ranks opportunities for you. It does not
  decide whether you're hired — a person at the employer does.

  [ Request human review ]        [ How matching works ]
```

---

## 4. Data retention

| Data | Retention | Basis |
|---|---|---|
| Active identity | While account is active | Contract |
| Deleted account | Hard-deleted after 30-day grace; derived stores purged | Erasure |
| Applications (candidate view) | Deleted with the account | Erasure |
| Applications (employer hiring record) | Retained per local employment law; **candidate PII stripped** | Legal obligation |
| Messages | With the account; other party retains their own record | Contract |
| Verification documents | Deleted immediately after verification completes; only the *result* persists | Minimisation |
| Match feature vectors | 24 months, or longer if displayed and subject to audit | AI Act record-keeping |
| Audit log | 24 months hot, then archived pseudonymised | Accountability |
| `automated_decision_log` | Duration of AEDT audit obligations | Bias audit |
| Aggregate analytics | Indefinite, only after irreversible aggregation | Legitimate interest |

Verification documents deserve emphasis: they are the highest-risk data Omelo touches and the
easiest to over-retain. Store the *verified claim*, not the passport scan.

---

## 5. Verification and platform integrity

### 5.1 Company verification

Two independent signals before posting or talent search ([05 §2.1](05-company-portal-flows.md)).
Talent search is **never** available to an unverified company.

### 5.2 Fraud patterns actively screened

| Pattern | Action |
|---|---|
| Requests for payment from candidates | Block posting; suspend account; warn affected candidates |
| Collection of bank or identity-document details in the hiring flow | Block; investigate |
| Redirection to external messaging apps early in the process | Warn candidate; flag for review |
| Compensation far outside the market band for the profession and location | Manual review before publication |
| Newly created company with high-volume posting | Rate limit; manual review |
| Job description copied from another posting | Dedupe; investigate |
| Reshipping, money-mule, and package-forwarding roles | Block category |

### 5.3 The persistent candidate warning

Shown in every conversation and application flow (FR-702):

> Omelo will never ask you to pay to apply, interview, or start a job. No legitimate employer
> will ask for bank details, identity documents, or payment during hiring. **Report it.**

This is the single highest-value anti-fraud control available, because it works even when
detection fails.

### 5.4 Candidate-side integrity

| Pattern | Action |
|---|---|
| Fabricated employment at a verified company | Employer dispute route; verification revoked; flagged |
| Skill keyword stuffing | Evidence weighting reduces its effect ([08 §4.4](08-matching-engine.md)); anomaly detection |
| Duplicate accounts | Detection and merge or suspension |
| Automated mass application | Rate limits; behavioural detection |

Note the asymmetry deliberately: candidate-side enforcement is corrective, employer-side
enforcement is preventive. Employers hold the power in this market, and a false accusation
against a candidate is far more damaging to them than a false accusation against a company.

---

## 6. Harassment and conduct

| Control | Implementation |
|---|---|
| Report | One tap from every message and profile (FR-425) |
| Block | Unilateral, permanent, undetectable to the blocked party (FR-424) |
| Screening | Automated detection of discriminatory, sexual, or coercive language in outreach |
| Response SLA | Reports triaged within 24 hours; harassment reports within 4 hours |
| Recruiter accountability | Report rates affect outreach quota and company standing |
| Evidence preservation | Reported threads preserved for investigation regardless of deletion |

Trust & Safety access to message content is limited to reported threads and is itself logged
([06 §2.3](06-permissions-and-rbac.md)).

---

## 7. Pre-launch checklist

None of these are optional, and all of them gate Phase 1 launch.

- [ ] DPIA completed and signed off
- [ ] Legal review per launch jurisdiction
- [ ] EU AI Act high-risk assessment and technical documentation
- [ ] Bias audit methodology defined; baseline established
- [ ] DPAs with every subprocessor, including AI providers
- [ ] Data residency verified end to end, including derived stores and backups
- [ ] Deletion pipeline tested against every derived store, with proof of purge
- [ ] Export tested for completeness
- [ ] Retention schedule implemented and automated
- [ ] Breach response plan documented and rehearsed
- [ ] Terms of service, privacy policy, and AEDT notice published
- [ ] Trust & Safety staffed with defined SLAs
- [ ] Fraud screening live and tested against known patterns
- [ ] Every `job_sources` entry has a documented `contract_ref`
- [ ] Feature registry reviewed and signed off
- [ ] Adversarial AI test suite passing in CI
- [ ] Accessibility audit (WCAG 2.2 AA)
- [ ] Penetration test completed and findings resolved

---

## 8. The trust thesis

Every control in this document costs something — conversion, employer satisfaction, or
engineering time. They are worth it because Omelo's entire proposition depends on people
volunteering the most sensitive professional information they have.

The specific bet:

> A candidate will build a complete, honest, structured professional identity **only if they
> believe it will not be used against them.**

Which requires, concretely: their current employer cannot find them, a machine cannot silently
reject them, they can see exactly why they were ranked, and they can take it all back at any
moment.

Every competitor in this market has, at some point, traded candidate trust for employer
revenue. The trade is available, it works in the short term, and it is the reason candidates
approach all of these platforms with suspicion.

Not making that trade is the product.

---

## Decision log

| Decision | Rationale |
|---|---|
| Compliance designed at Phase 0, not retrofitted | Reproducibility, attribute absence, and residency cannot be added to a live system |
| No automated rejection, ever | Converts every scoring bug into a silent, unappealable harm |
| Protected attributes never collected | Absence is the only clean guarantee once backups and derived stores exist |
| Verification documents deleted after use | Highest-risk data; store the claim, not the scan |
| Talent search gated on verification with no exceptions | An unverified account with search access is a harvesting vector |
| Blocking is undetectable to the blocked party | A detectable block endangers the employed candidate it protects |
| Candidate enforcement corrective, employer enforcement preventive | Power asymmetry makes false accusations against candidates far more damaging |
