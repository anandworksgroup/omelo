-- OMELO 35 (Release 1): accounts, progressive trust, rate limits, events, observability.
--
-- 1. Account deletion could not work: nine attribution FKs to persons were
--    NO ACTION, so deleting anyone who ever posted a job, ran an interview or
--    appears as an actor in an audit trail failed. They become SET NULL: the
--    hiring record survives, the attribution is removed.
-- 2. Progressive trust: email (and, when a provider exists, phone)
--    verification by one-time code. Codes are hashed; nothing is mandatory
--    unless an app_settings flag says so (offer acceptance can require it).
-- 3. Sessions: list and revoke your own sessions / sign out everywhere else.
-- 4. Account deletion with a 14-day grace period, processed daily by pg_cron.
-- 5. Rate limit on applying. 6. Missing domain events.
-- 7. Admin observability: system health and KPI functions.

-- 1 ---------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in
    select c.conname, c.conrelid::regclass as tbl, pg_get_constraintdef(c.oid) as def
      from pg_constraint c
     where c.contype = 'f' and c.confdeltype = 'a'
       and c.confrelid in ('public.persons'::regclass, 'auth.users'::regclass)
       and c.connamespace = 'public'::regnamespace
  loop
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
    execute format('alter table %s add constraint %I %s on delete set null', r.tbl, r.conname, r.def);
  end loop;
end;
$$;

-- The confirmation email must survive the deletion it confirms.
alter table outbound_messages drop constraint if exists outbound_messages_person_id_fkey;
alter table outbound_messages add constraint outbound_messages_person_id_fkey
  foreign key (person_id) references persons(id) on delete set null;

-- Account deletion requests (used by the trust status below; see section 4).
create table if not exists account_deletion_requests (
  person_id     uuid primary key references persons(id) on delete cascade,
  requested_at  timestamptz not null default now(),
  scheduled_for timestamptz not null,
  reason        text,
  cancelled_at  timestamptz
);
alter table account_deletion_requests enable row level security;
create policy account_deletion_requests_own on account_deletion_requests
  for select to authenticated using (person_id = (select auth.uid()));

-- Feature flags for progressive trust.
insert into omelo_private.app_settings (key, value) values
  ('phone_otp_enabled', 'false'),
  ('require_verified_email_to_accept_offer', 'false')
on conflict (key) do nothing;

create or replace function omelo_private.omelo_setting(p_key text, p_default text default null)
returns text
language sql stable security definer
set search_path = public, omelo_private
as $$
  select coalesce((select value from omelo_private.app_settings where key = p_key), p_default);
$$;
revoke execute on function omelo_private.omelo_setting(text, text) from public, anon, authenticated;

-- 2 ---------------------------------------------------------------------------
create table if not exists omelo_private.verification_challenges (
  id           uuid primary key default gen_random_uuid(),
  person_id    uuid not null references persons(id) on delete cascade,
  channel      text not null check (channel in ('email','phone')),
  target       text not null,
  code_hash    text not null,
  attempts     smallint not null default 0,
  expires_at   timestamptz not null,
  consumed_at  timestamptz,
  created_at   timestamptz not null default now()
);
create index if not exists verification_challenges_person on omelo_private.verification_challenges (person_id, channel, created_at desc);
revoke all on omelo_private.verification_challenges from public, anon, authenticated;

create or replace function omelo_private.omelo_new_code()
returns text
language sql volatile
set search_path = public, omelo_private, extensions
as $$
  select lpad(((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint % 1000000))::text, 6, '0');
$$;
revoke execute on function omelo_private.omelo_new_code() from public, anon, authenticated;

create or replace function omelo_private.omelo_hash_code(p_challenge uuid, p_code text)
returns text
language sql immutable
set search_path = public, omelo_private, extensions
as $$
  select encode(extensions.digest(p_challenge::text || ':' || p_code, 'sha256'), 'hex');
$$;
revoke execute on function omelo_private.omelo_hash_code(uuid, text) from public, anon, authenticated;

create or replace function public.omelo_my_trust_status()
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select jsonb_build_object(
    'email', (select email from auth.users where id = auth.uid()),
    'email_verified', exists (select 1 from verifications where person_id = auth.uid() and type = 'email'
                                and status = 'verified' and revoked_at is null),
    'phone', (select phone from persons where id = auth.uid()),
    'phone_verified', exists (select 1 from verifications where person_id = auth.uid() and type = 'phone'
                                and status = 'verified' and revoked_at is null),
    'identity_verified', exists (select 1 from verifications where person_id = auth.uid() and type = 'identity'
                                   and status = 'verified' and revoked_at is null),
    'verified_employments', (select count(*) from experiences where person_id = auth.uid() and is_verified),
    'phone_otp_available', omelo_private.omelo_setting('phone_otp_enabled', 'false') = 'true',
    'email_required_to_accept_offer', omelo_private.omelo_setting('require_verified_email_to_accept_offer', 'false') = 'true',
    'deletion_scheduled_for', (select scheduled_for from account_deletion_requests
                                where person_id = auth.uid() and cancelled_at is null));
$$;

create or replace function public.omelo_request_email_verification()
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_uid uuid := auth.uid(); v_email text; v_id uuid; v_code text;
begin
  if v_uid is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  select email into v_email from auth.users where id = v_uid;
  if v_email is null then raise exception 'Your account has no email address' using errcode = '22023'; end if;
  if exists (select 1 from verifications where person_id = v_uid and type = 'email' and status = 'verified'
               and revoked_at is null and claim->>'email' = v_email) then
    return jsonb_build_object('already_verified', true);
  end if;
  if (select count(*) from omelo_private.verification_challenges
       where person_id = v_uid and channel = 'email' and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'Too many codes requested. Try again in an hour.' using errcode = '54000';
  end if;

  v_id := gen_random_uuid();
  v_code := omelo_private.omelo_new_code();
  insert into omelo_private.verification_challenges (id, person_id, channel, target, code_hash, expires_at)
  values (v_id, v_uid, 'email', v_email, omelo_private.omelo_hash_code(v_id, v_code), now() + interval '15 minutes');

  perform omelo_private.omelo_enqueue_email(v_uid, 'verify_email', 'Your Omelo verification code: ' || v_code,
    jsonb_build_object('code', v_code, 'expires_minutes', 15), 'verify_email:' || v_id);

  return jsonb_build_object('sent_to', regexp_replace(v_email, '^(.).*(@.*)$', '\1•••\2'),
                            'expires_at', now() + interval '15 minutes');
end;
$$;

create or replace function public.omelo_request_phone_verification(p_phone text)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_uid uuid := auth.uid(); v_phone text; v_id uuid; v_code text;
begin
  if v_uid is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  if omelo_private.omelo_setting('phone_otp_enabled', 'false') <> 'true' then
    raise exception 'Phone verification is not available yet' using errcode = '22023';
  end if;
  v_phone := regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g');
  if v_phone !~ '^\+[1-9][0-9]{7,14}$' then
    raise exception 'Enter your phone number with country code, for example +919876543210' using errcode = '22023';
  end if;
  if (select count(*) from omelo_private.verification_challenges
       where person_id = v_uid and channel = 'phone' and created_at > now() - interval '1 hour') >= 5 then
    raise exception 'Too many codes requested. Try again in an hour.' using errcode = '54000';
  end if;
  v_id := gen_random_uuid();
  v_code := omelo_private.omelo_new_code();
  insert into omelo_private.verification_challenges (id, person_id, channel, target, code_hash, expires_at)
  values (v_id, v_uid, 'phone', v_phone, omelo_private.omelo_hash_code(v_id, v_code), now() + interval '10 minutes');
  insert into outbound_messages (person_id, channel, template, to_address, payload, dedupe_key)
  values (v_uid, 'sms', 'verify_phone', v_phone, jsonb_build_object('code', v_code), 'verify_phone:' || v_id);
  return jsonb_build_object('sent_to', left(v_phone, 3) || '•••' || right(v_phone, 2),
                            'expires_at', now() + interval '10 minutes');
end;
$$;

create or replace function public.omelo_confirm_verification(p_channel text, p_code text)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_uid uuid := auth.uid(); c omelo_private.verification_challenges;
begin
  if v_uid is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  if p_channel not in ('email','phone') then raise exception 'Unknown channel' using errcode = '22023'; end if;
  select * into c from omelo_private.verification_challenges
   where person_id = v_uid and channel = p_channel and consumed_at is null and expires_at > now()
   order by created_at desc limit 1
   for update;
  if c.id is null then
    raise exception 'That code has expired. Ask for a new one.' using errcode = '22023';
  end if;
  if c.attempts >= 5 then
    raise exception 'Too many wrong attempts. Ask for a new code.' using errcode = '54000';
  end if;
  if omelo_private.omelo_hash_code(c.id, trim(coalesce(p_code, ''))) <> c.code_hash then
    update omelo_private.verification_challenges set attempts = attempts + 1 where id = c.id;
    raise exception 'That code is not right. Check it and try again.' using errcode = '22023';
  end if;

  update omelo_private.verification_challenges set consumed_at = now() where id = c.id;
  update verifications set status = 'revoked', revoked_at = now(), revoke_reason = 'superseded'
   where person_id = v_uid and type = p_channel::verification_type and status = 'verified' and revoked_at is null;
  insert into verifications (subject_type, subject_id, person_id, type, status, method, claim, verified_at)
  values ('person', v_uid, v_uid, p_channel::verification_type, 'verified', 'otp',
          jsonb_build_object(p_channel, c.target), now());
  if p_channel = 'phone' then
    update persons set phone = c.target where id = v_uid;
  end if;
  perform omelo_private.omelo_emit(case when p_channel = 'email' then 'EmailVerified' else 'PhoneVerified' end,
    'person', v_uid, null, v_uid, '{}'::jsonb);
  return jsonb_build_object('verified', true, 'channel', p_channel);
end;
$$;

-- Progressive requirement: only enforced when the flag is on.
create or replace function omelo_private.omelo_require_trust_for_offer()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if new.status = 'accepted' and old.status is distinct from 'accepted'
     and omelo_private.omelo_setting('require_verified_email_to_accept_offer', 'false') = 'true'
     and not exists (select 1 from verifications where person_id = new.person_id and type = 'email'
                       and status = 'verified' and revoked_at is null) then
    raise exception 'Verify your email address before accepting an offer' using errcode = '22023';
  end if;
  return new;
end;
$$;
revoke execute on function omelo_private.omelo_require_trust_for_offer() from public, anon, authenticated;
drop trigger if exists offers_require_trust on offers;
create trigger offers_require_trust before update of status on offers
  for each row execute function omelo_private.omelo_require_trust_for_offer();

-- Codes never outlive delivery: scrub them from the outbox once sent.
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
         payload = case when p_ok then payload - 'code' else payload end,
         subject = case when p_ok and template like 'verify_%' then 'Your Omelo verification code' else subject end,
         send_after = case when p_ok then send_after else now() + (attempts * interval '5 minutes') end
   where id = p_id and status = 'sending';
$$;
revoke execute on function public.omelo_comms_mark(uuid, boolean, text, text) from public, anon, authenticated;
grant execute on function public.omelo_comms_mark(uuid, boolean, text, text) to service_role;

-- 3 ---------------------------------------------------------------------------
create or replace function public.omelo_my_sessions()
returns table (id uuid, created_at timestamptz, last_active_at timestamptz, user_agent text,
               ip_hint text, is_current boolean)
language sql stable security definer
set search_path = public, omelo_private
as $$
  select s.id, s.created_at, coalesce(s.refreshed_at, s.updated_at, s.created_at), s.user_agent,
         case when s.ip is null then null
              when family(s.ip) = 4 then split_part(host(s.ip), '.', 1) || '.' || split_part(host(s.ip), '.', 2) || '.x.x'
              else left(host(s.ip), 9) || '…' end,
         s.id::text = (auth.jwt() ->> 'session_id')
    from auth.sessions s
   where s.user_id = auth.uid()
   order by coalesce(s.refreshed_at, s.updated_at, s.created_at) desc;
$$;

create or replace function public.omelo_revoke_session(p_session_id uuid)
returns boolean
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  delete from auth.sessions where id = p_session_id and user_id = auth.uid();
  return found;
end;
$$;

create or replace function public.omelo_revoke_other_sessions()
returns integer
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_count int;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  delete from auth.sessions
   where user_id = auth.uid()
     and id::text is distinct from (auth.jwt() ->> 'session_id');
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- 4 ---------------------------------------------------------------------------
-- Companies this person is the only active owner of, that have other active members.
create or replace function omelo_private.omelo_blocking_companies(p_person uuid)
returns text[]
language sql stable security definer
set search_path = public, omelo_private
as $$
  select coalesce(array_agg(c.display_name order by c.display_name), '{}')
    from companies c
   where c.deleted_at is null
     and exists (select 1 from company_members m where m.company_id = c.id and m.person_id = p_person
                   and m.role = 'owner' and m.is_active)
     and not exists (select 1 from company_members m where m.company_id = c.id and m.person_id <> p_person
                       and m.role = 'owner' and m.is_active)
     and exists (select 1 from company_members m where m.company_id = c.id and m.person_id <> p_person
                   and m.is_active);
$$;
revoke execute on function omelo_private.omelo_blocking_companies(uuid) from public, anon, authenticated;

create or replace function public.omelo_request_account_deletion(p_reason text default null)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_uid uuid := auth.uid(); v_blocking text[]; v_when timestamptz := now() + interval '14 days';
begin
  if v_uid is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  v_blocking := omelo_private.omelo_blocking_companies(v_uid);
  if cardinality(v_blocking) > 0 then
    raise exception 'Make another team member an owner of % before deleting your account', array_to_string(v_blocking, ', ')
      using errcode = '22023';
  end if;
  insert into account_deletion_requests (person_id, requested_at, scheduled_for, reason, cancelled_at)
  values (v_uid, now(), v_when, nullif(trim(p_reason), ''), null)
  on conflict (person_id) do update
     set requested_at = now(), scheduled_for = v_when, reason = excluded.reason, cancelled_at = null;
  perform omelo_private.omelo_notify(v_uid, 'system', 'Account deletion scheduled',
    'Your account and data will be deleted on ' || to_char(v_when, 'DD Mon YYYY') ||
    '. You can cancel any time before then in Settings.', 'person', v_uid, '/settings');
  perform omelo_private.omelo_enqueue_email(v_uid, 'account_deletion_scheduled', 'Your Omelo account will be deleted',
    jsonb_build_object('scheduled_for', v_when), 'account_deletion:' || v_uid || ':' || extract(epoch from now())::bigint);
  perform omelo_private.omelo_emit('AccountDeletionRequested', 'person', v_uid, null, v_uid,
    jsonb_build_object('scheduled_for', v_when));
  return jsonb_build_object('scheduled_for', v_when);
end;
$$;

create or replace function public.omelo_cancel_account_deletion()
returns boolean
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  update account_deletion_requests set cancelled_at = now()
   where person_id = auth.uid() and cancelled_at is null;
  if found then
    perform omelo_private.omelo_emit('AccountDeletionCancelled', 'person', auth.uid(), null, auth.uid(), '{}'::jsonb);
  end if;
  return found;
end;
$$;

create or replace function omelo_private.omelo_process_account_deletions()
returns integer
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare r record; v_count int := 0;
begin
  for r in
    select person_id from account_deletion_requests
     where cancelled_at is null and scheduled_for <= now()
  loop
    -- Still blocked (someone joined meanwhile): push back a day rather than orphan a team.
    if cardinality(omelo_private.omelo_blocking_companies(r.person_id)) > 0 then
      update account_deletion_requests set scheduled_for = now() + interval '1 day' where person_id = r.person_id;
      continue;
    end if;
    -- Companies where they were the only member: close them.
    update jobs set status = 'closed', closed_at = now()
     where status in ('published','paused','draft')
       and company_id in (select c.id from companies c
                           where exists (select 1 from company_members m where m.company_id = c.id and m.person_id = r.person_id and m.role = 'owner')
                             and not exists (select 1 from company_members m where m.company_id = c.id and m.person_id <> r.person_id and m.is_active));
    update companies c set deleted_at = now()
     where c.deleted_at is null
       and exists (select 1 from company_members m where m.company_id = c.id and m.person_id = r.person_id and m.role = 'owner')
       and not exists (select 1 from company_members m where m.company_id = c.id and m.person_id <> r.person_id and m.is_active);
    perform omelo_private.omelo_emit('AccountDeleted', 'person', r.person_id, null, null, '{}'::jsonb);
    delete from auth.users where id = r.person_id;   -- cascades to persons and personal data
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
revoke execute on function omelo_private.omelo_process_account_deletions() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'omelo-account-deletions';
select cron.schedule('omelo-account-deletions', '17 3 * * *', $$ select omelo_private.omelo_process_account_deletions() $$);

-- 5 ---------------------------------------------------------------------------
-- Invoker rights on purpose: current_user must be the real caller, and the
-- applicant can count their own applications through RLS.
create or replace function omelo_private.omelo_rate_limit_applications()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if not omelo_private.omelo_is_privileged() then
    if (select count(*) from applications where person_id = new.person_id and applied_at > now() - interval '1 hour') >= 30
       or (select count(*) from applications where person_id = new.person_id and applied_at > now() - interval '1 day') >= 100 then
      raise exception 'You have applied to a lot of jobs today. Please wait a while before applying again.' using errcode = '54000';
    end if;
  end if;
  return new;
end;
$$;
revoke execute on function omelo_private.omelo_rate_limit_applications() from public, anon, authenticated;
drop trigger if exists applications_rate_limit on applications;
create trigger applications_rate_limit before insert on applications
  for each row execute function omelo_private.omelo_rate_limit_applications();

-- 6 ---------------------------------------------------------------------------
create or replace function omelo_private.omelo_emit_profile_events()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_person uuid; v_type text; v_payload jsonb := '{}'::jsonb; v_agg text;
begin
  if tg_table_name = 'persons' then
    v_person := new.id; v_agg := 'person';
    if tg_op = 'INSERT' then
      v_type := 'WorkerRegistered';
      v_payload := jsonb_build_object('country_code', new.country_code);
    else
      if (to_jsonb(new) - 'updated_at' - 'last_active_at') is not distinct from (to_jsonb(old) - 'updated_at' - 'last_active_at') then
        return new;
      end if;
      v_type := 'ProfileUpdated';
    end if;
  elsif tg_table_name = 'work_identities' then
    v_person := new.person_id; v_agg := 'work_identity';
    if tg_op = 'INSERT' then
      v_type := 'IdentityCreated';
      v_payload := jsonb_build_object('profession_id', new.profession_id, 'is_primary', new.is_primary);
    else
      if (to_jsonb(new) - 'updated_at' - 'completeness_score' - 'identity_embedding')
         is not distinct from (to_jsonb(old) - 'updated_at' - 'completeness_score' - 'identity_embedding') then
        return new;
      end if;
      v_type := 'ProfileUpdated';
    end if;
  elsif tg_table_name = 'person_skills' then
    v_person := new.person_id; v_agg := 'person'; v_type := 'SkillAdded';
    v_payload := jsonb_build_object('skill_id', new.skill_id, 'work_identity_id', new.work_identity_id,
                                    'proficiency', new.proficiency);
  end if;

  -- ProfileUpdated is throttled to one per aggregate per 10 minutes.
  if v_type = 'ProfileUpdated' and exists (
       select 1 from domain_events
        where event_type = 'ProfileUpdated' and aggregate_id = case when v_agg = 'person' then v_person else new.id end
          and occurred_at > now() - interval '10 minutes') then
    return new;
  end if;

  perform omelo_private.omelo_emit(v_type, v_agg, case when v_agg = 'person' then v_person else new.id end,
                                   null, v_person, v_payload);
  return new;
end;
$$;
revoke execute on function omelo_private.omelo_emit_profile_events() from public, anon, authenticated;

drop trigger if exists persons_emit_events on persons;
create trigger persons_emit_events after insert or update on persons
  for each row execute function omelo_private.omelo_emit_profile_events();
drop trigger if exists work_identities_emit_events on work_identities;
create trigger work_identities_emit_events after insert or update on work_identities
  for each row execute function omelo_private.omelo_emit_profile_events();
drop trigger if exists person_skills_emit_events on person_skills;
create trigger person_skills_emit_events after insert on person_skills
  for each row execute function omelo_private.omelo_emit_profile_events();

create or replace function omelo_private.omelo_emit_job_created()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  perform omelo_private.omelo_emit('JobCreated', 'job', new.id, new.company_id, null,
    jsonb_build_object('profession_id', new.profession_id, 'category_id', new.category_id,
                       'work_type', new.work_type, 'country_code', new.country_code));
  return new;
end;
$$;
revoke execute on function omelo_private.omelo_emit_job_created() from public, anon, authenticated;
drop trigger if exists jobs_emit_created on jobs;
create trigger jobs_emit_created after insert on jobs
  for each row execute function omelo_private.omelo_emit_job_created();

create or replace function omelo_private.omelo_emit_interview_joined()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare i interviews;
begin
  if new.event = 'joined' then
    select * into i from interviews where id = new.interview_id;
    perform omelo_private.omelo_emit('InterviewJoined', 'interview', i.id, i.company_id, i.person_id,
      jsonb_build_object('participant_id', new.subject_person_id, 'role', new.metadata->>'role',
                         'application_id', i.application_id));
  end if;
  return new;
end;
$$;
revoke execute on function omelo_private.omelo_emit_interview_joined() from public, anon, authenticated;
drop trigger if exists meet_events_emit_joined on meet_events;
create trigger meet_events_emit_joined after insert on meet_events
  for each row execute function omelo_private.omelo_emit_interview_joined();

-- 7 ---------------------------------------------------------------------------
create or replace function public.omelo_admin_system_health(p_hours integer default 24)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private, extensions
as $$
declare v_since timestamptz := now() - make_interval(hours => greatest(1, least(coalesce(p_hours, 24), 720)));
begin
  if not omelo_private.omelo_is_platform_admin() then
    raise exception 'Platform administrators only' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'window_hours', greatest(1, least(coalesce(p_hours, 24), 720)),
    'generated_at', now(),
    'edge_function_calls', (select jsonb_build_object(
        'total', count(*),
        'failed', count(*) filter (where status_code is null or status_code >= 400),
        'last_error', (select left(coalesce(error_msg, content::text), 300) from net._http_response
                        where created >= v_since and (status_code is null or status_code >= 400)
                        order by created desc limit 1))
      from net._http_response where created >= v_since),
    'email', (select jsonb_build_object(
        'by_status', coalesce(jsonb_object_agg(status, n), '{}'::jsonb),
        'overdue_queued', (select count(*) from outbound_messages where status = 'queued' and send_after < now() - interval '15 minutes'),
        'failed_recent', (select count(*) from outbound_messages where status = 'failed' and created_at >= v_since))
      from (select status, count(*) n from outbound_messages where created_at >= v_since group by status) x),
    'meet', jsonb_build_object(
        'rooms_live', (select count(*) from interview_rooms where status = 'live'),
        'sessions', (select count(*) from interview_sessions where started_at >= v_since),
        'joins', (select count(*) from meet_events where event = 'joined' and occurred_at >= v_since),
        'expired_unended', (select count(*) from meet_events where event = 'expired' and occurred_at >= v_since),
        'abuse_reports_open', (select count(*) from meet_abuse_reports where status = 'open')),
    'trust_and_safety', jsonb_build_object(
        'reports_open', (select count(*) from reports where status::text in ('open','pending','new')),
        'fraud_signals', (select count(*) from fraud_signals where detected_at >= v_since)),
    'events', (select coalesce(jsonb_object_agg(event_type, n), '{}'::jsonb)
                 from (select event_type, count(*) n from domain_events where occurred_at >= v_since group by 1) e),
    'cron', (select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'schedule', j.schedule, 'active', j.active,
                         'last_status', d.status, 'last_run', d.end_time, 'last_message', left(d.return_message, 200))), '[]'::jsonb)
               from cron.job j
               left join lateral (select status, end_time, return_message from cron.job_run_details r
                                   where r.jobid = j.jobid order by r.runid desc limit 1) d on true),
    'accounts', jsonb_build_object(
        'signups', (select count(*) from domain_events where event_type = 'WorkerRegistered' and occurred_at >= v_since),
        'deletions_pending', (select count(*) from account_deletion_requests where cancelled_at is null))
  );
end;
$$;

create or replace function public.omelo_admin_kpis(p_days integer default 30)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare
  v_since timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 365)));
  f record; t record;
begin
  if not omelo_private.omelo_is_platform_admin() then
    raise exception 'Platform administrators only' using errcode = '42501';
  end if;

  select count(*) filter (where event_type = 'WorkerApplied')        as applied,
         count(*) filter (where event_type = 'CandidateShortlisted') as shortlisted,
         count(*) filter (where event_type = 'InterviewScheduled')   as interviewed,
         count(*) filter (where event_type = 'OfferSent')            as offered,
         count(*) filter (where event_type = 'WorkerHired')          as hired,
         count(*) filter (where event_type = 'OfferAccepted')        as accepted,
         count(*) filter (where event_type = 'OfferDeclined')        as declined
    into f
    from domain_events where occurred_at >= v_since;

  with apps as (
    select aggregate_id, min(occurred_at) filter (where event_type = 'WorkerApplied') as applied_at,
           min(occurred_at) filter (where event_type = 'CandidateShortlisted') as shortlisted_at,
           min(occurred_at) filter (where event_type = 'InterviewScheduled') as interview_at,
           min(occurred_at) filter (where event_type = 'OfferSent') as offer_at,
           min(occurred_at) filter (where event_type = 'WorkerHired') as hired_at
      from domain_events
     where aggregate_type = 'application' and occurred_at >= v_since
     group by aggregate_id)
  select percentile_cont(0.5) within group (order by extract(epoch from shortlisted_at - applied_at) / 3600) as h_shortlist,
         percentile_cont(0.5) within group (order by extract(epoch from interview_at - applied_at) / 3600)   as h_interview,
         percentile_cont(0.5) within group (order by extract(epoch from offer_at - applied_at) / 3600)       as h_offer,
         percentile_cont(0.5) within group (order by extract(epoch from hired_at - applied_at) / 3600)       as h_hire
    into t
    from apps where applied_at is not null;

  return jsonb_build_object(
    'window_days', greatest(1, least(coalesce(p_days, 30), 365)),
    'marketplace', jsonb_build_object(
      'active_workers', (select count(distinct person_id) from domain_events where occurred_at >= v_since and person_id is not null),
      'active_employers', (select count(distinct company_id) from domain_events where occurred_at >= v_since and company_id is not null),
      'published_jobs', (select count(*) from jobs where status = 'published'),
      'job_fill_rate', (select round(count(*) filter (where exists (select 1 from applications a where a.job_id = j.id and a.state = 'hired'))::numeric
                                     / nullif(count(*), 0), 3)
                          from jobs j where j.status in ('closed','expired') and coalesce(j.closed_at, j.updated_at) >= v_since)),
    'funnel', jsonb_build_object('applied', f.applied, 'shortlisted', f.shortlisted, 'interviewed', f.interviewed,
                                 'offered', f.offered, 'hired', f.hired),
    'conversion', jsonb_build_object(
      'apply_to_shortlist', round(f.shortlisted::numeric / nullif(f.applied, 0), 3),
      'shortlist_to_interview', round(f.interviewed::numeric / nullif(f.shortlisted, 0), 3),
      'interview_to_offer', round(f.offered::numeric / nullif(f.interviewed, 0), 3),
      'offer_to_hire', round(f.hired::numeric / nullif(f.offered, 0), 3),
      'offer_acceptance', round(f.accepted::numeric / nullif(f.accepted + f.declined, 0), 3)),
    'median_hours', jsonb_build_object('to_shortlist', round(t.h_shortlist::numeric, 1), 'to_interview', round(t.h_interview::numeric, 1),
                                       'to_offer', round(t.h_offer::numeric, 1), 'to_hire', round(t.h_hire::numeric, 1)),
    'workers', jsonb_build_object(
      'email_verified', (select count(distinct person_id) from verifications where type = 'email' and status = 'verified' and revoked_at is null),
      'with_verified_employment', (select count(distinct person_id) from experiences where is_verified))
  );
end;
$$;

-- Grants --------------------------------------------------------------------
do $$
declare fn text;
begin
  foreach fn in array array[
    'omelo_my_trust_status()',
    'omelo_request_email_verification()',
    'omelo_request_phone_verification(text)',
    'omelo_confirm_verification(text, text)',
    'omelo_my_sessions()',
    'omelo_revoke_session(uuid)',
    'omelo_revoke_other_sessions()',
    'omelo_request_account_deletion(text)',
    'omelo_cancel_account_deletion()',
    'omelo_admin_system_health(integer)',
    'omelo_admin_kpis(integer)'
  ] loop
    execute format('revoke execute on function public.%s from public, anon', fn);
    execute format('grant execute on function public.%s to authenticated', fn);
  end loop;
end;
$$;
