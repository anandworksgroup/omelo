# Omelo — Company Portal (Next.js)

Employer web app. Spec: [`architecture/A2-company-portal.md`](../../architecture/A2-company-portal.md)

## Run

```bash
npm run dev --prefix apps/company_portal
```

Then open http://localhost:3000

Config lives in `.env.local` (publishable key only — the **service role key must
never appear in this app**).

## Demo account

```
sarah@zippylogistics.in  /  (password in DEMO_ACCOUNTS.local.md at the repo root)
```

Owns *Sector 18 Kitchens* with one published job and one real applicant.

## Built so far

| Screen | Spec | State |
|---|---|---|
| Landing | A2 | Working |
| Sign up / sign in | A2 §3 | Working (email + password) |
| Company onboarding | A2 §3 | Working — creates company, auto-grants owner + free tier |
| Dashboard | A2 §4 | Working — real stats, stale-application banner |
| Jobs list | A2 §5 | Working |
| Job wizard | A2 §5.1 | Working — 6 steps, live pool + pay benchmark |
| Job detail / publish | A2 §5 | Working — publish, pause, close |
| Company profile | A2 §12 | Working — edit, hiring stats, team list |
| Candidates | A2 §7 | List only. Opening, stage moves, messaging and rejection not built. |
| Talent search | A2 §8 | Not built — Phase 3, gated on verification |

## Behaviours already enforced

- **Free tier has talent search disabled.** It stays off until the company is verified.
- **Pipeline stages map to fixed candidate-visible states.** An employer names stages freely but cannot invent or hide a state.
- **Requirements show their cost** — the wizard reports how many workers match as you edit.
- **The pay benchmark refuses to show a range from too few samples** rather than inventing one.
- **A job cannot be published on-site without a location**, because workers find work by distance.
- Server components read as the **signed-in user**, never the service role, so a missing RLS policy fails loudly in development.

## Gotchas worth knowing

- `work_identities → professions` must be embedded as
  `professions!work_identities_profession_id_fkey(...)`. Unqualified, PostgREST
  returns HTTP 300 because there is also a many-to-many path through
  `person_professions`.
- Never destructure only `{ data }` from a Supabase query. An error yields
  `data: null`, which renders as an empty list and looks exactly like "no rows".
  That is how a silent regression ships — check `error` too.

## Build

```bash
npm run build --prefix apps/company_portal
```
