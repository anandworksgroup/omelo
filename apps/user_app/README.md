# Omelo — User App (Flutter)

Worker-facing mobile app. Spec: [`architecture/A1-user-app.md`](../../architecture/A1-user-app.md)

## Run

```bash
flutter run
```

Supabase URL and publishable key default to the live project in
`lib/core/env.dart`. Override at build time:

```bash
flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
```

The **service role key must never appear in this app.**

## Built so far

| Screen | Spec | State |
|---|---|---|
| Language / Country / Welcome | A1 §3 | Working, backed by `languages` + `country_policies` |
| Discover (nearby, search, filters) | A1 §6 | Working, backed by `omelo_nearby_jobs` |
| Job detail | A1 §7 | Working |
| Home | A1 §5 | Working (signed-out variant) |
| Applications / Messages / Profile | A1 §9-11 | Not built — screens state so honestly |
| Phone auth | A1 §3 | Not wired |

## Key behaviours already enforced

- Jobs are visible **before** sign-up (UC-1) — `omelo_nearby_jobs` is callable by `anon`.
- Pay always renders with its period; daily wage never shown as monthly.
- Empty results auto-widen the radius and say so, rather than showing "no jobs".
- The search origin is always displayed, so an empty list is explainable.
- Anti-fraud notice is persistent and non-dismissible on every job.

## Test

```bash
flutter test
```
