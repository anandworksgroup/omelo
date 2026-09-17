-- =====================================================================
-- OMELO 07 — Messaging, Consent Edges, Trust & Safety, Platform Admin
-- =====================================================================

-- ---------------------------------------------------------------
-- Direct hiring chat. Always anchored to a job. Not a social DM system.
-- ---------------------------------------------------------------
create table conversations (
  id             uuid primary key default gen_random_uuid(),
  company_id     uuid not null references companies(id) on delete cascade,
  person_id      uuid not null references persons(id) on delete cascade,
  job_id         uuid references jobs(id) on delete set null,
  application_id uuid references applications(id) on delete set null,
  initiated_by   actor_type not null default 'candidate',
  subject        text,
  person_archived boolean not null default false,
  company_archived boolean not null default false,
  last_message_at timestamptz,
  created_at     timestamptz not null default now(),
  unique (company_id, person_id, job_id)
);
create index conversations_person_idx  on conversations (person_id, last_message_at desc nulls last);
create index conversations_company_idx on conversations (company_id, last_message_at desc nulls last);

create table messages (
  id              bigserial primary key,
  conversation_id uuid not null references conversations(id) on delete cascade,
  sender_person_id uuid references persons(id) on delete set null,
  sender_type     actor_type not null,
  kind            message_kind not null default 'text',
  body            text,
  action_type     text,
  action_payload  jsonb,
  document_id     uuid references documents(id) on delete set null,
  read_at         timestamptz,
  sent_at         timestamptz not null default now()
);
create index messages_conversation_idx on messages (conversation_id, sent_at desc);

-- Internal employer notes. Structurally separate from messages so a
-- note can never be served through a candidate-facing response.
create table application_notes (
  id             uuid primary key default gen_random_uuid(),
  application_id uuid not null references applications(id) on delete cascade,
  company_id     uuid not null references companies(id) on delete cascade,
  author_id      uuid references persons(id) on delete set null,
  body           text not null,
  created_at     timestamptz not null default now()
);
create index application_notes_app_idx on application_notes (application_id);

comment on table application_notes is
  'Employer-internal only. Deliberately a separate table from messages so no candidate-facing query path can reach it.';

-- ---------------------------------------------------------------
-- Consent and relationship edges
-- ---------------------------------------------------------------
create table follows (
  person_id   uuid not null references persons(id) on delete cascade,
  target_type text not null check (target_type in ('company','profession','skill','category')),
  target_id   uuid not null,
  created_at  timestamptz not null default now(),
  primary key (person_id, target_type, target_id)
);

-- Employer blocklist. Enforced as a query-time anti-join, never as a UI
-- filter. A blocked employer must not be able to detect the block.
create table blocks (
  person_id   uuid not null references persons(id) on delete cascade,
  target_type text not null check (target_type in ('company','person')),
  target_id   uuid not null,
  reason      text,
  created_at  timestamptz not null default now(),
  primary key (person_id, target_type, target_id)
);
create index blocks_target_idx on blocks (target_type, target_id);

comment on table blocks is
  'Blocking produces absence, never a signal. This is what lets an employed person look for work without their current employer finding them.';

create table profile_views (
  id                uuid primary key default gen_random_uuid(),
  person_id         uuid not null references persons(id) on delete cascade,
  viewer_company_id uuid references companies(id) on delete set null,
  viewer_person_id  uuid references persons(id) on delete set null,
  context_job_id    uuid references jobs(id) on delete set null,
  viewed_at         timestamptz not null default now()
);
create index profile_views_person_idx  on profile_views (person_id, viewed_at desc);
create index profile_views_company_idx on profile_views (viewer_company_id, viewed_at desc);

create table talent_pools (
  id         uuid primary key default gen_random_uuid(),
  company_id uuid not null references companies(id) on delete cascade,
  name       text not null,
  created_by uuid references persons(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (company_id, name)
);

create table talent_pool_members (
  pool_id   uuid not null references talent_pools(id) on delete cascade,
  person_id uuid not null references persons(id) on delete cascade,
  added_by  uuid references persons(id) on delete set null,
  note      text,
  added_at  timestamptz not null default now(),
  primary key (pool_id, person_id)
);

-- Recruiter invitations to apply. Must reference a specific job.
create table candidate_invitations (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references companies(id) on delete cascade,
  job_id       uuid not null references jobs(id) on delete cascade,
  person_id    uuid not null references persons(id) on delete cascade,
  sent_by      uuid references persons(id) on delete set null,
  message      text,
  responded_at timestamptz,
  response     text check (response in ('applied','declined','ignored')),
  sent_at      timestamptz not null default now(),
  unique (job_id, person_id)
);
create index candidate_invitations_person_idx on candidate_invitations (person_id, sent_at desc);

-- ---------------------------------------------------------------
-- Notifications
-- ---------------------------------------------------------------
create table notifications (
  id          bigserial primary key,
  person_id   uuid not null references persons(id) on delete cascade,
  type        notification_type not null,
  title       text not null,
  body        text,
  -- Where tapping it goes. Nothing in Omelo is a dead end.
  deeplink    text,
  entity_type text,
  entity_id   uuid,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);
create index notifications_person_idx on notifications (person_id, created_at desc);
create index notifications_unread_idx on notifications (person_id) where read_at is null;

create table notification_preferences (
  person_id        uuid primary key references persons(id) on delete cascade,
  push_enabled     boolean not null default true,
  email_enabled    boolean not null default true,
  sms_enabled      boolean not null default false,
  whatsapp_enabled boolean not null default false,
  muted_types      notification_type[] not null default '{}',
  quiet_hours_start smallint,
  quiet_hours_end   smallint,
  updated_at       timestamptz not null default now()
);

-- ---------------------------------------------------------------
-- Trust & Safety
-- ---------------------------------------------------------------
create table reports (
  id             uuid primary key default gen_random_uuid(),
  reporter_id    uuid references persons(id) on delete set null,
  subject_type   text not null check (subject_type in
                 ('job','company','person','message','conversation','application')),
  subject_id     uuid not null,
  reason         report_reason not null,
  details        text,
  status         report_status not null default 'open',
  assigned_to    uuid references persons(id) on delete set null,
  resolution     moderation_action,
  resolution_note text,
  resolved_at    timestamptz,
  created_at     timestamptz not null default now()
);
create index reports_status_idx  on reports (status, created_at);
create index reports_subject_idx on reports (subject_type, subject_id);

create table moderation_actions (
  id           uuid primary key default gen_random_uuid(),
  report_id    uuid references reports(id) on delete set null,
  subject_type text not null,
  subject_id   uuid not null,
  action       moderation_action not null,
  reason       text not null,
  actor_id     uuid references persons(id) on delete set null,
  expires_at   timestamptz,
  reversed_at  timestamptz,
  created_at   timestamptz not null default now()
);
create index moderation_actions_subject_idx on moderation_actions (subject_type, subject_id);

create table fraud_signals (
  id           bigserial primary key,
  subject_type text not null,
  subject_id   uuid not null,
  signal       text not null,
  severity     smallint not null default 1 check (severity between 1 and 5),
  detail       jsonb not null default '{}'::jsonb,
  detected_at  timestamptz not null default now()
);
create index fraud_signals_subject_idx on fraud_signals (subject_type, subject_id, detected_at desc);

-- ---------------------------------------------------------------
-- Platform administration
-- ---------------------------------------------------------------
create table platform_admins (
  person_id  uuid primary key references persons(id) on delete cascade,
  role       text not null check (role in
             ('support','trust_safety','taxonomy_steward','analyst','superadmin')),
  granted_by uuid references persons(id) on delete set null,
  granted_at timestamptz not null default now(),
  expires_at timestamptz,
  is_active  boolean not null default true
);

-- Scoped, time-boxed, consented support access. Disclosed to the user.
create table support_sessions (
  id           uuid primary key default gen_random_uuid(),
  admin_id     uuid not null references persons(id) on delete cascade,
  person_id    uuid not null references persons(id) on delete cascade,
  reason       text not null,
  request_ref  text,
  started_at   timestamptz not null default now(),
  expires_at   timestamptz not null,
  ended_at     timestamptz,
  disclosed_at timestamptz
);
create index support_sessions_person_idx on support_sessions (person_id, started_at desc);

-- ---------------------------------------------------------------
-- Audit and automated-decision accountability
-- ---------------------------------------------------------------
create table audit_log (
  id           bigserial primary key,
  actor_type   actor_type not null,
  actor_id     uuid,
  action       text not null,
  subject_type text not null,
  subject_id   uuid,
  company_id   uuid,
  ip_hash      text,
  user_agent   text,
  metadata     jsonb not null default '{}'::jsonb,
  occurred_at  timestamptz not null default now()
);
create index audit_log_subject_idx on audit_log (subject_type, subject_id, occurred_at desc);
create index audit_log_actor_idx   on audit_log (actor_id, occurred_at desc);
create index audit_log_company_idx on audit_log (company_id, occurred_at desc);

-- Every automated ranking shown to anyone. Basis for human-review
-- requests and for bias auditing.
create table automated_decision_log (
  id             bigserial primary key,
  person_id      uuid references persons(id) on delete set null,
  job_id         uuid references jobs(id) on delete set null,
  company_id     uuid references companies(id) on delete set null,
  decision_kind  text not null check (decision_kind in ('ranking','recommendation','gate','knockout')),
  outcome        jsonb not null,
  engine_version text not null,
  human_reviewed boolean not null default false,
  review_requested_at timestamptz,
  reviewed_at    timestamptz,
  occurred_at    timestamptz not null default now()
);
create index automated_decision_person_idx on automated_decision_log (person_id, occurred_at desc);

comment on table automated_decision_log is
  'Records automated rankings so a person can request human review of any decision that affected them. Ranking never auto-rejects; rejection requires a human actor.';
