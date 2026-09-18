-- OMELO 55 — Release 5: workforce functions, part 3 of 3 (see 53 for the overview):
-- timesheets, the normalised earnings calculation, payments, agency billing, read models,
-- asynchronous bulk operations, the scheduler tick (pg_cron 'omelo-workforce-tick'),
-- the matcher extension (engine v1.1) and the grants for all R5 functions.
-- Rollback: drop the functions below, unschedule 'omelo-workforce-tick', re-run 47.

-- 6. Timesheets -------------------------------------------------------------------------------
create or replace function omelo_private.omelo_recompute_timesheet(p_timesheet uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare t timesheets; op overtime_policies; v_total int; v_days int; v_shifts int; v_daily int := 0; v_weekly int := 0;
        v_ot int := 0; v_weeks numeric;
begin
  select * into t from timesheets where id = p_timesheet;
  select op2.* into op from overtime_policies op2 join assignments a on a.overtime_policy_id = op2.id where a.id = t.assignment_id;
  select coalesce(sum(minutes), 0), count(distinct work_date) filter (where minutes > 0),
         count(*) filter (where attendance_id is not null and minutes > 0 and kind = 'regular')
    into v_total, v_days, v_shifts
    from timesheet_entries where timesheet_id = t.id;
  if op.id is not null then
    if op.daily_threshold_minutes is not null then
      select coalesce(sum(greatest(0, m - op.daily_threshold_minutes)), 0) into v_daily
        from (select work_date, sum(minutes) m from timesheet_entries where timesheet_id = t.id and kind <> 'leave' group by 1) d;
    end if;
    if op.weekly_threshold_minutes is not null then
      select coalesce(sum(greatest(0, m - op.weekly_threshold_minutes)), 0) into v_weekly
        from (select date_trunc('week', work_date) wk, sum(minutes) m from timesheet_entries
               where timesheet_id = t.id and kind <> 'leave' group by 1) w;
    end if;
    v_ot := greatest(v_daily, v_weekly);
    if op.max_overtime_minutes_week is not null then
      v_weeks := greatest(1, ceil((t.period_end - t.period_start + 1) / 7.0));
      v_ot := least(v_ot, (op.max_overtime_minutes_week * v_weeks)::int);
    end if;
  end if;
  v_ot := least(v_ot, v_total);
  update timesheets set total_minutes = v_total, overtime_minutes = v_ot, regular_minutes = v_total - v_ot,
         days_worked = v_days, shifts_worked = v_shifts
   where id = t.id;
end;
$$;

create or replace function public.omelo_build_timesheet(p_assignment uuid, p_period_start date, p_period_end date)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare a assignments; t timesheets; v_id uuid;
begin
  select * into a from assignments where id = p_assignment;
  if a.id is null then raise exception 'Assignment not found' using errcode = '42501'; end if;
  if a.person_id <> auth.uid() then
    perform omelo_private.omelo_require_workforce(auth.uid(), a.company_id, 'manage_workforce');
  end if;
  if p_period_end < p_period_start or p_period_end > p_period_start + 31 then
    raise exception 'A timesheet covers at most 31 days' using errcode = '22023';
  end if;
  if p_period_end < a.start_date or (a.end_date is not null and p_period_start > a.end_date) then
    raise exception 'The period is outside the assignment' using errcode = '22023';
  end if;
  select * into t from timesheets where assignment_id = a.id and period_start = p_period_start;
  if t.id is not null and t.status not in ('draft','rejected') then
    raise exception 'This timesheet is already %', t.status using errcode = '22023';
  end if;
  if t.id is null then
    if exists (select 1 from timesheets where assignment_id = a.id
                and daterange(period_start, period_end, '[]') && daterange(p_period_start, p_period_end, '[]')) then
      raise exception 'Another timesheet already covers part of this period' using errcode = '22023';
    end if;
    insert into timesheets (assignment_id, person_id, company_id, period_start, period_end)
    values (a.id, a.person_id, a.company_id, p_period_start, p_period_end) returning id into v_id;
  else
    v_id := t.id;
    if t.status = 'rejected' then update timesheets set status = 'draft' where id = v_id; end if;
    delete from timesheet_entries where timesheet_id = v_id and kind <> 'manual';
  end if;
  insert into timesheet_entries (timesheet_id, attendance_id, work_date, minutes, kind, created_by)
  select v_id, ar.id, (ar.scheduled_start at time zone a.timezone)::date,
         least(1440, greatest(0, case when ar.review_status in ('approved','adjusted','rejected') then coalesce(ar.payable_minutes, 0)
                                      else coalesce(ar.worked_minutes, 0) end)),
         case when ar.status = 'approved_leave' then 'leave' else 'regular' end, auth.uid()
    from attendance_records ar
   where ar.assignment_id = a.id
     and (ar.scheduled_start at time zone a.timezone)::date between p_period_start and p_period_end
     and (ar.check_out_at is not null or ar.status in ('approved_leave','absent','unapproved_absence'))
     and not exists (select 1 from timesheet_entries e where e.attendance_id = ar.id);
  perform omelo_private.omelo_recompute_timesheet(v_id);
  return v_id;
end;
$$;

create or replace function public.omelo_add_timesheet_entry(p_timesheet uuid, p_work_date date, p_minutes integer, p_note text)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare t timesheets; v_id uuid;
begin
  select * into t from timesheets where id = p_timesheet and person_id = auth.uid();
  if t.id is null then raise exception 'Timesheet not found' using errcode = '42501'; end if;
  if p_work_date not between t.period_start and t.period_end then
    raise exception 'That day is outside the timesheet' using errcode = '22023';
  end if;
  if length(trim(coalesce(p_note, ''))) < 3 then
    raise exception 'Say what the extra time was for' using errcode = '22023';
  end if;
  insert into timesheet_entries (timesheet_id, work_date, minutes, kind, note, created_by)
  values (t.id, p_work_date, p_minutes, 'manual', left(trim(p_note), 300), auth.uid()) returning id into v_id;
  perform omelo_private.omelo_recompute_timesheet(t.id);
  return v_id;
end;
$$;

create or replace function public.omelo_remove_timesheet_entry(p_entry uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare e timesheet_entries;
begin
  select e2.* into e from timesheet_entries e2 join timesheets t on t.id = e2.timesheet_id
   where e2.id = p_entry and t.person_id = auth.uid() and e2.kind = 'manual';
  if e.id is null then raise exception 'Only your own added entries can be removed' using errcode = '42501'; end if;
  delete from timesheet_entries where id = e.id;
  perform omelo_private.omelo_recompute_timesheet(e.timesheet_id);
end;
$$;

create or replace function public.omelo_submit_timesheet(p_timesheet uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare t timesheets; a assignments;
begin
  select * into t from timesheets where id = p_timesheet and person_id = auth.uid();
  if t.id is null then raise exception 'Timesheet not found' using errcode = '42501'; end if;
  if t.status <> 'draft' then raise exception 'This timesheet is %', t.status using errcode = '22023'; end if;
  select * into a from assignments where id = t.assignment_id;
  update timesheets set status = 'submitted', submitted_at = now() where id = t.id;
  perform omelo_private.omelo_notify_team(omelo_private.omelo_approver_company(a.id), 'approve_time', 'work_update',
    'Timesheet to approve', (select display_name from persons where id = a.person_id) || ' · ' || a.title || ' · '
      || round(t.total_minutes / 60.0, 1) || ' h', 'timesheet', t.id, '/dashboard/workforce/approvals');
  perform omelo_private.omelo_emit('TimesheetSubmitted', 'timesheet', t.id, a.company_id, a.person_id,
    jsonb_build_object('minutes', t.total_minutes));
end;
$$;

-- 7. Earnings (normalised calculation) --------------------------------------------------------
create or replace function omelo_private.omelo_calculate_earnings(p_timesheet uuid)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare
  t timesheets; a assignments; op overtime_policies; v_id uuid; c record; ab assignment_billing;
  v_hours numeric; v_reg_hours numeric; v_ot_hours numeric; v_days int; v_shifts int; v_period_days int;
  v_base numeric := 0; v_ot numeric := 0; v_allow numeric := 0; v_bonus numeric := 0; v_ded numeric := 0; v_hourly numeric;
  v_qty numeric; v_unit text; v_amount numeric; v_overlap int;
begin
  select * into t from timesheets where id = p_timesheet;
  select * into a from assignments where id = t.assignment_id;
  select * into op from overtime_policies where id = a.overtime_policy_id;
  v_hours := t.total_minutes / 60.0; v_reg_hours := t.regular_minutes / 60.0; v_ot_hours := t.overtime_minutes / 60.0;
  v_days := t.days_worked; v_shifts := t.shifts_worked;
  v_overlap := (least(t.period_end, coalesce(a.end_date, t.period_end)) - greatest(t.period_start, a.start_date) + 1);
  v_period_days := greatest(0, v_overlap);

  insert into earnings (timesheet_id, assignment_id, person_id, company_id, period_start, period_end, currency)
  values (t.id, a.id, a.person_id, a.company_id, t.period_start, t.period_end, a.currency)
  on conflict (timesheet_id) do update set status = 'calculated', approved_by = null, approved_at = null
  returning id into v_id;
  delete from earning_lines where earning_id = v_id and kind <> 'adjustment';

  -- base
  case a.pay_period
    when 'hour' then v_qty := v_reg_hours + case when op.id is null then v_ot_hours else 0 end; v_unit := 'hour';
    when 'day' then v_qty := v_days; v_unit := 'day';
    when 'week' then v_qty := round(v_period_days / 7.0, 4); v_unit := 'week';
    when 'fortnight' then v_qty := round(v_period_days / 14.0, 4); v_unit := 'period';
    when 'month' then v_qty := round(v_period_days::numeric /
                           extract(day from (date_trunc('month', t.period_start) + interval '1 month - 1 day'))::numeric, 4);
                      v_unit := 'month';
    when 'year' then v_qty := round(v_period_days / 365.0, 4); v_unit := 'period';
    else v_qty := 0; v_unit := 'fixed';
  end case;
  v_base := round(v_qty * a.pay_rate, 2);
  insert into earning_lines (earning_id, kind, description, quantity, unit, rate, amount)
  values (v_id, 'base', case a.pay_period when 'hour' then 'Hours worked' when 'day' then 'Days worked'
                              when 'month' then 'Salary for the period' else 'Pay for the period' end,
          round(v_qty, 2), v_unit, a.pay_rate, v_base);

  -- overtime: only when the company configured a policy for this assignment
  if op.id is not null and v_ot_hours > 0 then
    v_hourly := case a.pay_period
      when 'hour' then a.pay_rate
      when 'day' then a.pay_rate / (op.standard_minutes_per_day / 60.0)
      when 'week' then a.pay_rate / (op.standard_minutes_per_week / 60.0)
      when 'fortnight' then a.pay_rate / (2 * op.standard_minutes_per_week / 60.0)
      when 'month' then a.pay_rate * 12 / (52 * op.standard_minutes_per_week / 60.0)
      when 'year' then a.pay_rate / (52 * op.standard_minutes_per_week / 60.0)
      else 0 end;
    v_ot := round(v_ot_hours * v_hourly * op.multiplier, 2);
    insert into earning_lines (earning_id, kind, description, quantity, unit, rate, amount)
    values (v_id, 'overtime', op.name || ' (x' || op.multiplier || ')', round(v_ot_hours, 2), 'hour',
            round(v_hourly * op.multiplier, 4), v_ot);
  end if;

  -- allowances / bonuses / deductions configured for the requirement or this assignment
  for c in select pc.* from pay_components pc where pc.requirement_id = a.requirement_id or pc.assignment_id = a.id loop
    v_qty := case c.basis
      when 'per_hour' then v_hours
      when 'per_day' then v_days
      when 'per_shift' then (select count(*) from timesheet_entries e join attendance_records ar on ar.id = e.attendance_id
                              join shifts s on s.id = ar.shift_id
                             where e.timesheet_id = t.id and e.minutes > 0 and e.kind = 'regular'
                               and (cardinality(c.applies_to_shift_types) = 0 or s.shift_type = any (c.applies_to_shift_types)))
      else 1 end;
    v_amount := round(v_qty * c.amount, 2);
    continue when v_amount = 0;
    insert into earning_lines (earning_id, kind, description, quantity, unit, rate, amount)
    values (v_id, c.kind, c.name, round(v_qty, 2),
            case c.basis when 'per_hour' then 'hour' when 'per_day' then 'day' when 'per_shift' then 'shift' else 'period' end,
            c.amount, v_amount);
    if c.kind = 'allowance' then v_allow := v_allow + v_amount;
    elsif c.kind = 'bonus' then v_bonus := v_bonus + v_amount;
    else v_ded := v_ded + v_amount; end if;
  end loop;

  update earnings set base_amount = v_base, overtime_amount = v_ot, allowance_amount = v_allow, bonus_amount = v_bonus,
         deduction_amount = v_ded,
         adjustment_amount = coalesce((select sum(amount) from earning_lines where earning_id = v_id and kind = 'adjustment'), 0)
   where id = v_id;

  -- agency billing to the client (bill rate is separate from the worker's pay)
  select * into ab from assignment_billing where assignment_id = a.id;
  if ab.assignment_id is not null then
    v_qty := case ab.bill_period when 'hour' then v_hours when 'day' then v_days
                                 when 'week' then round(v_period_days / 7.0, 4)
                                 when 'month' then round(v_period_days::numeric /
                                   extract(day from (date_trunc('month', t.period_start) + interval '1 month - 1 day'))::numeric, 4)
                                 else 1 end;
    insert into billing_records (timesheet_id, assignment_id, agency_id, client_id, client_company_id, quantity, unit,
                                 bill_rate, amount, currency)
    values (t.id, a.id, a.company_id, a.client_id, a.client_company_id, round(v_qty, 2),
            case ab.bill_period when 'hour' then 'hour' when 'day' then 'day' when 'week' then 'week' when 'month' then 'month' else 'period' end,
            ab.bill_rate, round(v_qty * ab.bill_rate, 2), ab.currency)
    on conflict (timesheet_id) do update set quantity = excluded.quantity, amount = excluded.amount,
           bill_rate = excluded.bill_rate, status = 'draft', updated_at = now();
  end if;
  return v_id;
end;
$$;

create or replace function public.omelo_review_timesheet(p_timesheet uuid, p_approve boolean, p_reason text default null)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare t timesheets; a assignments; v_pending int; v_earning uuid;
begin
  select * into t from timesheets where id = p_timesheet for update;
  if t.id is null then raise exception 'Timesheet not found' using errcode = '42501'; end if;
  select * into a from assignments where id = t.assignment_id;
  perform omelo_private.omelo_require_workforce(auth.uid(), omelo_private.omelo_approver_company(a.id), 'approve_time');
  if t.status not in ('submitted','under_review') then raise exception 'This timesheet is %', t.status using errcode = '22023'; end if;
  if not p_approve then
    if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'Say why the timesheet is rejected' using errcode = '22023'; end if;
    update timesheets set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now(), reject_reason = left(p_reason, 500)
     where id = t.id;
    perform omelo_private.omelo_notify(t.person_id, 'work_update'::notification_type, 'Timesheet returned',
      left(p_reason, 140), 'timesheet', t.id, '/work/timesheets/' || t.id);
    perform omelo_private.omelo_emit('TimesheetRejected', 'timesheet', t.id, a.company_id, t.person_id, '{}'::jsonb);
    return jsonb_build_object('status', 'rejected');
  end if;
  select count(*) into v_pending from attendance_exceptions x join timesheet_entries e on e.attendance_id = x.attendance_id
   where e.timesheet_id = t.id and x.status = 'pending';
  if v_pending > 0 then
    raise exception 'Resolve % attendance exception(s) first', v_pending using errcode = '22023';
  end if;
  update attendance_records ar set payable_minutes = coalesce(ar.worked_minutes, 0), review_status = 'approved',
         reviewed_by = auth.uid(), reviewed_at = now()
    from timesheet_entries e
   where e.timesheet_id = t.id and e.attendance_id = ar.id and ar.review_status = 'none';
  update timesheets set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now(), reject_reason = null where id = t.id;
  v_earning := omelo_private.omelo_calculate_earnings(t.id);
  perform omelo_private.omelo_notify(t.person_id, 'work_update'::notification_type, 'Timesheet approved',
    round(t.total_minutes / 60.0, 1) || ' h · ' || to_char(t.period_start, 'DD Mon') || ' – ' || to_char(t.period_end, 'DD Mon'),
    'timesheet', t.id, '/work/earnings');
  perform omelo_private.omelo_notify_team(a.company_id, 'manage_pay', 'work_update', 'Earnings to approve',
    (select display_name from persons where id = a.person_id) || ' · ' || a.title, 'earning', v_earning,
    '/dashboard/workforce/pay');
  perform omelo_private.omelo_emit('TimesheetApproved', 'timesheet', t.id, a.company_id, t.person_id,
    jsonb_build_object('earning_id', v_earning));
  return jsonb_build_object('status', 'approved', 'earning_id', v_earning);
end;
$$;

create or replace function public.omelo_start_timesheet_review(p_timesheet uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare t timesheets;
begin
  select * into t from timesheets where id = p_timesheet;
  if t.id is null then raise exception 'Not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), omelo_private.omelo_approver_company(t.assignment_id), 'approve_time');
  update timesheets set status = 'under_review' where id = t.id and status = 'submitted';
end;
$$;

-- Authorised correction of an approved / locked timesheet (nothing paid yet).
create or replace function public.omelo_reopen_timesheet(p_timesheet uuid, p_reason text)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare t timesheets;
begin
  select * into t from timesheets where id = p_timesheet for update;
  if t.id is null then raise exception 'Not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), t.company_id, 'manage_pay');
  if t.status not in ('approved','locked') then raise exception 'Only an approved timesheet can be reopened' using errcode = '22023'; end if;
  if length(trim(coalesce(p_reason, ''))) < 5 then raise exception 'A reopening needs a reason' using errcode = '22023'; end if;
  if exists (select 1 from payment_records p join earnings e on e.id = p.earning_id
              where e.timesheet_id = t.id and p.status in ('scheduled','processing','paid')) then
    raise exception 'Payments exist for this timesheet; reverse them first' using errcode = '22023';
  end if;
  perform set_config('omelo.correction', 'on', true);
  update timesheets set status = 'under_review' where id = t.id;
  update earnings set status = 'reversed' where timesheet_id = t.id;
  update billing_records set status = 'void', updated_at = now() where timesheet_id = t.id and status = 'draft';
  perform set_config('omelo.correction', 'off', true);
  perform omelo_private.omelo_log_workforce(t.company_id, 'timesheet', t.id, 'TimesheetReopened', t.person_id,
    jsonb_build_object('status', t.status), jsonb_build_object('status', 'under_review'), p_reason);
end;
$$;

create or replace function public.omelo_add_earning_adjustment(p_earning uuid, p_amount numeric, p_reason text)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare e earnings;
begin
  select * into e from earnings where id = p_earning for update;
  if e.id is null then raise exception 'Not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), e.company_id, 'manage_pay');
  if e.status not in ('calculated','approved') then
    raise exception 'These earnings are % and can no longer be adjusted', e.status using errcode = '22023';
  end if;
  if length(trim(coalesce(p_reason, ''))) < 3 or p_amount = 0 then
    raise exception 'An adjustment needs an amount and a reason' using errcode = '22023';
  end if;
  if e.gross_amount + p_amount < 0 then raise exception 'Earnings cannot become negative' using errcode = '22023'; end if;
  insert into earning_lines (earning_id, kind, description, quantity, unit, rate, amount, reason, created_by)
  values (e.id, 'adjustment', case when p_amount > 0 then 'Adjustment' else 'Correction' end, 1, 'fixed', p_amount,
          round(p_amount, 2), left(trim(p_reason), 300), auth.uid());
  perform set_config('omelo.correction', 'on', true);
  update earnings set adjustment_amount = (select coalesce(sum(amount), 0) from earning_lines where earning_id = e.id and kind = 'adjustment')
   where id = e.id;
  perform set_config('omelo.correction', 'off', true);
  perform omelo_private.omelo_log_workforce(e.company_id, 'earning', e.id, 'EarningAdjusted', e.person_id,
    jsonb_build_object('gross', e.gross_amount), jsonb_build_object('adjustment', p_amount), p_reason);
end;
$$;

create or replace function public.omelo_approve_earnings(p_earning uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare e earnings;
begin
  select * into e from earnings where id = p_earning for update;
  if e.id is null then raise exception 'Not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), e.company_id, 'manage_pay');
  if e.status <> 'calculated' then raise exception 'These earnings are %', e.status using errcode = '22023'; end if;
  update earnings set status = 'approved', approved_by = auth.uid(), approved_at = now() where id = e.id;
  update timesheets set status = 'locked', locked_at = now() where id = e.timesheet_id and status = 'approved';
  perform omelo_private.omelo_notify(e.person_id, 'work_update'::notification_type, 'Earnings approved',
    e.currency || ' ' || to_char(e.gross_amount, 'FM999G999G990D00') || ' · ' || to_char(e.period_start, 'DD Mon') || ' – '
      || to_char(e.period_end, 'DD Mon'), 'earning', e.id, '/work/earnings');
  perform omelo_private.omelo_emit('EarningsApproved', 'earning', e.id, e.company_id, e.person_id,
    jsonb_build_object('gross', e.gross_amount, 'currency', e.currency));
end;
$$;

create or replace function omelo_private.omelo_sync_earning_status(p_earning uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare e earnings; v_paid numeric; v_status text;
begin
  select * into e from earnings where id = p_earning;
  select coalesce(sum(amount) filter (where status = 'paid'), 0) into v_paid from payment_records where earning_id = e.id;
  v_status := case
    when v_paid >= e.gross_amount and e.gross_amount > 0 then 'paid'
    when exists (select 1 from payment_records where earning_id = e.id and status = 'processing') then 'processing'
    when exists (select 1 from payment_records where earning_id = e.id and status = 'scheduled') then 'scheduled'
    when exists (select 1 from payment_records where earning_id = e.id and status = 'failed')
         and not exists (select 1 from payment_records where earning_id = e.id and status in ('paid','scheduled','processing')) then 'failed'
    else 'approved' end;
  update earnings set status = v_status where id = e.id and status is distinct from v_status;
end;
$$;

create or replace function public.omelo_record_payment(p_earning uuid, p_amount numeric, p_status text default 'scheduled',
                                                       p_provider text default null, p_reference text default null,
                                                       p_scheduled_for date default null)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare e earnings; v_id uuid;
begin
  select * into e from earnings where id = p_earning for update;
  if e.id is null then raise exception 'Not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), e.company_id, 'manage_pay');
  if p_status not in ('scheduled','processing','paid') then raise exception 'A new payment is scheduled, processing or paid' using errcode = '22023'; end if;
  insert into payment_records (earning_id, person_id, company_id, amount, currency, status, provider, provider_reference,
                               scheduled_for, paid_at, created_by)
  values (e.id, e.person_id, e.company_id, round(p_amount, 2), e.currency, p_status, left(p_provider, 60), left(p_reference, 120),
          p_scheduled_for, case when p_status = 'paid' then now() end, auth.uid())
  returning id into v_id;
  perform omelo_private.omelo_sync_earning_status(e.id);
  if p_status = 'paid' then
    perform omelo_private.omelo_notify(e.person_id, 'work_update'::notification_type, 'Payment sent',
      e.currency || ' ' || to_char(p_amount, 'FM999G999G990D00'), 'earning', e.id, '/work/earnings');
  end if;
  perform omelo_private.omelo_emit('PaymentRecorded', 'payment', v_id, e.company_id, e.person_id,
    jsonb_build_object('amount', p_amount, 'status', p_status));
  return v_id;
end;
$$;

create or replace function public.omelo_update_payment(p_payment uuid, p_status text, p_reference text default null,
                                                       p_failure_reason text default null)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare p payment_records;
begin
  select * into p from payment_records where id = p_payment for update;
  if p.id is null then raise exception 'Not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), p.company_id, 'manage_pay');
  update payment_records set status = p_status,
         provider_reference = coalesce(left(p_reference, 120), provider_reference),
         failure_reason = case when p_status = 'failed' then left(p_failure_reason, 300) else failure_reason end,
         paid_at = case when p_status = 'paid' then now() else paid_at end
   where id = p.id;
  perform omelo_private.omelo_sync_earning_status(p.earning_id);
  if p_status in ('paid','failed','reversed') then
    perform omelo_private.omelo_notify(p.person_id, 'work_update'::notification_type,
      case p_status when 'paid' then 'Payment sent' when 'failed' then 'Payment failed' else 'Payment reversed' end,
      p.currency || ' ' || to_char(p.amount, 'FM999G999G990D00'), 'earning', p.earning_id, '/work/earnings');
  end if;
end;
$$;

create or replace function public.omelo_update_billing_status(p_billing uuid, p_status text)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare b billing_records;
begin
  select * into b from billing_records where id = p_billing;
  if b.id is null then raise exception 'Not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), b.agency_id, 'manage_pay');
  if not ((b.status = 'draft' and p_status in ('invoiced','void')) or (b.status = 'invoiced' and p_status in ('paid','void'))) then
    raise exception 'A bill cannot go from % to %', b.status, p_status using errcode = '22023';
  end if;
  update billing_records set status = p_status, updated_at = now() where id = b.id;
end;
$$;

-- 8. Read models ---------------------------------------------------------------------------------
create or replace function public.omelo_my_work(p_from date default null, p_to date default null)
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select coalesce(jsonb_agg(x order by x->>'starts_at'), '[]'::jsonb) from (
    select jsonb_build_object(
      'shift_worker_id', w.id, 'shift_id', s.id, 'assignment_id', a.id, 'status', w.status, 'shift_status', s.status,
      'starts_at', s.starts_at, 'ends_at', s.ends_at, 'timezone', s.timezone, 'break_minutes', s.break_minutes,
      'kind', s.kind, 'shift_type', s.shift_type, 'title', a.title, 'location', s.location_text,
      'employer', (select display_name from companies where id = a.company_id),
      'client', (select display_name from companies where id = a.client_company_id),
      'supervisor', (select jsonb_build_object('name', p.display_name, 'phone', p.phone) from persons p
                      where p.id = coalesce(s.supervisor_id, a.supervisor_id)),
      'instructions', s.instructions,
      'pay', jsonb_build_object('rate', a.pay_rate, 'period', a.pay_period, 'currency', a.currency),
      'check_in_method', r.check_in_method,
      'attendance', (select jsonb_build_object('id', ar.id, 'check_in_at', ar.check_in_at, 'check_out_at', ar.check_out_at,
                                               'status', ar.status, 'review_status', ar.review_status,
                                               'worked_minutes', ar.worked_minutes)
                       from attendance_records ar where ar.shift_worker_id = w.id)) as x
      from shift_workers w
      join shifts s on s.id = w.shift_id
      join assignments a on a.id = w.assignment_id
      join workforce_requirements r on r.id = a.requirement_id
     where w.person_id = (select auth.uid())
       and w.status in ('offered','assigned','completed','absent','on_leave','cancelled')
       and s.ends_at >= coalesce(p_from, current_date - 1)::timestamptz
       and s.starts_at < (coalesce(p_to, current_date + 14) + 1)::timestamptz
     limit 500) q;
$$;

create or replace function public.omelo_my_assignments()
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select coalesce(jsonb_agg(x order by (x->>'status' = 'offered') desc, x->>'start_date' desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', a.id, 'status', a.status, 'title', a.title, 'start_date', a.start_date, 'end_date', a.end_date,
      'location', a.location_text, 'timezone', a.timezone, 'employment_type', a.employment_type, 'work_type', a.work_type,
      'pay', jsonb_build_object('rate', a.pay_rate, 'period', a.pay_period, 'frequency', a.pay_frequency, 'currency', a.currency),
      'agreement', a.agreement, 'offer_expires_at', a.offer_expires_at, 'end_reason', a.end_reason,
      'employer', (select display_name from companies where id = a.company_id),
      'employer_is_agency', (select company_kind = 'agency' from companies where id = a.company_id),
      'client', (select display_name from companies where id = a.client_company_id),
      'identity_label', (select label from work_identities where id = a.work_identity_id),
      'next_shift', (select min(w.starts_at) from shift_workers w where w.assignment_id = a.id and w.status = 'assigned'
                       and w.starts_at > now()),
      'verified_experience', exists (select 1 from experiences x where x.verified_employment_id = a.employment_id)) as x
      from assignments a where a.person_id = (select auth.uid())
     limit 200) q;
$$;

create or replace function public.omelo_my_earnings()
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select coalesce(jsonb_agg(x order by x->>'period_start' desc), '[]'::jsonb) from (
    select jsonb_build_object(
      'id', e.id, 'period_start', e.period_start, 'period_end', e.period_end, 'currency', e.currency,
      'base', e.base_amount, 'overtime', e.overtime_amount, 'allowances', e.allowance_amount, 'bonus', e.bonus_amount,
      'deductions', e.deduction_amount, 'adjustments', e.adjustment_amount, 'gross', e.gross_amount, 'status', e.status,
      'title', a.title, 'employer', (select display_name from companies where id = a.company_id),
      'lines', (select jsonb_agg(jsonb_build_object('kind', l.kind, 'description', l.description, 'quantity', l.quantity,
                                                    'unit', l.unit, 'rate', l.rate, 'amount', l.amount, 'reason', l.reason)
                                 order by l.created_at) from earning_lines l where l.earning_id = e.id),
      'payments', (select jsonb_agg(jsonb_build_object('amount', p.amount, 'status', p.status, 'paid_at', p.paid_at,
                                                       'scheduled_for', p.scheduled_for, 'reference', p.provider_reference)
                                    order by p.created_at) from payment_records p where p.earning_id = e.id)) as x
      from earnings e join assignments a on a.id = e.assignment_id
     where e.person_id = (select auth.uid()) and e.status <> 'reversed'
     limit 200) q;
$$;

create or replace function public.omelo_shift_roster(p_shift uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare s shifts;
begin
  select * into s from shifts where id = p_shift;
  if s.id is null or not (omelo_private.omelo_workforce_can(s.company_id, 'view')
       or exists (select 1 from workforce_requirements r join agency_clients cl on cl.id = r.client_id
                   where r.id = s.requirement_id and cl.link_status = 'confirmed'
                     and omelo_private.omelo_workforce_can(cl.client_company_id, 'view'))) then
    raise exception 'Shift not found' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'shift', to_jsonb(s),
    'code', case when omelo_private.omelo_workforce_can(s.company_id, 'approve_time')
                   or exists (select 1 from workforce_requirements r join agency_clients cl on cl.id = r.client_id
                               where r.id = s.requirement_id and cl.link_status = 'confirmed'
                                 and omelo_private.omelo_workforce_can(cl.client_company_id, 'approve_time'))
                 then (select code from shift_codes where shift_id = s.id) end,
    'workers', coalesce((select jsonb_agg(jsonb_build_object(
        'shift_worker_id', w.id, 'assignment_id', w.assignment_id, 'person_id', w.person_id, 'name', p.display_name,
        'status', w.status,
        'attendance', (select jsonb_build_object('id', ar.id, 'check_in_at', ar.check_in_at, 'check_out_at', ar.check_out_at,
                                                 'status', ar.status, 'review_status', ar.review_status,
                                                 'worked_minutes', ar.worked_minutes,
                                                 'exceptions', (select jsonb_agg(jsonb_build_object('id', x.id, 'kind', x.kind,
                                                                   'minutes', x.minutes, 'status', x.status))
                                                                  from attendance_exceptions x where x.attendance_id = ar.id))
                         from attendance_records ar where ar.shift_worker_id = w.id))
        order by p.display_name)
      from shift_workers w join persons p on p.id = w.person_id where w.shift_id = s.id), '[]'::jsonb));
end;
$$;

create or replace function public.omelo_workforce_approvals(p_company uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
begin
  perform omelo_private.omelo_require_workforce(auth.uid(), p_company, 'approve_time');
  return jsonb_build_object(
    'exceptions', coalesce((select jsonb_agg(jsonb_build_object('attendance_id', ar.id, 'exception_id', x.id, 'kind', x.kind,
                              'minutes', x.minutes, 'detail', x.detail, 'worker', p.display_name, 'title', a.title,
                              'scheduled_start', ar.scheduled_start, 'check_in_at', ar.check_in_at,
                              'check_out_at', ar.check_out_at) order by ar.scheduled_start)
                             from attendance_exceptions x join attendance_records ar on ar.id = x.attendance_id
                             join assignments a on a.id = ar.assignment_id join persons p on p.id = ar.person_id
                            where x.status = 'pending' and coalesce(a.client_company_id, a.company_id) = p_company), '[]'::jsonb),
    'timesheets', coalesce((select jsonb_agg(jsonb_build_object('timesheet_id', t.id, 'worker', p.display_name, 'title', a.title,
                              'period_start', t.period_start, 'period_end', t.period_end, 'total_minutes', t.total_minutes,
                              'overtime_minutes', t.overtime_minutes, 'status', t.status, 'submitted_at', t.submitted_at)
                              order by t.submitted_at)
                             from timesheets t join assignments a on a.id = t.assignment_id join persons p on p.id = t.person_id
                            where t.status in ('submitted','under_review') and coalesce(a.client_company_id, a.company_id) = p_company),
                           '[]'::jsonb),
    'leave', coalesce((select jsonb_agg(jsonb_build_object('leave_id', l.id, 'worker', p.display_name, 'title', a.title,
                         'leave_type', l.leave_type, 'label', l.label, 'start_date', l.start_date, 'end_date', l.end_date,
                         'reason', l.reason) order by l.created_at)
                        from leave_requests l join assignments a on a.id = l.assignment_id join persons p on p.id = l.person_id
                       where l.status = 'requested' and (a.company_id = p_company or a.client_company_id = p_company)), '[]'::jsonb));
end;
$$;

create or replace function public.omelo_workforce_dashboard(p_company uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare v jsonb; v_agency boolean;
begin
  perform omelo_private.omelo_require_workforce(auth.uid(), p_company, 'view');
  select company_kind = 'agency' into v_agency from companies where id = p_company;
  select jsonb_build_object(
    'active_workers', (select count(distinct person_id) from assignments
                        where status = 'active' and (company_id = p_company or client_company_id = p_company)),
    'todays_shifts', (select count(*) from shifts s
                       where (s.company_id = p_company or exists (select 1 from workforce_requirements r join agency_clients cl on cl.id = r.client_id
                                                                   where r.id = s.requirement_id and cl.client_company_id = p_company))
                         and s.status <> 'cancelled'
                         and (s.starts_at at time zone s.timezone)::date = (now() at time zone s.timezone)::date),
    'present', (select count(*) from attendance_records ar join assignments a on a.id = ar.assignment_id
                 where (a.company_id = p_company or a.client_company_id = p_company) and ar.check_in_at is not null
                   and ar.scheduled_start::date = current_date),
    'absent', (select count(*) from attendance_records ar join assignments a on a.id = ar.assignment_id
                where (a.company_id = p_company or a.client_company_id = p_company)
                  and ar.status in ('absent','unapproved_absence') and ar.scheduled_start::date = current_date),
    'open_positions', (select coalesce(sum(greatest(0, r.openings - (select count(*) from assignments a
                          where a.requirement_id = r.id and a.status in ('accepted','active','paused')))), 0)
                         from workforce_requirements r where r.company_id = p_company and r.status in ('open','filled','active')),
    'pending_approvals', (select count(*) from attendance_exceptions x join attendance_records ar on ar.id = x.attendance_id
                           join assignments a on a.id = ar.assignment_id
                          where x.status = 'pending' and coalesce(a.client_company_id, a.company_id) = p_company)
                       + (select count(*) from leave_requests l join assignments a on a.id = l.assignment_id
                           where l.status = 'requested' and (a.company_id = p_company or a.client_company_id = p_company)),
    'timesheets', (select count(*) from timesheets t join assignments a on a.id = t.assignment_id
                    where t.status in ('submitted','under_review') and coalesce(a.client_company_id, a.company_id) = p_company),
    'offers_pending', (select count(*) from assignments where company_id = p_company and status = 'offered'),
    'earnings_to_approve', (select count(*) from earnings where company_id = p_company and status = 'calculated'))
  into v;
  if v_agency then
    v := v || jsonb_build_object(
      'clients', (select count(*) from agency_clients where agency_id = p_company and relationship_status in ('active','prospect')),
      'active_job_orders', (select count(*) from job_orders where agency_id = p_company and status in ('open','on_hold')),
      'pending_consents', (select count(*) from candidate_consents where agency_id = p_company and status = 'requested'),
      'submissions', (select count(*) from candidate_submissions where agency_id = p_company and status not in ('rejected','withdrawn','hired')),
      'interviews', (select count(*) from candidate_submissions where agency_id = p_company and status = 'interview'),
      'offers', (select count(*) from candidate_submissions where agency_id = p_company and status = 'offer'),
      'placements', (select count(*) from placements where agency_id = p_company and status in ('pending_start','active')));
  end if;
  return v;
end;
$$;

-- What a client company sees of the agency workforce at its sites: no pay.
create or replace function public.omelo_client_workforce(p_company uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
begin
  perform omelo_private.omelo_require_workforce(auth.uid(), p_company, 'view');
  return coalesce((select jsonb_agg(jsonb_build_object(
      'assignment_id', a.id, 'worker', p.display_name, 'identity_label', wi.label, 'title', a.title, 'status', a.status,
      'start_date', a.start_date, 'end_date', a.end_date, 'agency', c.display_name,
      'next_shift', (select min(w.starts_at) from shift_workers w where w.assignment_id = a.id and w.status = 'assigned'
                       and w.starts_at > now()))
      order by a.start_date desc)
    from assignments a join persons p on p.id = a.person_id join companies c on c.id = a.company_id
    left join work_identities wi on wi.id = a.work_identity_id
    where a.client_company_id = p_company and a.status in ('accepted','active','paused','completed')), '[]'::jsonb);
end;
$$;

-- 9. Bulk operations (asynchronous; authority re-checked per item) ----------------------------
create or replace function public.omelo_start_workforce_job(p_company uuid, p_kind text, p_payload jsonb)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_total int; v_id uuid;
begin
  perform omelo_private.omelo_require_workforce(auth.uid(), p_company, 'manage_workforce');
  v_total := case p_kind
    when 'offer_assignments' then jsonb_array_length(coalesce(p_payload->'identity_ids', '[]'::jsonb))
    when 'assign_shifts' then jsonb_array_length(coalesce(p_payload->'shift_ids', '[]'::jsonb))
                              * jsonb_array_length(coalesce(p_payload->'assignment_ids', '[]'::jsonb))
    when 'generate_shifts' then 1
    else null end;
  if v_total is null then raise exception 'Unknown bulk operation %', p_kind using errcode = '22023'; end if;
  if v_total = 0 or v_total > 20000 then raise exception 'A bulk operation handles 1 to 20,000 items' using errcode = '22023'; end if;
  if p_kind = 'offer_assignments' and not exists (select 1 from workforce_requirements
                                                   where id = nullif(p_payload->>'requirement_id', '')::uuid and company_id = p_company) then
    raise exception 'That requirement belongs to another company' using errcode = '42501';
  end if;
  if (select count(*) from workforce_jobs where company_id = p_company and status in ('queued','running')) >= 5 then
    raise exception 'Wait for your running bulk operations to finish' using errcode = '22023';
  end if;
  insert into workforce_jobs (company_id, kind, payload, total, created_by)
  values (p_company, p_kind, p_payload, v_total, auth.uid()) returning id into v_id;
  perform omelo_private.omelo_emit('WorkforceBulkQueued', 'workforce_job', v_id, p_company, null,
    jsonb_build_object('kind', p_kind, 'total', v_total));
  return v_id;
end;
$$;

create or replace function public.omelo_cancel_workforce_job(p_job uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare j workforce_jobs;
begin
  select * into j from workforce_jobs where id = p_job;
  if j.id is null then raise exception 'Not found' using errcode = '42501'; end if;
  perform omelo_private.omelo_require_workforce(auth.uid(), j.company_id, 'manage_workforce');
  update workforce_jobs set status = 'cancelled', finished_at = now() where id = j.id and status in ('queued','running');
end;
$$;

create or replace function omelo_private.omelo_process_workforce_jobs(p_budget integer default 300)
returns integer
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare
  j workforce_jobs; v_left int := p_budget; i int; v_item jsonb; v_ok int; v_bad int; v_errors jsonb;
  v_shifts jsonb; v_asgs jsonb; v_n_asg int; v_done int := 0;
begin
  for j in select * from workforce_jobs where status in ('queued','running') order by created_at for update skip locked loop
    exit when v_left <= 0;
    update workforce_jobs set status = 'running', started_at = coalesce(started_at, now()) where id = j.id;
    v_ok := 0; v_bad := 0; v_errors := '[]'::jsonb;
    i := j.processed;
    while i < j.total and v_left > 0 loop
      begin
        if j.kind = 'offer_assignments' then
          perform omelo_private.omelo_offer_assignment_core(j.created_by, (j.payload->>'requirement_id')::uuid,
                    (j.payload->'identity_ids'->>i)::uuid, coalesce(j.payload->'fields', '{}'::jsonb), 'bulk');
        elsif j.kind = 'assign_shifts' then
          v_shifts := j.payload->'shift_ids'; v_asgs := j.payload->'assignment_ids'; v_n_asg := jsonb_array_length(v_asgs);
          perform omelo_private.omelo_assign_shift_core(j.created_by, (v_shifts->>(i / v_n_asg))::uuid,
                    (v_asgs->>(i % v_n_asg))::uuid, false);
        elsif j.kind = 'generate_shifts' then
          perform omelo_private.omelo_generate_shifts_core(j.created_by, (j.payload->>'template_id')::uuid,
                    (j.payload->>'from')::date, (j.payload->>'to')::date);
        end if;
        v_ok := v_ok + 1;
      exception when others then
        v_bad := v_bad + 1;
        if jsonb_array_length(v_errors) + jsonb_array_length(j.errors) < 200 then
          v_errors := v_errors || jsonb_build_object('item', i, 'error', sqlerrm);
        end if;
      end;
      i := i + 1; v_left := v_left - 1; v_done := v_done + 1;
    end loop;
    update workforce_jobs
       set processed = i, succeeded = succeeded + v_ok, failed = failed + v_bad, errors = errors || v_errors,
           status = case when i >= total then (case when failed + v_bad = 0 then 'succeeded'
                                                     when succeeded + v_ok = 0 then 'failed' else 'partial' end)
                         else 'running' end,
           finished_at = case when i >= total then now() end
     where id = j.id;
    if i >= j.total and j.created_by is not null then
      perform omelo_private.omelo_notify(j.created_by, 'work_update'::notification_type, 'Bulk operation finished',
        replace(j.kind, '_', ' ') || ': ' || (j.succeeded + v_ok) || ' done, ' || (j.failed + v_bad) || ' failed',
        'workforce_job', j.id, '/dashboard/workforce/bulk');
    end if;
  end loop;
  return v_done;
end;
$$;

-- 10. The scheduler tick (every minute) -------------------------------------------------------
create or replace function omelo_private.omelo_workforce_tick()
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare r record; v_bulk int; v_abs int := 0; v_id uuid;
begin
  v_bulk := omelo_private.omelo_process_workforce_jobs(300);

  -- offers that were never answered
  update assignments set status = 'cancelled', end_reason = 'Offer expired'
   where status = 'offered' and offer_expires_at < now();
  update shift_workers set status = 'declined' where status = 'offered' and starts_at < now();

  -- assignments start and end on their dates
  for r in select id from assignments where status = 'accepted' and start_date <= (now() at time zone timezone)::date limit 500 loop
    perform omelo_private.omelo_activate_assignment(r.id);
  end loop;
  for r in select a.id, a.company_id, a.person_id, a.employment_id, a.end_date from assignments a
            where a.status in ('active','paused') and a.end_date < (now() at time zone a.timezone)::date limit 500 loop
    update assignments set status = 'completed', ended_at = now(), end_reason = coalesce(end_reason, 'Assignment period ended')
     where id = r.id;
    if r.employment_id is not null then
      update employments set status = 'ended', ended_on = r.end_date, end_reason = 'Assignment completed'
       where id = r.employment_id and status in ('active','on_notice');
    end if;
    perform omelo_private.omelo_emit('AssignmentCompleted', 'assignment', r.id, r.company_id, r.person_id, '{}'::jsonb);
  end loop;

  -- shift status follows the clock
  update shifts set status = 'in_progress' where status = 'scheduled' and starts_at <= now() and ends_at > now();
  update shifts set status = 'completed' where status in ('scheduled','in_progress') and ends_at <= now();

  -- absences: nobody checked in by 30 minutes after the end
  for r in select w.*, s.break_minutes as brk from shift_workers w join shifts s on s.id = w.shift_id
            where w.status = 'assigned' and s.status <> 'cancelled' and w.ends_at < now() - interval '30 minutes'
              and not exists (select 1 from attendance_records ar where ar.shift_worker_id = w.id)
            limit 500 loop
    insert into attendance_records (shift_worker_id, shift_id, assignment_id, person_id, scheduled_start, scheduled_end,
                                    break_minutes, payable_minutes, status, review_status)
    values (r.id, r.shift_id, r.assignment_id, r.person_id, r.starts_at, r.ends_at, r.brk, 0, 'absent', 'pending')
    returning id into v_id;
    insert into attendance_exceptions (attendance_id, kind, detail) values (v_id, 'absent', 'No check-in for this shift');
    update shift_workers set status = 'absent' where id = r.id;
    perform omelo_private.omelo_notify_team(omelo_private.omelo_approver_company(r.assignment_id), 'approve_time', 'work_update',
      'Worker absent', (select display_name from persons where id = r.person_id), 'attendance', v_id, '/dashboard/workforce/approvals');
    perform omelo_private.omelo_emit('WorkerAbsent', 'attendance', v_id,
      (select company_id from assignments where id = r.assignment_id), r.person_id, '{}'::jsonb);
    v_abs := v_abs + 1;
  end loop;

  -- checked in but never checked out
  for r in select ar.id from attendance_records ar
            where ar.check_in_at is not null and ar.check_out_at is null and ar.scheduled_end < now() - interval '6 hours'
              and not exists (select 1 from attendance_exceptions x where x.attendance_id = ar.id and x.kind = 'missing_check_out')
            limit 500 loop
    insert into attendance_exceptions (attendance_id, kind, detail) values (r.id, 'missing_check_out', 'No check-out recorded');
    update attendance_records set review_status = 'pending' where id = r.id and review_status = 'none';
  end loop;

  -- reminders one hour ahead
  for r in select w.id, w.person_id, s.id as shift_id, s.starts_at, s.timezone, s.location_text
             from shift_workers w join shifts s on s.id = w.shift_id
            where w.status = 'assigned' and w.reminder_sent_at is null and s.status = 'scheduled'
              and s.starts_at between now() and now() + interval '60 minutes' limit 1000 loop
    update shift_workers set reminder_sent_at = now() where id = r.id;
    perform omelo_private.omelo_notify(r.person_id, 'shift_update'::notification_type, 'Your shift starts soon',
      to_char(r.starts_at at time zone r.timezone, 'HH24:MI') || coalesce(' · ' || r.location_text, ''),
      'shift', r.shift_id, '/work/shifts/' || r.shift_id);
  end loop;

  -- assignments ending in 7 days
  for r in select id, company_id, person_id, title, end_date from assignments
            where status = 'active' and ending_notice_sent_at is null
              and end_date = (now() at time zone timezone)::date + 7 limit 500 loop
    update assignments set ending_notice_sent_at = now() where id = r.id;
    perform omelo_private.omelo_notify(r.person_id, 'work_update'::notification_type, 'Your assignment ends in 7 days',
      r.title || ' · ' || to_char(r.end_date, 'DD Mon'), 'assignment', r.id, '/work/assignments/' || r.id);
    perform omelo_private.omelo_notify_team(r.company_id, 'manage_workforce', 'work_update', 'Assignment ending in 7 days',
      r.title, 'assignment', r.id, '/dashboard/workforce/assignments/' || r.id);
    perform omelo_private.omelo_emit('AssignmentEnding', 'assignment', r.id, r.company_id, r.person_id, '{}'::jsonb);
  end loop;

  return jsonb_build_object('bulk_items', v_bulk, 'absences', v_abs);
end;
$$;

do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'omelo-workforce-tick';
  perform cron.schedule('omelo-workforce-tick', '* * * * *', 'select omelo_private.omelo_workforce_tick()');
end;
$$;

-- 11. The matcher, extended (engine v1.1) -----------------------------------------------------
do $$
declare d text;
begin
  d := pg_get_functiondef('omelo_private.omelo_score_match'::regproc);
  if position($r$'engine_version', 'v1.0'$r$ in d) = 0 or position('v_final int;' in d) = 0
     or position($r$for k, w in select key, value::numeric from jsonb_each_text(wp.weights) loop$r$ in d) = 0
     or position('v_final := case when sum_w = 0' in d) = 0 then
    raise exception 'omelo_score_match is not the expected version';
  end if;
  d := replace(d, 'v_final int;', 'v_final int;
  wr record; v_sched numeric; v_sched_notes text[] := ''{}'';');
  d := replace(d, $r$for k, w in select key, value::numeric from jsonb_each_text(wp.weights) loop$r$,
$r$-- R5: workforce requirements add schedule fit and a conflict gate
  select * into wr from workforce_requirements
   where (job_id = j.id or job_order_id in (select jo.id from job_orders jo where jo.job_id = j.id))
     and status in ('open','filled','active')
   order by created_at desc limit 1;
  if wr.id is not null then
    v_sched := 1;
    if pref.work_identity_id is not null then
      if wr.start_date is not null and pref.available_from is not null and pref.available_from > wr.start_date then
        v_sched := v_sched - 0.3; v_sched_notes := array_append(v_sched_notes, 'Available from ' || to_char(pref.available_from, 'DD Mon'));
      end if;
      if wr.end_date is not null and pref.available_until is not null and pref.available_until < wr.end_date then
        v_sched := v_sched - 0.3; v_sched_notes := array_append(v_sched_notes, 'Available until ' || to_char(pref.available_until, 'DD Mon'));
      end if;
      if wr.hours_per_week is not null and pref.max_weekly_hours is not null and pref.max_weekly_hours < wr.hours_per_week then
        v_sched := v_sched - 0.3; v_sched_notes := array_append(v_sched_notes, 'Wants at most ' || pref.max_weekly_hours || ' h a week');
      end if;
      if cardinality(pref.preferred_days) > 0 and exists (select 1 from shift_templates st where st.requirement_id = wr.id
                  and st.status = 'active' and not (st.days_of_week <@ pref.preferred_days)) then
        v_sched := v_sched - 0.2; v_sched_notes := array_append(v_sched_notes, 'Some shifts fall outside preferred days');
      end if;
    end if;
    v_sched := greatest(0, v_sched);
    f := f || jsonb_build_object('schedule_fit', omelo_factor(v_sched,
      case when pref.work_identity_id is null then 'unknown' when v_sched >= 0.85 then 'strong' when v_sched >= 0.4 then 'partial' else 'gap' end,
      case when pref.work_identity_id is null then 'Availability not set'
           when cardinality(v_sched_notes) = 0 then 'Available for these dates and hours'
           else array_to_string(v_sched_notes, '; ') end));
    if exists (select 1 from shift_workers sw join shifts sh on sh.requirement_id = wr.id
                where sw.person_id = pr.id and sw.status = 'assigned' and sh.status <> 'cancelled' and sh.starts_at > now()
                  and sw.shift_id <> sh.id and tstzrange(sw.starts_at, sw.ends_at) && tstzrange(sh.starts_at, sh.ends_at)) then
      gates := gates || jsonb_build_object('schedule_conflict', 'fail');
      gate_failures := array_append(gate_failures, 'schedule_conflict');
    else
      gates := gates || jsonb_build_object('schedule_conflict', 'pass');
    end if;
  end if;

  for k, w in select key, value::numeric from jsonb_each_text(wp.weights) loop$r$);
  d := replace(d, 'v_final := case when sum_w = 0',
$r$if f ? 'schedule_fit' then
    sum_w := sum_w + 0.08;
    sum_sw := sum_sw + 0.08 * (f -> 'schedule_fit' ->> 'score')::numeric;
    f := jsonb_set(f, array['schedule_fit'], (f -> 'schedule_fit') || jsonb_build_object('weight', 0.08,
           'contribution', round(0.08 * (f -> 'schedule_fit' ->> 'score')::numeric, 4)));
    case f -> 'schedule_fit' ->> 'status'
      when 'strong' then strengths := strengths || jsonb_build_object('factor', 'schedule_fit', 'weight', 0.08, 'text', f -> 'schedule_fit' ->> 'explanation');
      when 'unknown' then unknowns := unknowns || jsonb_build_object('factor', 'schedule_fit', 'weight', 0.08, 'text', f -> 'schedule_fit' ->> 'explanation');
      else gaps := gaps || jsonb_build_object('factor', 'schedule_fit', 'weight', 0.08, 'text', f -> 'schedule_fit' ->> 'explanation');
    end case;
  end if;

  v_final := case when sum_w = 0$r$);
  d := replace(d, $r$'engine_version', 'v1.0'$r$, $r$'engine_version', 'v1.1'$r$);
  execute d;
end;
$$;

-- 12. Grants ------------------------------------------------------------------------------------
do $$
declare fn text;
begin
  foreach fn in array array[
    'omelo_create_requirement(uuid, jsonb)', 'omelo_update_requirement(uuid, jsonb)',
    'omelo_save_pay_component(uuid, uuid, text, text, numeric, text, text[])', 'omelo_remove_pay_component(uuid)',
    'omelo_offer_assignment(uuid, uuid, jsonb)', 'omelo_respond_to_assignment(uuid, boolean, text)',
    'omelo_set_assignment_status(uuid, text, text, date)', 'omelo_set_assignment_billing(uuid, numeric, text, text)',
    'omelo_save_shift_template(uuid, jsonb, uuid)', 'omelo_generate_shifts(uuid, date, date)',
    'omelo_create_shift(uuid, jsonb)', 'omelo_update_shift(uuid, jsonb)', 'omelo_cancel_shift(uuid, text)',
    'omelo_assign_shift(uuid, uuid[])', 'omelo_offer_shift(uuid, uuid[])', 'omelo_respond_to_shift(uuid, boolean)',
    'omelo_unassign_shift(uuid, text)', 'omelo_shift_replacements(uuid)',
    'omelo_check_in(uuid, text, double precision, double precision, text)',
    'omelo_check_out(uuid, double precision, double precision)',
    'omelo_record_attendance(uuid, timestamptz, timestamptz, text)',
    'omelo_review_attendance(uuid, text, timestamptz, timestamptz, integer, text)',
    'omelo_correct_attendance(uuid, timestamptz, timestamptz, text)',
    'omelo_request_leave(uuid, text, date, date, text, text)', 'omelo_cancel_leave(uuid)', 'omelo_review_leave(uuid, boolean, text)',
    'omelo_build_timesheet(uuid, date, date)', 'omelo_add_timesheet_entry(uuid, date, integer, text)',
    'omelo_remove_timesheet_entry(uuid)', 'omelo_submit_timesheet(uuid)', 'omelo_review_timesheet(uuid, boolean, text)',
    'omelo_start_timesheet_review(uuid)', 'omelo_reopen_timesheet(uuid, text)',
    'omelo_add_earning_adjustment(uuid, numeric, text)', 'omelo_approve_earnings(uuid)',
    'omelo_record_payment(uuid, numeric, text, text, text, date)', 'omelo_update_payment(uuid, text, text, text)',
    'omelo_update_billing_status(uuid, text)',
    'omelo_my_work(date, date)', 'omelo_my_assignments()', 'omelo_my_earnings()', 'omelo_shift_roster(uuid)',
    'omelo_workforce_approvals(uuid)', 'omelo_workforce_dashboard(uuid)', 'omelo_client_workforce(uuid)',
    'omelo_start_workforce_job(uuid, text, jsonb)', 'omelo_cancel_workforce_job(uuid)'
  ] loop
    execute format('revoke execute on function public.%s from public, anon', fn);
    execute format('grant execute on function public.%s to authenticated', fn);
  end loop;
end;
$$;

do $$
declare fn text;
begin
  foreach fn in array array[
    'omelo_require_workforce(uuid, uuid, text)', 'omelo_approver_company(uuid)',
    'omelo_notify_team(uuid, text, text, text, text, text, uuid, text)',
    'omelo_apply_requirement_fields(workforce_requirements, jsonb)', 'omelo_check_requirement(workforce_requirements)',
    'omelo_offer_assignment_core(uuid, uuid, uuid, jsonb, text)', 'omelo_activate_assignment(uuid)',
    'omelo_generate_shifts_core(uuid, uuid, date, date)', 'omelo_assign_shift_core(uuid, uuid, uuid, boolean)',
    'omelo_recompute_timesheet(uuid)', 'omelo_calculate_earnings(uuid)', 'omelo_sync_earning_status(uuid)',
    'omelo_process_workforce_jobs(integer)', 'omelo_workforce_tick()'
  ] loop
    execute format('revoke execute on function omelo_private.%s from public, anon, authenticated', fn);
  end loop;
end;
$$;
