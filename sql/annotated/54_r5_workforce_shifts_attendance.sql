-- OMELO 54 — Release 5: workforce functions, part 2 of 3 (see 53 for the overview):
-- shift templates and shifts, assignment to shifts, replacements, check-in / check-out,
-- attendance review and correction, leave.
-- Rollback: drop the functions below.

-- 3. Shift templates and shifts --------------------------------------------------------------
create or replace function public.omelo_save_shift_template(p_requirement uuid, p_template jsonb, p_template_id uuid default null)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare r workforce_requirements; v_id uuid := coalesce(p_template_id, gen_random_uuid()); t jsonb := coalesce(p_template, '{}'::jsonb);
begin
  select * into r from workforce_requirements where id = p_requirement;
  if r.id is null then raise exception 'Requirement not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), r.company_id, 'manage_workforce');
  if p_template_id is not null and not exists (select 1 from shift_templates where id = p_template_id and requirement_id = r.id) then
    raise exception 'Template not found' using errcode = '42501';
  end if;
  begin
    insert into shift_templates (id, requirement_id, name, days_of_week, start_time, end_time, break_minutes,
                                 required_workers, shift_type, valid_from, valid_until, status, created_by)
    values (v_id, r.id, trim(t->>'name'), array(select jsonb_array_elements_text(t->'days_of_week'))::smallint[],
            (t->>'start_time')::time, (t->>'end_time')::time, coalesce((t->>'break_minutes')::int, 0),
            coalesce((t->>'required_workers')::int, 1), nullif(t->>'shift_type', '')::shift_type,
            nullif(t->>'valid_from', '')::date, nullif(t->>'valid_until', '')::date,
            coalesce(nullif(t->>'status', ''), 'active'), auth.uid())
    on conflict (id) do update
       set name = excluded.name, days_of_week = excluded.days_of_week, start_time = excluded.start_time,
           end_time = excluded.end_time, break_minutes = excluded.break_minutes, required_workers = excluded.required_workers,
           shift_type = excluded.shift_type, valid_from = excluded.valid_from, valid_until = excluded.valid_until,
           status = excluded.status;
  exception when others then
    raise exception 'Check the shift template: %', sqlerrm using errcode = '22023';
  end;
  return v_id;
end;
$$;

create or replace function omelo_private.omelo_generate_shifts_core(p_actor uuid, p_template uuid, p_from date, p_to date)
returns integer
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare t shift_templates; r workforce_requirements; d date; v_start timestamptz; v_end timestamptz; v_n int := 0; v_id uuid;
        v_from date; v_to date;
begin
  select * into t from shift_templates where id = p_template;
  select * into r from workforce_requirements where id = t.requirement_id;
  if t.id is null then raise exception 'Template not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(p_actor, r.company_id, 'manage_workforce');
  if t.status <> 'active' then raise exception 'This template is archived' using errcode = '22023'; end if;
  if p_to < p_from or p_to > p_from + 400 then
    raise exception 'Generate at most 400 days at a time' using errcode = '22023';
  end if;
  v_from := greatest(p_from, coalesce(t.valid_from, p_from), coalesce(r.start_date, p_from));
  v_to := least(p_to, coalesce(t.valid_until, p_to), coalesce(r.end_date, p_to));
  d := v_from;
  while d <= v_to loop
    if extract(isodow from d)::smallint = any (t.days_of_week) then
      v_start := (d + t.start_time)::timestamp at time zone r.timezone;
      v_end := (d + t.end_time + case when t.end_time <= t.start_time then interval '1 day' else interval '0' end)::timestamp
               at time zone r.timezone;
      insert into shifts (requirement_id, template_id, company_id, location_id, location_text, starts_at, ends_at, timezone,
                          break_minutes, required_workers, shift_type, kind, supervisor_id, created_by)
      values (r.id, t.id, r.company_id, r.location_id, coalesce(r.site_name || ', ', '') || coalesce(r.location_text, ''),
              v_start, v_end, r.timezone, t.break_minutes, t.required_workers, t.shift_type, 'regular', r.supervisor_id, p_actor)
      on conflict (template_id, starts_at) where template_id is not null do nothing
      returning id into v_id;
      if v_id is not null then
        insert into shift_codes (shift_id, code) values (v_id, lpad((floor(random() * 1000000))::int::text, 6, '0'));
        v_n := v_n + 1;
      end if;
      v_id := null;
    end if;
    d := d + 1;
  end loop;
  return v_n;
end;
$$;

create or replace function public.omelo_generate_shifts(p_template uuid, p_from date, p_to date)
returns integer
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  return omelo_private.omelo_generate_shifts_core(auth.uid(), p_template, p_from, p_to);
end;
$$;

create or replace function public.omelo_create_shift(p_requirement uuid, p_shift jsonb)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare r workforce_requirements; v_id uuid; s jsonb := coalesce(p_shift, '{}'::jsonb);
begin
  select * into r from workforce_requirements where id = p_requirement;
  if r.id is null then raise exception 'Requirement not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), r.company_id, 'manage_workforce');
  begin
    insert into shifts (requirement_id, company_id, location_id, location_text, starts_at, ends_at, timezone, break_minutes,
                        required_workers, shift_type, kind, instructions, supervisor_id, created_by)
    values (r.id, r.company_id, coalesce(nullif(s->>'location_id', '')::uuid, r.location_id),
            coalesce(nullif(s->>'location_text', ''), coalesce(r.site_name || ', ', '') || coalesce(r.location_text, '')),
            (s->>'starts_at')::timestamptz, (s->>'ends_at')::timestamptz, r.timezone,
            coalesce((s->>'break_minutes')::int, 0), coalesce((s->>'required_workers')::int, 1),
            nullif(s->>'shift_type', '')::shift_type, coalesce(nullif(s->>'kind', ''), 'regular'),
            nullif(s->>'instructions', ''), coalesce(nullif(s->>'supervisor_id', '')::uuid, r.supervisor_id), auth.uid())
    returning id into v_id;
  exception when others then
    raise exception 'Check the shift: %', sqlerrm using errcode = '22023';
  end;
  insert into shift_codes (shift_id, code) values (v_id, lpad((floor(random() * 1000000))::int::text, 6, '0'));
  return v_id;
end;
$$;

create or replace function public.omelo_update_shift(p_shift uuid, p_changes jsonb)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare s shifts; m record; c jsonb := coalesce(p_changes, '{}'::jsonb);
begin
  select * into s from shifts where id = p_shift;
  if s.id is null then raise exception 'Shift not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), s.company_id, 'manage_workforce');
  if s.status in ('completed','cancelled') then raise exception 'This shift is %', s.status using errcode = '22023'; end if;
  begin
    update shifts set
      starts_at = coalesce(nullif(c->>'starts_at', '')::timestamptz, starts_at),
      ends_at = coalesce(nullif(c->>'ends_at', '')::timestamptz, ends_at),
      break_minutes = coalesce((c->>'break_minutes')::int, break_minutes),
      required_workers = coalesce((c->>'required_workers')::int, required_workers),
      instructions = case when c ? 'instructions' then nullif(c->>'instructions', '') else instructions end,
      supervisor_id = case when c ? 'supervisor_id' then nullif(c->>'supervisor_id', '')::uuid else supervisor_id end
    where id = s.id;
  exception when others then
    raise exception 'Could not change the shift: %', sqlerrm using errcode = '22023';
  end;
  for m in select person_id from shift_workers where shift_id = s.id and status = 'assigned' loop
    perform omelo_private.omelo_notify(m.person_id, 'shift_update'::notification_type, 'Your shift changed',
      to_char(coalesce(nullif(c->>'starts_at', '')::timestamptz, s.starts_at) at time zone s.timezone, 'Dy DD Mon HH24:MI'),
      'shift', s.id, '/work/shifts/' || s.id);
  end loop;
  perform omelo_private.omelo_emit('ShiftChanged', 'shift', s.id, s.company_id, null, c);
  perform omelo_private.omelo_log_workforce(s.company_id, 'shift', s.id, 'ShiftChanged', null, to_jsonb(s), c, null);
end;
$$;

create or replace function public.omelo_cancel_shift(p_shift uuid, p_reason text)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare s shifts; m record;
begin
  select * into s from shifts where id = p_shift;
  if s.id is null then raise exception 'Shift not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), s.company_id, 'manage_workforce');
  if s.status in ('completed','cancelled') then raise exception 'This shift is %', s.status using errcode = '22023'; end if;
  if exists (select 1 from attendance_records where shift_id = s.id and check_in_at is not null) then
    raise exception 'Workers have already checked in to this shift' using errcode = '22023';
  end if;
  for m in select person_id from shift_workers where shift_id = s.id and status in ('assigned','offered') loop
    perform omelo_private.omelo_notify(m.person_id, 'shift_update'::notification_type, 'Shift cancelled',
      to_char(s.starts_at at time zone s.timezone, 'Dy DD Mon HH24:MI') || coalesce(' · ' || nullif(trim(p_reason), ''), ''),
      'shift', s.id, '/work/shifts/' || s.id);
  end loop;
  update shifts set status = 'cancelled', cancel_reason = left(nullif(trim(p_reason), ''), 300) where id = s.id;
  perform omelo_private.omelo_emit('ShiftCancelled', 'shift', s.id, s.company_id, null, jsonb_build_object('reason', p_reason));
end;
$$;

create or replace function omelo_private.omelo_assign_shift_core(p_actor uuid, p_shift uuid, p_assignment uuid, p_offer boolean)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare s shifts; a assignments; v_taken int; v_id uuid;
begin
  select * into s from shifts where id = p_shift for update;
  select * into a from assignments where id = p_assignment;
  if s.id is null or a.id is null then raise exception 'Shift or assignment not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(p_actor, s.company_id, 'manage_workforce');
  if a.company_id <> s.company_id then raise exception 'That assignment belongs to another company' using errcode = '42501'; end if;
  if exists (select 1 from shift_workers where shift_id = s.id and assignment_id = a.id and status in ('offered','assigned')) then
    raise exception 'The worker is already on this shift' using errcode = '22023';
  end if;
  select count(*) into v_taken from shift_workers where shift_id = s.id and status = 'assigned';
  if not p_offer and v_taken >= s.required_workers then
    raise exception 'This shift is full (% of %)', v_taken, s.required_workers using errcode = '22023';
  end if;
  if a.status = 'accepted' and (s.starts_at at time zone s.timezone)::date >= a.start_date then
    perform omelo_private.omelo_activate_assignment(a.id);
  end if;
  insert into shift_workers (shift_id, assignment_id, person_id, status, starts_at, ends_at, assigned_by)
  values (s.id, a.id, a.person_id, case when p_offer then 'offered' else 'assigned' end, s.starts_at, s.ends_at, p_actor)
  on conflict (shift_id, assignment_id) do update
     set status = excluded.status, assigned_by = excluded.assigned_by, assigned_at = now()
   where shift_workers.status in ('declined','cancelled')
  returning id into v_id;
  if v_id is null then raise exception 'The worker is already on this shift' using errcode = '22023'; end if;
  perform omelo_private.omelo_notify(a.person_id, 'shift_update'::notification_type,
    case when p_offer then 'Extra shift available' else 'New shift' end,
    to_char(s.starts_at at time zone s.timezone, 'Dy DD Mon HH24:MI') || '–' || to_char(s.ends_at at time zone s.timezone, 'HH24:MI')
      || ' · ' || coalesce(s.location_text, a.title),
    'shift', s.id, '/work/shifts/' || s.id);
  perform omelo_private.omelo_emit(case when p_offer then 'ShiftOffered' else 'ShiftAssigned' end, 'shift', s.id,
    s.company_id, a.person_id, jsonb_build_object('assignment_id', a.id));
  return v_id;
end;
$$;

create or replace function public.omelo_assign_shift(p_shift uuid, p_assignments uuid[])
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare x uuid; v_ok int := 0; v_err jsonb := '[]'::jsonb;
begin
  if cardinality(p_assignments) > 200 then
    raise exception 'Use a bulk operation for more than 200 workers' using errcode = '22023';
  end if;
  foreach x in array coalesce(p_assignments, '{}') loop
    begin
      perform omelo_private.omelo_assign_shift_core(auth.uid(), p_shift, x, false);
      v_ok := v_ok + 1;
    exception when others then
      if sqlstate = '42501' and v_ok = 0 and jsonb_array_length(v_err) = 0 then raise; end if;
      v_err := v_err || jsonb_build_object('assignment_id', x, 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('assigned', v_ok, 'errors', v_err);
end;
$$;

create or replace function public.omelo_offer_shift(p_shift uuid, p_assignments uuid[])
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare x uuid; v_ok int := 0; v_err jsonb := '[]'::jsonb;
begin
  if cardinality(p_assignments) > 200 then
    raise exception 'Offer to at most 200 workers at once' using errcode = '22023';
  end if;
  foreach x in array coalesce(p_assignments, '{}') loop
    begin
      perform omelo_private.omelo_assign_shift_core(auth.uid(), p_shift, x, true);
      v_ok := v_ok + 1;
    exception when others then
      if sqlstate = '42501' and v_ok = 0 and jsonb_array_length(v_err) = 0 then raise; end if;
      v_err := v_err || jsonb_build_object('assignment_id', x, 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('offered', v_ok, 'errors', v_err);
end;
$$;

create or replace function public.omelo_respond_to_shift(p_shift_worker uuid, p_accept boolean)
returns text
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare w shift_workers; s shifts; v_taken int;
begin
  select * into w from shift_workers where id = p_shift_worker and person_id = auth.uid() for update;
  if w.id is null then raise exception 'Shift not found' using errcode = '42501'; end if;
  if w.status <> 'offered' then raise exception 'This shift offer was already answered' using errcode = '22023'; end if;
  select * into s from shifts where id = w.shift_id for update;
  if not p_accept or s.starts_at <= now() then
    update shift_workers set status = 'declined', responded_at = now() where id = w.id;
    return 'declined';
  end if;
  select count(*) into v_taken from shift_workers where shift_id = s.id and status = 'assigned';
  if v_taken >= s.required_workers then
    update shift_workers set status = 'declined', responded_at = now() where id = w.id;
    raise exception 'Sorry, this shift has just been filled' using errcode = '22023';
  end if;
  update shift_workers set status = 'assigned', responded_at = now() where id = w.id;
  perform omelo_private.omelo_emit('ShiftAssigned', 'shift', s.id, s.company_id, w.person_id,
    jsonb_build_object('assignment_id', w.assignment_id, 'via', 'offer'));
  return 'assigned';
end;
$$;

create or replace function public.omelo_unassign_shift(p_shift_worker uuid, p_reason text default null)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare w shift_workers; s shifts;
begin
  select * into w from shift_workers where id = p_shift_worker;
  select * into s from shifts where id = w.shift_id;
  if w.id is null then raise exception 'Not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), s.company_id, 'manage_workforce');
  if exists (select 1 from attendance_records where shift_worker_id = w.id and check_in_at is not null) then
    raise exception 'The worker already checked in' using errcode = '22023';
  end if;
  update shift_workers set status = 'cancelled' where id = w.id and status in ('offered','assigned');
  perform omelo_private.omelo_notify(w.person_id, 'shift_update'::notification_type, 'Removed from a shift',
    to_char(s.starts_at at time zone s.timezone, 'Dy DD Mon HH24:MI') || coalesce(' · ' || nullif(trim(p_reason), ''), ''),
    'shift', s.id, '/work/shifts/' || s.id);
end;
$$;

-- Replacement: who can fill a vacancy on this shift (reuses assignments; external
-- candidates come from the talent search of the requirement's job / job order).
create or replace function public.omelo_shift_replacements(p_shift uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare s shifts; r workforce_requirements;
begin
  select * into s from shifts where id = p_shift;
  select * into r from workforce_requirements where id = s.requirement_id;
  if s.id is null then raise exception 'Shift not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), s.company_id, 'manage_workforce');
  return jsonb_build_object(
    'shift_id', s.id,
    'open', greatest(0, s.required_workers - (select count(*) from shift_workers where shift_id = s.id and status = 'assigned')),
    'external_search', case when r.job_order_id is not null then jsonb_build_object('job_order_id', r.job_order_id)
                            when r.job_id is not null then jsonb_build_object('job_id', r.job_id) end,
    'candidates', coalesce((
      select jsonb_agg(jsonb_build_object(
               'assignment_id', a.id, 'person_id', a.person_id, 'name', p.display_name, 'title', a.title,
               'status', a.status,
               'minutes_this_week', coalesce((select sum(extract(epoch from (w.ends_at - w.starts_at)) / 60)::int
                                                 from shift_workers w where w.person_id = a.person_id and w.status = 'assigned'
                                                  and w.starts_at >= date_trunc('week', s.starts_at)
                                                  and w.starts_at < date_trunc('week', s.starts_at) + interval '7 days'), 0),
               'offered', exists (select 1 from shift_workers w where w.shift_id = s.id and w.assignment_id = a.id
                                    and w.status = 'offered'))
             order by p.display_name)
        from assignments a join persons p on p.id = a.person_id
       where a.requirement_id = s.requirement_id and a.status in ('accepted','active')
         and not exists (select 1 from shift_workers w where w.shift_id = s.id and w.assignment_id = a.id
                           and w.status in ('assigned'))
         and not exists (select 1 from shift_workers w where w.person_id = a.person_id and w.status = 'assigned'
                           and tstzrange(w.starts_at, w.ends_at) && tstzrange(s.starts_at, s.ends_at))
         and not exists (select 1 from leave_requests l where l.person_id = a.person_id and l.status = 'approved'
                           and (s.starts_at at time zone s.timezone)::date between l.start_date and l.end_date)
         and (s.starts_at at time zone s.timezone)::date between a.start_date and coalesce(a.end_date, 'infinity'::date)),
      '[]'::jsonb));
end;
$$;

-- 4. Check-in / check-out / attendance ---------------------------------------------------------
create or replace function public.omelo_check_in(p_shift_worker uuid, p_method text default 'app',
                                                 p_lat double precision default null, p_lng double precision default null,
                                                 p_code text default null)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private, extensions
as $$
declare w shift_workers; s shifts; a assignments; r workforce_requirements; v_id uuid; v_geo geography; v_site geography;
        v_late int; v_method text := coalesce(nullif(p_method, ''), 'app');
begin
  select * into w from shift_workers where id = p_shift_worker and person_id = auth.uid() for update;
  if w.id is null then raise exception 'This is not your shift' using errcode = '42501'; end if;
  select * into s from shifts where id = w.shift_id;
  select * into a from assignments where id = w.assignment_id;
  select * into r from workforce_requirements where id = a.requirement_id;
  if s.status = 'cancelled' or w.status <> 'assigned' then
    raise exception 'You are not on this shift (it is %)', case when s.status = 'cancelled' then 'cancelled' else w.status end
      using errcode = '22023';
  end if;
  if a.status = 'accepted' then perform omelo_private.omelo_activate_assignment(a.id); select * into a from assignments where id = a.id; end if;
  if a.status <> 'active' then raise exception 'Your assignment is %', a.status using errcode = '22023'; end if;
  if now() < s.starts_at - interval '60 minutes' or now() > s.ends_at then
    raise exception 'Check-in opens 60 minutes before the shift starts and closes when it ends' using errcode = '22023';
  end if;
  if exists (select 1 from attendance_records where shift_worker_id = w.id and check_in_at is not null) then
    raise exception 'You already checked in' using errcode = '22023';
  end if;
  if r.check_in_method = 'employer' then
    raise exception 'Your supervisor records your arrival for this work' using errcode = '22023';
  end if;
  if r.check_in_method = 'qr' then
    if p_code is null or p_code is distinct from (select code from shift_codes where shift_id = s.id) then
      raise exception 'That check-in code is not right. Ask your supervisor for the code.' using errcode = '22023';
    end if;
    v_method := 'qr';
  end if;
  if p_lat is not null and p_lng is not null then
    v_geo := st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography;
  end if;
  if r.check_in_method = 'geofence' then
    select geo into v_site from locations where id = coalesce(s.location_id, r.location_id);
    if v_geo is null then raise exception 'Share your location to check in' using errcode = '22023'; end if;
    if v_site is not null and st_distance(v_geo, v_site) > r.geofence_radius_m then
      raise exception 'You seem to be % m from the work site. Check in when you arrive.', round(st_distance(v_geo, v_site))
        using errcode = '22023';
    end if;
    v_method := 'geofence';
  end if;
  if v_method not in ('app','qr','geofence') then v_method := 'app'; end if;

  insert into attendance_records (shift_worker_id, shift_id, assignment_id, person_id, scheduled_start, scheduled_end,
                                  break_minutes, check_in_at, check_in_method, check_in_geo, status)
  values (w.id, s.id, a.id, a.person_id, s.starts_at, s.ends_at, s.break_minutes, now(), v_method, v_geo, 'checked_in')
  on conflict (shift_worker_id) do update
     set check_in_at = excluded.check_in_at, check_in_method = excluded.check_in_method,
         check_in_geo = excluded.check_in_geo, status = 'checked_in'
  returning id into v_id;
  if s.status = 'scheduled' then update shifts set status = 'in_progress' where id = s.id; end if;

  v_late := floor(extract(epoch from (now() - s.starts_at)) / 60);
  if v_late > r.late_grace_minutes then
    insert into attendance_exceptions (attendance_id, kind, minutes, detail)
    values (v_id, 'late', v_late, 'Late arrival — ' || v_late || ' minutes');
    update attendance_records set review_status = 'pending' where id = v_id;
    perform omelo_private.omelo_notify_team(omelo_private.omelo_approver_company(a.id), 'approve_time', 'work_update',
      'Late arrival — ' || v_late || ' minutes', (select display_name from persons where id = a.person_id) || ' · ' || a.title,
      'attendance', v_id, '/dashboard/workforce/approvals');
    perform omelo_private.omelo_emit('WorkerLate', 'attendance', v_id, a.company_id, a.person_id, jsonb_build_object('minutes', v_late));
  end if;
  perform omelo_private.omelo_emit('WorkerCheckedIn', 'attendance', v_id, a.company_id, a.person_id,
    jsonb_build_object('shift_id', s.id, 'method', v_method));
  return v_id;
end;
$$;

create or replace function public.omelo_check_out(p_shift_worker uuid, p_lat double precision default null,
                                                  p_lng double precision default null)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private, extensions
as $$
declare ar attendance_records; r workforce_requirements; v_worked int; v_early int; v_status text; v_pending boolean;
begin
  select * into ar from attendance_records where shift_worker_id = p_shift_worker and person_id = auth.uid() for update;
  if ar.id is null or ar.check_in_at is null then
    raise exception 'Check in first' using errcode = '22023';     -- R5-006
  end if;
  if ar.check_out_at is not null then raise exception 'You already checked out' using errcode = '22023'; end if;
  if now() > ar.scheduled_end + interval '6 hours' then
    raise exception 'Check-out closed 6 hours after the shift ended. Ask your supervisor to correct it.' using errcode = '22023';
  end if;
  select r2.* into r from workforce_requirements r2 join assignments a on a.requirement_id = r2.id where a.id = ar.assignment_id;
  v_worked := greatest(0, floor(extract(epoch from (now() - ar.check_in_at)) / 60)::int
                          - case when extract(epoch from (now() - ar.check_in_at)) / 60 > ar.break_minutes then ar.break_minutes else 0 end);
  v_early := floor(extract(epoch from (ar.scheduled_end - now())) / 60);
  if v_early > r.late_grace_minutes then
    insert into attendance_exceptions (attendance_id, kind, minutes, detail)
    values (ar.id, 'early_departure', v_early, 'Left ' || v_early || ' minutes early');
  end if;
  v_pending := exists (select 1 from attendance_exceptions where attendance_id = ar.id and status = 'pending');
  v_status := case
    when v_early > r.late_grace_minutes and v_worked < extract(epoch from (ar.scheduled_end - ar.scheduled_start)) / 120 then 'partial'
    when v_early > r.late_grace_minutes then 'early_departure'
    when exists (select 1 from attendance_exceptions where attendance_id = ar.id and kind = 'late') then 'late'
    else 'present' end;
  update attendance_records
     set check_out_at = now(), check_out_method = 'app', worked_minutes = least(v_worked, 1440),
         payable_minutes = case when v_pending then null else least(v_worked, 1440) end,
         status = v_status, review_status = case when v_pending then 'pending' else review_status end
   where id = ar.id;
  update shift_workers set status = 'completed' where id = ar.shift_worker_id;
  perform omelo_private.omelo_emit('WorkerCheckedOut', 'attendance', ar.id, (select company_id from assignments where id = ar.assignment_id),
    ar.person_id, jsonb_build_object('worked_minutes', v_worked, 'status', v_status));
  return jsonb_build_object('attendance_id', ar.id, 'worked_minutes', v_worked, 'status', v_status, 'needs_review', v_pending);
end;
$$;

-- Supervisor records arrival/departure (employer confirmation).
create or replace function public.omelo_record_attendance(p_shift_worker uuid, p_check_in timestamptz,
                                                          p_check_out timestamptz default null, p_note text default null)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare w shift_workers; s shifts; v_id uuid; v_worked int;
begin
  select * into w from shift_workers where id = p_shift_worker;
  select * into s from shifts where id = w.shift_id;
  if w.id is null then raise exception 'Not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), omelo_private.omelo_approver_company(w.assignment_id), 'approve_time');
  if w.status not in ('assigned','completed','absent') then
    raise exception 'The worker is not on this shift (%)', w.status using errcode = '22023';
  end if;
  if p_check_in is null or p_check_in < s.starts_at - interval '2 hours' or p_check_in > s.ends_at
     or (p_check_out is not null and (p_check_out <= p_check_in or p_check_out > s.ends_at + interval '6 hours')) then
    raise exception 'Times must fall around the shift' using errcode = '22023';
  end if;
  if exists (select 1 from attendance_records where shift_worker_id = w.id and review_status in ('approved','adjusted','rejected')) then
    raise exception 'This attendance was already reviewed; use a correction' using errcode = '22023';
  end if;
  v_worked := case when p_check_out is not null
                   then greatest(0, floor(extract(epoch from (p_check_out - p_check_in)) / 60)::int - s.break_minutes) end;
  insert into attendance_records (shift_worker_id, shift_id, assignment_id, person_id, scheduled_start, scheduled_end,
                                  break_minutes, check_in_at, check_in_method, check_out_at, check_out_method,
                                  worked_minutes, payable_minutes, status, review_status, reviewed_by, reviewed_at, review_note)
  values (w.id, s.id, w.assignment_id, w.person_id, s.starts_at, s.ends_at, s.break_minutes, p_check_in, 'employer',
          p_check_out, case when p_check_out is not null then 'employer' end, v_worked, v_worked,
          case when p_check_out is null then 'checked_in' else 'present' end,
          case when p_check_out is null then 'none' else 'approved' end,
          case when p_check_out is null then null else auth.uid() end,
          case when p_check_out is null then null else now() end, left(p_note, 500))
  on conflict (shift_worker_id) do update
     set check_in_at = excluded.check_in_at, check_in_method = 'employer', check_out_at = excluded.check_out_at,
         check_out_method = excluded.check_out_method, worked_minutes = excluded.worked_minutes,
         payable_minutes = excluded.payable_minutes, status = excluded.status, review_status = excluded.review_status,
         reviewed_by = excluded.reviewed_by, reviewed_at = excluded.reviewed_at, review_note = excluded.review_note
  returning id into v_id;
  update attendance_exceptions set status = 'approved', resolved_by = auth.uid(), resolved_at = now(),
         resolution_note = 'Recorded by the supervisor'
   where attendance_id = v_id and status = 'pending' and kind in ('absent','missing_check_out');
  if p_check_out is not null then update shift_workers set status = 'completed' where id = w.id; end if;
  perform omelo_private.omelo_log_workforce((select company_id from assignments where id = w.assignment_id), 'attendance', v_id,
    'AttendanceRecordedBySupervisor', w.person_id, null,
    jsonb_build_object('check_in', p_check_in, 'check_out', p_check_out), p_note);
  return v_id;
end;
$$;

create or replace function public.omelo_review_attendance(p_attendance uuid, p_decision text,
                                                          p_check_in timestamptz default null, p_check_out timestamptz default null,
                                                          p_break_minutes integer default null, p_note text default null)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare ar attendance_records; v_in timestamptz; v_out timestamptz; v_break int; v_worked int;
begin
  select * into ar from attendance_records where id = p_attendance for update;
  if ar.id is null then raise exception 'Not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), omelo_private.omelo_approver_company(ar.assignment_id), 'approve_time');
  if ar.review_status in ('approved','adjusted','rejected') then
    raise exception 'Already reviewed; use a correction' using errcode = '22023';
  end if;
  if p_decision not in ('approve','adjust','reject') then raise exception 'Choose approve, adjust or reject' using errcode = '22023'; end if;
  if p_decision = 'adjust' then
    v_in := coalesce(p_check_in, ar.check_in_at); v_out := coalesce(p_check_out, ar.check_out_at);
    v_break := coalesce(p_break_minutes, ar.break_minutes);
    if v_in is null or v_out is null or v_out <= v_in then
      raise exception 'Give both corrected times' using errcode = '22023';
    end if;
    v_worked := greatest(0, floor(extract(epoch from (v_out - v_in)) / 60)::int - v_break);
    update attendance_records set check_in_at = v_in, check_out_at = v_out, break_minutes = v_break,
           check_in_method = case when p_check_in is not null then 'correction' else check_in_method end,
           check_out_method = case when p_check_out is not null then 'correction' else check_out_method end,
           worked_minutes = least(v_worked, 1440), payable_minutes = least(v_worked, 1440),
           status = case when status in ('absent','checked_in') then 'present' else status end,
           review_status = 'adjusted', reviewed_by = auth.uid(), reviewed_at = now(), review_note = left(p_note, 500)
     where id = ar.id;
  elsif p_decision = 'approve' then
    update attendance_records set payable_minutes = coalesce(worked_minutes, 0),
           review_status = 'approved', reviewed_by = auth.uid(), reviewed_at = now(), review_note = left(p_note, 500)
     where id = ar.id;
  else
    update attendance_records set payable_minutes = 0,
           status = case when check_in_at is null then 'unapproved_absence' else status end,
           review_status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now(), review_note = left(p_note, 500)
     where id = ar.id;
  end if;
  update attendance_exceptions
     set status = case p_decision when 'approve' then 'approved' when 'adjust' then 'adjusted' else 'rejected' end,
         resolved_by = auth.uid(), resolved_at = now(), resolution_note = left(p_note, 500)
   where attendance_id = ar.id and status = 'pending';
  perform omelo_private.omelo_log_workforce((select company_id from assignments where id = ar.assignment_id), 'attendance', ar.id,
    'AttendanceReviewed', ar.person_id, to_jsonb(ar),
    (select to_jsonb(x) from attendance_records x where x.id = ar.id), p_note);
  perform omelo_private.omelo_notify(ar.person_id, 'work_update'::notification_type,
    'Your attendance was ' || case p_decision when 'approve' then 'approved' when 'adjust' then 'adjusted' else 'not accepted' end,
    to_char(ar.scheduled_start, 'DD Mon') || coalesce(' · ' || nullif(trim(p_note), ''), ''),
    'attendance', ar.id, '/work/shifts/' || ar.shift_id);
end;
$$;

-- R5-007: reviewed attendance changes only here, with a reason, and never under an approved timesheet.
create or replace function public.omelo_correct_attendance(p_attendance uuid, p_check_in timestamptz, p_check_out timestamptz,
                                                           p_reason text)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare ar attendance_records; v_worked int;
begin
  select * into ar from attendance_records where id = p_attendance for update;
  if ar.id is null then raise exception 'Not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), omelo_private.omelo_approver_company(ar.assignment_id), 'approve_time');
  if length(trim(coalesce(p_reason, ''))) < 5 then
    raise exception 'A correction needs a reason' using errcode = '22023';
  end if;
  if p_check_in is null or p_check_out is null or p_check_out <= p_check_in then
    raise exception 'Give both corrected times' using errcode = '22023';
  end if;
  if exists (select 1 from timesheet_entries e join timesheets t on t.id = e.timesheet_id
              where e.attendance_id = ar.id and t.status in ('approved','locked')) then
    raise exception 'This attendance is on an approved timesheet; reopen the timesheet first' using errcode = '22023';
  end if;
  v_worked := greatest(0, floor(extract(epoch from (p_check_out - p_check_in)) / 60)::int - ar.break_minutes);
  perform set_config('omelo.correction', 'on', true);
  update attendance_records set check_in_at = p_check_in, check_out_at = p_check_out,
         check_in_method = 'correction', check_out_method = 'correction',
         worked_minutes = least(v_worked, 1440), payable_minutes = least(v_worked, 1440),
         status = case when status in ('absent','unapproved_absence','checked_in') then 'present' else status end,
         review_status = 'adjusted', reviewed_by = auth.uid(), reviewed_at = now(), review_note = left(p_reason, 500)
   where id = ar.id;
  perform set_config('omelo.correction', 'off', true);
  insert into attendance_exceptions (attendance_id, kind, detail, status, resolved_by, resolved_at, resolution_note)
  values (ar.id, 'manual_correction', 'Corrected by ' || coalesce((select display_name from persons where id = auth.uid()), 'a manager'),
          'adjusted', auth.uid(), now(), left(p_reason, 500));
  perform omelo_private.omelo_log_workforce((select company_id from assignments where id = ar.assignment_id), 'attendance', ar.id,
    'AttendanceCorrected', ar.person_id, to_jsonb(ar), (select to_jsonb(x) from attendance_records x where x.id = ar.id), p_reason);
end;
$$;

-- 5. Leave -------------------------------------------------------------------------------------
create or replace function public.omelo_request_leave(p_assignment uuid, p_type text, p_start date, p_end date,
                                                      p_reason text default null, p_label text default null)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare a assignments; v_id uuid;
begin
  select * into a from assignments where id = p_assignment and person_id = auth.uid();
  if a.id is null then raise exception 'Assignment not found' using errcode = '42501'; end if;
  if a.status not in ('accepted','active','paused') then raise exception 'Your assignment is %', a.status using errcode = '22023'; end if;
  if exists (select 1 from leave_requests where assignment_id = a.id and status in ('requested','approved')
              and daterange(start_date, end_date, '[]') && daterange(p_start, p_end, '[]')) then
    raise exception 'You already asked for leave on some of these days' using errcode = '22023';
  end if;
  insert into leave_requests (assignment_id, person_id, company_id, leave_type, label, start_date, end_date, reason)
  values (a.id, a.person_id, a.company_id, p_type, left(nullif(trim(p_label), ''), 80), p_start, p_end, left(nullif(trim(p_reason), ''), 500))
  returning id into v_id;
  perform omelo_private.omelo_notify_team(a.company_id, 'approve_time', 'work_update', 'Leave request',
    (select display_name from persons where id = a.person_id) || ' · ' || to_char(p_start, 'DD Mon') || ' – ' || to_char(p_end, 'DD Mon'),
    'leave_request', v_id, '/dashboard/workforce/approvals');
  perform omelo_private.omelo_emit('LeaveRequested', 'leave_request', v_id, a.company_id, a.person_id, '{}'::jsonb);
  return v_id;
end;
$$;

create or replace function public.omelo_cancel_leave(p_leave uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare l leave_requests;
begin
  select * into l from leave_requests where id = p_leave and person_id = auth.uid();
  if l.id is null then raise exception 'Not found' using errcode = '42501'; end if;
  if l.status <> 'requested' then raise exception 'Only a pending request can be cancelled' using errcode = '22023'; end if;
  update leave_requests set status = 'cancelled', updated_at = now() where id = l.id;
end;
$$;

create or replace function public.omelo_review_leave(p_leave uuid, p_approve boolean, p_note text default null)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare l leave_requests; w record;
begin
  select * into l from leave_requests where id = p_leave for update;
  if l.id is null then raise exception 'Not found' using errcode = '42501'; end if;
  if not (omelo_private.omelo_workforce_can(l.company_id, 'approve_time')
          or omelo_private.omelo_workforce_can(omelo_private.omelo_approver_company(l.assignment_id), 'approve_time')) then
    raise exception 'You cannot review leave for this worker' using errcode = '42501';
  end if;
  if l.status <> 'requested' then raise exception 'This request was already answered' using errcode = '22023'; end if;
  update leave_requests set status = case when p_approve then 'approved' else 'rejected' end, reviewed_by = auth.uid(),
         reviewed_at = now(), review_note = left(p_note, 500), updated_at = now()
   where id = l.id;
  if p_approve then
    for w in select sw.*, s.timezone, s.break_minutes as brk from shift_workers sw join shifts s on s.id = sw.shift_id
              where sw.assignment_id = l.assignment_id and sw.status = 'assigned'
                and (sw.starts_at at time zone s.timezone)::date between l.start_date and l.end_date loop
      update shift_workers set status = 'on_leave' where id = w.id;
      insert into attendance_records (shift_worker_id, shift_id, assignment_id, person_id, scheduled_start, scheduled_end,
                                      break_minutes, payable_minutes, status, review_status, reviewed_by, reviewed_at)
      values (w.id, w.shift_id, w.assignment_id, w.person_id, w.starts_at, w.ends_at, w.brk,
              case when l.leave_type = 'paid' then greatest(0, (extract(epoch from (w.ends_at - w.starts_at)) / 60)::int - w.brk) else 0 end,
              'approved_leave', 'approved', auth.uid(), now())
      on conflict (shift_worker_id) do nothing;
    end loop;
  end if;
  perform omelo_private.omelo_notify(l.person_id, 'work_update'::notification_type,
    'Leave ' || case when p_approve then 'approved' else 'not approved' end,
    to_char(l.start_date, 'DD Mon') || ' – ' || to_char(l.end_date, 'DD Mon') || coalesce(' · ' || nullif(trim(p_note), ''), ''),
    'leave_request', l.id, '/work/leave');
  perform omelo_private.omelo_emit(case when p_approve then 'LeaveApproved' else 'LeaveRejected' end, 'leave_request', l.id,
    l.company_id, l.person_id, '{}'::jsonb);
end;
$$;
