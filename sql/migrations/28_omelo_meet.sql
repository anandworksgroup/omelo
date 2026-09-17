-- ============================================================
-- OMELO 28 — Omelo Meet + Communications (architecture/A6)
--
-- Interviews become first-class rounds with a native Omelo Meet room,
-- private structured feedback, profession-specific questions, a waiting
-- room with host controls, in-room chat, an audit trail, and a
-- transactional email outbox. Extends the hiring loop from 25; nothing is
-- redesigned.
-- ============================================================

create extension if not exists pgcrypto with schema extensions;

-- ============================================================
-- 1. INTERVIEWS AS ROUNDS
-- ============================================================
alter table interviews add column if not exists round_name   text;
alter table interviews add column if not exists round_kind   text;
alter table interviews add column if not exists meeting_mode text;

update interviews set meeting_mode = case when type in ('video','panel') then 'omelo_meet'
                                          when type = 'phone' then 'phone' else 'in_person' end
 where meeting_mode is null;

alter table interviews alter column meeting_mode set default 'omelo_meet';
alter table interviews alter column meeting_mode set not null;
alter table interviews drop constraint if exists interviews_meeting_mode_check;
alter table interviews add constraint interviews_meeting_mode_check
  check (meeting_mode in ('omelo_meet','phone','in_person'));
alter table interviews drop constraint if exists interviews_round_kind_check;
alter table interviews add constraint interviews_round_kind_check
  check (round_kind is null or round_kind in ('screening','technical','practical','hiring_manager','culture','final','general'));

-- The planned process for a job, so a candidate can see what comes next.
create table if not exists job_interview_rounds (
  id               uuid primary key default gen_random_uuid(),
  job_id           uuid not null references jobs(id) on delete cascade,
  position         smallint not null check (position between 1 and 20),
  name             text not null check (length(trim(name)) between 2 and 80),
  kind             text not null default 'general'
                   check (kind in ('screening','technical','practical','hiring_manager','culture','final','general')),
  meeting_mode     text not null default 'omelo_meet' check (meeting_mode in ('omelo_meet','phone','in_person')),
  duration_minutes smallint not null default 30 check (duration_minutes between 5 and 480),
  created_at       timestamptz not null default now(),
  unique (job_id, position)
);
alter table job_interview_rounds enable row level security;

create policy job_interview_rounds_company on job_interview_rounds
  for all to authenticated
  using (omelo_private.omelo_can_access_job(job_id))
  with check (omelo_private.omelo_can_access_job(job_id));

create policy job_interview_rounds_applicant on job_interview_rounds
  for select to authenticated
  using (exists (select 1 from applications a where a.job_id = job_interview_rounds.job_id and a.person_id = auth.uid()));

-- ============================================================
-- 2. MEET TABLES
-- ============================================================
create table if not exists interview_rooms (
  id                uuid primary key default gen_random_uuid(),
  interview_id      uuid not null unique references interviews(id) on delete cascade,
  room_name         text not null unique
                    default 'om-' || encode(extensions.gen_random_bytes(18), 'hex'),
  status            text not null default 'scheduled'
                    check (status in ('scheduled','live','ended','expired','cancelled')),
  waiting_room      boolean not null default true,
  -- Recording is deliberately impossible until a consent + retention design exists.
  recording_enabled boolean not null default false check (recording_enabled = false),
  opens_at          timestamptz not null,
  closes_at         timestamptz not null,
  started_at        timestamptz,
  ended_at          timestamptz,
  ended_by          uuid,
  created_at        timestamptz not null default now(),
  check (closes_at > opens_at)
);
alter table interview_rooms enable row level security;

create table if not exists interview_participants (
  id            uuid primary key default gen_random_uuid(),
  interview_id  uuid not null references interviews(id) on delete cascade,
  person_id     uuid not null references persons(id) on delete cascade,
  display_name  text,
  role          text not null check (role in ('candidate','host','interviewer','observer')),
  status        text not null default 'invited'
                check (status in ('invited','waiting','admitted','in_room','left','removed','denied')),
  invited_at    timestamptz not null default now(),
  requested_at  timestamptz,
  admitted_at   timestamptz,
  admitted_by   uuid,
  joined_at     timestamptz,
  left_at       timestamptz,
  removed_at    timestamptz,
  removed_by    uuid,
  remove_reason text,
  unique (interview_id, person_id)
);
alter table interview_participants enable row level security;

create table if not exists interview_sessions (
  id               uuid primary key default gen_random_uuid(),
  interview_id     uuid not null references interviews(id) on delete cascade,
  room_id          uuid not null references interview_rooms(id) on delete cascade,
  started_at       timestamptz not null default now(),
  ended_at         timestamptz,
  duration_seconds integer
);
alter table interview_sessions enable row level security;

create table if not exists interview_question_templates (
  id            uuid primary key default gen_random_uuid(),
  profession_id uuid references professions(id) on delete cascade,
  category_id   uuid references job_categories(id) on delete cascade,
  round_kind    text check (round_kind is null or round_kind in ('screening','technical','practical','hiring_manager','culture','final','general')),
  question      text not null,
  category      text not null default 'general',
  position      smallint not null default 1,
  locale        text not null default 'en',
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);
alter table interview_question_templates enable row level security;
create policy interview_question_templates_read on interview_question_templates
  for select to authenticated using (is_active);

create table if not exists interview_questions (
  id           uuid primary key default gen_random_uuid(),
  interview_id uuid not null references interviews(id) on delete cascade,
  position     smallint not null default 1,
  question     text not null check (length(trim(question)) between 3 and 500),
  category     text not null default 'general',
  required     boolean not null default false,
  source       text not null default 'custom' check (source in ('template','custom')),
  template_id  uuid references interview_question_templates(id) on delete set null,
  created_at   timestamptz not null default now()
);
alter table interview_questions enable row level security;

create table if not exists interview_feedback (
  id              uuid primary key default gen_random_uuid(),
  interview_id    uuid not null references interviews(id) on delete cascade,
  application_id  uuid not null references applications(id) on delete cascade,
  company_id      uuid not null references companies(id) on delete cascade,
  interviewer_id  uuid not null references persons(id) on delete cascade,
  recommendation  text check (recommendation in ('strong_hire','hire','further_review','no_hire')),
  overall_rating  smallint check (overall_rating between 1 and 5),
  strengths       text,
  concerns        text,
  notes           text,
  -- [{"name": "Communication", "assessment": "strong|meets|needs_development|not_assessed"}]
  competencies    jsonb not null default '[]'::jsonb,
  -- [{"skill_id": uuid|null, "name": "Python", "demonstrated": true}]
  skills_assessed jsonb not null default '[]'::jsonb,
  status          text not null default 'draft' check (status in ('draft','submitted')),
  submitted_at    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (interview_id, interviewer_id),
  check (status = 'draft' or recommendation is not null)
);
alter table interview_feedback enable row level security;

create table if not exists interview_answers (
  id             uuid primary key default gen_random_uuid(),
  interview_id   uuid not null references interviews(id) on delete cascade,
  question_id    uuid not null references interview_questions(id) on delete cascade,
  interviewer_id uuid not null references persons(id) on delete cascade,
  evaluation     text check (evaluation in ('strong','good','weak','not_asked')),
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (question_id, interviewer_id)
);
alter table interview_answers enable row level security;

create table if not exists meet_messages (
  id           bigint generated always as identity primary key,
  interview_id uuid not null references interviews(id) on delete cascade,
  sender_id    uuid not null references persons(id) on delete cascade,
  sender_name  text,
  body         text not null check (length(trim(body)) between 1 and 2000),
  sent_at      timestamptz not null default now()
);
alter table meet_messages enable row level security;

create table if not exists meet_events (
  id                bigint generated always as identity primary key,
  interview_id      uuid not null references interviews(id) on delete cascade,
  actor_id          uuid,
  subject_person_id uuid,
  event             text not null check (event in ('room_created','join_requested','admitted','denied','joined',
                                                    'left','removed','ended','expired','abuse_reported','too_early')),
  metadata          jsonb not null default '{}'::jsonb,
  occurred_at       timestamptz not null default now()
);
alter table meet_events enable row level security;
create index if not exists meet_events_interview on meet_events (interview_id, id);
create index if not exists meet_events_rate on meet_events (actor_id, interview_id, occurred_at);

create table if not exists meet_abuse_reports (
  id                 uuid primary key default gen_random_uuid(),
  interview_id       uuid not null references interviews(id) on delete cascade,
  reporter_id        uuid not null references persons(id) on delete cascade,
  reported_person_id uuid references persons(id) on delete set null,
  reason             text not null check (reason in ('harassment','discrimination','inappropriate_content',
                                                    'impersonation','scam_or_fee_request','other')),
  details            text,
  status             text not null default 'open' check (status in ('open','reviewing','closed')),
  created_at         timestamptz not null default now()
);
alter table meet_abuse_reports enable row level security;

-- Transactional outbox for email / SMS / push.
create table if not exists outbound_messages (
  id                  uuid primary key default gen_random_uuid(),
  person_id           uuid references persons(id) on delete cascade,
  channel             text not null check (channel in ('email','sms','push')),
  template            text not null,
  to_address          text,
  subject             text,
  payload             jsonb not null default '{}'::jsonb,
  dedupe_key          text unique,
  status              text not null default 'queued'
                      check (status in ('queued','sending','sent','failed','cancelled','skipped')),
  attempts            smallint not null default 0,
  last_error          text,
  provider_message_id text,
  send_after          timestamptz not null default now(),
  created_at          timestamptz not null default now(),
  sent_at             timestamptz
);
alter table outbound_messages enable row level security;
revoke all on outbound_messages from anon, authenticated;
create index if not exists outbound_messages_due on outbound_messages (send_after) where status = 'queued';

create index if not exists interview_participants_person on interview_participants (person_id);
create index if not exists interview_feedback_application on interview_feedback (application_id);
create index if not exists meet_messages_interview on meet_messages (interview_id, id);

-- ============================================================
-- 3. PREDICATES (definer, so policies never recurse)
-- ============================================================
create or replace function omelo_private.omelo_is_hiring_team_for_interview(p_interview_id uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select exists (
    select 1 from interviews i
      join company_members cm on cm.company_id = i.company_id and cm.person_id = auth.uid() and cm.is_active
     where i.id = p_interview_id
       and cm.role in ('owner','admin','recruiter','hiring_manager','hr'));
$$;

create or replace function omelo_private.omelo_is_interview_candidate(p_interview_id uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select exists (select 1 from interviews where id = p_interview_id and person_id = auth.uid());
$$;

-- Was admitted to the room at some point (can read and write its chat).
create or replace function omelo_private.omelo_was_admitted(p_interview_id uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select exists (select 1 from interview_participants
                  where interview_id = p_interview_id and person_id = auth.uid()
                    and status in ('admitted','in_room','left') and admitted_at is not null);
$$;

grant execute on function omelo_private.omelo_is_hiring_team_for_interview(uuid) to authenticated;
grant execute on function omelo_private.omelo_is_interview_candidate(uuid) to authenticated;
grant execute on function omelo_private.omelo_was_admitted(uuid) to authenticated;

-- ============================================================
-- 4. POLICIES
-- ============================================================
create policy interview_rooms_read on interview_rooms for select to authenticated
  using (omelo_private.omelo_is_interview_candidate(interview_id)
      or omelo_private.omelo_can_access_interview(interview_id)
      or omelo_private.omelo_is_interview_panelist(interview_id));

create policy interview_participants_read on interview_participants for select to authenticated
  using (person_id = auth.uid()
      or omelo_private.omelo_can_access_interview(interview_id)
      or omelo_private.omelo_is_interview_panelist(interview_id)
      -- the candidate can see who is on the call once they are in it
      or (omelo_private.omelo_is_interview_candidate(interview_id) and omelo_private.omelo_was_admitted(interview_id)));

create policy interview_sessions_read on interview_sessions for select to authenticated
  using (omelo_private.omelo_can_access_interview(interview_id));

-- Questions, feedback and answers: hiring team and panel only. Never the candidate.
create policy interview_questions_team on interview_questions for select to authenticated
  using (omelo_private.omelo_can_access_interview(interview_id)
      or omelo_private.omelo_is_interview_panelist(interview_id));
create policy interview_questions_write on interview_questions for all to authenticated
  using (omelo_private.omelo_can_access_interview(interview_id))
  with check (omelo_private.omelo_can_access_interview(interview_id));

create policy interview_feedback_team on interview_feedback for select to authenticated
  using (interviewer_id = auth.uid()
      or omelo_private.omelo_is_hiring_team_for_interview(interview_id));

create policy interview_answers_team on interview_answers for select to authenticated
  using (interviewer_id = auth.uid()
      or omelo_private.omelo_is_hiring_team_for_interview(interview_id));

create policy meet_messages_read on meet_messages for select to authenticated
  using (omelo_private.omelo_was_admitted(interview_id)
      or omelo_private.omelo_can_access_interview(interview_id));

create policy meet_messages_send on meet_messages for insert to authenticated
  with check (sender_id = auth.uid()
          and omelo_private.omelo_was_admitted(interview_id)
          and exists (select 1 from interview_participants p
                       where p.interview_id = meet_messages.interview_id and p.person_id = auth.uid()
                         and p.status in ('admitted','in_room')));

create policy meet_events_team on meet_events for select to authenticated
  using (omelo_private.omelo_can_access_interview(interview_id));

create policy meet_abuse_reports_own on meet_abuse_reports for select to authenticated
  using (reporter_id = auth.uid());

-- Chat: server-stamped sender name, and a flood limit.
create or replace function omelo_private.omelo_guard_meet_message()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if (select count(*) from meet_messages
       where sender_id = new.sender_id and interview_id = new.interview_id
         and sent_at > now() - interval '1 minute') >= 30 then
    raise exception 'You are sending messages too quickly' using errcode = '54000';
  end if;
  new.sender_name := (select display_name from persons where id = new.sender_id);
  new.sent_at := now();
  return new;
end;
$$;
revoke execute on function omelo_private.omelo_guard_meet_message() from public, anon, authenticated;

drop trigger if exists meet_messages_guard on meet_messages;
create trigger meet_messages_guard before insert on meet_messages
  for each row execute function omelo_private.omelo_guard_meet_message();

-- Interview logistics that must go through reschedule (they move the room).
create or replace function omelo_private.omelo_guard_interview()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
declare a record;
begin
  if tg_op in ('INSERT', 'UPDATE') then
    select k.job_id, k.company_id, k.person_id into a from omelo_private.omelo_application_keys(new.application_id) k;
    if a.job_id is null
       or new.job_id is distinct from a.job_id
       or new.company_id is distinct from a.company_id
       or new.person_id is distinct from a.person_id then
      raise exception 'Interview does not match its application' using errcode = '23514';
    end if;
  end if;

  if omelo_private.omelo_is_privileged() then
    return coalesce(new, old);
  end if;

  if tg_op = 'INSERT' then
    raise exception 'Schedule interviews with omelo_schedule_interview' using errcode = '42501';
  elsif tg_op = 'DELETE' then
    raise exception 'Cancel an interview instead of deleting it' using errcode = '42501';
  end if;

  if new.status is distinct from old.status
  or new.scheduled_at is distinct from old.scheduled_at
  or new.duration_minutes is distinct from old.duration_minutes
  or new.meeting_mode is distinct from old.meeting_mode
  or new.candidate_confirmed_at is distinct from old.candidate_confirmed_at
  or new.completed_at is distinct from old.completed_at
  or new.cancelled_at is distinct from old.cancelled_at
  or new.cancel_reason is distinct from old.cancel_reason
  or new.round is distinct from old.round
  or new.type is distinct from old.type
  or new.created_by is distinct from old.created_by then
    raise exception 'Interview status, time and format change through Omelo interview actions' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- ============================================================
-- 5. COMMUNICATIONS
-- ============================================================
create or replace function omelo_private.omelo_interview_payload(p_interview_id uuid)
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select jsonb_build_object(
    'interview_id', i.id, 'application_id', i.application_id,
    'job_title', j.title, 'company_name', c.display_name,
    'candidate_name', p.display_name,
    'round', i.round, 'round_name', coalesce(i.round_name, 'Interview'),
    'meeting_mode', i.meeting_mode, 'type', i.type,
    'scheduled_at', i.scheduled_at, 'duration_minutes', i.duration_minutes, 'timezone', i.timezone,
    'location_text', i.location_text, 'instructions', i.instructions,
    'room_name', r.room_name, 'cancel_reason', i.cancel_reason)
  from interviews i
  join jobs j on j.id = i.job_id
  join companies c on c.id = i.company_id
  join persons p on p.id = i.person_id
  left join interview_rooms r on r.interview_id = i.id
  where i.id = p_interview_id;
$$;
revoke execute on function omelo_private.omelo_interview_payload(uuid) from public, anon, authenticated;

create or replace function omelo_private.omelo_enqueue_email(
  p_person uuid, p_template text, p_subject text, p_payload jsonb,
  p_dedupe text default null, p_send_after timestamptz default now()
) returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_email text;
begin
  select email into v_email from persons where id = p_person;
  if v_email is null or position('@' in v_email) = 0 then
    return;   -- no address: the in-app notification still reaches them
  end if;
  insert into outbound_messages (person_id, channel, template, to_address, subject, payload, dedupe_key, send_after)
  values (p_person, 'email', p_template, v_email, p_subject, coalesce(p_payload, '{}'), p_dedupe, p_send_after)
  on conflict (dedupe_key) do nothing;
end;
$$;
revoke execute on function omelo_private.omelo_enqueue_email(uuid, text, text, jsonb, text, timestamptz) from public, anon, authenticated;

-- Reminders are cancelled and re-queued whenever the time changes.
create or replace function omelo_private.omelo_queue_interview_reminders(p_interview_id uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare i interviews; v_payload jsonb; v_subject text;
begin
  select * into i from interviews where id = p_interview_id;
  update outbound_messages set status = 'cancelled'
   where status = 'queued' and template = 'interview_reminder'
     and payload->>'interview_id' = p_interview_id::text;
  if i.status not in ('scheduled','rescheduled') then
    return;
  end if;
  v_payload := omelo_private.omelo_interview_payload(p_interview_id);
  v_subject := 'Reminder: ' || (v_payload->>'round_name') || ' with ' || (v_payload->>'company_name');
  if i.scheduled_at - interval '24 hours' > now() then
    perform omelo_private.omelo_enqueue_email(i.person_id, 'interview_reminder', v_subject,
      v_payload || jsonb_build_object('lead', '24h'),
      'interview_reminder_24h:' || i.id || ':' || extract(epoch from i.scheduled_at)::bigint,
      i.scheduled_at - interval '24 hours');
  end if;
  if i.scheduled_at - interval '1 hour' > now() then
    perform omelo_private.omelo_enqueue_email(i.person_id, 'interview_reminder', v_subject,
      v_payload || jsonb_build_object('lead', '1h'),
      'interview_reminder_1h:' || i.id || ':' || extract(epoch from i.scheduled_at)::bigint,
      i.scheduled_at - interval '1 hour');
  end if;
end;
$$;
revoke execute on function omelo_private.omelo_queue_interview_reminders(uuid) from public, anon, authenticated;

-- Offer email, whenever an offer is sent.
create or replace function omelo_private.omelo_email_offer_sent()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if new.status = 'sent' and (tg_op = 'INSERT' or old.status is distinct from 'sent') then
    perform omelo_private.omelo_enqueue_email(new.person_id, 'offer_received',
      'Job offer: ' || new.title || ' at ' || (select display_name from companies where id = new.company_id),
      jsonb_build_object('offer_id', new.id, 'application_id', new.application_id, 'title', new.title,
        'company_name', (select display_name from companies where id = new.company_id),
        'pay_amount', new.pay_amount, 'pay_period', new.pay_period, 'pay_currency', new.pay_currency,
        'start_date', new.start_date, 'expires_at', new.expires_at),
      'offer_received:' || new.id);
  end if;
  return new;
end;
$$;
revoke execute on function omelo_private.omelo_email_offer_sent() from public, anon, authenticated;

drop trigger if exists offers_email_sent on offers;
create trigger offers_email_sent after insert or update of status on offers
  for each row execute function omelo_private.omelo_email_offer_sent();

-- Server-only claim / mark for the comms-dispatch Edge Function.
create or replace function public.omelo_comms_claim(p_limit integer default 25)
returns setof outbound_messages
language sql volatile security definer
set search_path = public, omelo_private
as $$
  update outbound_messages m
     set status = 'sending', attempts = attempts + 1
   where m.id in (select id from outbound_messages
                   where status = 'queued' and channel = 'email' and send_after <= now()
                   order by send_after
                   limit greatest(1, least(coalesce(p_limit, 25), 100))
                   for update skip locked)
  returning m.*;
$$;

create or replace function public.omelo_comms_mark(
  p_id uuid, p_ok boolean, p_provider_id text default null, p_error text default null
) returns void
language sql volatile security definer
set search_path = public, omelo_private
as $$
  update outbound_messages
     set status = case when p_ok then 'sent'
                       when attempts >= 5 then 'failed'
                       else 'queued' end,
         sent_at = case when p_ok then now() end,
         provider_message_id = p_provider_id,
         last_error = left(p_error, 1000),
         send_after = case when p_ok then send_after else now() + (attempts * interval '5 minutes') end
   where id = p_id and status = 'sending';
$$;

revoke execute on function public.omelo_comms_claim(integer) from public, anon, authenticated;
revoke execute on function public.omelo_comms_mark(uuid, boolean, text, text) from public, anon, authenticated;
grant execute on function public.omelo_comms_claim(integer) to service_role;
grant execute on function public.omelo_comms_mark(uuid, boolean, text, text) to service_role;

-- ============================================================
-- 6. SCHEDULING (replaces the 25 version; adds rounds, panel, room,
--    questions, email)
-- ============================================================
drop function if exists public.omelo_schedule_interview(uuid, interview_type, timestamptz, integer, text, text, text, text);

create or replace function public.omelo_schedule_interview(
  p_application_id    uuid,
  p_scheduled_at      timestamptz,
  p_duration_minutes  integer  default null,   -- null: the planned round's, else 30
  p_round_name        text     default null,
  p_round_kind        text     default null,
  p_meeting_mode      text     default null,   -- null: the planned round's, else omelo_meet
  p_timezone          text     default null,
  p_location_text     text     default null,
  p_instructions      text     default null,
  p_interviewer_ids   uuid[]   default null,
  p_questions         jsonb    default null,
  p_send_email        boolean  default true,
  p_send_notification boolean  default true
) returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare
  a applications; j jobs;
  v_id uuid; v_round int; v_company text; v_type interview_type;
  v_panel uuid[]; v_lead uuid; v_person uuid; v_duration int;
  v_round_name text; v_kind text; v_payload jsonb; v_q jsonb; v_pos int := 0;
  v_is_next_round boolean; v_mode text; v_plan_duration int;
begin
  a := omelo_private.omelo_employer_application(p_application_id);
  if a.state not in ('applied','viewed','shortlisted','screening','assessment','interview') then
    raise exception 'Cannot schedule an interview for a % application', a.state using errcode = '22023';
  end if;
  if p_scheduled_at is null or p_scheduled_at < now() - interval '10 minutes' then
    raise exception 'Choose a time in the future' using errcode = '22023';
  end if;
  if p_round_kind is not null and p_round_kind not in ('screening','technical','practical','hiring_manager','culture','final','general') then
    raise exception 'Unknown interview kind %', p_round_kind using errcode = '22023';
  end if;

  select * into j from jobs where id = a.job_id;
  select coalesce(max(round), 0) + 1 into v_round from interviews where application_id = a.id;
  v_is_next_round := v_round > 1;

  -- Anything the employer did not choose comes from the job's planned round.
  select coalesce(nullif(trim(p_round_name), ''), r.name, case when v_round = 1 then 'Interview' else 'Interview round ' || v_round end),
         coalesce(p_round_kind, r.kind, 'general'),
         coalesce(p_meeting_mode, r.meeting_mode, 'omelo_meet'),
         r.duration_minutes
    into v_round_name, v_kind, v_mode, v_plan_duration
    from (select 1) x
    left join job_interview_rounds r on r.job_id = a.job_id and r.position = v_round;

  if v_mode not in ('omelo_meet','phone','in_person') then
    raise exception 'Interview format must be Omelo Meet, phone or in person' using errcode = '22023';
  end if;
  v_duration := greatest(5, least(coalesce(p_duration_minutes, v_plan_duration, 30), 480));

  v_type := case v_mode when 'omelo_meet' then 'video' when 'phone' then 'phone' else 'in_person' end;

  -- Panel: named interviewers must be active members of this company.
  v_panel := coalesce(p_interviewer_ids, array[auth.uid()]);
  if cardinality(v_panel) = 0 then v_panel := array[auth.uid()]; end if;
  if cardinality(v_panel) > 10 then
    raise exception 'At most 10 interviewers' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(v_panel) pid
              where not exists (select 1 from company_members cm
                                 where cm.company_id = a.company_id and cm.person_id = pid and cm.is_active
                                   and cm.role in ('owner','admin','recruiter','hiring_manager','interviewer','hr'))) then
    raise exception 'Every interviewer must be an active member of your hiring team' using errcode = '22023';
  end if;
  v_lead := case when auth.uid() = any(v_panel) then auth.uid() else v_panel[1] end;

  insert into interviews (application_id, job_id, company_id, person_id, type, status, round,
                          round_name, round_kind, meeting_mode,
                          scheduled_at, duration_minutes, timezone, location_text, instructions, created_by)
  values (a.id, a.job_id, a.company_id, a.person_id, v_type, 'scheduled', v_round,
          v_round_name, v_kind, v_mode,
          p_scheduled_at, v_duration, p_timezone,
          case when v_mode = 'in_person'
               then coalesce(nullif(trim(p_location_text), ''), j.location_text)
               else nullif(trim(p_location_text), '') end,
          nullif(trim(p_instructions), ''), auth.uid())
  returning id into v_id;

  foreach v_person in array v_panel loop
    insert into interview_interviewers (interview_id, person_id, is_lead)
    values (v_id, v_person, v_person = v_lead) on conflict do nothing;
    insert into interview_participants (interview_id, person_id, display_name, role)
    values (v_id, v_person, (select display_name from persons where id = v_person),
            case when v_person = v_lead then 'host' else 'interviewer' end)
    on conflict do nothing;
  end loop;
  insert into interview_participants (interview_id, person_id, display_name, role)
  values (v_id, a.person_id, (select display_name from persons where id = a.person_id), 'candidate')
  on conflict do nothing;

  if v_mode = 'omelo_meet' then
    insert into interview_rooms (interview_id, opens_at, closes_at)
    values (v_id, p_scheduled_at - interval '15 minutes',
            p_scheduled_at + make_interval(mins => v_duration) + interval '60 minutes');
    insert into meet_events (interview_id, actor_id, event) values (v_id, auth.uid(), 'room_created');
  end if;

  -- Questions: the employer's list, or the profession's template bank.
  if p_questions is not null and jsonb_typeof(p_questions) = 'array' and jsonb_array_length(p_questions) > 0 then
    for v_q in select * from jsonb_array_elements(p_questions) limit 30 loop
      continue when coalesce(length(trim(v_q->>'question')), 0) < 3;
      v_pos := v_pos + 1;
      insert into interview_questions (interview_id, position, question, category, required, source, template_id)
      values (v_id, v_pos, left(trim(v_q->>'question'), 500), coalesce(nullif(v_q->>'category', ''), 'general'),
              coalesce((v_q->>'required')::boolean, false),
              case when v_q ? 'template_id' then 'template' else 'custom' end,
              nullif(v_q->>'template_id', '')::uuid);
    end loop;
  else
    insert into interview_questions (interview_id, position, question, category, required, source, template_id)
    select v_id, row_number() over (order by t.rank, t.position), t.question, t.category, false, 'template', t.id
      from public.omelo_interview_question_suggestions(a.job_id, v_kind) t
     limit 8;
  end if;

  update applications set first_viewed_at = coalesce(first_viewed_at, now()) where id = a.id;
  perform omelo_private.omelo_set_application_state(a.id, 'interview');

  insert into application_events (application_id, event_type, actor_type, actor_id, from_state, to_state, metadata)
  values (a.id, 'interview_scheduled', 'recruiter', auth.uid(), a.state, 'interview',
          jsonb_build_object('interview_id', v_id, 'round', v_round, 'round_name', v_round_name,
                             'meeting_mode', v_mode, 'scheduled_at', p_scheduled_at));

  select c.display_name into v_company from companies c where c.id = a.company_id;
  if p_send_notification then
    perform omelo_private.omelo_notify(a.person_id, 'interview_scheduled',
      case when v_is_next_round then 'Invited to the next round' else 'Interview scheduled' end,
      coalesce(v_company, 'The employer') || ' invited you to ' || v_round_name || ' for ' || j.title ||
        case when v_mode = 'omelo_meet' then ' on Omelo Meet.' else '.' end || ' Please confirm you can attend.',
      'interview', v_id, '/applications/' || a.id);
  end if;
  if p_send_email then
    v_payload := omelo_private.omelo_interview_payload(v_id);
    perform omelo_private.omelo_enqueue_email(a.person_id,
      case when v_is_next_round then 'next_round_invitation' else 'interview_invitation' end,
      'Interview invitation: ' || j.title || ' at ' || coalesce(v_company, 'Omelo'),
      v_payload, 'interview_invitation:' || v_id);
    perform omelo_private.omelo_queue_interview_reminders(v_id);
  end if;
  return v_id;
end;
$$;

-- Question bank lookup, most specific first: profession → category → general.
create or replace function public.omelo_interview_question_suggestions(p_job_id uuid, p_round_kind text default null)
returns table (id uuid, question text, category text, "position" smallint, rank int)
language sql stable security definer
set search_path = public, omelo_private
as $$
  with j as (select profession_id, category_id from jobs where jobs.id = p_job_id),
  ranked as (
    select t.id, t.question, t.category, t.position,
           case when t.profession_id is not null then 1 when t.category_id is not null then 2 else 3 end as rank
      from interview_question_templates t, j
     where t.is_active
       and (t.round_kind is null or p_round_kind is null or t.round_kind = p_round_kind)
       and (t.profession_id = j.profession_id
            or (t.profession_id is null and t.category_id = j.category_id)
            or (t.profession_id is null and t.category_id is null))
  ),
  best as (select min(rank) as r from ranked)
  select ranked.id, ranked.question, ranked.category, ranked.position, ranked.rank
    from ranked, best
   where ranked.rank = best.r
      or (ranked.rank = 3 and (select count(*) from ranked r2 where r2.rank = best.r) < 4)
   order by ranked.rank, ranked.position;
$$;

-- ============================================================
-- 7. RESCHEDULE / CANCEL / COMPLETE (room + email aware)
-- ============================================================
drop function if exists public.omelo_reschedule_interview(uuid, timestamptz, text);
create or replace function public.omelo_reschedule_interview(
  p_interview_id uuid, p_scheduled_at timestamptz, p_reason text default null,
  p_duration_minutes integer default null
) returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare i interviews; v_duration int; v_payload jsonb;
begin
  select * into i from interviews where id = p_interview_id;
  if i.id is null or not omelo_private.omelo_can_access_job(i.job_id) then
    raise exception 'Interview not found, or you do not have access to it' using errcode = '42501';
  end if;
  if i.status not in ('scheduled','rescheduled') then
    raise exception 'This interview is %', i.status using errcode = '22023';
  end if;
  if p_scheduled_at is null or p_scheduled_at < now() - interval '10 minutes' then
    raise exception 'Choose a time in the future' using errcode = '22023';
  end if;
  if exists (select 1 from interview_rooms where interview_id = i.id and status = 'live') then
    raise exception 'This interview is in progress' using errcode = '22023';
  end if;
  v_duration := greatest(5, least(coalesce(p_duration_minutes, i.duration_minutes, 30), 480));

  update interviews set scheduled_at = p_scheduled_at, duration_minutes = v_duration,
                        status = 'rescheduled', candidate_confirmed_at = null
   where id = i.id;
  update interview_rooms
     set opens_at = p_scheduled_at - interval '15 minutes',
         closes_at = p_scheduled_at + make_interval(mins => v_duration) + interval '60 minutes',
         status = 'scheduled'
   where interview_id = i.id;

  insert into application_events (application_id, event_type, actor_type, actor_id, reason, metadata)
  values (i.application_id, 'interview_scheduled', 'recruiter', auth.uid(), p_reason,
          jsonb_build_object('interview_id', i.id, 'rescheduled_from', i.scheduled_at, 'scheduled_at', p_scheduled_at));
  perform omelo_private.omelo_notify(i.person_id, 'interview_scheduled', 'Interview time changed',
    'Your ' || coalesce(i.round_name, 'interview') || ' was moved. Please confirm the new time.',
    'interview', i.id, '/applications/' || i.application_id);

  v_payload := omelo_private.omelo_interview_payload(i.id)
               || jsonb_build_object('previous_scheduled_at', i.scheduled_at, 'reason', p_reason);
  perform omelo_private.omelo_enqueue_email(i.person_id, 'interview_rescheduled',
    'Interview time changed: ' || (v_payload->>'job_title'), v_payload,
    'interview_rescheduled:' || i.id || ':' || extract(epoch from p_scheduled_at)::bigint);
  perform omelo_private.omelo_queue_interview_reminders(i.id);
end;
$$;

create or replace function public.omelo_cancel_interview(p_interview_id uuid, p_reason text)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare i interviews; v_is_candidate boolean; v_payload jsonb; v_lead uuid;
begin
  select * into i from interviews where id = p_interview_id;
  v_is_candidate := i.person_id = auth.uid();
  if i.id is null or not (v_is_candidate or omelo_private.omelo_can_access_job(i.job_id)) then
    raise exception 'Interview not found, or you do not have access to it' using errcode = '42501';
  end if;
  if i.status not in ('scheduled','rescheduled') then
    raise exception 'This interview is %', i.status using errcode = '22023';
  end if;
  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'A reason is required to cancel' using errcode = '22023';
  end if;
  update interviews set status = 'cancelled', cancelled_at = now(), cancel_reason = trim(p_reason) where id = i.id;
  update interview_rooms set status = 'cancelled', ended_at = now(), ended_by = auth.uid()
   where interview_id = i.id and status in ('scheduled','live');
  perform omelo_private.omelo_queue_interview_reminders(i.id);   -- cancels queued reminders

  insert into application_events (application_id, event_type, actor_type, actor_id, reason, metadata)
  values (i.application_id, 'interview_completed',
          case when v_is_candidate then 'candidate' else 'recruiter' end::actor_type, auth.uid(), trim(p_reason),
          jsonb_build_object('interview_id', i.id, 'outcome', 'cancelled'));

  if v_is_candidate then
    select person_id into v_lead from interview_interviewers where interview_id = i.id order by is_lead desc limit 1;
    if coalesce(v_lead, i.created_by) is not null then
      perform omelo_private.omelo_notify(coalesce(v_lead, i.created_by), 'application_update',
        'Candidate cannot attend',
        (select display_name from persons where id = i.person_id) || ' cancelled ' ||
          coalesce(i.round_name, 'the interview') || ': ' || trim(p_reason),
        'interview', i.id, '/dashboard/candidates/' || i.application_id);
    end if;
  else
    perform omelo_private.omelo_notify(i.person_id, 'interview_scheduled', 'Interview cancelled',
      trim(p_reason), 'interview', i.id, '/applications/' || i.application_id);
    v_payload := omelo_private.omelo_interview_payload(i.id);
    perform omelo_private.omelo_enqueue_email(i.person_id, 'interview_cancelled',
      'Interview cancelled: ' || (v_payload->>'job_title'), v_payload, 'interview_cancelled:' || i.id);
  end if;
end;
$$;

-- Complete without the room (phone / in person, or after the fact),
-- recording the caller's feedback in the structured feedback table.
drop function if exists public.omelo_complete_interview(uuid, interview_status, smallint, text, text);
create or replace function public.omelo_complete_interview(
  p_interview_id   uuid,
  p_outcome        interview_status default 'completed',
  p_recommendation text     default null,
  p_rating         smallint default null,
  p_strengths      text     default null,
  p_concerns       text     default null,
  p_notes          text     default null
) returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare i interviews; v_payload jsonb;
begin
  select * into i from interviews where id = p_interview_id;
  if i.id is null or not omelo_private.omelo_can_access_job(i.job_id) then
    raise exception 'Interview not found, or you do not have access to it' using errcode = '42501';
  end if;
  if i.status not in ('scheduled','rescheduled') then
    raise exception 'This interview is already %', i.status using errcode = '22023';
  end if;
  if p_outcome not in ('completed','no_show_candidate','no_show_employer') then
    raise exception 'Outcome must be completed or a no-show' using errcode = '22023';
  end if;

  update interviews set status = p_outcome, completed_at = now() where id = i.id;
  update interview_rooms set status = 'ended', ended_at = coalesce(ended_at, now()), ended_by = auth.uid()
   where interview_id = i.id and status in ('scheduled','live');
  update interview_sessions set ended_at = now(), duration_seconds = extract(epoch from now() - started_at)::int
   where interview_id = i.id and ended_at is null;
  perform omelo_private.omelo_queue_interview_reminders(i.id);

  insert into application_events (application_id, event_type, actor_type, actor_id, metadata)
  values (i.application_id, 'interview_completed', 'recruiter', auth.uid(),
          jsonb_build_object('interview_id', i.id, 'round', i.round, 'round_name', i.round_name, 'outcome', p_outcome));

  if p_recommendation is not null or p_rating is not null or coalesce(trim(p_notes), '') <> ''
     or coalesce(trim(p_strengths), '') <> '' or coalesce(trim(p_concerns), '') <> '' then
    perform public.omelo_save_interview_feedback(i.id, p_recommendation, p_rating, p_strengths, p_concerns,
                                                 p_notes, null, null, null, p_recommendation is not null);
  end if;

  if p_outcome = 'completed' then
    perform omelo_private.omelo_notify(i.person_id, 'application_update', 'Interview completed',
      'Your ' || coalesce(i.round_name, 'interview') || ' has been submitted to the employer. You will be notified when they update your application.',
      'interview', i.id, '/applications/' || i.application_id);
    v_payload := omelo_private.omelo_interview_payload(i.id);
    perform omelo_private.omelo_enqueue_email(i.person_id, 'interview_completed',
      'Interview completed: ' || (v_payload->>'job_title'), v_payload, 'interview_completed:' || i.id);
  end if;
end;
$$;

-- ============================================================
-- 8. FEEDBACK (private to the hiring team)
-- ============================================================
create or replace function public.omelo_save_interview_feedback(
  p_interview_id   uuid,
  p_recommendation text     default null,
  p_rating         smallint default null,
  p_strengths      text     default null,
  p_concerns       text     default null,
  p_notes          text     default null,
  p_competencies   jsonb    default null,
  p_skills         jsonb    default null,
  p_answers        jsonb    default null,
  p_submit         boolean  default false
) returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare i interviews; v_id uuid; v_ans jsonb; v_was_submitted boolean;
begin
  select * into i from interviews where id = p_interview_id;
  if i.id is null
     or not (omelo_private.omelo_is_interview_panelist(i.id) or omelo_private.omelo_is_hiring_team_for_interview(i.id)) then
    raise exception 'Only the interview panel and hiring team can record feedback' using errcode = '42501';
  end if;
  if i.status = 'cancelled' then
    raise exception 'This interview was cancelled' using errcode = '22023';
  end if;
  if p_recommendation is not null and p_recommendation not in ('strong_hire','hire','further_review','no_hire') then
    raise exception 'Recommendation must be strong_hire, hire, further_review or no_hire' using errcode = '22023';
  end if;
  if p_rating is not null and p_rating not between 1 and 5 then
    raise exception 'Rating is 1 to 5' using errcode = '22023';
  end if;
  if p_submit and p_recommendation is null then
    raise exception 'Choose a recommendation before submitting' using errcode = '22023';
  end if;
  if p_competencies is not null and jsonb_typeof(p_competencies) <> 'array' then
    raise exception 'competencies must be an array' using errcode = '22023';
  end if;
  if p_skills is not null and jsonb_typeof(p_skills) <> 'array' then
    raise exception 'skills must be an array' using errcode = '22023';
  end if;

  select status = 'submitted' into v_was_submitted
    from interview_feedback where interview_id = i.id and interviewer_id = auth.uid();

  insert into interview_feedback (interview_id, application_id, company_id, interviewer_id, recommendation,
                                  overall_rating, strengths, concerns, notes, competencies, skills_assessed,
                                  status, submitted_at)
  values (i.id, i.application_id, i.company_id, auth.uid(), p_recommendation, p_rating,
          nullif(trim(p_strengths), ''), nullif(trim(p_concerns), ''), nullif(trim(p_notes), ''),
          coalesce(p_competencies, '[]'), coalesce(p_skills, '[]'),
          case when p_submit then 'submitted' else 'draft' end,
          case when p_submit then now() end)
  on conflict (interview_id, interviewer_id) do update
     set recommendation  = excluded.recommendation,
         overall_rating  = excluded.overall_rating,
         strengths       = excluded.strengths,
         concerns        = excluded.concerns,
         notes           = excluded.notes,
         competencies    = case when p_competencies is null then interview_feedback.competencies else excluded.competencies end,
         skills_assessed = case when p_skills is null then interview_feedback.skills_assessed else excluded.skills_assessed end,
         status          = case when interview_feedback.status = 'submitted' then 'submitted' else excluded.status end,
         submitted_at    = coalesce(interview_feedback.submitted_at, excluded.submitted_at),
         updated_at      = now()
  returning id into v_id;

  if p_answers is not null and jsonb_typeof(p_answers) = 'array' then
    for v_ans in select * from jsonb_array_elements(p_answers) loop
      continue when not exists (select 1 from interview_questions q
                                 where q.id = nullif(v_ans->>'question_id', '')::uuid and q.interview_id = i.id);
      insert into interview_answers (interview_id, question_id, interviewer_id, evaluation, notes)
      values (i.id, (v_ans->>'question_id')::uuid, auth.uid(),
              nullif(v_ans->>'evaluation', ''), nullif(trim(v_ans->>'notes'), ''))
      on conflict (question_id, interviewer_id) do update
         set evaluation = excluded.evaluation, notes = excluded.notes, updated_at = now();
    end loop;
  end if;

  if p_submit and not coalesce(v_was_submitted, false) then
    perform omelo_private.omelo_emit('InterviewFeedbackSubmitted', 'interview', i.id, i.company_id, i.person_id,
      jsonb_build_object('application_id', i.application_id, 'round', i.round, 'round_name', i.round_name,
                         'recommendation', p_recommendation, 'rating', p_rating));
  end if;
  return v_id;
end;
$$;

-- ============================================================
-- 9. THE ROOM
-- ============================================================

-- Called (as the user) by the meet-token Edge Function, which mints a media
-- token only when this returns state = 'admitted'.
create or replace function public.omelo_meet_join(p_room_name text)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare
  r interview_rooms; i interviews; p interview_participants;
  v_uid uuid := auth.uid(); v_role text; v_name text;
begin
  if v_uid is null then
    raise exception 'Sign in to join this interview' using errcode = '42501';
  end if;
  select * into r from interview_rooms where room_name = p_room_name;
  if r.id is null then
    raise exception 'Interview not found' using errcode = '42501';
  end if;
  select * into i from interviews where id = r.interview_id;

  -- Who are you to this interview?
  select * into p from interview_participants where interview_id = i.id and person_id = v_uid;
  if p.id is null then
    if omelo_private.omelo_is_hiring_team_for_interview(i.id) then
      insert into interview_participants (interview_id, person_id, display_name, role)
      values (i.id, v_uid, (select display_name from persons where id = v_uid), 'observer')
      returning * into p;
    else
      raise exception 'Interview not found' using errcode = '42501';   -- do not confirm the room exists
    end if;
  end if;
  v_role := p.role;

  -- Rate limit join attempts.
  if (select count(*) from meet_events
       where interview_id = i.id and actor_id = v_uid and occurred_at > now() - interval '1 minute') >= 20 then
    raise exception 'Too many attempts. Wait a moment and try again.' using errcode = '54000';
  end if;

  if p.status in ('removed','denied') then
    raise exception 'You cannot join this interview' using errcode = '42501';
  end if;
  if i.status = 'cancelled' or r.status = 'cancelled' then
    raise exception 'This interview was cancelled' using errcode = '22023';
  end if;
  if r.status in ('ended','expired') or i.status in ('completed','no_show_candidate','no_show_employer') then
    raise exception 'This interview has ended' using errcode = '22023';
  end if;
  if now() > r.closes_at then
    update interview_rooms set status = 'expired', ended_at = now() where id = r.id;
    insert into meet_events (interview_id, actor_id, event) values (i.id, v_uid, 'expired');
    raise exception 'This interview has ended' using errcode = '22023';
  end if;

  select display_name into v_name from persons where id = v_uid;

  if now() < r.opens_at then
    insert into meet_events (interview_id, actor_id, event) values (i.id, v_uid, 'too_early');
    return jsonb_build_object('state', 'too_early', 'role', v_role, 'opens_at', r.opens_at,
      'scheduled_at', i.scheduled_at, 'interview', omelo_private.omelo_interview_payload(i.id));
  end if;

  -- Candidates wait to be admitted (unless already admitted earlier in this room).
  if v_role = 'candidate' and r.waiting_room and p.admitted_at is null then
    if p.status <> 'waiting' then
      update interview_participants set status = 'waiting', requested_at = now() where id = p.id;
      insert into meet_events (interview_id, actor_id, subject_person_id, event)
      values (i.id, v_uid, v_uid, 'join_requested');
      perform omelo_private.omelo_notify(ii.person_id, 'application_update', 'Candidate is waiting',
                v_name || ' is in the waiting room for ' || coalesce(i.round_name, 'the interview') || '.',
                'interview', i.id, '/meet/' || r.room_name)
         from interview_interviewers ii where ii.interview_id = i.id;
    end if;
    return jsonb_build_object('state', 'waiting', 'role', v_role, 'room_name', r.room_name,
      'scheduled_at', i.scheduled_at, 'interview', omelo_private.omelo_interview_payload(i.id));
  end if;

  -- In.
  update interview_participants
     set status = 'in_room', joined_at = now(),
         admitted_at = coalesce(admitted_at, now()),
         admitted_by = coalesce(admitted_by, v_uid)
   where id = p.id;
  if r.status = 'scheduled' then
    update interview_rooms set status = 'live', started_at = coalesce(started_at, now()) where id = r.id;
    insert into interview_sessions (interview_id, room_id) values (i.id, r.id);
    perform omelo_private.omelo_emit('MeetStarted', 'interview', i.id, i.company_id, i.person_id,
      jsonb_build_object('room_name', r.room_name, 'round_name', i.round_name));
  end if;
  insert into meet_events (interview_id, actor_id, subject_person_id, event, metadata)
  values (i.id, v_uid, v_uid, 'joined', jsonb_build_object('role', v_role));

  return jsonb_build_object(
    'state', 'admitted', 'room_name', r.room_name, 'role', v_role,
    'identity', v_uid, 'display_name', coalesce(v_name, 'Participant'),
    'can_publish', true,
    'can_moderate', v_role in ('host','interviewer','observer'),
    'closes_at', r.closes_at,
    'interview', omelo_private.omelo_interview_payload(i.id));
end;
$$;

-- The employer side of a room: must be panel or hiring team.
create or replace function omelo_private.omelo_meet_moderator_interview(p_interview_id uuid)
returns interviews
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare i interviews;
begin
  select * into i from interviews where id = p_interview_id;
  if i.id is null
     or not (omelo_private.omelo_is_interview_panelist(i.id) or omelo_private.omelo_is_hiring_team_for_interview(i.id)) then
    raise exception 'Only the interview panel can do that' using errcode = '42501';
  end if;
  return i;
end;
$$;
revoke execute on function omelo_private.omelo_meet_moderator_interview(uuid) from public, anon, authenticated;

create or replace function public.omelo_meet_admit(p_interview_id uuid, p_person_id uuid, p_admit boolean default true)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare i interviews; p interview_participants;
begin
  i := omelo_private.omelo_meet_moderator_interview(p_interview_id);
  select * into p from interview_participants where interview_id = i.id and person_id = p_person_id;
  if p.id is null or p.status <> 'waiting' then
    raise exception 'That person is not in the waiting room' using errcode = '22023';
  end if;
  if p_admit then
    update interview_participants set status = 'admitted', admitted_at = now(), admitted_by = auth.uid() where id = p.id;
  else
    update interview_participants set status = 'denied', removed_at = now(), removed_by = auth.uid() where id = p.id;
  end if;
  insert into meet_events (interview_id, actor_id, subject_person_id, event)
  values (i.id, auth.uid(), p_person_id, case when p_admit then 'admitted' else 'denied' end);
end;
$$;

create or replace function public.omelo_meet_leave(p_interview_id uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  update interview_participants set status = 'left', left_at = now()
   where interview_id = p_interview_id and person_id = auth.uid() and status in ('waiting','admitted','in_room');
  if found then
    insert into meet_events (interview_id, actor_id, subject_person_id, event)
    values (p_interview_id, auth.uid(), auth.uid(), 'left');
  end if;
end;
$$;

-- Returns the room name so meet-control can eject them from the media server.
create or replace function public.omelo_meet_remove(p_interview_id uuid, p_person_id uuid, p_reason text default null)
returns text
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare i interviews; v_role text;
begin
  i := omelo_private.omelo_meet_moderator_interview(p_interview_id);
  select role into v_role from interview_participants where interview_id = i.id and person_id = p_person_id;
  if v_role is null then
    raise exception 'That person is not part of this interview' using errcode = '22023';
  end if;
  if v_role = 'host' and p_person_id <> auth.uid() then
    raise exception 'The host cannot be removed' using errcode = '42501';
  end if;
  update interview_participants
     set status = 'removed', removed_at = now(), removed_by = auth.uid(), remove_reason = nullif(trim(p_reason), '')
   where interview_id = i.id and person_id = p_person_id;
  insert into meet_events (interview_id, actor_id, subject_person_id, event, metadata)
  values (i.id, auth.uid(), p_person_id, 'removed', jsonb_build_object('reason', p_reason));
  return (select room_name from interview_rooms where interview_id = i.id);
end;
$$;

-- End the interview for everyone. The candidate is told it has gone to the employer.
create or replace function public.omelo_meet_end(p_interview_id uuid)
returns text
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare i interviews; r interview_rooms; v_payload jsonb;
begin
  i := omelo_private.omelo_meet_moderator_interview(p_interview_id);
  select * into r from interview_rooms where interview_id = i.id;
  if r.id is null then
    raise exception 'This interview is not on Omelo Meet' using errcode = '22023';
  end if;
  if r.status in ('ended','expired','cancelled') then
    return r.room_name;
  end if;

  update interview_rooms set status = 'ended', ended_at = now(), ended_by = auth.uid() where id = r.id;
  update interview_sessions set ended_at = now(), duration_seconds = extract(epoch from now() - started_at)::int
   where room_id = r.id and ended_at is null;
  update interview_participants set status = 'left', left_at = now()
   where interview_id = i.id and status in ('waiting','admitted','in_room');
  insert into meet_events (interview_id, actor_id, event) values (i.id, auth.uid(), 'ended');

  if i.status in ('scheduled','rescheduled') then
    update interviews set status = 'completed', completed_at = now() where id = i.id;
    perform omelo_private.omelo_queue_interview_reminders(i.id);
    insert into application_events (application_id, event_type, actor_type, actor_id, metadata)
    values (i.application_id, 'interview_completed', 'recruiter', auth.uid(),
            jsonb_build_object('interview_id', i.id, 'round', i.round, 'round_name', i.round_name,
                               'outcome', 'completed', 'via', 'omelo_meet'));
    perform omelo_private.omelo_notify(i.person_id, 'application_update', 'Interview completed',
      'Your ' || coalesce(i.round_name, 'interview') || ' has been submitted to the employer. You will be notified when they update your application.',
      'interview', i.id, '/applications/' || i.application_id);
    v_payload := omelo_private.omelo_interview_payload(i.id);
    perform omelo_private.omelo_enqueue_email(i.person_id, 'interview_completed',
      'Interview completed: ' || (v_payload->>'job_title'), v_payload, 'interview_completed:' || i.id);
    -- Ask each interviewer for feedback.
    perform omelo_private.omelo_notify(ii.person_id, 'application_update', 'Submit interview feedback',
              'Record your feedback for ' || (v_payload->>'candidate_name') || ' while it is fresh.',
              'interview', i.id, '/dashboard/candidates/' || i.application_id)
       from interview_interviewers ii where ii.interview_id = i.id;
  end if;

  perform omelo_private.omelo_emit('MeetEnded', 'interview', i.id, i.company_id, i.person_id,
    jsonb_build_object('room_name', r.room_name,
                       'duration_seconds', (select sum(duration_seconds) from interview_sessions where room_id = r.id)));
  return r.room_name;
end;
$$;

create or replace function public.omelo_report_meet_abuse(
  p_interview_id uuid, p_reason text, p_details text default null, p_reported_person_id uuid default null
) returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_id uuid; i interviews;
begin
  select * into i from interviews where id = p_interview_id;
  if i.id is null or not exists (select 1 from interview_participants
                                  where interview_id = i.id and person_id = auth.uid()) then
    raise exception 'Interview not found' using errcode = '42501';
  end if;
  if (select count(*) from meet_abuse_reports where reporter_id = auth.uid() and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'Too many reports. Our team has been alerted.' using errcode = '54000';
  end if;
  insert into meet_abuse_reports (interview_id, reporter_id, reported_person_id, reason, details)
  values (i.id, auth.uid(), p_reported_person_id, p_reason, nullif(trim(p_details), ''))
  returning id into v_id;
  insert into meet_events (interview_id, actor_id, subject_person_id, event, metadata)
  values (i.id, auth.uid(), p_reported_person_id, 'abuse_reported', jsonb_build_object('reason', p_reason));
  perform omelo_private.omelo_emit('MeetAbuseReported', 'interview', i.id, i.company_id, i.person_id,
    jsonb_build_object('report_id', v_id, 'reason', p_reason, 'reporter_id', auth.uid()));
  return v_id;
end;
$$;

-- Expire rooms nobody ended, and close their sessions.
create or replace function omelo_private.omelo_meet_housekeeping()
returns integer
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_count int;
begin
  with stale as (
    update interview_rooms set status = case when status = 'live' then 'ended' else 'expired' end,
                               ended_at = coalesce(ended_at, now())
     where status in ('scheduled','live') and closes_at < now()
    returning id, interview_id)
  select count(*) into v_count from stale;
  update interview_sessions set ended_at = now(), duration_seconds = extract(epoch from now() - started_at)::int
   where ended_at is null and room_id in (select id from interview_rooms where status in ('ended','expired'));
  update interview_participants p set status = 'left', left_at = now()
    from interview_rooms r
   where r.interview_id = p.interview_id and r.status in ('ended','expired') and p.status in ('waiting','admitted','in_room');
  return v_count;
end;
$$;
revoke execute on function omelo_private.omelo_meet_housekeeping() from public, anon, authenticated;

-- ============================================================
-- 10. GRANTS, REALTIME
-- ============================================================
do $$
declare fn text;
begin
  foreach fn in array array[
    'omelo_schedule_interview(uuid, timestamptz, integer, text, text, text, text, text, text, uuid[], jsonb, boolean, boolean)',
    'omelo_reschedule_interview(uuid, timestamptz, text, integer)',
    'omelo_cancel_interview(uuid, text)',
    'omelo_complete_interview(uuid, interview_status, text, smallint, text, text, text)',
    'omelo_save_interview_feedback(uuid, text, smallint, text, text, text, jsonb, jsonb, jsonb, boolean)',
    'omelo_interview_question_suggestions(uuid, text)',
    'omelo_meet_join(text)',
    'omelo_meet_admit(uuid, uuid, boolean)',
    'omelo_meet_leave(uuid)',
    'omelo_meet_remove(uuid, uuid, text)',
    'omelo_meet_end(uuid)',
    'omelo_report_meet_abuse(uuid, text, text, uuid)'
  ] loop
    execute format('revoke execute on function public.%s from public, anon', fn);
    execute format('grant execute on function public.%s to authenticated', fn);
  end loop;
end;
$$;

do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end;
$$;
alter publication supabase_realtime add table interview_participants, interview_rooms, meet_messages;
