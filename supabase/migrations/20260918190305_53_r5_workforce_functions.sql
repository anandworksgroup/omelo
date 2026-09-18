-- OMELO 53 — Release 5: Staffing & Workforce engine — the functions (part 1 of 3:
-- helpers, requirements, pay components, assignments; 54 and 55 follow).
--
-- All writes to the workforce tables (51) go through these functions; each
-- checks authority first, then the integrity triggers of 51 check the data
-- again for every writer. Bulk operations run in the background
-- (workforce_jobs + pg_cron) and re-check the requesting user's authority for
-- EVERY item (R5-016). Notifications and events reuse omelo_notify /
-- omelo_emit; there is no second notification system.
--
-- Pay calculation is a normalised layer: base (hour / day / week / fortnight /
-- month / year), overtime (only where the company configured an
-- overtime_policy — no universal rule is assumed), allowances, bonuses,
-- deductions and adjustments are separate lines. Omelo records payments; it
-- is not a payroll provider (payment_records.provider is filled by whatever
-- provider is integrated later).
--
-- The matcher is extended, not replaced: when a job belongs to a workforce
-- requirement, a schedule_fit factor (dates, weekly hours, preferred days)
-- is scored and a schedule_conflict gate stops a worker already booked at
-- those times (engine v1.1).
--
-- Rollback: drop the functions below, unschedule 'omelo-workforce-tick', and
-- re-run 47 to restore omelo_score_match v1.0.

-- 0. Helpers ---------------------------------------------------------------------------
create or replace function omelo_private.omelo_require_workforce(p_actor uuid, p_company uuid, p_action text)
returns void
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
begin
  if p_actor is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  if not omelo_private.omelo_person_workforce_can(p_actor, p_company, p_action) then
    raise exception 'You are not allowed to do this for this company (%)', replace(p_action, '_', ' ') using errcode = '42501';
  end if;
end;
$$;

create or replace function omelo_private.omelo_approver_company(p_assignment uuid)
returns uuid
language sql stable security definer
set search_path = public, omelo_private
as $$
  select coalesce(client_company_id, company_id) from assignments where id = p_assignment;
$$;

create or replace function omelo_private.omelo_notify_team(p_company uuid, p_action text, p_type text, p_title text,
                                                           p_body text, p_entity text, p_id uuid, p_link text)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare m record;
begin
  for m in select distinct cm.person_id from company_members cm join companies c on c.id = cm.company_id
            where cm.company_id = p_company and cm.is_active
              and cm.role::text = any (omelo_private.omelo_workforce_roles(c.company_kind, p_action)) loop
    perform omelo_private.omelo_notify(m.person_id, p_type::notification_type, p_title, p_body, p_entity, p_id, p_link);
  end loop;
end;
$$;

create or replace function omelo_private.omelo_local_today(p_tz text)
returns date
language sql stable
as $$
  select (now() at time zone coalesce(p_tz, 'UTC'))::date;
$$;

-- 1. Requirements ---------------------------------------------------------------------------
create or replace function omelo_private.omelo_apply_requirement_fields(r workforce_requirements, p jsonb)
returns workforce_requirements
language plpgsql stable
set search_path = public, omelo_private
as $$
begin
  if p ? 'title'              then r.title := trim(p->>'title'); end if;
  if p ? 'profession_id'      then r.profession_id := nullif(p->>'profession_id', '')::uuid; end if;
  if p ? 'openings'           then r.openings := (p->>'openings')::int; end if;
  if p ? 'location_id'        then r.location_id := nullif(p->>'location_id', '')::uuid; end if;
  if p ? 'location_text'      then r.location_text := nullif(trim(p->>'location_text'), ''); end if;
  if p ? 'site_name'          then r.site_name := nullif(trim(p->>'site_name'), ''); end if;
  if p ? 'country_code'       then r.country_code := upper(nullif(p->>'country_code', '')); end if;
  if p ? 'currency'           then r.currency := upper(nullif(p->>'currency', '')); end if;
  if p ? 'timezone'           then r.timezone := nullif(p->>'timezone', ''); end if;
  if p ? 'employment_type'    then r.employment_type := p->>'employment_type'; end if;
  if p ? 'work_type'          then r.work_type := (p->>'work_type')::work_type; end if;
  if p ? 'pay_rate'           then r.pay_rate := nullif(p->>'pay_rate', '')::numeric; end if;
  if p ? 'pay_period'         then r.pay_period := nullif(p->>'pay_period', '')::pay_period; end if;
  if p ? 'pay_frequency'      then r.pay_frequency := p->>'pay_frequency'; end if;
  if p ? 'hours_per_week'     then r.hours_per_week := nullif(p->>'hours_per_week', '')::numeric; end if;
  if p ? 'start_date'         then r.start_date := nullif(p->>'start_date', '')::date; end if;
  if p ? 'end_date'           then r.end_date := nullif(p->>'end_date', '')::date; end if;
  if p ? 'check_in_method'    then r.check_in_method := p->>'check_in_method'; end if;
  if p ? 'geofence_radius_m'  then r.geofence_radius_m := nullif(p->>'geofence_radius_m', '')::int; end if;
  if p ? 'late_grace_minutes' then r.late_grace_minutes := (p->>'late_grace_minutes')::int; end if;
  if p ? 'overtime_policy_id' then r.overtime_policy_id := nullif(p->>'overtime_policy_id', '')::uuid; end if;
  if p ? 'supervisor_id'      then r.supervisor_id := nullif(p->>'supervisor_id', '')::uuid; end if;
  if p ? 'status'             then r.status := p->>'status'; end if;
  if p ? 'notes'              then r.notes := nullif(p->>'notes', ''); end if;
  return r;
end;
$$;

create or replace function omelo_private.omelo_check_requirement(r workforce_requirements)
returns void
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
begin
  if r.job_id is not null and not exists (select 1 from jobs where id = r.job_id and company_id = r.company_id) then
    raise exception 'That job belongs to another company' using errcode = '42501';
  end if;
  if r.job_order_id is not null and not exists (select 1 from job_orders where id = r.job_order_id and agency_id = r.company_id) then
    raise exception 'That job order belongs to another agency' using errcode = '42501';
  end if;
  if r.overtime_policy_id is not null
     and not exists (select 1 from overtime_policies where id = r.overtime_policy_id and company_id = r.company_id) then
    raise exception 'That overtime policy belongs to another company' using errcode = '42501';
  end if;
  if r.supervisor_id is not null and not exists (
       select 1 from company_members where person_id = r.supervisor_id and is_active
          and company_id in (r.company_id, (select client_company_id from agency_clients where id = r.client_id and link_status = 'confirmed'))) then
    raise exception 'The supervisor must be a member of the company or its client' using errcode = '22023';
  end if;
  if not exists (select 1 from pg_timezone_names where name = r.timezone) then
    raise exception 'Unknown time zone %', r.timezone using errcode = '22023';
  end if;
  if r.currency is null then
    raise exception 'Choose the currency workers are paid in' using errcode = '22023';
  end if;
end;
$$;

create or replace function public.omelo_create_requirement(p_company uuid, p_fields jsonb)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare r workforce_requirements; jo job_orders; j jobs;
begin
  perform omelo_private.omelo_require_workforce(auth.uid(), p_company, 'manage_workforce');
  r.id := gen_random_uuid();
  r.company_id := p_company;
  r.job_order_id := nullif(p_fields->>'job_order_id', '')::uuid;
  r.job_id := nullif(p_fields->>'job_id', '')::uuid;
  if r.job_order_id is not null then
    select * into jo from job_orders where id = r.job_order_id and agency_id = p_company;
    if jo.id is null then raise exception 'That job order belongs to another agency' using errcode = '42501'; end if;
    r.client_id := jo.client_id;
    r.title := jo.title; r.profession_id := jo.profession_id; r.openings := jo.openings;
    r.location_id := jo.location_id; r.location_text := jo.location_text; r.work_type := jo.work_type;
    r.pay_rate := jo.pay_min; r.pay_period := jo.pay_period; r.currency := jo.pay_currency;
    r.start_date := jo.start_date;
  elsif r.job_id is not null then
    select * into j from jobs where id = r.job_id and company_id = p_company;
    if j.id is null then raise exception 'That job belongs to another company' using errcode = '42501'; end if;
    r.title := j.title; r.profession_id := j.profession_id; r.openings := coalesce(j.openings, 1);
    r.location_id := j.location_id; r.location_text := j.location_text; r.work_type := j.work_type;
    r.pay_rate := j.pay_min; r.pay_period := j.pay_period; r.currency := j.pay_currency; r.start_date := j.start_date;
    r.country_code := j.country_code;
  elsif (select company_kind from companies where id = p_company) = 'agency' then
    raise exception 'An agency requirement starts from one of its job orders' using errcode = '22023';
  end if;
  r.openings := coalesce(r.openings, 1); r.employment_type := 'temporary'; r.work_type := coalesce(r.work_type, 'full_time');
  r.pay_frequency := 'monthly'; r.check_in_method := 'app'; r.late_grace_minutes := 10; r.status := 'open';
  begin
    r := omelo_private.omelo_apply_requirement_fields(r, coalesce(p_fields, '{}'::jsonb));
  exception when others then
    raise exception 'Check the requirement details: %', sqlerrm using errcode = '22023';
  end;
  r.timezone := coalesce(r.timezone, (select timezone from locations where id = r.location_id), 'UTC');
  r.country_code := coalesce(r.country_code, (select country_code from locations where id = r.location_id));
  if r.title is null then raise exception 'Give the requirement a title' using errcode = '22023'; end if;
  perform omelo_private.omelo_check_requirement(r);
  r.created_by := auth.uid(); r.created_at := now(); r.updated_at := now();
  insert into workforce_requirements select r.*;
  perform omelo_private.omelo_emit('WorkforceRequirementCreated', 'workforce_requirement', r.id, p_company, null,
    jsonb_build_object('openings', r.openings, 'job_order_id', r.job_order_id, 'job_id', r.job_id));
  return r.id;
end;
$$;

create or replace function public.omelo_update_requirement(p_requirement uuid, p_changes jsonb)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare r workforce_requirements; v_before jsonb;
begin
  select * into r from workforce_requirements where id = p_requirement;
  if r.id is null then raise exception 'Requirement not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), r.company_id, 'manage_workforce');
  v_before := to_jsonb(r);
  begin
    r := omelo_private.omelo_apply_requirement_fields(r, coalesce(p_changes, '{}'::jsonb));
  exception when others then
    raise exception 'Check the requirement details: %', sqlerrm using errcode = '22023';
  end;
  perform omelo_private.omelo_check_requirement(r);
  update workforce_requirements set
    title = r.title, profession_id = r.profession_id, openings = r.openings, location_id = r.location_id,
    location_text = r.location_text, site_name = r.site_name, country_code = r.country_code, currency = r.currency,
    timezone = r.timezone, employment_type = r.employment_type, work_type = r.work_type, pay_rate = r.pay_rate,
    pay_period = r.pay_period, pay_frequency = r.pay_frequency, hours_per_week = r.hours_per_week,
    start_date = r.start_date, end_date = r.end_date, check_in_method = r.check_in_method,
    geofence_radius_m = r.geofence_radius_m, late_grace_minutes = r.late_grace_minutes,
    overtime_policy_id = r.overtime_policy_id, supervisor_id = r.supervisor_id, status = r.status,
    notes = r.notes, updated_at = now()
  where id = r.id;
  perform omelo_private.omelo_log_workforce(r.company_id, 'workforce_requirement', r.id, 'RequirementUpdated', null,
    v_before, to_jsonb(r), null);
end;
$$;

create or replace function public.omelo_save_pay_component(p_requirement uuid, p_assignment uuid, p_kind text, p_name text,
                                                           p_amount numeric, p_basis text,
                                                           p_shift_types text[] default '{}')
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_company uuid; v_id uuid;
begin
  v_company := coalesce((select company_id from workforce_requirements where id = p_requirement),
                        (select company_id from assignments where id = p_assignment));
  if v_company is null then raise exception 'Requirement or assignment not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), v_company, 'manage_pay');
  insert into pay_components (requirement_id, assignment_id, kind, name, amount, basis, applies_to_shift_types, created_by)
  values (case when p_assignment is null then p_requirement end, p_assignment, p_kind, trim(p_name), p_amount, p_basis,
          coalesce(p_shift_types, '{}')::shift_type[], auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.omelo_remove_pay_component(p_component uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_company uuid;
begin
  select coalesce(r.company_id, a.company_id) into v_company
    from pay_components pc left join workforce_requirements r on r.id = pc.requirement_id
    left join assignments a on a.id = pc.assignment_id where pc.id = p_component;
  if v_company is null then raise exception 'Not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), v_company, 'manage_pay');
  delete from pay_components where id = p_component;
end;
$$;

-- 2. Assignments ---------------------------------------------------------------------------
create or replace function omelo_private.omelo_offer_assignment_core(p_actor uuid, p_requirement uuid, p_identity uuid,
                                                                     p_fields jsonb, p_source text)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare
  r workforce_requirements; wi work_identities; v_kind text; a assignments; f jsonb := coalesce(p_fields, '{}'::jsonb);
  v_company_name text; v_client_name text;
begin
  select * into r from workforce_requirements where id = p_requirement;
  if r.id is null then raise exception 'Requirement not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(p_actor, r.company_id, 'manage_workforce');
  if r.status not in ('open','filled','active') then
    raise exception 'The requirement is %', r.status using errcode = '22023';
  end if;
  select * into wi from work_identities where id = p_identity and status = 'active';
  if wi.id is null then raise exception 'That work identity is not available' using errcode = '22023'; end if;
  select company_kind, display_name into v_kind, v_company_name from companies where id = r.company_id;
  if v_kind <> 'agency' and not (
       exists (select 1 from applications where person_id = wi.person_id and company_id = r.company_id)
    or exists (select 1 from employments where person_id = wi.person_id and company_id = r.company_id)
    or omelo_private.omelo_is_identity_discoverable_to(wi.id, r.company_id)) then
    raise exception 'This worker has no relationship with your company yet: invite them to apply first' using errcode = '42501';
  end if;

  a.id := gen_random_uuid();
  a.requirement_id := r.id; a.company_id := r.company_id; a.client_id := r.client_id;
  a.job_order_id := r.job_order_id; a.job_id := r.job_id;
  a.person_id := wi.person_id; a.work_identity_id := wi.id;
  a.title := coalesce(nullif(trim(f->>'title'), ''), r.title);
  a.location_id := r.location_id; a.location_text := coalesce(r.site_name || ', ', '') || coalesce(r.location_text, '');
  a.timezone := r.timezone;
  begin
    a.start_date := coalesce(nullif(f->>'start_date', '')::date, r.start_date, omelo_private.omelo_local_today(r.timezone));
    a.end_date := coalesce(nullif(f->>'end_date', '')::date, r.end_date);
    a.employment_type := coalesce(nullif(f->>'employment_type', ''), r.employment_type);
    a.work_type := coalesce(nullif(f->>'work_type', '')::work_type, r.work_type);
    a.pay_rate := coalesce(nullif(f->>'pay_rate', '')::numeric, r.pay_rate);
    a.pay_period := coalesce(nullif(f->>'pay_period', '')::pay_period, r.pay_period);
    a.pay_frequency := coalesce(nullif(f->>'pay_frequency', ''), r.pay_frequency);
    a.supervisor_id := coalesce(nullif(f->>'supervisor_id', '')::uuid, r.supervisor_id);
  exception when others then
    raise exception 'Check the assignment details: %', sqlerrm using errcode = '22023';
  end;
  if a.pay_rate is null or a.pay_period is null then
    raise exception 'Set the pay rate and pay period on the requirement or the offer' using errcode = '22023';
  end if;
  a.currency := r.currency; a.overtime_policy_id := r.overtime_policy_id;
  a.source := coalesce(p_source, 'direct');
  if v_kind = 'agency' then
    a.source := case when a.source = 'bulk' then 'bulk' else 'agency' end;
    a.consent_id := (select id from candidate_consents where person_id = wi.person_id and agency_id = r.company_id
                       and job_order_id = r.job_order_id order by requested_at desc limit 1);
    a.submission_id := (select id from candidate_submissions where person_id = wi.person_id and agency_id = r.company_id
                          and job_order_id = r.job_order_id);
    v_client_name := (select coalesce(c.display_name, cl.name) from agency_clients cl
                        left join companies c on c.id = cl.client_company_id where cl.id = r.client_id);
  else
    a.application_id := (select id from applications where person_id = wi.person_id and company_id = r.company_id
                          and (r.job_id is null or job_id = r.job_id) order by applied_at desc limit 1);
  end if;
  a.status := 'offered'; a.offered_at := now(); a.offer_expires_at := now() + interval '7 days';
  a.agreement := jsonb_strip_nulls(jsonb_build_object(
    'employer', v_company_name, 'client', v_client_name, 'title', a.title, 'location', a.location_text,
    'start_date', a.start_date, 'end_date', a.end_date, 'employment_type', a.employment_type, 'work_type', a.work_type,
    'pay', jsonb_build_object('rate', a.pay_rate, 'period', a.pay_period, 'frequency', a.pay_frequency, 'currency', a.currency),
    'hours_per_week', r.hours_per_week,
    'shifts', (select jsonb_agg(jsonb_build_object('name', t.name, 'days', t.days_of_week, 'start', t.start_time,
                                                   'end', t.end_time, 'break_minutes', t.break_minutes))
                 from shift_templates t where t.requirement_id = r.id and t.status = 'active'),
    'supervisor', (select display_name from persons where id = a.supervisor_id),
    'check_in', r.check_in_method,
    'allowances', (select jsonb_agg(jsonb_build_object('kind', pc.kind, 'name', pc.name, 'amount', pc.amount, 'basis', pc.basis))
                     from pay_components pc where pc.requirement_id = r.id),
    'overtime', (select jsonb_build_object('name', op.name, 'multiplier', op.multiplier,
                                           'daily_threshold_minutes', op.daily_threshold_minutes,
                                           'weekly_threshold_minutes', op.weekly_threshold_minutes)
                   from overtime_policies op where op.id = r.overtime_policy_id)));
  a.created_by := p_actor; a.created_at := now(); a.updated_at := now();
  insert into assignments select a.*;

  if f ? 'bill_rate' and v_kind = 'agency' then
    insert into assignment_billing (assignment_id, bill_rate, bill_period, currency, updated_by)
    values (a.id, (f->>'bill_rate')::numeric, coalesce(nullif(f->>'bill_period', '')::pay_period, a.pay_period), a.currency, p_actor);
  end if;

  perform omelo_private.omelo_notify(a.person_id, 'work_update'::notification_type,
    v_company_name || ' offered you work: ' || a.title,
    coalesce(v_client_name || ' · ', '') || coalesce(a.location_text, '') || ' · from ' || to_char(a.start_date, 'DD Mon YYYY'),
    'assignment', a.id, '/work/assignments/' || a.id);
  perform omelo_private.omelo_emit('AssignmentOffered', 'assignment', a.id, a.company_id, a.person_id,
    jsonb_build_object('requirement_id', r.id, 'source', a.source));
  perform omelo_private.omelo_log_workforce(a.company_id, 'assignment', a.id, 'AssignmentOffered', a.person_id,
    null, jsonb_build_object('status', 'offered'), null);
  return a.id;
end;
$$;

create or replace function public.omelo_offer_assignment(p_requirement uuid, p_identity uuid, p_fields jsonb default '{}'::jsonb)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  return omelo_private.omelo_offer_assignment_core(auth.uid(), p_requirement, p_identity, p_fields, 'direct');
end;
$$;

create or replace function omelo_private.omelo_activate_assignment(p_assignment uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare a assignments; v_emp uuid; v_prof uuid;
begin
  select * into a from assignments where id = p_assignment for update;
  if a.status <> 'accepted' then return; end if;
  -- the hire through an agency submission already created the employment
  if a.submission_id is not null then
    select e.id into v_emp from employments e join candidate_submissions s on s.application_id = e.application_id
     where s.id = a.submission_id limit 1;
  end if;
  if v_emp is null and a.application_id is not null then
    select id into v_emp from employments where application_id = a.application_id limit 1;
  end if;
  if v_emp is null then
    select profession_id into v_prof from workforce_requirements where id = a.requirement_id;
    insert into employments (person_id, company_id, job_id, title, profession_id, work_type, location_id,
                             started_on, status, is_omelo_hire)
    values (a.person_id, coalesce(a.client_company_id, a.company_id), a.job_id, a.title, v_prof, a.work_type,
            a.location_id, a.start_date, 'active', true)
    returning id into v_emp;
    update experiences set work_identity_id = a.work_identity_id
     where verified_employment_id = v_emp and work_identity_id is null;
  end if;
  update assignments set status = 'active', activated_at = now(), employment_id = v_emp where id = a.id;
  perform omelo_private.omelo_emit('AssignmentStarted', 'assignment', a.id, a.company_id, a.person_id,
    jsonb_build_object('employment_id', v_emp));
  perform omelo_private.omelo_log_workforce(a.company_id, 'assignment', a.id, 'AssignmentStarted', a.person_id,
    jsonb_build_object('status', 'accepted'), jsonb_build_object('status', 'active', 'employment_id', v_emp), null);
end;
$$;

create or replace function public.omelo_respond_to_assignment(p_assignment uuid, p_accept boolean, p_reason text default null)
returns text
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare a assignments; r workforce_requirements; v_taken int;
begin
  select * into a from assignments where id = p_assignment and person_id = auth.uid() for update;
  if a.id is null then raise exception 'Assignment not found' using errcode = '42501'; end if;
  if a.status <> 'offered' then raise exception 'You already answered this offer' using errcode = '22023'; end if;
  if a.offer_expires_at < now() then
    update assignments set status = 'cancelled', end_reason = 'Offer expired' where id = a.id;
    raise exception 'This offer has expired' using errcode = '22023';
  end if;
  if not p_accept then
    update assignments set status = 'declined', responded_at = now(),
           decline_reason = left(nullif(trim(coalesce(p_reason, '')), ''), 300) where id = a.id;
    perform omelo_private.omelo_notify_team(a.company_id, 'manage_workforce', 'work_update',
      'An assignment offer was declined', a.title, 'assignment', a.id, '/dashboard/workforce/assignments/' || a.id);
    perform omelo_private.omelo_emit('AssignmentDeclined', 'assignment', a.id, a.company_id, a.person_id, '{}'::jsonb);
    return 'declined';
  end if;
  select * into r from workforce_requirements where id = a.requirement_id for update;
  select count(*) into v_taken from assignments where requirement_id = r.id and status in ('accepted','active','paused');
  if v_taken >= r.openings then
    raise exception 'All positions for this work are filled' using errcode = '22023';
  end if;
  update assignments set status = 'accepted', responded_at = now() where id = a.id;
  if v_taken + 1 >= r.openings and r.status = 'open' then
    update workforce_requirements set status = 'filled' where id = r.id;
  end if;
  perform omelo_private.omelo_notify_team(a.company_id, 'manage_workforce', 'work_update',
    'A worker accepted an assignment', a.title, 'assignment', a.id, '/dashboard/workforce/assignments/' || a.id);
  perform omelo_private.omelo_emit('AssignmentAccepted', 'assignment', a.id, a.company_id, a.person_id, '{}'::jsonb);
  if a.start_date <= omelo_private.omelo_local_today(a.timezone) then
    perform omelo_private.omelo_activate_assignment(a.id);
    return 'active';
  end if;
  return 'accepted';
end;
$$;

create or replace function public.omelo_set_assignment_status(p_assignment uuid, p_status text, p_reason text default null,
                                                              p_end_date date default null)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare a assignments; v_end date;
begin
  select * into a from assignments where id = p_assignment for update;
  if a.id is null then raise exception 'Assignment not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), a.company_id, 'manage_workforce');
  if p_status not in ('offered','active','paused','completed','terminated','cancelled') then
    raise exception 'Unknown status %', p_status using errcode = '22023';
  end if;
  if p_status = 'active' and a.status = 'accepted' then
    perform omelo_private.omelo_activate_assignment(a.id);
    return;
  end if;
  if p_status in ('completed','terminated') then
    v_end := coalesce(p_end_date, least(coalesce(a.end_date, omelo_private.omelo_local_today(a.timezone)),
                                        omelo_private.omelo_local_today(a.timezone)));
    if v_end < a.start_date then v_end := a.start_date; end if;
    update assignments set status = p_status, ended_at = now(), end_date = v_end,
           end_reason = left(coalesce(nullif(trim(p_reason), ''), initcap(p_status)), 500)
     where id = a.id;
    update shift_workers set status = 'cancelled'
     where assignment_id = a.id and status in ('offered','assigned') and starts_at > now();
    if a.employment_id is not null then
      update employments set status = case when p_status = 'completed' then 'ended'::employment_status else 'terminated'::employment_status end,
             ended_on = v_end, end_reason = left(coalesce(nullif(trim(p_reason), ''), initcap(p_status)), 300)
       where id = a.employment_id and status in ('active','on_notice');
    end if;
  else
    update assignments set status = p_status,
           end_reason = case when p_status = 'cancelled' then left(nullif(trim(p_reason), ''), 500) else end_reason end
     where id = a.id;
    if p_status = 'cancelled' then
      update shift_workers set status = 'cancelled' where assignment_id = a.id and status in ('offered','assigned');
    end if;
  end if;
  perform omelo_private.omelo_log_workforce(a.company_id, 'assignment', a.id, 'AssignmentStatusChanged', a.person_id,
    jsonb_build_object('status', a.status), jsonb_build_object('status', p_status), p_reason);
  perform omelo_private.omelo_emit(case p_status when 'completed' then 'AssignmentCompleted'
                                                  when 'terminated' then 'AssignmentTerminated'
                                                  when 'paused' then 'AssignmentPaused'
                                                  when 'cancelled' then 'AssignmentCancelled'
                                                  else 'AssignmentStatusChanged' end,
    'assignment', a.id, a.company_id, a.person_id, jsonb_build_object('from', a.status, 'to', p_status));
  perform omelo_private.omelo_notify(a.person_id, 'work_update'::notification_type,
    'Your assignment is ' || replace(p_status, '_', ' '), a.title, 'assignment', a.id, '/work/assignments/' || a.id);
end;
$$;

create or replace function public.omelo_set_assignment_billing(p_assignment uuid, p_bill_rate numeric, p_bill_period text,
                                                               p_note text default null)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare a assignments;
begin
  select * into a from assignments where id = p_assignment;
  if a.id is null or (select company_kind from companies where id = a.company_id) <> 'agency' then
    raise exception 'Billing applies to agency assignments' using errcode = '42501';
  end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), a.company_id, 'manage_pay');
  insert into assignment_billing (assignment_id, bill_rate, bill_period, currency, note, updated_by, updated_at)
  values (a.id, p_bill_rate, p_bill_period::pay_period, a.currency, left(p_note, 500), auth.uid(), now())
  on conflict (assignment_id) do update
     set bill_rate = excluded.bill_rate, bill_period = excluded.bill_period, note = excluded.note,
         updated_by = excluded.updated_by, updated_at = now();
end;
$$;
