# Deploying Omelo

Everything needed to stand up Omelo in a new environment is in this repo.
External accounts (LiveKit, Resend, app stores, hosting) are configured at
deploy time; the code already handles them being absent.

```
supabase/migrations/   database, in order (the exact SQL that runs in production)
supabase/functions/    Edge Functions: auth-signup, meet-token, meet-control, comms-dispatch
supabase/config.toml   CLI config, including which functions skip JWT verification
apps/company_portal/   employer portal (Next.js 16)
apps/user_app/         worker app (Flutter: Android, iOS, web)
sql/verify-invariants.sql   run after every migration — every row must say OK
tests/api/             end-to-end tests against a live project, as real users
```

---

## 1. Supabase project

1. Create a project (Postgres 17). Note the **project ref**, **URL** and the
   **publishable key**. The service role key never leaves Supabase.
2. Link and push the schema:
   ```bash
   supabase link --project-ref <ref>
   supabase db push
   ```
   This applies every migration in `supabase/migrations/` in order, including
   the taxonomy, skills, weight profiles and interview question bank seeds.
3. Point scheduled jobs at this project (migration 33 stores it as data):
   ```sql
   update omelo_private.app_settings
      set value = 'https://<ref>.supabase.co/functions/v1', updated_at = now()
    where key = 'functions_base_url';
   ```
4. Verify: run `sql/verify-invariants.sql` in the SQL editor. **All 36 rows must read OK.**
5. Dashboard settings (not expressible as migrations):
   - **Auth → Passwords:** enable *Leaked password protection*; minimum length 8+.
   - **Auth → URL configuration:** set Site URL to the portal URL; add the
     worker web app URL and the mobile deep-link scheme to redirect URLs.
   - **Database → Backups:** enable PITR for production.
   - **Realtime:** enabled (migrations add the tables to `supabase_realtime`).
   - **Auth → SMTP:** use a custom SMTP server (Resend SMTP works) — the default mailer is heavily
     rate-limited and password-reset emails depend on it.
   - **Auth → URL configuration → Redirect URLs:** add `<portal>/auth/reset`, `<portal>/auth/callback`,
     the worker web URL (`<worker-web>/#/reset-password`) and the mobile scheme
     `com.omelo.app://reset-password`.
6. Grant the first platform admin (unlocks `/admin` system health and KPIs in the portal):
   ```sql
   insert into platform_admins (person_id, role, is_active)
   select id, 'superadmin', true from persons where email = '<you@company.com>';
   ```
7. Talent search is an Omelo-granted capability. A platform admin verifies a company and
   enables it (portal `/admin` → Companies, or SQL): `omelo_admin_set_company_verification(company, true)`
   and `omelo_admin_set_entitlements(company, 'pro', true, <searches per month, 0 = unlimited>,
   <invitations per day, 0 = unlimited>)`. Employers cannot grant it to themselves.
8. Feature flags (`omelo_private.app_settings`): `phone_otp_enabled` (set `true` once an SMS
   provider is wired), `require_verified_email_to_accept_offer` (progressive trust; default `false`).

## 2. Edge Functions

```bash
supabase functions deploy auth-signup meet-token meet-control comms-dispatch
```

`config.toml` makes `auth-signup` and `comms-dispatch` public (each explains
why in its source); the other two require a signed-in user.

### Secrets — Supabase → Edge Functions → Secrets

| Secret | Required for | Behaviour until set |
|---|---|---|
| `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` | Omelo Meet video | Joining returns `503 meet_not_configured`; both apps explain it and the rest of the interview flow (waiting room, questions, feedback, chat) still works. |
| `RESEND_API_KEY`, `EMAIL_FROM` | Email | Emails stay `queued` in `outbound_messages` and send as soon as the key is added. `EMAIL_FROM` must be on a domain verified in Resend. |
| `WORKER_APP_URL` | Links in emails | Defaults to `http://localhost:5173/#`. Use the production worker web URL (keep the `/#` if the web build uses hash routing). |
| `IP_HASH_SALT` | Signup rate limiting | A dev salt is used. Set a long random value in production. |

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are
provided to functions automatically.

LiveKit: create a project at cloud.livekit.io (or self-host LiveKit), then
copy the WebSocket URL, API key and secret. No code change is needed to move
between LiveKit Cloud and self-hosted.

## 3. Employer portal (Next.js)

Any Node 22 host (Vercel, Netlify, a container). Environment:

| Variable | Value |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | `https://<ref>.supabase.co` |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | the publishable key |

```bash
cd apps/company_portal
npm ci && npm run build && npm start
```

Security headers (HSTS, frame denial, camera/microphone limited to the site)
are set in `next.config`. Serve over HTTPS only — browsers require it for
camera and microphone access.

## 4. Worker app (Flutter)

Production builds must pass the production project explicitly — the defaults
in `lib/core/env.dart` point at the development project:

```bash
cd apps/user_app
DEFINES="--dart-define=SUPABASE_URL=https://<ref>.supabase.co --dart-define=SUPABASE_KEY=<publishable key>"

flutter build web --release $DEFINES          # host build/web on any static host (HTTPS)
flutter build appbundle --release $DEFINES    # Google Play
flutter build ipa --release $DEFINES          # App Store (on macOS)
```

- **Android signing:** create `android/key.properties` from
  `android/key.properties.example` (gitignored) pointing at your upload keystore.
- **iOS:** minimum iOS 13 (required by the video SDK). Camera and microphone
  usage descriptions are already in `Info.plist`.
- **Permissions:** camera/microphone are requested only when joining an
  interview; location only for nearby jobs.

## 5. After deploying

```bash
python tests/api/hiring_loop_e2e.py
python tests/api/messaging_e2e.py
python tests/api/meet_e2e.py
python tests/api/account_e2e.py
python tests/api/identity_e2e.py
python tests/api/talent_e2e.py setup   # then apply the SQL it prints (Omelo-only fixture)
python tests/api/talent_e2e.py run
```

Point `tests/api/omelo_api.py` (`BASE`, `KEY`) at the new project first. Each
suite creates throwaway `probe.*` accounts (signup allows 10 per IP per hour)
— remove them afterwards with the SQL in `hiring_loop_e2e.py`. Do not run the
suites against a production project with real users; use a staging project.

With LiveKit keys set, `meet_e2e.py` also verifies the issued video token.

## 6. Launch checklist

- [ ] `verify-invariants.sql` — 36/36 OK
- [ ] Leaked password protection on; Site URL and redirect URLs set
- [ ] `functions_base_url` updated; `select * from cron.job` shows the 4 `omelo-*` jobs
- [ ] First platform admin granted; `/admin` shows healthy cron runs and 0 function failures
- [ ] Custom SMTP configured; password reset email received on portal and worker app
- [ ] Edge Function secrets set (LiveKit, Resend, `WORKER_APP_URL`, `IP_HASH_SALT`)
- [ ] Sending domain verified in Resend; a test invitation email received
- [ ] Two-person Omelo Meet call tested on web, Android and iOS
- [ ] Portal and worker web served over HTTPS
- [ ] Worker app built with production `--dart-define`s; release signing configured
- [ ] Demo accounts and `sql/seed/dev-seed.sql` data NOT loaded in production
- [ ] Email confirmation policy decided (currently accounts are created pre-confirmed)
- [ ] Backups / PITR enabled

## Known limitations at launch

- **Email confirmation is off by design** (accounts are created
  pre-confirmed). Before a public launch, decide whether to require email or
  phone verification.
- **Recording** of interviews is intentionally impossible until a consent and
  retention design exists.
- **SMS and push** channels exist in the outbox schema but have no provider.
- **Invitations to people without an account** (talent outreach) are not built.
