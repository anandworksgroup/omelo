-- OMELO 64 — Release 7: Career intelligence + Employer intelligence — schema and reference data.
--
-- Reused (nothing duplicated):
--   career_goals (self-only)          + status, target date, updated_at
--   profession_skills                 what a profession needs (importance 0..1)
--   profession_transitions            from -> to professions (prior strength, typical months) — seeded here
--   person_skills.evidence_type       'assessment' becomes real evidence (only through a passed Omelo assessment)
--   matches / match_events / domain_events / applications / interviews / offers   (employer intelligence reads these)
--
-- New:
--   learning_resources           reference: how to build a skill (Omelo practice, assessment, on-the-job, official
--                                provider); read-only; https only; source + reviewed date
--   skill_assessments            Omelo-owned short assessments per skill (pass mark, attempt limits)
--   skill_assessment_questions   the questions; the answer key is NEVER readable by clients (R7-002)
--   skill_assessment_attempts    a worker's attempts (self-read only; written by functions only)
--   career_plan_items            the worker's development plan for a goal (skill, assessment, resource, job, licence)
--
-- Rollback: drop the new tables and columns; delete the seeded rows by slug.

-- 1. Career goals: lifecycle -----------------------------------------------------------------
alter table career_goals
  add column if not exists status text not null default 'active' check (status in ('active','achieved','archived')),
  add column if not exists target_date date,
  add column if not exists updated_at timestamptz not null default now();

-- 2. Taxonomy for the worked example (electrician -> industrial electrician) ---------------------
insert into skills (slug, name, type, description) values
  ('plc-programming', 'PLC programming', 'technical', 'Reading, writing and troubleshooting programmable logic controller programs (ladder logic).'),
  ('motor-controls', 'Motor controls', 'technical', 'Starters, contactors, overloads, VFDs and control circuits for electric motors.'),
  ('industrial-safety', 'Industrial safety', 'safety', 'Lockout/tagout, arc-flash awareness and safe work in plants and factories.'),
  ('preventive-maintenance', 'Preventive maintenance', 'method', 'Planned inspection and servicing of machines to prevent breakdowns.'),
  ('team-leadership', 'Team leadership', 'soft', 'Planning a team''s work, briefing, and handling issues on shift.')
on conflict (slug) do nothing;

insert into professions (category_id, slug, name, description, requires_license)
select p.category_id, 'industrial-electrician', 'Industrial Electrician',
       'Installs, maintains and troubleshoots electrical systems, motors and controls in plants and factories.', true
  from professions p where p.slug = 'electrician'
on conflict (slug) do nothing;

insert into profession_skills (profession_id, skill_id, importance, source)
select p.id, s.id, v.imp, 'admin'
  from (values
    ('industrial-electrician','electrical-wiring',1.0), ('industrial-electrician','plc-programming',0.9),
    ('industrial-electrician','motor-controls',0.9), ('industrial-electrician','industrial-safety',0.9),
    ('industrial-electrician','blueprint-reading',0.7), ('industrial-electrician','preventive-maintenance',0.6),
    ('maintenance-technician','preventive-maintenance',1.0), ('maintenance-technician','motor-controls',0.7),
    ('maintenance-technician','industrial-safety',0.8), ('maintenance-technician','hand-tools',0.8),
    ('maintenance-technician','power-tools',0.7),
    ('warehouse-supervisor','team-leadership',0.9)) v(prof, skill, imp)
  join professions p on p.slug = v.prof
  join skills s on s.slug = v.skill
on conflict (profession_id, skill_id) do nothing;

-- Typical next steps. prior_strength is an editorial prior (0..1), replaced by observed transitions
-- (observed_count / median_months) as Omelo records real careers.
insert into profession_transitions (from_profession_id, to_profession_id, prior_strength, median_months)
select f.id, t.id, v.strength, v.months
  from (values
    ('electrician','industrial-electrician',0.8,24), ('electrician','maintenance-technician',0.6,18),
    ('electrician','site-supervisor',0.4,48), ('electrician','electrical-engineer',0.2,60),
    ('maintenance-technician','industrial-electrician',0.5,24),
    ('warehouse-worker','warehouse-supervisor',0.6,24), ('warehouse-worker','truck-driver',0.3,12),
    ('cook','chef',0.7,36), ('driver','truck-driver',0.6,12), ('driver','bus-driver',0.5,12),
    ('security-guard','security-supervisor',0.6,24)) v(f_slug, t_slug, strength, months)
  join professions f on f.slug = v.f_slug
  join professions t on t.slug = v.t_slug
on conflict (from_profession_id, to_profession_id) do nothing;

-- 3. Learning resources (reference) ---------------------------------------------------------------
create table if not exists public.learning_resources (
  id              uuid primary key default gen_random_uuid(),
  skill_id        uuid not null references skills(id) on delete cascade,
  kind            text not null check (kind in ('omelo_assessment','practice','on_the_job','course','certification','official_guidance')),
  title           text not null check (length(trim(title)) between 3 and 200),
  description     text check (description is null or length(description) <= 1000),
  provider        text not null,
  url             text check (url is null or url ~ '^https://'),
  cost            text not null default 'free' check (cost in ('free','paid','employer_sponsored','varies')),
  duration_hours  numeric check (duration_hours is null or duration_hours > 0),
  country_codes   char(2)[] not null default '{}',
  language_code   text,
  source          text not null,
  reviewed_at     date not null,
  active          boolean not null default true,
  unique (skill_id, kind, title)
);
alter table learning_resources enable row level security;
drop policy if exists learning_resources_read on learning_resources;
create policy learning_resources_read on learning_resources for select to anon, authenticated using (active);
revoke insert, update, delete on learning_resources from anon, authenticated;

-- 4. Omelo skill assessments -----------------------------------------------------------------------
create table if not exists public.skill_assessments (
  id                   uuid primary key default gen_random_uuid(),
  skill_id             uuid not null unique references skills(id) on delete cascade,
  title                text not null,
  questions_per_attempt smallint not null default 5 check (questions_per_attempt between 3 and 30),
  pass_percent         smallint not null default 70 check (pass_percent between 50 and 100),
  time_limit_minutes   smallint not null default 20 check (time_limit_minutes between 5 and 120),
  cooldown_hours       smallint not null default 24 check (cooldown_hours between 1 and 720),
  proficiency_on_pass  proficiency_level not null default 'intermediate',
  active               boolean not null default true,
  created_at           timestamptz not null default now()
);
create table if not exists public.skill_assessment_questions (
  id             uuid primary key default gen_random_uuid(),
  assessment_id  uuid not null references skill_assessments(id) on delete cascade,
  prompt         text not null check (length(trim(prompt)) between 10 and 1000),
  options        jsonb not null check (jsonb_typeof(options) = 'array' and jsonb_array_length(options) between 2 and 6),
  answer_index   smallint not null,
  explanation    text,
  active         boolean not null default true,
  unique (assessment_id, prompt),
  check (answer_index >= 0 and answer_index < jsonb_array_length(options))
);
create table if not exists public.skill_assessment_attempts (
  id             uuid primary key default gen_random_uuid(),
  assessment_id  uuid not null references skill_assessments(id) on delete cascade,
  person_id      uuid not null references persons(id) on delete cascade,
  work_identity_id uuid references work_identities(id) on delete cascade,
  question_ids   uuid[] not null,
  answers        smallint[],
  status         text not null default 'in_progress' check (status in ('in_progress','passed','failed','expired')),
  score_percent  smallint check (score_percent between 0 and 100),
  started_at     timestamptz not null default now(),
  expires_at     timestamptz not null,
  completed_at   timestamptz
);
create index if not exists skill_assessment_attempts_person on skill_assessment_attempts (person_id, assessment_id, started_at desc);
create unique index if not exists skill_assessment_attempts_one_open on skill_assessment_attempts (person_id, assessment_id)
  where status = 'in_progress';

alter table skill_assessments enable row level security;
alter table skill_assessment_questions enable row level security;
alter table skill_assessment_attempts enable row level security;
drop policy if exists skill_assessments_read on skill_assessments;
create policy skill_assessments_read on skill_assessments for select to anon, authenticated using (active);
-- questions: no client policy at all (served without answers by omelo_start_skill_assessment)
revoke all on skill_assessment_questions from anon, authenticated;
drop policy if exists skill_assessment_attempts_self on skill_assessment_attempts;
create policy skill_assessment_attempts_self on skill_assessment_attempts for select to authenticated
  using (person_id = (select auth.uid()));
revoke insert, update, delete on skill_assessments, skill_assessment_attempts from anon, authenticated;

-- 5. Career plan -----------------------------------------------------------------------------------
create table if not exists public.career_plan_items (
  id            uuid primary key default gen_random_uuid(),
  person_id     uuid not null references persons(id) on delete cascade,
  goal_id       uuid not null references career_goals(id) on delete cascade,
  kind          text not null check (kind in ('skill','assessment','resource','project','job','licence','custom')),
  skill_id      uuid references skills(id) on delete set null,
  resource_id   uuid references learning_resources(id) on delete set null,
  job_id        uuid references jobs(id) on delete set null,
  title         text not null check (length(trim(title)) between 2 and 200),
  status        text not null default 'todo' check (status in ('todo','in_progress','done','dismissed')),
  due_on        date,
  position      smallint not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists career_plan_items_goal on career_plan_items (goal_id, position);
alter table career_plan_items enable row level security;
drop policy if exists career_plan_items_self on career_plan_items;
create policy career_plan_items_self on career_plan_items for all to authenticated
  using (person_id = (select auth.uid())) with check (person_id = (select auth.uid()));

create or replace function omelo_private.omelo_validate_plan_item()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if not exists (select 1 from career_goals g where g.id = new.goal_id and g.person_id = new.person_id) then
    raise exception 'A plan item belongs to one of your own goals' using errcode = '42501';
  end if;
  if new.kind in ('skill','assessment') and new.skill_id is null then
    raise exception 'Choose the skill for this step' using errcode = '22023';
  end if;
  if new.kind = 'resource' and new.resource_id is null then
    raise exception 'Choose the resource for this step' using errcode = '22023';
  end if;
  if new.kind = 'job' and (new.job_id is null
       or not exists (select 1 from jobs where id = new.job_id and status = 'published')) then
    raise exception 'Choose an open job for this step' using errcode = '22023';
  end if;
  if tg_op = 'UPDATE' and (new.person_id is distinct from old.person_id or new.goal_id is distinct from old.goal_id) then
    raise exception 'A plan item cannot move to another goal' using errcode = '42501';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists career_plan_items_validate on career_plan_items;
create trigger career_plan_items_validate before insert or update on career_plan_items
  for each row execute function omelo_private.omelo_validate_plan_item();

create or replace function omelo_private.omelo_validate_career_goal()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if new.work_identity_id is not null
     and not exists (select 1 from work_identities where id = new.work_identity_id and person_id = new.person_id) then
    raise exception 'That work identity is not yours' using errcode = '42501';
  end if;
  if new.profession_id is null and nullif(trim(coalesce(new.goal_text, '')), '') is null then
    raise exception 'Choose a target role or describe the goal' using errcode = '22023';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists career_goals_validate on career_goals;
create trigger career_goals_validate before insert or update on career_goals
  for each row execute function omelo_private.omelo_validate_career_goal();

-- 6. Seed: assessments + questions + resources for the example skills ------------------------------
insert into skill_assessments (skill_id, title, questions_per_attempt, pass_percent)
select s.id, v.title, 5, 70
  from (values ('plc-programming','PLC programming basics'), ('motor-controls','Motor control fundamentals'),
               ('industrial-safety','Industrial safety essentials')) v(slug, title)
  join skills s on s.slug = v.slug
on conflict (skill_id) do nothing;

insert into skill_assessment_questions (assessment_id, prompt, options, answer_index, explanation)
select a.id, v.prompt, v.options::jsonb, v.ans, v.expl
  from (values
    ('plc-programming','In ladder logic, what does a normally open (NO) contact do when its input bit is ON (1)?',
     '["It blocks power flow","It passes power flow","It resets the output","It inverts the output"]',1,'An examined-if-closed (XIC / NO) contact is true when its bit is 1.'),
    ('plc-programming','What is the typical order of a PLC scan cycle?',
     '["Execute program, read inputs, write outputs","Read inputs, execute program, write outputs","Write outputs, read inputs, execute program","Read inputs, write outputs, execute program"]',1,'Input scan, program scan, output update.'),
    ('plc-programming','Which instruction keeps an output ON after the start button is released, until it is reset?',
     '["A normally closed contact","A latch (set) coil or a seal-in contact","A timer done bit only","A counter preset"]',1,'Latch/set coils or a seal-in branch hold the output.'),
    ('plc-programming','A TON (timer on-delay) done bit turns ON when…',
     '["the rung goes false","the accumulated time reaches the preset while the rung stays true","the PLC powers up","the preset is zero"]',1,'TON times while its rung is true and sets DN at the preset.'),
    ('plc-programming','Why are stop buttons usually wired as normally closed (NC) devices?',
     '["They are cheaper","A broken wire then stops the machine (fail-safe)","The PLC cannot read NO contacts","To save input points"]',1,'Fail-safe: a cut wire reads as stop.'),
    ('plc-programming','What is a PLC''s analogue input typically used for?',
     '["Push buttons","Continuous values such as 4–20 mA pressure or temperature signals","Relay outputs","Network addresses"]',1,'Analogue inputs read ranges such as 4–20 mA or 0–10 V.'),
    ('motor-controls','What does a thermal overload relay protect a motor against?',
     '["Short circuits only","Sustained over-current that overheats the windings","Over-voltage spikes","Reverse rotation"]',1,'Overloads trip on sustained current above the motor rating.'),
    ('motor-controls','In a three-wire start/stop circuit, what keeps the contactor energised after START is released?',
     '["The overload contact","An auxiliary (holding) contact of the contactor in parallel with START","The stop button","The motor''s back-EMF"]',1,'The seal-in auxiliary contact.'),
    ('motor-controls','How do you reverse the direction of a three-phase induction motor?',
     '["Swap any two of the three supply phases","Reverse the neutral","Lower the frequency","Swap the earth and a phase"]',0,'Swapping two phases reverses the rotating field.'),
    ('motor-controls','What does a variable frequency drive (VFD) mainly control?',
     '["Motor speed, by varying supply frequency and voltage","Only the starting current","The motor insulation class","Power factor of the building"]',0,'A VFD varies frequency (and voltage) to set speed.'),
    ('motor-controls','Why is a star-delta starter used on larger motors?',
     '["To increase starting torque","To reduce starting current","To reverse the motor","To brake the motor"]',1,'Starting in star lowers the voltage per winding and the inrush current.'),
    ('motor-controls','Interlocking the forward and reverse contactors prevents…',
     '["Both contactors closing together and causing a phase-to-phase short","The motor overheating","The overload tripping","Low voltage"]',0,'Electrical/mechanical interlocks stop both closing at once.'),
    ('industrial-safety','What is the purpose of lockout/tagout (LOTO)?',
     '["To speed up maintenance","To keep equipment from being energised or started while someone works on it","To record machine hours","To test fuses"]',1,'LOTO isolates and secures energy sources.'),
    ('industrial-safety','After applying your lock to an isolator, what should you do before starting work?',
     '["Start work immediately","Verify zero energy (try the start / test for absence of voltage)","Remove the tag","Tell the operator to restart"]',1,'Always verify the isolation.'),
    ('industrial-safety','Who may remove a personal safety lock?',
     '["Any supervisor","The person who applied it (or a formal, documented procedure if they are absent)","The machine operator","Anyone with a key"]',1,'Personal locks are removed by their owner.'),
    ('industrial-safety','An arc flash is best described as…',
     '["A slow leak of current to earth","A sudden release of energy from an electric arc causing extreme heat and light","A tripped breaker","Static discharge"]',1,'Arc flash is an explosive release of energy.'),
    ('industrial-safety','Which should be checked before using a voltage tester to prove a circuit is dead?',
     '["That it works on a known live source (prove–test–prove)","Its colour","Its battery brand","Nothing"]',0,'Prove the tester before and after.'),
    ('industrial-safety','Stored energy that still needs controlling after switching off can include…',
     '["Only electricity","Springs, pressure, gravity, capacitors and heat","Nothing — off means safe","Only compressed air"]',1,'All stored energy must be released or restrained.')
  ) v(slug, prompt, options, ans, expl)
  join skills s on s.slug = v.slug
  join skill_assessments a on a.skill_id = s.id
on conflict (assessment_id, prompt) do nothing;

insert into learning_resources (skill_id, kind, title, description, provider, cost, duration_hours, source, reviewed_at)
select s.id, v.kind, v.title, v.descr, v.provider, v.cost, v.hours, 'Omelo', date '2026-09-19'
  from (values
    ('plc-programming','omelo_assessment','PLC programming basics — Omelo assessment','Five questions; pass to add assessed evidence to the skill.','Omelo','free',0.5),
    ('plc-programming','on_the_job','Shadow a controls technician on PLC fault-finding','Ask your employer or site lead to pair you on PLC diagnostics for a few shifts.','Your employer','employer_sponsored',16),
    ('plc-programming','course','Vendor or ITI course in PLC programming','Look for a course that includes hands-on ladder-logic practice on real hardware or a simulator.','Training provider','varies',40),
    ('motor-controls','omelo_assessment','Motor control fundamentals — Omelo assessment','Five questions; pass to add assessed evidence to the skill.','Omelo','free',0.5),
    ('motor-controls','practice','Wire and test a DOL and a forward/reverse starter','Build both circuits on a training board under supervision; document with photos as a project.','Self-directed','free',6),
    ('industrial-safety','omelo_assessment','Industrial safety essentials — Omelo assessment','Five questions; pass to add assessed evidence to the skill.','Omelo','free',0.5),
    ('industrial-safety','certification','Site safety induction / LOTO certification','Many plants require their own induction and lockout/tagout certification before work.','Employer or safety body','varies',8),
    ('preventive-maintenance','on_the_job','Join a planned-maintenance round','Follow a preventive-maintenance checklist with a senior technician and log the results.','Your employer','employer_sponsored',8),
    ('team-leadership','on_the_job','Lead a shift handover','Ask to run the briefing and handover for your team for a week.','Your employer','free',5)
  ) v(slug, kind, title, descr, provider, cost, hours)
  join skills s on s.slug = v.slug
on conflict (skill_id, kind, title) do nothing;
