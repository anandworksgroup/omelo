create or replace function omelo_private.omelo_guard_application_transitions()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if new.stage_id is not null and new.stage_id is distinct from old.stage_id
     and not omelo_private.omelo_stage_in_job(new.stage_id, new.job_id) then
    raise exception 'That stage belongs to a different job' using errcode = '23514';
  end if;

  if omelo_private.omelo_is_privileged() then
    return new;
  end if;

  if old.person_id = auth.uid()
     and new.state = 'withdrawn' and omelo_private.omelo_is_open_state(old.state)
     and new.stage_id is not distinct from old.stage_id
     and new.rejection_reason is not distinct from old.rejection_reason
     and new.rejected_by is not distinct from old.rejected_by
     and new.first_viewed_at is not distinct from old.first_viewed_at
     and new.match_score is not distinct from old.match_score then
    return new;
  end if;

  if new.state            is distinct from old.state
  or new.stage_id         is distinct from old.stage_id
  or new.rejection_reason is distinct from old.rejection_reason
  or new.rejected_by      is distinct from old.rejected_by
  or new.withdrawal_reason is distinct from old.withdrawal_reason
  or new.first_viewed_at  is distinct from old.first_viewed_at
  or new.closed_at        is distinct from old.closed_at
  or new.match_score      is distinct from old.match_score
  or new.cover_note       is distinct from old.cover_note
  or new.answers          is distinct from old.answers
  or new.resume_document_id is distinct from old.resume_document_id
  or new.applied_via      is distinct from old.applied_via then
    raise exception 'Application status changes go through Omelo hiring actions (move, reject, interview, offer)'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

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
  end if;
  if new.company_id is distinct from omelo_private.omelo_job_company(new.job_id) then
    raise exception 'Application company does not match the job' using errcode = '23514';
  end if;
  return new;
end;
$$;