-- OMELO 47 (Release 4 fixes, found by tests/api/recruitment_e2e.py)
--
-- 1. omelo_score_match appended gate failures with `text[] || 'literal'`,
--    which Postgres parses as array || array and fails ("malformed array
--    literal"). It never fired before because R3 only scored published jobs
--    and no test candidate failed a gate — but any candidate failing the
--    work-authorization or licence gate would have broken ranking,
--    recommendations and search. All three gates now use array_append.
--    A job order's private backing job counts as open while the order is.
-- 2. The pool guard checked identity ownership as the caller; RLS hides the
--    identity from a sourcer, so sourcers could never save anyone. The check
--    now reads ownership through a definer helper.
-- 3. applications.applied_via gains 'agency' (submissions create
--    applications); only the server may set it, so a worker cannot pose as
--    an agency submission.

do $$
declare d text; n int := 0;
begin
  d := pg_get_functiondef('omelo_private.omelo_score_match'::regproc);
  if position($r$gate_failures || 'job_open'$r$ in d) > 0 then n := n + 1; end if;
  if position($r$gate_failures || 'work_authorization'$r$ in d) > 0 then n := n + 1; end if;
  if position($r$gate_failures || 'required_licence'$r$ in d) > 0 then n := n + 1; end if;
  if n <> 3 then
    raise exception 'omelo_score_match is not the expected version (found % of 3 gate appends)', n;
  end if;
  d := replace(d, $r$gate_failures := gate_failures || 'job_open';$r$,
                  $r$gate_failures := array_append(gate_failures, 'job_open');$r$);
  d := replace(d, $r$gate_failures := gate_failures || 'work_authorization';$r$,
                  $r$gate_failures := array_append(gate_failures, 'work_authorization');$r$);
  d := replace(d, $r$gate_failures := gate_failures || 'required_licence';$r$,
                  $r$gate_failures := array_append(gate_failures, 'required_licence');$r$);
  d := replace(d, $r$case when j.status = 'published' then 'pass' else 'fail' end$r$,
                  $r$case when j.status = 'published'
                   or exists (select 1 from job_orders jo where jo.job_id = j.id
                                and jo.status in ('draft','open','on_hold')) then 'pass' else 'fail' end$r$);
  d := replace(d, $r$if j.status <> 'published' then gate_failures$r$,
                  $r$if j.status <> 'published'
     and not exists (select 1 from job_orders jo where jo.job_id = j.id
                       and jo.status in ('draft','open','on_hold')) then gate_failures$r$);
  if position('gate_failures || ' in d) > 0 or position('job_orders jo' in d) = 0 then
    raise exception 'omelo_score_match patch did not apply cleanly';
  end if;
  execute d;
end;
$$;

create or replace function omelo_private.omelo_identity_owner(p_identity uuid)
returns uuid
language sql stable security definer
set search_path = public, omelo_private
as $$
  select person_id from work_identities where id = p_identity;
$$;
revoke execute on function omelo_private.omelo_identity_owner(uuid) from public, anon;
grant execute on function omelo_private.omelo_identity_owner(uuid) to authenticated;

create or replace function omelo_private.omelo_guard_pool_member()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if omelo_private.omelo_is_privileged() then
    return new;
  end if;
  if new.work_identity_id is null then
    raise exception 'Choose which work identity to save' using errcode = '22023';
  end if;
  if omelo_private.omelo_identity_owner(new.work_identity_id) is distinct from new.person_id then
    raise exception 'That work identity does not belong to this person' using errcode = '22023';
  end if;
  if not (omelo_private.omelo_can_view_identity(new.work_identity_id)
          or exists (select 1 from talent_pools tp
                      where tp.id = new.pool_id
                        and omelo_private.omelo_agency_can(tp.company_id, 'search_talent')
                        and omelo_private.omelo_is_identity_discoverable_to(new.work_identity_id, tp.company_id))) then
    raise exception 'You can only save candidates who are visible to your company' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' then
    new.added_by := auth.uid();
    new.added_at := now();
  end if;
  if new.note is not null and length(new.note) > 500 then
    raise exception 'Keep the note under 500 characters' using errcode = '22023';
  end if;
  return new;
end;
$$;

alter table applications drop constraint if exists applications_applied_via_check;
alter table applications add constraint applications_applied_via_check
  check (applied_via = any (array['omelo','quick_apply','walk_in','phone','import','agency']));

create or replace function omelo_private.omelo_guard_application_insert()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if not omelo_private.omelo_is_privileged() then
    new.state := 'applied';
    new.stage_id := omelo_private.omelo_first_stage(new.job_id, 'applied');
    new.first_viewed_at := null;
    new.closed_at := null;
    new.rejection_reason := null;
    new.rejected_by := null;
    if new.applied_via = 'agency' then
      raise exception 'Agency submissions are created by the agency''s consented submission' using errcode = '42501';
    end if;
  end if;
  if new.company_id is distinct from omelo_private.omelo_job_company(new.job_id) then
    raise exception 'Application company does not match the job' using errcode = '23514';
  end if;
  return new;
end;
$$;
