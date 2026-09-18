-- OMELO 51 — Release 5: Staffing & Workforce engine — schema, security, integrity.
--
-- Lifecycle: requirement -> assignment -> shift -> check-in/out -> attendance
--            -> timesheet -> approval -> earnings -> payment
--            -> completed employment -> verified experience (existing loop)
--
-- Reused, not duplicated:
--   companies / company_members (employer or agency; roles + RBAC)
--   agency_clients / job_orders / candidate_consents / candidate_submissions (R4)
--   jobs, applications, employments (a completed assignment IS an employment;
--     the existing employments triggers create verified experience)
--   notifications, domain_events, pg_cron, the matcher (extended in 52)
--
-- New tables (one requirement can hold 1 or 1,000,000 openings — openings are
-- a number, never rows): overtime_policies, workforce_requirements,
-- pay_components, assignments, assignment_billing, shift_templates, shifts,
-- shift_codes, shift_workers, attendance_records, attendance_exceptions,
-- leave_requests, timesheets, timesheet_entries, earnings, earning_lines,
-- payment_records, billing_records, workforce_events, workforce_jobs.
--
-- Every write goes through functions (52); clients have no INSERT/UPDATE/
-- DELETE on any of these tables except company configuration
-- (overtime_policies, pay_components). The integrity rules below are
-- triggers that run for EVERY writer, service_role included:
--   R5-001 assignment = the worker's own identity; R5-002 agency assignments
--   need consent/submission for that agency + client + job order; R5-003
--   valid dates; R5-004 no overlapping shifts; R5-005/006 attendance only for
--   the worker's own shift, check-out only after check-in; R5-007 reviewed
--   attendance is not silently changed; R5-008 locked timesheets are not
--   edited; R5-009 earnings only from an approved timesheet; R5-010 payments
--   never exceed approved earnings; R5-014 no attendance on a cancelled
--   shift; R5-015 no new shifts outside an assignment's period or status.
--
-- Worker pay is never exposed to a client company (client-facing reads are
-- functions that omit it); agency bill rates live in assignment_billing /
-- billing_records, never readable by the worker.
--
-- Rollback: drop the tables below (children first) and the helper functions.

-- 0. Worker availability (extends person_work_preferences, fed to the matcher)
alter table person_work_preferences
  add column if not exists available_until date,
  add column if not exists preferred_days smallint[] not null default '{}',
  add column if not exists preferred_start_time time,
  add column if not exists preferred_end_time time,
  add column if not exists max_travel_km integer;
alter table person_work_preferences drop constraint if exists person_work_preferences_days_check;
alter table person_work_preferences add constraint person_work_preferences_days_check
  check (preferred_days <@ array[1,2,3,4,5,6,7]::smallint[]
         and (max_travel_km is null or max_travel_km between 0 and 1000)
         and (available_until is null or available_from is null or available_until >= available_from));

-- 1. Authority -------------------------------------------------------------------------
create or replace function omelo_private.omelo_workforce_roles(p_kind text, p_action text)
returns text[]
language sql immutable
as $$
  select case
    when p_kind = 'agency' then case p_action
      when 'manage_workforce' then array['owner','admin','recruiter','coordinator']
      when 'approve_time'     then array['owner','admin','coordinator']
      when 'manage_pay'       then array['owner','admin','finance','coordinator']
      when 'view'             then array['owner','admin','recruiter','sourcer','coordinator','finance','viewer']
      else array[]::text[] end
    else case p_action
      when 'manage_workforce' then array['owner','admin','recruiter','hiring_manager','hr']
      when 'approve_time'     then array['owner','admin','hiring_manager','hr']
      when 'manage_pay'       then array['owner','admin','finance','hr']
      when 'view'             then array['owner','admin','recruiter','hiring_manager','interviewer','hr','finance','viewer']
      else array[]::text[] end
  end;
$$;

create or replace function omelo_private.omelo_person_workforce_can(p_person uuid, p_company uuid, p_action text)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select exists (
    select 1 from companies c
      join company_members cm on cm.company_id = c.id and cm.person_id = p_person and cm.is_active
     where c.id = p_company and c.deleted_at is null
       and cm.role::text = any (omelo_private.omelo_workforce_roles(c.company_kind, p_action)));
$$;

create or replace function omelo_private.omelo_workforce_can(p_company uuid, p_action text)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select omelo_private.omelo_person_workforce_can((select auth.uid()), p_company, p_action);
$$;
grant execute on function omelo_private.omelo_workforce_roles(text, text) to authenticated;
grant execute on function omelo_private.omelo_person_workforce_can(uuid, uuid, text) to authenticated;
grant execute on function omelo_private.omelo_workforce_can(uuid, text) to authenticated;

-- 2. Configuration: overtime policies (no legal defaults: the company configures its jurisdiction)
create table if not exists public.overtime_policies (
  id                         uuid primary key default gen_random_uuid(),
  company_id                 uuid not null references companies(id) on delete cascade,
  name                       text not null check (length(trim(name)) between 1 and 80),
  country_code               char(2),
  daily_threshold_minutes    integer check (daily_threshold_minutes between 0 and 1440),
  weekly_threshold_minutes   integer check (weekly_threshold_minutes between 0 and 10080),
  multiplier                 numeric(4,2) not null default 1.5 check (multiplier between 1 and 5),
  max_overtime_minutes_week  integer check (max_overtime_minutes_week >= 0),
  standard_minutes_per_day   integer not null default 480 check (standard_minutes_per_day between 60 and 1440),
  standard_minutes_per_week  integer not null default 2880 check (standard_minutes_per_week between 60 and 10080),
  notes                      text check (notes is null or length(notes) <= 1000),
  created_at                 timestamptz not null default now(),
  check (daily_threshold_minutes is not null or weekly_threshold_minutes is not null)
);
create index if not exists overtime_policies_company_idx on overtime_policies (company_id);

-- 3. Requirement -------------------------------------------------------------------------
create table if not exists public.workforce_requirements (
  id                   uuid primary key default gen_random_uuid(),
  company_id           uuid not null references companies(id) on delete cascade,
  client_id            uuid references agency_clients(id) on delete set null,
  job_order_id         uuid references job_orders(id) on delete set null,
  job_id               uuid references jobs(id) on delete set null,
  title                text not null check (length(trim(title)) between 2 and 120),
  profession_id        uuid references professions(id) on delete set null,
  openings             integer not null default 1 check (openings between 1 and 1000000),
  location_id          uuid references locations(id) on delete set null,
  location_text        text check (location_text is null or length(location_text) <= 200),
  site_name            text check (site_name is null or length(site_name) <= 120),
  country_code         char(2),
  currency             char(3) not null check (currency ~ '^[A-Z]{3}$'),
  timezone             text not null default 'UTC',
  employment_type      text not null default 'temporary'
                       check (employment_type in ('permanent','temporary','contract','seasonal','project','gig',
                                                  'freelance','internship','apprenticeship','on_call')),
  work_type            work_type not null default 'full_time',
  pay_rate             numeric check (pay_rate is null or pay_rate >= 0),
  pay_period           pay_period,
  pay_frequency        text not null default 'monthly'
                       check (pay_frequency in ('daily','weekly','biweekly','semimonthly','monthly','per_shift','on_completion')),
  hours_per_week       numeric(5,2) check (hours_per_week is null or hours_per_week between 0 and 168),
  start_date           date,
  end_date             date,
  check_in_method      text not null default 'app' check (check_in_method in ('app','qr','geofence','employer')),
  geofence_radius_m    integer check (geofence_radius_m is null or geofence_radius_m between 25 and 5000),
  late_grace_minutes   integer not null default 10 check (late_grace_minutes between 0 and 240),
  overtime_policy_id   uuid references overtime_policies(id) on delete set null,
  supervisor_id        uuid references persons(id) on delete set null,
  status               text not null default 'open'
                       check (status in ('draft','open','filled','active','completed','cancelled')),
  notes                text check (notes is null or length(notes) <= 4000),
  created_by           uuid references persons(id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  check (end_date is null or start_date is null or end_date >= start_date),
  check (check_in_method <> 'geofence' or geofence_radius_m is not null)
);
create index if not exists workforce_requirements_company_idx on workforce_requirements (company_id, status);
create index if not exists workforce_requirements_job_idx on workforce_requirements (job_id) where job_id is not null;
create index if not exists workforce_requirements_order_idx on workforce_requirements (job_order_id) where job_order_id is not null;

-- 4. Assignment (the central entity) -----------------------------------------------------
create table if not exists public.assignments (
  id                  uuid primary key default gen_random_uuid(),
  requirement_id      uuid not null references workforce_requirements(id) on delete cascade,
  company_id          uuid not null references companies(id) on delete cascade,   -- managing employer or agency
  client_id           uuid references agency_clients(id) on delete set null,
  client_company_id   uuid references companies(id) on delete set null,            -- workplace company on Omelo
  job_order_id        uuid references job_orders(id) on delete set null,
  job_id              uuid references jobs(id) on delete set null,
  application_id      uuid references applications(id) on delete set null,
  consent_id          uuid references candidate_consents(id) on delete set null,
  submission_id       uuid references candidate_submissions(id) on delete set null,
  person_id           uuid not null references persons(id) on delete cascade,
  work_identity_id    uuid not null references work_identities(id) on delete cascade,
  employment_id       uuid references employments(id) on delete set null,
  title               text not null check (length(trim(title)) between 2 and 120),
  location_id         uuid references locations(id) on delete set null,
  location_text       text,
  timezone            text not null,
  start_date          date not null,
  end_date            date,
  employment_type     text not null
                      check (employment_type in ('permanent','temporary','contract','seasonal','project','gig',
                                                 'freelance','internship','apprenticeship','on_call')),
  work_type           work_type not null,
  pay_rate            numeric not null check (pay_rate >= 0),
  pay_period          pay_period not null,
  pay_frequency       text not null
                      check (pay_frequency in ('daily','weekly','biweekly','semimonthly','monthly','per_shift','on_completion')),
  currency            char(3) not null check (currency ~ '^[A-Z]{3}$'),
  overtime_policy_id  uuid references overtime_policies(id) on delete set null,
  supervisor_id       uuid references persons(id) on delete set null,
  source              text not null check (source in ('direct','application','agency','replacement','bulk')),
  agreement           jsonb not null default '{}'::jsonb,
  status              text not null default 'offered'
                      check (status in ('draft','offered','accepted','active','paused','completed','declined','cancelled','terminated')),
  offer_expires_at    timestamptz,
  offered_at          timestamptz,
  responded_at        timestamptz,
  activated_at        timestamptz,
  ended_at            timestamptz,
  end_reason          text check (end_reason is null or length(end_reason) <= 500),
  decline_reason      text check (decline_reason is null or length(decline_reason) <= 300),
  ending_notice_sent_at timestamptz,
  created_by          uuid references persons(id) on delete set null,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (end_date is null or end_date >= start_date),
  check (end_date is null or end_date <= start_date + 3650)
);
create unique index if not exists assignments_one_open on assignments (requirement_id, person_id)
  where status in ('draft','offered','accepted','active','paused');
create index if not exists assignments_person_idx on assignments (person_id, status);
create index if not exists assignments_company_idx on assignments (company_id, status);
create index if not exists assignments_client_company_idx on assignments (client_company_id) where client_company_id is not null;
create index if not exists assignments_requirement_idx on assignments (requirement_id, status);

-- Agency margin: kept apart from the worker's pay, never readable by the worker.
create table if not exists public.assignment_billing (
  assignment_id  uuid primary key references assignments(id) on delete cascade,
  bill_rate      numeric not null check (bill_rate >= 0),
  bill_period    pay_period not null,
  currency       char(3) not null check (currency ~ '^[A-Z]{3}$'),
  note           text check (note is null or length(note) <= 500),
  updated_by     uuid references persons(id) on delete set null,
  updated_at     timestamptz not null default now()
);

create table if not exists public.pay_components (
  id                     uuid primary key default gen_random_uuid(),
  requirement_id         uuid references workforce_requirements(id) on delete cascade,
  assignment_id          uuid references assignments(id) on delete cascade,
  kind                   text not null check (kind in ('allowance','bonus','deduction')),
  name                   text not null check (length(trim(name)) between 1 and 80),
  amount                 numeric not null check (amount >= 0),
  basis                  text not null check (basis in ('per_hour','per_shift','per_day','per_period')),
  applies_to_shift_types shift_type[] not null default '{}',
  created_by             uuid references persons(id) on delete set null,
  created_at             timestamptz not null default now(),
  check (num_nonnulls(requirement_id, assignment_id) = 1)
);
create index if not exists pay_components_req_idx on pay_components (requirement_id) where requirement_id is not null;
create index if not exists pay_components_asg_idx on pay_components (assignment_id) where assignment_id is not null;

-- 5. Shifts --------------------------------------------------------------------------------
create table if not exists public.shift_templates (
  id               uuid primary key default gen_random_uuid(),
  requirement_id   uuid not null references workforce_requirements(id) on delete cascade,
  name             text not null check (length(trim(name)) between 1 and 80),
  days_of_week     smallint[] not null check (days_of_week <@ array[1,2,3,4,5,6,7]::smallint[] and cardinality(days_of_week) >= 1),
  start_time       time not null,
  end_time         time not null,          -- end <= start means the shift ends the next day (overnight)
  break_minutes    integer not null default 0 check (break_minutes between 0 and 480),
  required_workers integer not null default 1 check (required_workers between 1 and 100000),
  shift_type       shift_type,
  valid_from       date,
  valid_until      date,
  status           text not null default 'active' check (status in ('active','archived')),
  created_by       uuid references persons(id) on delete set null,
  created_at       timestamptz not null default now(),
  check (valid_until is null or valid_from is null or valid_until >= valid_from),
  check (start_time <> end_time)
);
create index if not exists shift_templates_req_idx on shift_templates (requirement_id);

create table if not exists public.shifts (
  id                uuid primary key default gen_random_uuid(),
  requirement_id    uuid not null references workforce_requirements(id) on delete cascade,
  template_id       uuid references shift_templates(id) on delete set null,
  company_id        uuid not null references companies(id) on delete cascade,
  location_id       uuid references locations(id) on delete set null,
  location_text     text,
  starts_at         timestamptz not null,
  ends_at           timestamptz not null,
  timezone          text not null,
  break_minutes     integer not null default 0 check (break_minutes between 0 and 480),
  required_workers  integer not null default 1 check (required_workers between 1 and 100000),
  shift_type        shift_type,
  kind              text not null default 'regular' check (kind in ('regular','overtime','emergency','split','on_call')),
  status            text not null default 'scheduled' check (status in ('scheduled','in_progress','completed','cancelled')),
  cancel_reason     text check (cancel_reason is null or length(cancel_reason) <= 300),
  instructions      text check (instructions is null or length(instructions) <= 2000),
  supervisor_id     uuid references persons(id) on delete set null,
  created_by        uuid references persons(id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (ends_at > starts_at and ends_at <= starts_at + interval '24 hours'),
  check (break_minutes * interval '1 minute' < ends_at - starts_at)
);
create unique index if not exists shifts_template_start_key on shifts (template_id, starts_at) where template_id is not null;
create index if not exists shifts_requirement_idx on shifts (requirement_id, starts_at);
create index if not exists shifts_company_idx on shifts (company_id, starts_at);

-- Check-in code shown by the supervisor (QR / typed); never readable by workers.
create table if not exists public.shift_codes (
  shift_id    uuid primary key references shifts(id) on delete cascade,
  code        text not null check (code ~ '^[0-9]{6}$'),
  created_at  timestamptz not null default now()
);

create table if not exists public.shift_workers (
  id               uuid primary key default gen_random_uuid(),
  shift_id         uuid not null references shifts(id) on delete cascade,
  assignment_id    uuid not null references assignments(id) on delete cascade,
  person_id        uuid not null references persons(id) on delete cascade,
  status           text not null default 'assigned'
                   check (status in ('offered','assigned','declined','cancelled','on_leave','completed','absent')),
  starts_at        timestamptz not null,
  ends_at          timestamptz not null,
  assigned_by      uuid references persons(id) on delete set null,
  assigned_at      timestamptz not null default now(),
  responded_at     timestamptz,
  reminder_sent_at timestamptz,
  unique (shift_id, assignment_id)
);
create index if not exists shift_workers_person_idx on shift_workers (person_id, starts_at);
create index if not exists shift_workers_shift_idx on shift_workers (shift_id, status);
create index if not exists shift_workers_assignment_idx on shift_workers (assignment_id);

-- 6. Attendance --------------------------------------------------------------------------
create table if not exists public.attendance_records (
  id                uuid primary key default gen_random_uuid(),
  shift_worker_id   uuid not null unique references shift_workers(id) on delete cascade,
  shift_id          uuid not null references shifts(id) on delete cascade,
  assignment_id     uuid not null references assignments(id) on delete cascade,
  person_id         uuid not null references persons(id) on delete cascade,
  scheduled_start   timestamptz not null,
  scheduled_end     timestamptz not null,
  break_minutes     integer not null default 0,
  check_in_at       timestamptz,
  check_in_method   text check (check_in_method in ('app','qr','geofence','employer','correction')),
  check_in_geo      extensions.geography(point, 4326),
  check_out_at      timestamptz,
  check_out_method  text check (check_out_method in ('app','qr','geofence','employer','correction')),
  worked_minutes    integer check (worked_minutes between 0 and 1440),
  payable_minutes   integer check (payable_minutes between 0 and 1440),
  status            text not null
                    check (status in ('checked_in','present','late','absent','partial','early_departure',
                                      'approved_leave','unapproved_absence')),
  review_status     text not null default 'none' check (review_status in ('none','pending','approved','adjusted','rejected')),
  reviewed_by       uuid references persons(id) on delete set null,
  reviewed_at       timestamptz,
  review_note       text check (review_note is null or length(review_note) <= 500),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (check_out_at is null or check_in_at is not null),
  check (check_out_at is null or check_out_at > check_in_at)
);
create index if not exists attendance_person_idx on attendance_records (person_id, scheduled_start desc);
create index if not exists attendance_assignment_idx on attendance_records (assignment_id, scheduled_start);
create index if not exists attendance_shift_idx on attendance_records (shift_id);

create table if not exists public.attendance_exceptions (
  id               uuid primary key default gen_random_uuid(),
  attendance_id    uuid not null references attendance_records(id) on delete cascade,
  kind             text not null check (kind in ('late','early_departure','absent','missing_check_out',
                                                 'location_mismatch','manual_correction')),
  minutes          integer,
  detail           text,
  status           text not null default 'pending' check (status in ('pending','approved','adjusted','rejected')),
  resolved_by      uuid references persons(id) on delete set null,
  resolved_at      timestamptz,
  resolution_note  text check (resolution_note is null or length(resolution_note) <= 500),
  created_at       timestamptz not null default now()
);
create index if not exists attendance_exceptions_att_idx on attendance_exceptions (attendance_id);
create index if not exists attendance_exceptions_pending_idx on attendance_exceptions (status) where status = 'pending';

create table if not exists public.leave_requests (
  id            uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references assignments(id) on delete cascade,
  person_id     uuid not null references persons(id) on delete cascade,
  company_id    uuid not null references companies(id) on delete cascade,
  leave_type    text not null check (leave_type in ('paid','unpaid','sick','personal','other')),
  label         text check (label is null or length(label) <= 80),   -- the jurisdiction's own name for it
  start_date    date not null,
  end_date      date not null,
  reason        text check (reason is null or length(reason) <= 500),
  status        text not null default 'requested' check (status in ('requested','approved','rejected','cancelled')),
  reviewed_by   uuid references persons(id) on delete set null,
  reviewed_at   timestamptz,
  review_note   text check (review_note is null or length(review_note) <= 500),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (end_date >= start_date and end_date <= start_date + 365)
);
create index if not exists leave_requests_assignment_idx on leave_requests (assignment_id, status);
create index if not exists leave_requests_company_idx on leave_requests (company_id, status);

-- 7. Timesheets, earnings, payments, billing --------------------------------------------
create table if not exists public.timesheets (
  id                uuid primary key default gen_random_uuid(),
  assignment_id     uuid not null references assignments(id) on delete cascade,
  person_id         uuid not null references persons(id) on delete cascade,
  company_id        uuid not null references companies(id) on delete cascade,
  period_start      date not null,
  period_end        date not null,
  status            text not null default 'draft'
                    check (status in ('draft','submitted','under_review','approved','rejected','locked')),
  total_minutes     integer not null default 0 check (total_minutes >= 0),
  regular_minutes   integer not null default 0 check (regular_minutes >= 0),
  overtime_minutes  integer not null default 0 check (overtime_minutes >= 0),
  days_worked       integer not null default 0,
  shifts_worked     integer not null default 0,
  submitted_at      timestamptz,
  reviewed_by       uuid references persons(id) on delete set null,
  reviewed_at       timestamptz,
  reject_reason     text check (reject_reason is null or length(reject_reason) <= 500),
  locked_at         timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (assignment_id, period_start),
  check (period_end >= period_start and period_end <= period_start + 31),
  check (regular_minutes + overtime_minutes = total_minutes)
);
create index if not exists timesheets_company_idx on timesheets (company_id, status);
create index if not exists timesheets_person_idx on timesheets (person_id, period_start desc);

create table if not exists public.timesheet_entries (
  id             uuid primary key default gen_random_uuid(),
  timesheet_id   uuid not null references timesheets(id) on delete cascade,
  attendance_id  uuid references attendance_records(id) on delete set null,
  work_date      date not null,
  minutes        integer not null check (minutes between 0 and 1440),
  kind           text not null check (kind in ('regular','manual','leave')),
  note           text check (note is null or length(note) <= 300),
  created_by     uuid references persons(id) on delete set null,
  created_at     timestamptz not null default now(),
  check (kind <> 'manual' or note is not null)
);
create index if not exists timesheet_entries_ts_idx on timesheet_entries (timesheet_id, work_date);
create unique index if not exists timesheet_entries_attendance_key on timesheet_entries (attendance_id) where attendance_id is not null;

create table if not exists public.earnings (
  id                 uuid primary key default gen_random_uuid(),
  timesheet_id       uuid not null unique references timesheets(id) on delete cascade,
  assignment_id      uuid not null references assignments(id) on delete cascade,
  person_id          uuid not null references persons(id) on delete cascade,
  company_id         uuid not null references companies(id) on delete cascade,
  period_start       date not null,
  period_end         date not null,
  currency           char(3) not null,
  base_amount        numeric(14,2) not null default 0,
  overtime_amount    numeric(14,2) not null default 0,
  allowance_amount   numeric(14,2) not null default 0,
  bonus_amount       numeric(14,2) not null default 0,
  deduction_amount   numeric(14,2) not null default 0,
  adjustment_amount  numeric(14,2) not null default 0,
  gross_amount       numeric(14,2) generated always as
                     (base_amount + overtime_amount + allowance_amount + bonus_amount + adjustment_amount - deduction_amount) stored,
  status             text not null default 'calculated'
                     check (status in ('calculated','approved','scheduled','processing','paid','failed','reversed')),
  approved_by        uuid references persons(id) on delete set null,
  approved_at        timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  check (base_amount >= 0 and overtime_amount >= 0 and allowance_amount >= 0 and bonus_amount >= 0 and deduction_amount >= 0)
);
create index if not exists earnings_person_idx on earnings (person_id, period_start desc);
create index if not exists earnings_company_idx on earnings (company_id, status);

create table if not exists public.earning_lines (
  id           uuid primary key default gen_random_uuid(),
  earning_id   uuid not null references earnings(id) on delete cascade,
  kind         text not null check (kind in ('base','overtime','allowance','bonus','deduction','adjustment')),
  description  text not null,
  quantity     numeric(12,2),
  unit         text check (unit in ('hour','day','shift','week','month','period','fixed')),
  rate         numeric(14,4),
  amount       numeric(14,2) not null,
  reason       text check (reason is null or length(reason) <= 300),
  created_by   uuid references persons(id) on delete set null,
  created_at   timestamptz not null default now(),
  check (kind = 'adjustment' or amount >= 0),
  check (kind <> 'adjustment' or reason is not null)
);
create index if not exists earning_lines_earning_idx on earning_lines (earning_id);

create table if not exists public.payment_records (
  id                 uuid primary key default gen_random_uuid(),
  earning_id         uuid not null references earnings(id) on delete cascade,
  person_id          uuid not null references persons(id) on delete cascade,
  company_id         uuid not null references companies(id) on delete cascade,
  amount             numeric(14,2) not null check (amount > 0),
  currency           char(3) not null,
  status             text not null default 'scheduled'
                     check (status in ('scheduled','processing','paid','failed','reversed')),
  provider           text check (provider is null or length(provider) <= 60),
  provider_reference text check (provider_reference is null or length(provider_reference) <= 120),
  scheduled_for      date,
  paid_at            timestamptz,
  failure_reason     text check (failure_reason is null or length(failure_reason) <= 300),
  created_by         uuid references persons(id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index if not exists payment_records_earning_idx on payment_records (earning_id);
create index if not exists payment_records_person_idx on payment_records (person_id);

create table if not exists public.billing_records (
  id                 uuid primary key default gen_random_uuid(),
  timesheet_id       uuid not null unique references timesheets(id) on delete cascade,
  assignment_id      uuid not null references assignments(id) on delete cascade,
  agency_id          uuid not null references companies(id) on delete cascade,
  client_id          uuid references agency_clients(id) on delete set null,
  client_company_id  uuid references companies(id) on delete set null,
  quantity           numeric(12,2) not null,
  unit               text not null check (unit in ('hour','day','week','month','period')),
  bill_rate          numeric(14,4) not null,
  amount             numeric(14,2) not null check (amount >= 0),
  currency           char(3) not null,
  status             text not null default 'draft' check (status in ('draft','invoiced','paid','void')),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index if not exists billing_records_agency_idx on billing_records (agency_id, status);
create index if not exists billing_records_client_idx on billing_records (client_company_id) where client_company_id is not null;

-- 8. Audit + bulk jobs -------------------------------------------------------------------
create table if not exists public.workforce_events (
  id           bigint generated always as identity primary key,
  company_id   uuid references companies(id) on delete cascade,
  entity_type  text not null,
  entity_id    uuid not null,
  event        text not null,
  actor_id     uuid references persons(id) on delete set null,
  person_id    uuid references persons(id) on delete set null,
  before       jsonb,
  after        jsonb,
  reason       text,
  occurred_at  timestamptz not null default now()
);
create index if not exists workforce_events_entity_idx on workforce_events (entity_type, entity_id, occurred_at);
create index if not exists workforce_events_company_idx on workforce_events (company_id, occurred_at desc);

create table if not exists public.workforce_jobs (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references companies(id) on delete cascade,
  kind         text not null check (kind in ('offer_assignments','assign_shifts','generate_shifts')),
  payload      jsonb not null,
  status       text not null default 'queued' check (status in ('queued','running','succeeded','partial','failed','cancelled')),
  total        integer not null default 0,
  processed    integer not null default 0,
  succeeded    integer not null default 0,
  failed       integer not null default 0,
  errors       jsonb not null default '[]'::jsonb,
  created_by   uuid references persons(id) on delete set null,
  created_at   timestamptz not null default now(),
  started_at   timestamptz,
  finished_at  timestamptz
);
create index if not exists workforce_jobs_queue_idx on workforce_jobs (status, created_at) where status in ('queued','running');

-- 9. Integrity (every writer) ------------------------------------------------------------
create or replace function omelo_private.omelo_log_workforce(p_company uuid, p_type text, p_id uuid, p_event text,
                                                             p_person uuid, p_before jsonb, p_after jsonb, p_reason text)
returns void
language sql security definer
set search_path = public, omelo_private
as $$
  insert into workforce_events (company_id, entity_type, entity_id, event, actor_id, person_id, before, after, reason)
  values (p_company, p_type, p_id, p_event, (select auth.uid()), p_person, p_before, p_after, p_reason);
$$;
revoke execute on function omelo_private.omelo_log_workforce(uuid, text, uuid, text, uuid, jsonb, jsonb, text) from public, anon, authenticated;

create or replace function omelo_private.omelo_validate_assignment()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare r workforce_requirements; v_kind text;
begin
  select * into r from workforce_requirements where id = new.requirement_id;
  -- R5-001: the worker's own identity
  if not exists (select 1 from work_identities where id = new.work_identity_id and person_id = new.person_id) then
    raise exception 'The work identity does not belong to this worker' using errcode = '23514';
  end if;
  if new.company_id is distinct from r.company_id then
    raise exception 'An assignment belongs to its requirement''s company' using errcode = '23514';
  end if;
  -- R5-003: valid dates (and inside the requirement)
  if new.end_date is not null and new.end_date < new.start_date then
    raise exception 'The assignment ends before it starts' using errcode = '23514';
  end if;
  if tg_op = 'INSERT' then
    if (r.start_date is not null and new.start_date < r.start_date) or (r.end_date is not null and new.end_date is null)
       or (r.end_date is not null and new.end_date > r.end_date) then
      raise exception 'The assignment must fall within the requirement''s dates' using errcode = '23514';
    end if;
    select company_kind into v_kind from companies where id = new.company_id;
    -- R5-002: an agency may assign only whom it represents for this client and job order
    if v_kind = 'agency' then
      if new.client_id is distinct from r.client_id or new.job_order_id is distinct from r.job_order_id
         or r.job_order_id is null then
        raise exception 'An agency assignment needs its requirement''s client and job order' using errcode = '23514';
      end if;
      if not exists (select 1 from candidate_consents c
                      where c.person_id = new.person_id and c.agency_id = new.company_id
                        and c.job_order_id = new.job_order_id
                        and (c.status = 'active' or (c.status = 'accepted' and c.expires_at > now())))
         and not exists (select 1 from candidate_submissions s
                          where s.person_id = new.person_id and s.agency_id = new.company_id
                            and s.job_order_id = new.job_order_id and s.status = 'hired') then
        raise exception 'The agency does not represent this worker for this job order' using errcode = '23514';
      end if;
      new.client_company_id := (select client_company_id from agency_clients where id = r.client_id and link_status = 'confirmed');
    else
      new.client_id := null;
      new.client_company_id := null;
    end if;
  else
    if new.person_id is distinct from old.person_id or new.work_identity_id is distinct from old.work_identity_id
    or new.company_id is distinct from old.company_id or new.requirement_id is distinct from old.requirement_id
    or new.client_id is distinct from old.client_id or new.job_order_id is distinct from old.job_order_id
    or new.created_by is distinct from old.created_by or new.source is distinct from old.source then
      raise exception 'An assignment cannot change owner, worker or requirement' using errcode = '23514';
    end if;
    if new.status is distinct from old.status and not (
         (old.status = 'draft'    and new.status in ('offered','cancelled'))
      or (old.status = 'offered'  and new.status in ('accepted','declined','cancelled'))
      or (old.status = 'accepted' and new.status in ('active','cancelled'))
      or (old.status = 'active'   and new.status in ('paused','completed','terminated'))
      or (old.status = 'paused'   and new.status in ('active','completed','terminated'))) then
      raise exception 'An assignment cannot go from % to %', old.status, new.status using errcode = '23514';
    end if;
    if old.status in ('accepted','active','paused')
       and (new.pay_rate is distinct from old.pay_rate or new.pay_period is distinct from old.pay_period
            or new.currency is distinct from old.currency or new.start_date is distinct from old.start_date) then
      raise exception 'Accepted terms (pay, currency, start) change only with a new assignment offer' using errcode = '23514';
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists assignments_validate on assignments;
create trigger assignments_validate before insert or update on assignments
  for each row execute function omelo_private.omelo_validate_assignment();

-- R5-004 / R5-014 / R5-015: a worker is placed on a shift only inside a live
-- assignment, on a live shift, without overlapping another shift or leave.
create or replace function omelo_private.omelo_validate_shift_worker()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare s shifts; a assignments; v_local date;
begin
  select * into s from shifts where id = new.shift_id;
  select * into a from assignments where id = new.assignment_id;
  new.person_id := a.person_id;
  new.starts_at := s.starts_at;
  new.ends_at := s.ends_at;
  if new.status in ('offered','assigned') and (tg_op = 'INSERT' or old.status is distinct from new.status
                                               or old.starts_at is distinct from new.starts_at
                                               or old.ends_at is distinct from new.ends_at) then
    if s.status = 'cancelled' then
      raise exception 'This shift was cancelled' using errcode = '23514';
    end if;
    if s.requirement_id is distinct from a.requirement_id then
      raise exception 'The shift and the assignment belong to different requirements' using errcode = '23514';
    end if;
    if a.status not in ('accepted','active') then
      raise exception 'The worker''s assignment is not in force (%)', a.status using errcode = '23514';
    end if;
    v_local := (s.starts_at at time zone s.timezone)::date;
    if v_local < a.start_date or (a.end_date is not null and v_local > a.end_date) then
      raise exception 'The shift is outside the assignment period' using errcode = '23514';
    end if;
    perform pg_advisory_xact_lock(hashtext('shift_worker:' || a.person_id::text));
    if exists (select 1 from shift_workers w
                where w.person_id = a.person_id and w.id <> new.id and w.status = 'assigned'
                  and tstzrange(w.starts_at, w.ends_at) && tstzrange(new.starts_at, new.ends_at)) then
      raise exception 'Schedule conflict: the worker already has a shift at this time' using errcode = '23P01';
    end if;
    if exists (select 1 from leave_requests l where l.person_id = a.person_id and l.status = 'approved'
                and v_local between l.start_date and l.end_date) then
      raise exception 'The worker is on approved leave that day' using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists shift_workers_validate on shift_workers;
create trigger shift_workers_validate before insert or update on shift_workers
  for each row execute function omelo_private.omelo_validate_shift_worker();

-- A shift that moves re-validates its workers; a cancelled shift releases them.
create or replace function omelo_private.omelo_after_shift_change()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if new.status = 'cancelled' and old.status <> 'cancelled' then
    update shift_workers set status = 'cancelled' where shift_id = new.id and status in ('offered','assigned');
  elsif new.starts_at is distinct from old.starts_at or new.ends_at is distinct from old.ends_at then
    if exists (select 1 from attendance_records where shift_id = new.id and check_in_at is not null) then
      raise exception 'Workers have already checked in to this shift; it cannot move' using errcode = '23514';
    end if;
    update shift_workers set starts_at = new.starts_at, ends_at = new.ends_at where shift_id = new.id;
  end if;
  return null;
end;
$$;
drop trigger if exists shifts_after_change on shifts;
create trigger shifts_after_change after update on shifts
  for each row execute function omelo_private.omelo_after_shift_change();

create or replace function omelo_private.omelo_validate_shift()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare r workforce_requirements;
begin
  select * into r from workforce_requirements where id = new.requirement_id;
  if new.company_id is distinct from r.company_id then
    raise exception 'A shift belongs to its requirement''s company' using errcode = '23514';
  end if;
  if tg_op = 'INSERT' or new.starts_at is distinct from old.starts_at then
    if r.status in ('completed','cancelled') then
      raise exception 'The requirement is %', r.status using errcode = '23514';
    end if;
    if (r.start_date is not null and (new.starts_at at time zone new.timezone)::date < r.start_date)
       or (r.end_date is not null and (new.starts_at at time zone new.timezone)::date > r.end_date) then
      raise exception 'The shift is outside the requirement''s dates' using errcode = '23514';
    end if;
  end if;
  if tg_op = 'UPDATE' and old.status in ('completed','cancelled') and new.status is distinct from old.status then
    raise exception 'This shift is already %', old.status using errcode = '23514';
  end if;
  if not exists (select 1 from pg_timezone_names where name = new.timezone) then
    raise exception 'Unknown time zone %', new.timezone using errcode = '22023';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists shifts_validate on shifts;
create trigger shifts_validate before insert or update on shifts
  for each row execute function omelo_private.omelo_validate_shift();

-- R5-005/006/007/014: attendance integrity.
create or replace function omelo_private.omelo_validate_attendance()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare w shift_workers; s shifts; v_correction boolean := coalesce(current_setting('omelo.correction', true), '') = 'on';
begin
  select * into w from shift_workers where id = new.shift_worker_id;
  select * into s from shifts where id = w.shift_id;
  if new.shift_id is distinct from w.shift_id or new.assignment_id is distinct from w.assignment_id
     or new.person_id is distinct from w.person_id then
    raise exception 'Attendance must match the worker''s own shift' using errcode = '23514';
  end if;
  if s.status = 'cancelled' and new.status not in ('approved_leave') then
    raise exception 'A cancelled shift cannot record attendance' using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' then
    if old.review_status in ('approved','adjusted','rejected') and not v_correction
       and (new.check_in_at is distinct from old.check_in_at or new.check_out_at is distinct from old.check_out_at
            or new.payable_minutes is distinct from old.payable_minutes or new.status is distinct from old.status
            or new.break_minutes is distinct from old.break_minutes) then
      raise exception 'Reviewed attendance changes only through an authorised correction' using errcode = '23514';
    end if;
    if exists (select 1 from timesheet_entries e join timesheets t on t.id = e.timesheet_id
                where e.attendance_id = new.id and t.status in ('approved','locked'))
       and (new.check_in_at is distinct from old.check_in_at or new.check_out_at is distinct from old.check_out_at
            or new.payable_minutes is distinct from old.payable_minutes) then
      raise exception 'This attendance is on an approved timesheet' using errcode = '23514';
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists attendance_validate on attendance_records;
create trigger attendance_validate before insert or update on attendance_records
  for each row execute function omelo_private.omelo_validate_attendance();

-- R5-008: timesheet lifecycle and locked contents.
create or replace function omelo_private.omelo_validate_timesheet()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_correction boolean := coalesce(current_setting('omelo.correction', true), '') = 'on';
begin
  if tg_op = 'INSERT' then
    if new.status <> 'draft' then raise exception 'A timesheet starts as a draft' using errcode = '23514'; end if;
    new.person_id := (select person_id from assignments where id = new.assignment_id);
    new.company_id := (select company_id from assignments where id = new.assignment_id);
    return new;
  end if;
  if new.assignment_id is distinct from old.assignment_id or new.person_id is distinct from old.person_id
     or new.company_id is distinct from old.company_id or new.period_start is distinct from old.period_start
     or new.period_end is distinct from old.period_end then
    raise exception 'A timesheet''s worker and period are fixed' using errcode = '23514';
  end if;
  if new.status is distinct from old.status and not (
       (old.status = 'draft'        and new.status = 'submitted')
    or (old.status = 'submitted'    and new.status in ('under_review','approved','rejected','draft'))
    or (old.status = 'under_review' and new.status in ('approved','rejected'))
    or (old.status = 'rejected'     and new.status = 'draft')
    or (old.status = 'approved'     and new.status = 'locked')
    or (old.status in ('approved','locked') and new.status = 'under_review' and v_correction)) then
    raise exception 'A timesheet cannot go from % to %', old.status, new.status using errcode = '23514';
  end if;
  if old.status in ('approved','locked') and new.status = old.status and not v_correction
     and (new.total_minutes is distinct from old.total_minutes or new.overtime_minutes is distinct from old.overtime_minutes) then
    raise exception 'An approved timesheet changes only through an authorised correction' using errcode = '23514';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists timesheets_validate on timesheets;
create trigger timesheets_validate before insert or update on timesheets
  for each row execute function omelo_private.omelo_validate_timesheet();

create or replace function omelo_private.omelo_validate_timesheet_entry()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_status text; v_correction boolean := coalesce(current_setting('omelo.correction', true), '') = 'on';
begin
  select status into v_status from timesheets where id = coalesce(new.timesheet_id, old.timesheet_id);
  if v_status not in ('draft','rejected') and not v_correction then
    raise exception 'Only a draft timesheet can be edited (this one is %)', v_status using errcode = '23514';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
drop trigger if exists timesheet_entries_validate on timesheet_entries;
create trigger timesheet_entries_validate before insert or update or delete on timesheet_entries
  for each row execute function omelo_private.omelo_validate_timesheet_entry();

-- R5-009 / R5-010: earnings from approved work only; payments within approved pay.
create or replace function omelo_private.omelo_validate_earning()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_ts text;
begin
  if tg_op = 'INSERT' then
    select status into v_ts from timesheets where id = new.timesheet_id;
    if v_ts not in ('approved','locked') then
      raise exception 'Earnings come only from an approved timesheet' using errcode = '23514';
    end if;
    if new.status <> 'calculated' then raise exception 'Earnings start as calculated' using errcode = '23514'; end if;
    return new;
  end if;
  if new.timesheet_id is distinct from old.timesheet_id or new.person_id is distinct from old.person_id
     or new.assignment_id is distinct from old.assignment_id or new.currency is distinct from old.currency then
    raise exception 'Earnings belong to one timesheet and worker' using errcode = '23514';
  end if;
  if old.status not in ('calculated','reversed')
     and (new.base_amount, new.overtime_amount, new.allowance_amount, new.bonus_amount, new.deduction_amount, new.adjustment_amount)
         is distinct from (old.base_amount, old.overtime_amount, old.allowance_amount, old.bonus_amount, old.deduction_amount, old.adjustment_amount)
     and coalesce(current_setting('omelo.correction', true), '') <> 'on' then
    raise exception 'Approved earnings change only through an authorised adjustment' using errcode = '23514';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists earnings_validate on earnings;
create trigger earnings_validate before insert or update on earnings
  for each row execute function omelo_private.omelo_validate_earning();

create or replace function omelo_private.omelo_validate_payment()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare e earnings; v_committed numeric;
begin
  select * into e from earnings where id = new.earning_id;
  if tg_op = 'INSERT' then
    if e.status not in ('approved','scheduled','processing','paid','failed') then
      raise exception 'Only approved earnings can be paid' using errcode = '23514';
    end if;
    new.person_id := e.person_id;
    new.company_id := e.company_id;
    new.currency := e.currency;
  else
    if new.earning_id is distinct from old.earning_id or new.amount is distinct from old.amount
       or new.currency is distinct from old.currency then
      raise exception 'A payment''s earning, amount and currency are fixed' using errcode = '23514';
    end if;
    if new.status is distinct from old.status and not (
         (old.status = 'scheduled'  and new.status in ('processing','paid','failed'))
      or (old.status = 'processing' and new.status in ('paid','failed'))
      or (old.status = 'paid'       and new.status = 'reversed')) then
      raise exception 'A payment cannot go from % to %', old.status, new.status using errcode = '23514';
    end if;
  end if;
  select coalesce(sum(amount), 0) into v_committed from payment_records
   where earning_id = e.id and status in ('scheduled','processing','paid') and id <> new.id;
  if new.status in ('scheduled','processing','paid') and v_committed + new.amount > e.gross_amount then
    raise exception 'Payments cannot exceed the approved earnings (% of % already committed)', v_committed, e.gross_amount
      using errcode = '23514';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists payment_records_validate on payment_records;
create trigger payment_records_validate before insert or update on payment_records
  for each row execute function omelo_private.omelo_validate_payment();

-- 10. Row-level security ------------------------------------------------------------------
-- Who may see an assignment's operational records: the worker, the managing
-- company, and (for agency assignments) the confirmed client company.
create or replace function omelo_private.omelo_can_see_assignment(p_assignment uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select exists (
    select 1 from assignments a
     where a.id = p_assignment
       and (a.person_id = (select auth.uid())
            or omelo_private.omelo_workforce_can(a.company_id, 'view')
            or (a.client_company_id is not null and omelo_private.omelo_workforce_can(a.client_company_id, 'view'))));
$$;
grant execute on function omelo_private.omelo_can_see_assignment(uuid) to authenticated;

do $$
declare t text;
begin
  foreach t in array array['overtime_policies','workforce_requirements','assignments','assignment_billing','pay_components',
                           'shift_templates','shifts','shift_codes','shift_workers','attendance_records',
                           'attendance_exceptions','leave_requests','timesheets','timesheet_entries','earnings',
                           'earning_lines','payment_records','billing_records','workforce_events','workforce_jobs'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke insert, update, delete on public.%I from anon, authenticated', t);
  end loop;
end;
$$;

create policy overtime_policies_read on overtime_policies for select to authenticated
  using (omelo_private.omelo_workforce_can(company_id, 'view'));
create policy overtime_policies_write on overtime_policies for all to authenticated
  using (omelo_private.omelo_workforce_can(company_id, 'manage_pay'))
  with check (omelo_private.omelo_workforce_can(company_id, 'manage_pay'));
grant insert, update, delete on overtime_policies to authenticated;

create policy workforce_requirements_read on workforce_requirements for select to authenticated
  using (omelo_private.omelo_workforce_can(company_id, 'view'));

create policy assignments_read on assignments for select to authenticated
  using (person_id = (select auth.uid()) or omelo_private.omelo_workforce_can(company_id, 'view'));

create policy assignment_billing_read on assignment_billing for select to authenticated
  using (exists (select 1 from assignments a where a.id = assignment_id
                   and omelo_private.omelo_workforce_can(a.company_id, 'manage_pay')));

create policy pay_components_read on pay_components for select to authenticated
  using (exists (select 1 from workforce_requirements r where r.id = requirement_id
                   and omelo_private.omelo_workforce_can(r.company_id, 'view'))
      or exists (select 1 from assignments a where a.id = assignment_id
                   and (a.person_id = (select auth.uid()) or omelo_private.omelo_workforce_can(a.company_id, 'view'))));

create policy shift_templates_read on shift_templates for select to authenticated
  using (exists (select 1 from workforce_requirements r where r.id = requirement_id
                   and omelo_private.omelo_workforce_can(r.company_id, 'view')));

create policy shifts_read on shifts for select to authenticated
  using (omelo_private.omelo_workforce_can(company_id, 'view')
      or exists (select 1 from shift_workers w where w.shift_id = shifts.id and w.person_id = (select auth.uid()))
      or exists (select 1 from workforce_requirements r join agency_clients cl on cl.id = r.client_id
                  where r.id = requirement_id and cl.link_status = 'confirmed'
                    and omelo_private.omelo_workforce_can(cl.client_company_id, 'view')));

create policy shift_codes_read on shift_codes for select to authenticated
  using (exists (select 1 from shifts s where s.id = shift_id
                   and (omelo_private.omelo_workforce_can(s.company_id, 'approve_time')
                        or exists (select 1 from workforce_requirements r join agency_clients cl on cl.id = r.client_id
                                    where r.id = s.requirement_id and cl.link_status = 'confirmed'
                                      and omelo_private.omelo_workforce_can(cl.client_company_id, 'approve_time')))));

create policy shift_workers_read on shift_workers for select to authenticated
  using (person_id = (select auth.uid()) or omelo_private.omelo_can_see_assignment(assignment_id));
create policy attendance_records_read on attendance_records for select to authenticated
  using (person_id = (select auth.uid()) or omelo_private.omelo_can_see_assignment(assignment_id));
create policy attendance_exceptions_read on attendance_exceptions for select to authenticated
  using (exists (select 1 from attendance_records ar where ar.id = attendance_id
                   and (ar.person_id = (select auth.uid()) or omelo_private.omelo_can_see_assignment(ar.assignment_id))));
create policy leave_requests_read on leave_requests for select to authenticated
  using (person_id = (select auth.uid()) or omelo_private.omelo_can_see_assignment(assignment_id));
create policy timesheets_read on timesheets for select to authenticated
  using (person_id = (select auth.uid()) or omelo_private.omelo_can_see_assignment(assignment_id));
create policy timesheet_entries_read on timesheet_entries for select to authenticated
  using (exists (select 1 from timesheets t where t.id = timesheet_id
                   and (t.person_id = (select auth.uid()) or omelo_private.omelo_can_see_assignment(t.assignment_id))));

-- Pay: the worker and the paying company only — never the client company.
create policy earnings_read on earnings for select to authenticated
  using (person_id = (select auth.uid()) or omelo_private.omelo_workforce_can(company_id, 'manage_pay')
      or omelo_private.omelo_workforce_can(company_id, 'approve_time'));
create policy earning_lines_read on earning_lines for select to authenticated
  using (exists (select 1 from earnings e where e.id = earning_id
                   and (e.person_id = (select auth.uid()) or omelo_private.omelo_workforce_can(e.company_id, 'manage_pay')
                        or omelo_private.omelo_workforce_can(e.company_id, 'approve_time'))));
create policy payment_records_read on payment_records for select to authenticated
  using (person_id = (select auth.uid()) or omelo_private.omelo_workforce_can(company_id, 'manage_pay'));

-- Billing: the agency's pay team and the client company that is billed — never the worker.
create policy billing_records_read on billing_records for select to authenticated
  using (omelo_private.omelo_workforce_can(agency_id, 'manage_pay')
      or (client_company_id is not null and omelo_private.omelo_workforce_can(client_company_id, 'manage_pay')));

create policy workforce_events_read on workforce_events for select to authenticated
  using (person_id = (select auth.uid()) or omelo_private.omelo_workforce_can(company_id, 'view'));
create policy workforce_jobs_read on workforce_jobs for select to authenticated
  using (omelo_private.omelo_workforce_can(company_id, 'view'));
