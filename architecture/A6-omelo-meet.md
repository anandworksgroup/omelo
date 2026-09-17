# A6 — Omelo Meet and Communications

Omelo Meet is a native part of the hiring system, not an integration.

```
Employer schedules → Omelo invites → candidate joins inside Omelo →
interview happens inside Omelo → feedback is recorded against the application
```

No Zoom, Google Meet or Teams link ever appears. The candidate needs an Omelo
account (every applicant already has one) and a browser or the Omelo app.

---

## 1. Decisions

| Decision | Choice | Why |
|---|---|---|
| Media layer | **LiveKit** (WebRTC SFU), cloud now, self-hostable later | Open source (Apache-2.0), official Flutter (Android/iOS/web) and React SDKs, no code change to move from LiveKit Cloud to our own servers. Omelo owns the product and the control plane; LiveKit only moves audio/video packets. |
| Control plane | Postgres functions + Supabase Edge Functions | The same place that already enforces the hiring loop. A room is joinable only if the database says so. |
| Room tokens | Minted per join, 10 minute TTL, never stored | A leaked link is useless without a signed-in, authorised account. |
| Waiting room | **On** by default | The candidate waits until an interviewer admits them. |
| Recording | **Off, and impossible** in v1 (`check (recording_enabled = false)`) | Recording needs a consent flow per jurisdiction, retention rules and storage. It will be a deliberate later migration, not a toggle. |
| Chat | Stored in `meet_messages`, delivered over Supabase Realtime | Auditable and subject to RLS. Rate limited in the database. |
| Email | Transactional outbox (`outbound_messages`) → `comms-dispatch` Edge Function → Resend | Emails are written in the same transaction as the hiring action, so an invitation can never be "sent" for an interview that was rolled back. Provider is replaceable. |
| SMS / push | Channels exist in the outbox; no provider yet | Same pipeline when a provider is chosen. |

## 2. Flow

```
EMPLOYER                                   CANDIDATE
omelo_schedule_interview(...)
  ├─ interviews row (round, mode, time)
  ├─ interview_interviewers (panel)
  ├─ interview_rooms (unguessable room_name,
  │    opens 15 min before, closes 60 min after end)
  ├─ interview_participants (candidate, host, interviewers)
  ├─ interview_questions (from profession templates, editable)
  ├─ application → interview state + timeline event
  ├─ notification + email (invitation) ───────────────► email + in-app "Join Interview"
  └─ reminder emails queued (24 h, 1 h)                      │
                                                             ▼
                                              /meet/<room_name> (app or web)
                                                             │
                              meet-token Edge Function ◄─────┘
                                ├─ omelo_meet_join(room) as the user
                                │    too_early → countdown
                                │    waiting   → waiting room (realtime)
                                │    admitted  → LiveKit token (10 min)
host joins → room live ──► admits candidate ──────────► candidate enters room
                    video · audio · screen share · chat
                    side panel: profile, experience, skills,
                    job requirements, match, questions, private notes
host ends → omelo_meet_end
  ├─ room ended, session closed
  ├─ interview completed
  ├─ candidate: "Interview completed ✓ — Final review"
  └─ panel: "Submit feedback"
omelo_save_interview_feedback (private) → pipeline decision
  (next round · offer · reject)
```

## 3. Data model (migration 28)

Extends the existing hiring tables; nothing is redesigned.

| Table | Purpose | Who can read |
|---|---|---|
| `interviews` + `round_name`, `round_kind`, `meeting_mode` | An interview is a first-class **round** | Candidate (own), hiring team, panel |
| `job_interview_rounds` | The planned process for a job (Technical → System design → Hiring manager) so the candidate sees ○ upcoming steps | Hiring team; candidates who applied |
| `interview_rooms` | One Omelo Meet room per interview: `room_name`, status, window, waiting room, recording (always false) | Candidate (own), hiring team |
| `interview_participants` | Who may join, and live presence: invited → waiting → admitted → in_room → left / removed / denied | Self, hiring team |
| `interview_sessions` | Each time the room actually ran (start, end, duration) | Hiring team |
| `interview_questions` | Questions for this interview, seeded from templates | Hiring team and panel — **never the candidate** |
| `interview_question_templates` | Profession/category-specific question bank (driver ≠ nurse ≠ engineer) | Signed-in users |
| `interview_feedback` | Structured private feedback per interviewer: recommendation, rating, strengths, concerns, competencies, skills demonstrated | Hiring team, and each interviewer their own — **never the candidate** |
| `interview_answers` | Per-question notes and evaluation per interviewer | Same as feedback |
| `meet_messages` | In-room chat | People who were admitted to that room |
| `meet_events` | Append-only room audit: join requested, admitted, denied, joined, left, removed, ended, abuse reported | Hiring team |
| `meet_abuse_reports` | Either side can report abuse from inside the room | Reporter (own) |
| `outbound_messages` | Email / SMS / push outbox with dedupe keys, `send_after`, retries | Server only |

## 4. Security

| Requirement | How |
|---|---|
| Authenticated, authorised access | `omelo_meet_join` admits only the candidate, the panel, and the company's hiring roles (as observers). Everyone else gets 42501. |
| Short-lived tokens | LiveKit JWT, 10 min, minted per join by `meet-token`; not stored. |
| Waiting room + host controls | Candidate waits until admitted; host/interviewers admit, deny, remove, end. |
| Participant removal | `omelo_meet_remove` records it (removed people cannot rejoin); `meet-control` also ejects them from the media server. |
| Room expiry | Joinable only from 15 min before start to 60 min after the scheduled end; `omelo_meet_housekeeping` (pg_cron) expires stale rooms. |
| No public room discovery | `room_name` is 36 hex chars of randomness; RLS hides rooms from non-participants; knowing it grants nothing. |
| Rate limiting | Join attempts (20/min per person per room) and chat (30/min per sender) are limited in the database. |
| Encrypted transport | WebRTC DTLS-SRTP; signalling over WSS. |
| Abuse reporting | `omelo_report_meet_abuse` from inside the room. |
| Audit | `meet_events` + `application_events` (candidate-visible, no feedback content) + `domain_events` (`MeetStarted`, `MeetEnded`, `InterviewFeedbackSubmitted`, `MeetAbuseReported`). |
| Private feedback | `interview_feedback`, `interview_answers`, `interview_questions` have no candidate-readable policy. Verified by invariant. |
| Recording off | Check constraint; there is no code path to enable it. |

## 5. Configuration (set in Supabase → Edge Functions → Secrets)

| Secret | Used by | Without it |
|---|---|---|
| `LIVEKIT_URL` (wss://…), `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` | `meet-token`, `meet-control` | Scheduling, invitations, waiting room and feedback all work; joining the call returns `meet_not_configured` and the apps say so plainly. |
| `RESEND_API_KEY`, `EMAIL_FROM` | `comms-dispatch` | In-app notifications work; emails stay `queued` and send once the key is added. |
| `WORKER_APP_URL`, `PORTAL_URL` | `comms-dispatch` (deep links) | Links default to localhost. |

## 6. Not in v1

- Recording and transcripts (needs consent + retention design).
- Invitations to people without an Omelo account (outreach / talent search). The design is a single-use invitation token that walks them through lightweight sign-up before the waiting room.
- SMS and push providers.
- AI interview assistance (question generation beyond templates, live notes).
- "Skills demonstrated" feeding the Professional Identity Graph — the data is captured in `interview_feedback.skills_assessed` now so this can be built without changing the schema.
