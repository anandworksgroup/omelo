drop function if exists public.omelo_schedule_interview(uuid, timestamptz, integer, text, text, text, text, text, text, uuid[], jsonb, boolean, boolean);

create or replace function public.omelo_schedule_interview(
  p_application_id    uuid,
  p_scheduled_at      timestamptz,
  p_duration_minutes  integer  default null,
  p_round_name        text     default null,
  p_round_kind        text     default null,
  p_meeting_mode      text     default null,
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

revoke execute on function public.omelo_schedule_interview(uuid, timestamptz, integer, text, text, text, text, text, text, uuid[], jsonb, boolean, boolean) from public, anon;
grant execute on function public.omelo_schedule_interview(uuid, timestamptz, integer, text, text, text, text, text, text, uuid[], jsonb, boolean, boolean) to authenticated;