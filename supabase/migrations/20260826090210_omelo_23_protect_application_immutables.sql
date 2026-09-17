-- ============================================================
-- OMELO 23 — Make the application record honest by construction
--
-- BUG 1: applications_employer_update allowed updating ANY column, so an
-- employer could PATCH first_viewed_at back to NULL and erase the fact that
-- they had opened an application. That directly breaks FR-331 — "viewed
-- cannot be faked or suppressed by the employer" — which the whole
-- candidate-trust model rests on. RLS cannot express column-level rules, so
-- this is enforced with a trigger.
--
-- BUG 2: marking an application viewed twice logged a duplicate event.
-- ============================================================

create or replace function omelo_guard_application_immutables()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  -- Identity of the application never changes after submission.
  if new.job_id            is distinct from old.job_id
  or new.person_id         is distinct from old.person_id
  or new.company_id        is distinct from old.company_id
  or new.work_identity_id  is distinct from old.work_identity_id
  or new.applied_at        is distinct from old.applied_at then
    raise exception 'An application''s job, applicant, identity or submission time cannot be changed';
  end if;

  -- The snapshot is a copy taken at submission. If it could be edited, an
  -- employer could review something the worker never actually sent.
  if new.identity_snapshot is distinct from old.identity_snapshot then
    raise exception 'The identity snapshot is immutable once submitted';
  end if;

  -- first_viewed_at is monotonic: it can be set once, and never cleared or
  -- moved. This is the mechanism behind the honest "Employer viewed" state.
  if old.first_viewed_at is not null
     and (new.first_viewed_at is null
          or new.first_viewed_at is distinct from old.first_viewed_at) then
    raise exception 'first_viewed_at cannot be cleared or altered once set';
  end if;

  return new;
end;
$$;

revoke execute on function omelo_guard_application_immutables() from public, anon, authenticated;

create trigger applications_guard_immutables
  before update on applications
  for each row execute function omelo_guard_application_immutables();

-- Idempotent view marking: opening the same application twice must not
-- append a second event.
create or replace function omelo_mark_application_viewed(p_application_id uuid)
returns void
language plpgsql
security definer
set search_path = public, omelo_private
as $$
declare
  v_already boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select (a.first_viewed_at is not null) into v_already
  from applications a
  where a.id = p_application_id
    and omelo_private.omelo_can_access_job(a.job_id);

  if v_already is null then
    raise exception 'Application not found, or you do not have access to it';
  end if;

  if v_already then
    return;                              -- already recorded; stay idempotent
  end if;

  update applications
     set first_viewed_at = now(),
         state = case when state = 'applied' then 'viewed'::application_state
                      else state end,
         last_activity_at = now()
   where id = p_application_id;
end;
$$;

revoke execute on function omelo_mark_application_viewed(uuid) from public, anon;
grant execute on function omelo_mark_application_viewed(uuid) to authenticated;