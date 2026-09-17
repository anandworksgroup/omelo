alter type notification_type add value if not exists 'message_received';

drop policy if exists conversations_participant on conversations;

create policy conversations_read on conversations for select to authenticated
  using (person_id = (select auth.uid())
      or omelo_private.omelo_has_company_role(company_id,
           array['owner','admin','recruiter','hiring_manager','hr']::company_role[]));

create policy conversations_archive on conversations for update to authenticated
  using (person_id = (select auth.uid())
      or omelo_private.omelo_has_company_role(company_id,
           array['owner','admin','recruiter','hiring_manager','hr']::company_role[]))
  with check (person_id = (select auth.uid())
      or omelo_private.omelo_has_company_role(company_id,
           array['owner','admin','recruiter','hiring_manager','hr']::company_role[]));

create or replace function omelo_private.omelo_guard_conversation()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if omelo_private.omelo_is_privileged() then
    return new;
  end if;
  if (to_jsonb(new) - 'person_archived' - 'company_archived')
       is distinct from (to_jsonb(old) - 'person_archived' - 'company_archived') then
    raise exception 'Only the archive setting of a conversation can be changed' using errcode = '42501';
  end if;
  if new.person_archived is distinct from old.person_archived and old.person_id <> auth.uid() then
    raise exception 'You can only archive your own side of a conversation' using errcode = '42501';
  end if;
  if new.company_archived is distinct from old.company_archived and old.person_id = auth.uid() then
    raise exception 'You can only archive your own side of a conversation' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists conversations_guard on conversations;
create trigger conversations_guard before update on conversations
  for each row execute function omelo_private.omelo_guard_conversation();

drop policy if exists messages_insert on messages;
drop policy if exists messages_read on messages;
create policy messages_read on messages for select to authenticated
  using (exists (select 1 from conversations c
                  where c.id = messages.conversation_id
                    and (c.person_id = (select auth.uid())
                         or omelo_private.omelo_has_company_role(c.company_id,
                              array['owner','admin','recruiter','hiring_manager','hr']::company_role[]))));

drop policy if exists notifications_self on notifications;
create policy notifications_read on notifications for select to authenticated
  using (person_id = (select auth.uid()));
create policy notifications_mark on notifications for update to authenticated
  using (person_id = (select auth.uid())) with check (person_id = (select auth.uid()));
create policy notifications_delete on notifications for delete to authenticated
  using (person_id = (select auth.uid()));

create or replace function omelo_private.omelo_guard_notification()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if not omelo_private.omelo_is_privileged()
     and (to_jsonb(new) - 'read_at') is distinct from (to_jsonb(old) - 'read_at') then
    raise exception 'Only read status of a notification can be changed' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists notifications_guard on notifications;
create trigger notifications_guard before update on notifications
  for each row execute function omelo_private.omelo_guard_notification();

create or replace function public.omelo_start_conversation(p_application_id uuid)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare a applications; v_id uuid; v_is_candidate boolean;
begin
  if auth.uid() is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;
  select * into a from applications where id = p_application_id;
  v_is_candidate := a.person_id = auth.uid();
  if a.id is null
     or not (v_is_candidate
             or omelo_private.omelo_has_company_role(a.company_id,
                  array['owner','admin','recruiter','hiring_manager','hr']::company_role[])) then
    raise exception 'Application not found, or you do not have access to it' using errcode = '42501';
  end if;

  select id into v_id from conversations
   where company_id = a.company_id and person_id = a.person_id and job_id = a.job_id;
  if v_id is null then
    insert into conversations (company_id, person_id, job_id, application_id, initiated_by, subject)
    values (a.company_id, a.person_id, a.job_id, a.id,
            case when v_is_candidate then 'candidate' else 'recruiter' end::actor_type,
            (select title from jobs where id = a.job_id))
    on conflict (company_id, person_id, job_id) do nothing
    returning id into v_id;
    if v_id is null then
      select id into v_id from conversations
       where company_id = a.company_id and person_id = a.person_id and job_id = a.job_id;
    end if;
  end if;
  return v_id;
end;
$$;

create or replace function public.omelo_send_message(p_conversation_id uuid, p_body text)
returns bigint
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare
  c conversations; a applications;
  v_uid uuid := auth.uid(); v_is_candidate boolean; v_id bigint; v_body text;
  v_company text; v_job text; v_sender text; v_preview text; v_recipient uuid;
begin
  if v_uid is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;
  select * into c from conversations where id = p_conversation_id;
  v_is_candidate := c.person_id = v_uid;
  if c.id is null
     or not (v_is_candidate
             or omelo_private.omelo_has_company_role(c.company_id,
                  array['owner','admin','recruiter','hiring_manager','hr']::company_role[])) then
    raise exception 'Conversation not found' using errcode = '42501';
  end if;

  v_body := trim(coalesce(p_body, ''));
  if length(v_body) = 0 then
    raise exception 'Write a message first' using errcode = '22023';
  end if;
  if length(v_body) > 4000 then
    raise exception 'Messages can be up to 4000 characters' using errcode = '22023';
  end if;
  if (select count(*) from messages
       where sender_person_id = v_uid and sent_at > now() - interval '1 minute') >= 20 then
    raise exception 'You are sending messages too quickly' using errcode = '54000';
  end if;

  select * into a from applications where id = c.application_id;
  if not v_is_candidate and a.state in ('withdrawn','declined_by_candidate') then
    raise exception 'The candidate withdrew from this job, so you cannot send new messages' using errcode = '22023';
  end if;

  insert into messages (conversation_id, sender_person_id, sender_type, kind, body)
  values (c.id, v_uid, case when v_is_candidate then 'candidate' else 'recruiter' end::actor_type, 'text', v_body)
  returning id into v_id;

  update conversations
     set last_message_at = now(), person_archived = false, company_archived = false
   where id = c.id;

  select display_name into v_company from companies where id = c.company_id;
  select title into v_job from jobs where id = c.job_id;
  select display_name into v_sender from persons where id = v_uid;
  v_preview := left(regexp_replace(v_body, '\s+', ' ', 'g'), 140);

  if not v_is_candidate then
    perform omelo_private.omelo_notify(c.person_id, 'message_received',
      'New message from ' || coalesce(v_company, 'an employer'), v_preview,
      'conversation', c.id, '/messages/' || c.id);
    perform omelo_private.omelo_enqueue_email(c.person_id, 'new_message',
      'New message from ' || coalesce(v_company, 'an employer') || ' about ' || coalesce(v_job, 'your application'),
      jsonb_build_object('conversation_id', c.id, 'application_id', c.application_id,
                         'company_name', v_company, 'job_title', v_job, 'preview', v_preview),
      'new_message:' || c.id || ':' || floor(extract(epoch from now()) / 1800)::bigint,
      now() + interval '3 minutes');
  else
    for v_recipient in
      select distinct pid from (
        select m.sender_person_id as pid from messages m
         where m.conversation_id = c.id and m.sender_type = 'recruiter'
        union
        select j.created_by from jobs j where j.id = c.job_id
      ) x
      where pid is not null and pid <> v_uid
        and exists (select 1 from company_members cm
                     where cm.company_id = c.company_id and cm.person_id = pid and cm.is_active)
    loop
      perform omelo_private.omelo_notify(v_recipient, 'message_received',
        coalesce(v_sender, 'A candidate') || ' replied about ' || coalesce(v_job, 'a job'), v_preview,
        'conversation', c.id, '/dashboard/messages/' || c.id);
    end loop;
  end if;
  return v_id;
end;
$$;

create or replace function public.omelo_mark_conversation_read(p_conversation_id uuid)
returns integer
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare c conversations; v_is_candidate boolean; v_count int;
begin
  select * into c from conversations where id = p_conversation_id;
  v_is_candidate := c.person_id = auth.uid();
  if c.id is null
     or not (v_is_candidate
             or omelo_private.omelo_has_company_role(c.company_id,
                  array['owner','admin','recruiter','hiring_manager','hr']::company_role[])) then
    raise exception 'Conversation not found' using errcode = '42501';
  end if;
  update messages set read_at = now()
   where conversation_id = c.id and read_at is null
     and sender_type = case when v_is_candidate then 'recruiter' else 'candidate' end::actor_type;
  get diagnostics v_count = row_count;
  update notifications set read_at = now()
   where person_id = auth.uid() and entity_type = 'conversation' and entity_id = c.id and read_at is null;
  return v_count;
end;
$$;

do $$
declare fn text;
begin
  foreach fn in array array[
    'omelo_start_conversation(uuid)',
    'omelo_send_message(uuid, text)',
    'omelo_mark_conversation_read(uuid)'
  ] loop
    execute format('revoke execute on function public.%s from public, anon', fn);
    execute format('grant execute on function public.%s to authenticated', fn);
  end loop;
end;
$$;

create index if not exists messages_unread on messages (conversation_id, sender_type) where read_at is null;

alter publication supabase_realtime add table conversations, messages, notifications;