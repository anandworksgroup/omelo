-- OMELO 70 — Release 8: approval workflows.
--
-- An organization describes its own chain; Omelo hard-codes nobody's process:
--
--   Hiring manager → create job → [Department approval] → [Finance] → [HR] → recruiter publishes
--
--   approval_workflows   one active chain per organization and entity type (job, workforce
--                        requirement, offer)
--   approval_steps       ordered steps: which role approves, at which scope, how many approvals
--   approval_requests    one open request per entity; position walks the steps
--   approval_decisions   every decision, append-only audit
--
-- Rules (R8-003, R8-004):
--   * only a member whose role AND scope cover the entity may decide a step (the R8 scope helper)
--   * nobody approves their own request
--   * while an active workflow exists for jobs, a job cannot be published without an approved
--     request — enforced by a trigger, so it holds for every writer, service role included
--   * requests and decisions are written only by the functions below
--
-- Rollback: drop the tables, the two triggers and the functions.

create table if not exists public.approval_workflows (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references companies(id) on delete cascade,
  entity_type  text not null check (entity_type in ('job','workforce_requirement','offer')),
  name         text not null check (length(trim(name)) between 2 and 120),
  is_active    boolean not null default true,
  created_by   uuid references persons(id) on delete set null,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (company_id, entity_type, name)
);
create unique index if not exists approval_workflows_one_active
  on approval_workflows (company_id, entity_type) where is_active;

create table if not exists public.approval_steps (
  id                 uuid primary key default gen_random_uuid(),
  workflow_id        uuid not null references approval_workflows(id) on delete cascade,
  position           smallint not null check (position between 1 and 20),
  name               text not null check (length(trim(name)) between 2 and 80),
  approver_role      company_role not null,
  approver_scope     text not null default 'organization'
                     check (approver_scope in ('organization','business_unit','department','location','legal_entity')),
  required_approvals smallint not null default 1 check (required_approvals between 1 and 5),
  unique (workflow_id, position)
);

create table if not exists public.approval_requests (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references companies(id) on delete cascade,
  workflow_id   uuid not null references approval_workflows(id) on delete cascade,
  entity_type   text not null check (entity_type in ('job','workforce_requirement','offer')),
  entity_id     uuid not null,
  status        text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  position      smallint not null default 1,
  note          text check (note is null or length(note) <= 1000),
  requested_by  uuid not null references persons(id) on delete cascade,
  requested_at  timestamptz not null default now(),
  decided_at    timestamptz
);
create unique index if not exists approval_requests_one_open
  on approval_requests (entity_type, entity_id) where status = 'pending';
create index if not exists approval_requests_entity on approval_requests (entity_type, entity_id, status);
create index if not exists approval_requests_company on approval_requests (company_id, status);

create table if not exists public.approval_decisions (
  id           uuid primary key default gen_random_uuid(),
  request_id   uuid not null references approval_requests(id) on delete cascade,
  position     smallint not null,
  step_id      uuid references approval_steps(id) on delete set null,
  decided_by   uuid not null references persons(id) on delete cascade,
  decision     text not null check (decision in ('approved','rejected')),
  note         text check (note is null or length(note) <= 1000),
  decided_at   timestamptz not null default now(),
  unique (request_id, position, decided_by)
);

alter table approval_workflows enable row level security;
alter table approval_steps enable row level security;
alter table approval_requests enable row level security;
alter table approval_decisions enable row level security;

drop policy if exists approval_workflows_read on approval_workflows;
drop policy if exists approval_workflows_write on approval_workflows;
create policy approval_workflows_read on approval_workflows for select to authenticated
  using (omelo_private.omelo_is_company_member(company_id));
create policy approval_workflows_write on approval_workflows for all to authenticated
  using (omelo_private.omelo_has_company_role(company_id, array['owner','admin']::company_role[]))
  with check (omelo_private.omelo_has_company_role(company_id, array['owner','admin']::company_role[]));

drop policy if exists approval_steps_read on approval_steps;
drop policy if exists approval_steps_write on approval_steps;
create policy approval_steps_read on approval_steps for select to authenticated
  using (exists (select 1 from approval_workflows w where w.id = workflow_id and omelo_private.omelo_is_company_member(w.company_id)));
create policy approval_steps_write on approval_steps for all to authenticated
  using (exists (select 1 from approval_workflows w where w.id = workflow_id
                  and omelo_private.omelo_has_company_role(w.company_id, array['owner','admin']::company_role[])))
  with check (exists (select 1 from approval_workflows w where w.id = workflow_id
                  and omelo_private.omelo_has_company_role(w.company_id, array['owner','admin']::company_role[])));

-- Requests and decisions: read by the organization, written only by the functions below.
drop policy if exists approval_requests_read on approval_requests;
create policy approval_requests_read on approval_requests for select to authenticated
  using (omelo_private.omelo_is_company_member(company_id));
revoke insert, update, delete on approval_requests from anon, authenticated;

drop policy if exists approval_decisions_read on approval_decisions;
create policy approval_decisions_read on approval_decisions for select to authenticated
  using (exists (select 1 from approval_requests r where r.id = request_id and omelo_private.omelo_is_company_member(r.company_id)));
revoke insert, update, delete on approval_decisions from anon, authenticated;

-- Where does the entity sit in the organization? (for the step's scope)
create or replace function omelo_private.omelo_entity_scope(p_entity_type text, p_entity_id uuid)
returns table (company_id uuid, department_id uuid, company_location_id uuid, legal_entity_id uuid)
language sql stable security definer
set search_path = public, omelo_private
as $$
  select j.company_id, j.department_id, j.company_location_id, j.legal_entity_id
    from jobs j where p_entity_type = 'job' and j.id = p_entity_id
  union all
  select r.company_id, null::uuid, null::uuid, null::uuid
    from workforce_requirements r where p_entity_type = 'workforce_requirement' and r.id = p_entity_id
  union all
  select o.company_id, j.department_id, j.company_location_id, j.legal_entity_id
    from offers o join jobs j on j.id = o.job_id where p_entity_type = 'offer' and o.id = p_entity_id;
$$;

-- Who to tell: active members holding that role (by their own role or by a grant).
create or replace function omelo_private.omelo_notify_role(p_company uuid, p_role company_role, p_type text,
                                                           p_title text, p_body text, p_entity text, p_id uuid, p_link text)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare m record;
begin
  for m in select distinct cm.person_id from company_members cm
            where cm.company_id = p_company and cm.is_active
              and (cm.role = p_role
                   or exists (select 1 from company_role_grants g
                               where g.company_id = p_company and g.person_id = cm.person_id and g.role = p_role)) loop
    perform omelo_private.omelo_notify(m.person_id, p_type::notification_type, p_title, p_body, p_entity, p_id, p_link);
  end loop;
end;
$$;

create or replace function public.omelo_save_approval_workflow(p jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_company uuid := nullif(p->>'company_id', '')::uuid; w approval_workflows; s jsonb; v_pos int := 0;
begin
  if not omelo_private.omelo_has_company_role(v_company, array['owner','admin']::company_role[]) then
    raise exception 'Only an owner or admin sets approval workflows' using errcode = '42501';
  end if;
  if jsonb_typeof(p->'steps') <> 'array' or jsonb_array_length(p->'steps') = 0 then
    raise exception 'An approval workflow needs at least one step' using errcode = '22023';
  end if;
  if nullif(p->>'id', '') is not null then
    update approval_workflows set name = coalesce(nullif(trim(p->>'name'), ''), name),
           is_active = coalesce((p->>'is_active')::boolean, is_active), updated_at = now()
     where id = (p->>'id')::uuid and company_id = v_company returning * into w;
    if w.id is null then raise exception 'Workflow not found' using errcode = '22023'; end if;
    delete from approval_steps where workflow_id = w.id;
  else
    insert into approval_workflows (company_id, entity_type, name, is_active, created_by)
    values (v_company, coalesce(nullif(p->>'entity_type', ''), 'job'), coalesce(nullif(trim(p->>'name'), ''), 'Approval'),
            coalesce((p->>'is_active')::boolean, true), auth.uid())
    returning * into w;
  end if;
  for s in select x from jsonb_array_elements(p->'steps') x loop
    v_pos := v_pos + 1;
    insert into approval_steps (workflow_id, position, name, approver_role, approver_scope, required_approvals)
    values (w.id, v_pos, coalesce(nullif(trim(s->>'name'), ''), 'Step ' || v_pos),
            (s->>'approver_role')::company_role,
            coalesce(nullif(s->>'approver_scope', ''), 'organization'),
            coalesce((s->>'required_approvals')::smallint, 1));
  end loop;
  perform omelo_private.omelo_emit('ApprovalWorkflowSaved', 'company', v_company, v_company, auth.uid(),
                                   jsonb_build_object('workflow_id', w.id, 'entity_type', w.entity_type));
  return to_jsonb(w);
exception
  when check_violation or invalid_text_representation or not_null_violation then
    raise exception 'Check the workflow steps: %', sqlerrm using errcode = '22023';
end;
$$;

create or replace function public.omelo_submit_for_approval(p_entity_type text, p_entity_id uuid, p_note text default null)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare e record; w approval_workflows; r approval_requests; st approval_steps;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  select * into e from omelo_private.omelo_entity_scope(p_entity_type, p_entity_id);
  if e.company_id is null then raise exception 'Not found' using errcode = '22023'; end if;
  if not omelo_private.omelo_scope_covers(e.company_id, auth.uid(),
        array['owner','admin','recruiter','hiring_manager','hr']::company_role[],
        e.department_id, e.company_location_id, e.legal_entity_id) then
    raise exception 'You cannot submit this for approval' using errcode = '42501';
  end if;
  select * into w from approval_workflows where company_id = e.company_id and entity_type = p_entity_type and is_active;
  if w.id is null then raise exception 'This organization has no approval workflow for %', p_entity_type using errcode = '22023'; end if;
  if exists (select 1 from approval_requests where entity_type = p_entity_type and entity_id = p_entity_id and status = 'pending') then
    raise exception 'This is already waiting for approval' using errcode = '22023';
  end if;
  insert into approval_requests (company_id, workflow_id, entity_type, entity_id, requested_by, note)
  values (e.company_id, w.id, p_entity_type, p_entity_id, auth.uid(), nullif(trim(p_note), ''))
  returning * into r;
  select * into st from approval_steps where workflow_id = w.id and position = 1;
  perform omelo_private.omelo_notify_role(e.company_id, st.approver_role, 'approval_request',
            'Approval needed', st.name || ' — ' || p_entity_type || ' waiting for your approval',
            'approval_request', r.id, '/dashboard/approvals');
  perform omelo_private.omelo_emit('ApprovalRequested', 'approval_request', r.id, e.company_id, auth.uid(),
                                   jsonb_build_object('entity_type', p_entity_type, 'entity_id', p_entity_id, 'workflow_id', w.id));
  return to_jsonb(r);
end;
$$;

create or replace function public.omelo_decide_approval(p_request uuid, p_approve boolean, p_note text default null)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare r approval_requests; st approval_steps; e record; v_done int; v_next approval_steps;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  select * into r from approval_requests where id = p_request for update;
  if r.id is null then raise exception 'Request not found' using errcode = '22023'; end if;
  if r.status <> 'pending' then raise exception 'This request is already %', r.status using errcode = '22023'; end if;
  if r.requested_by = auth.uid() then
    raise exception 'You cannot approve your own request' using errcode = '42501';
  end if;
  select * into st from approval_steps where workflow_id = r.workflow_id and position = r.position;
  if st.id is null then raise exception 'That approval step no longer exists' using errcode = '22023'; end if;
  select * into e from omelo_private.omelo_entity_scope(r.entity_type, r.entity_id);
  if not omelo_private.omelo_scope_covers(r.company_id, auth.uid(), array[st.approver_role]::company_role[],
                                          e.department_id, e.company_location_id, e.legal_entity_id) then
    raise exception 'This step is approved by % for that part of the organization', st.approver_role using errcode = '42501';
  end if;
  insert into approval_decisions (request_id, position, step_id, decided_by, decision, note)
  values (r.id, r.position, st.id, auth.uid(), case when p_approve then 'approved' else 'rejected' end, nullif(trim(p_note), ''));

  if not p_approve then
    update approval_requests set status = 'rejected', decided_at = now() where id = r.id returning * into r;
  else
    select count(*) into v_done from approval_decisions
     where request_id = r.id and position = r.position and decision = 'approved';
    if v_done >= st.required_approvals then
      select * into v_next from approval_steps where workflow_id = r.workflow_id and position = r.position + 1;
      if v_next.id is null then
        update approval_requests set status = 'approved', decided_at = now() where id = r.id returning * into r;
      else
        update approval_requests set position = v_next.position where id = r.id returning * into r;
        perform omelo_private.omelo_notify_role(r.company_id, v_next.approver_role, 'approval_request',
                  'Approval needed', v_next.name || ' — ' || r.entity_type || ' waiting for your approval',
                  'approval_request', r.id, '/dashboard/approvals');
      end if;
    end if;
  end if;
  perform omelo_private.omelo_notify(r.requested_by, 'approval_update'::notification_type,
            case r.status when 'approved' then 'Approved' when 'rejected' then 'Not approved' else 'Approval moved on' end,
            st.name || ': ' || case when p_approve then 'approved' else 'not approved' end,
            'approval_request', r.id, '/dashboard/approvals');
  perform omelo_private.omelo_emit(case when p_approve then 'ApprovalStepApproved' else 'ApprovalRejected' end,
                                   'approval_request', r.id, r.company_id, auth.uid(),
                                   jsonb_build_object('position', st.position, 'status', r.status));
  return to_jsonb(r);
end;
$$;

create or replace function public.omelo_cancel_approval(p_request uuid, p_note text default null)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare r approval_requests;
begin
  select * into r from approval_requests where id = p_request for update;
  if r.id is null then raise exception 'Request not found' using errcode = '22023'; end if;
  if r.status <> 'pending' then raise exception 'This request is already %', r.status using errcode = '22023'; end if;
  if r.requested_by <> auth.uid()
     and not omelo_private.omelo_has_company_role(r.company_id, array['owner','admin']::company_role[]) then
    raise exception 'Only the person who asked, or an owner or admin, can withdraw it' using errcode = '42501';
  end if;
  update approval_requests set status = 'cancelled', decided_at = now(), note = coalesce(nullif(trim(p_note), ''), note)
   where id = r.id returning * into r;
  perform omelo_private.omelo_emit('ApprovalCancelled', 'approval_request', r.id, r.company_id, auth.uid(), '{}'::jsonb);
  return to_jsonb(r);
end;
$$;

create or replace function public.omelo_my_approvals(p_company uuid default null)
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'request_id', r.id, 'company_id', r.company_id, 'entity_type', r.entity_type, 'entity_id', r.entity_id,
           'step', st.name, 'position', r.position, 'role', st.approver_role, 'requested_at', r.requested_at,
           'requested_by_me', r.requested_by = auth.uid(), 'note', r.note,
           'title', case r.entity_type when 'job' then (select j.title from jobs j where j.id = r.entity_id)
                                       when 'offer' then (select j.title from offers o join jobs j on j.id = o.job_id where o.id = r.entity_id)
                                       else (select rq.title from workforce_requirements rq where rq.id = r.entity_id) end)
           order by r.requested_at), '[]'::jsonb)
    from approval_requests r
    join approval_steps st on st.workflow_id = r.workflow_id and st.position = r.position
    left join lateral omelo_private.omelo_entity_scope(r.entity_type, r.entity_id) e on true
   where r.status = 'pending' and (p_company is null or r.company_id = p_company)
     and r.requested_by <> auth.uid()
     and omelo_private.omelo_scope_covers(r.company_id, auth.uid(), array[st.approver_role]::company_role[],
                                          e.department_id, e.company_location_id, e.legal_entity_id);
$$;

create or replace function public.omelo_approval_status(p_entity_type text, p_entity_id uuid)
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select jsonb_build_object(
    'required', exists (select 1 from approval_workflows w
                         join omelo_private.omelo_entity_scope(p_entity_type, p_entity_id) e on e.company_id = w.company_id
                        where w.entity_type = p_entity_type and w.is_active),
    'request', (select jsonb_build_object('id', r.id, 'status', r.status, 'position', r.position,
                                          'requested_at', r.requested_at, 'decided_at', r.decided_at,
                                          'steps', (select jsonb_agg(jsonb_build_object('position', s.position, 'name', s.name,
                                                                                        'role', s.approver_role,
                                                                                        'required', s.required_approvals,
                                                                                        'approvals', (select count(*) from approval_decisions d
                                                                                                       where d.request_id = r.id and d.position = s.position
                                                                                                         and d.decision = 'approved'))
                                                             order by s.position)
                                                     from approval_steps s where s.workflow_id = r.workflow_id),
                                          'decisions', (select coalesce(jsonb_agg(jsonb_build_object('position', d.position,
                                                                                                    'decision', d.decision,
                                                                                                    'note', d.note,
                                                                                                    'at', d.decided_at) order by d.decided_at), '[]'::jsonb)
                                                          from approval_decisions d where d.request_id = r.id))
                  from approval_requests r
                 where r.entity_type = p_entity_type and r.entity_id = p_entity_id
                 order by r.requested_at desc limit 1))
  where exists (select 1 from omelo_private.omelo_entity_scope(p_entity_type, p_entity_id) e
                 where omelo_private.omelo_is_company_member(e.company_id));
$$;

-- R8-004: with an active workflow, publishing needs an approved request. Enforced for every writer.
create or replace function omelo_private.omelo_validate_approval_gate()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_entity text; v_company uuid; v_now text; v_before text;
begin
  if tg_table_name = 'jobs' then
    v_entity := 'job'; v_company := new.company_id; v_now := new.status::text;
    v_before := case when tg_op = 'UPDATE' then old.status::text end;
    if v_now <> 'published' or v_before = 'published' then return new; end if;
  else
    v_entity := 'workforce_requirement'; v_company := new.company_id; v_now := new.status;
    v_before := case when tg_op = 'UPDATE' then old.status end;
    if v_now <> 'open' or v_before = 'open' then return new; end if;
  end if;
  if exists (select 1 from approval_workflows w where w.company_id = v_company and w.entity_type = v_entity and w.is_active)
     and not exists (select 1 from approval_requests r
                      where r.entity_type = v_entity and r.entity_id = new.id and r.status = 'approved') then
    raise exception 'This organization approves % before it goes live — submit it for approval first', v_entity
      using errcode = '42501';
  end if;
  return new;
end;
$$;
drop trigger if exists jobs_approval_gate on jobs;
create trigger jobs_approval_gate before insert or update on jobs
  for each row execute function omelo_private.omelo_validate_approval_gate();
drop trigger if exists workforce_requirements_approval_gate on workforce_requirements;
create trigger workforce_requirements_approval_gate before insert or update on workforce_requirements
  for each row execute function omelo_private.omelo_validate_approval_gate();

revoke all on function omelo_private.omelo_entity_scope(text, uuid) from public, anon, authenticated;
revoke all on function omelo_private.omelo_notify_role(uuid, company_role, text, text, text, text, uuid, text) from public, anon, authenticated;
revoke all on function public.omelo_save_approval_workflow(jsonb) from public, anon;
revoke all on function public.omelo_submit_for_approval(text, uuid, text) from public, anon;
revoke all on function public.omelo_decide_approval(uuid, boolean, text) from public, anon;
revoke all on function public.omelo_cancel_approval(uuid, text) from public, anon;
revoke all on function public.omelo_my_approvals(uuid) from public, anon;
revoke all on function public.omelo_approval_status(text, uuid) from public, anon;
grant execute on function public.omelo_save_approval_workflow(jsonb) to authenticated;
grant execute on function public.omelo_submit_for_approval(text, uuid, text) to authenticated;
grant execute on function public.omelo_decide_approval(uuid, boolean, text) to authenticated;
grant execute on function public.omelo_cancel_approval(uuid, text) to authenticated;
grant execute on function public.omelo_my_approvals(uuid) to authenticated;
grant execute on function public.omelo_approval_status(text, uuid) to authenticated;
