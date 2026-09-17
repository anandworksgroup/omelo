create or replace function omelo_private.omelo_is_interview_panelist(p_interview_id uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select exists (select 1 from interview_interviewers
                  where interview_id = p_interview_id and person_id = auth.uid());
$$;

create or replace function omelo_private.omelo_can_access_interview(p_interview_id uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select exists (select 1 from interviews i
                  where i.id = p_interview_id and omelo_private.omelo_can_access_job(i.job_id));
$$;

grant execute on function omelo_private.omelo_is_interview_panelist(uuid) to authenticated;
grant execute on function omelo_private.omelo_can_access_interview(uuid) to authenticated;

drop policy if exists interviews_interviewer on interviews;
create policy interviews_interviewer on interviews
  for select to authenticated
  using (omelo_private.omelo_is_interview_panelist(id));

drop policy if exists interview_interviewers_read on interview_interviewers;
create policy interview_interviewers_read on interview_interviewers
  for select to authenticated
  using (person_id = auth.uid() or omelo_private.omelo_can_access_interview(interview_id));

drop policy if exists interview_interviewers_write on interview_interviewers;
create policy interview_interviewers_write on interview_interviewers
  for all to authenticated
  using (omelo_private.omelo_can_access_interview(interview_id))
  with check (omelo_private.omelo_can_access_interview(interview_id));