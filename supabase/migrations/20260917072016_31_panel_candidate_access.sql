create or replace function omelo_private.omelo_has_application_from(p_person_id uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select exists (
    select 1 from applications a
    join company_members cm
      on cm.company_id = a.company_id and cm.person_id = auth.uid() and cm.is_active
    where a.person_id = p_person_id
      and cm.role in ('owner','admin','recruiter','hiring_manager','hr')
  )
  or exists (
    select 1 from interviews i
    join interview_interviewers ii on ii.interview_id = i.id and ii.person_id = auth.uid()
    join company_members cm on cm.company_id = i.company_id and cm.person_id = auth.uid() and cm.is_active
    where i.person_id = p_person_id
      and i.status <> 'cancelled'
  );
$$;

create or replace function omelo_private.omelo_is_panelist_for(p_person_id uuid, p_job_id uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select exists (
    select 1 from interviews i
    join interview_interviewers ii on ii.interview_id = i.id and ii.person_id = auth.uid()
    join company_members cm on cm.company_id = i.company_id and cm.person_id = auth.uid() and cm.is_active
    where i.person_id = p_person_id and i.job_id = p_job_id and i.status <> 'cancelled');
$$;
grant execute on function omelo_private.omelo_is_panelist_for(uuid, uuid) to authenticated;

drop policy if exists matches_panel on matches;
create policy matches_panel on matches for select to authenticated
  using (omelo_private.omelo_is_panelist_for(person_id, job_id));