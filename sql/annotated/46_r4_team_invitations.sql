-- OMELO 46 — Release 4: joining a team (agency or employer) needs the person's consent.
--
-- Before: company_members_manage let an owner/admin INSERT any person into
-- their company with any role, and company_invitations had no acceptance
-- path. A recruiter "joining an agency" therefore meant being added without
-- being asked, and an admin could create owners by writing invitation rows.
--
-- Now:
--   * members are added only by accepting an invitation
--     (omelo_invite_team_member -> omelo_accept_team_invitation); the
--     invitee must be signed in with the invited email address
--   * only an owner can invite another owner; agency-only roles (sourcer,
--     coordinator) exist only in agencies
--   * optional flag require_verified_email_to_join_team (default false, the
--     project runs without email confirmation): turn it on in production so
--     an address cannot be claimed by whoever signs up with it first
--   * owners/admins still update (role, active) and remove members directly
--
-- Rollback: restore company_members_manage / company_invitations_manage
-- (08_rls_policies) and drop the functions below.

insert into omelo_private.app_settings (key, value)
values ('require_verified_email_to_join_team', 'false')
on conflict (key) do nothing;

drop policy if exists company_members_manage on company_members;
drop policy if exists company_members_update on company_members;
drop policy if exists company_members_delete on company_members;
create policy company_members_update on company_members for update to authenticated
  using (omelo_private.omelo_has_company_role(company_id, array['owner','admin']::company_role[]))
  with check (omelo_private.omelo_has_company_role(company_id, array['owner','admin']::company_role[]));
create policy company_members_delete on company_members for delete to authenticated
  using (omelo_private.omelo_has_company_role(company_id, array['owner','admin']::company_role[]));
revoke insert on company_members from anon, authenticated;

drop policy if exists company_invitations_manage on company_invitations;
drop policy if exists company_invitations_read on company_invitations;
drop policy if exists company_invitations_delete on company_invitations;
create policy company_invitations_read on company_invitations for select to authenticated
  using (omelo_private.omelo_has_company_role(company_id, array['owner','admin']::company_role[]));
create policy company_invitations_delete on company_invitations for delete to authenticated
  using (omelo_private.omelo_has_company_role(company_id, array['owner','admin']::company_role[]));
revoke insert, update on company_invitations from anon, authenticated;

-- Role changes by admins cannot mint owners or put agency roles in an employer.
create or replace function omelo_private.omelo_guard_member_role()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if omelo_private.omelo_is_privileged() then
    return new;
  end if;
  if new.company_id is distinct from old.company_id or new.person_id is distinct from old.person_id then
    raise exception 'A membership cannot move to another person or company' using errcode = '42501';
  end if;
  if new.role is distinct from old.role then
    if (new.role::text = 'owner' or old.role::text = 'owner')
       and not omelo_private.omelo_has_company_role(new.company_id, array['owner']::company_role[]) then
      raise exception 'Only an owner can grant or remove the owner role' using errcode = '42501';
    end if;
    if new.role::text in ('sourcer','coordinator')
       and not exists (select 1 from companies where id = new.company_id and company_kind = 'agency') then
      raise exception 'Sourcer and coordinator are agency roles' using errcode = '22023';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists company_members_guard_role on company_members;
create trigger company_members_guard_role before update on company_members
  for each row execute function omelo_private.omelo_guard_member_role();

create or replace function public.omelo_invite_team_member(p_company uuid, p_email text, p_role text)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare
  v_email text := lower(trim(coalesce(p_email, ''))); v_id uuid; v_company companies; v_person uuid;
begin
  if not omelo_private.omelo_has_company_role(p_company, array['owner','admin']::company_role[]) then
    raise exception 'Only owners and admins can invite team members' using errcode = '42501';
  end if;
  select * into v_company from companies where id = p_company and deleted_at is null;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_email) > 254 then
    raise exception 'Enter a valid email address' using errcode = '22023';
  end if;
  if p_role is null or p_role not in (select e.enumlabel from pg_enum e join pg_type t on t.oid = e.enumtypid
                                        where t.typname = 'company_role') then
    raise exception 'Unknown role %', p_role using errcode = '22023';
  end if;
  if p_role = 'owner' and not omelo_private.omelo_has_company_role(p_company, array['owner']::company_role[]) then
    raise exception 'Only an owner can invite another owner' using errcode = '42501';
  end if;
  if p_role in ('sourcer','coordinator') and v_company.company_kind <> 'agency' then
    raise exception 'Sourcer and coordinator are agency roles' using errcode = '22023';
  end if;
  if exists (select 1 from company_members cm join persons p on p.id = cm.person_id
              where cm.company_id = p_company and cm.is_active and lower(p.email) = v_email
                and cm.role::text = p_role) then
    raise exception 'That person already has this role' using errcode = '22023';
  end if;
  if (select count(*) from company_invitations where company_id = p_company
        and created_at > now() - interval '1 day') >= 50 then
    raise exception 'Too many invitations today' using errcode = '22023';
  end if;

  insert into company_invitations (company_id, email, role, token_hash, invited_by, expires_at, accepted_at)
  values (p_company, v_email, p_role::company_role,
          encode(sha256(convert_to(gen_random_uuid()::text || gen_random_uuid()::text, 'UTF8')), 'hex'),
          auth.uid(), now() + interval '14 days', null)
  on conflict (company_id, email) do update
     set role = excluded.role, token_hash = excluded.token_hash, invited_by = excluded.invited_by,
         expires_at = excluded.expires_at, accepted_at = null, created_at = now()
  returning id into v_id;

  select id into v_person from persons where lower(email) = v_email and deleted_at is null;
  if v_person is not null then
    perform omelo_private.omelo_notify(v_person, 'company_update'::notification_type,
      v_company.display_name || ' invited you to join the team',
      'Role: ' || replace(p_role, '_', ' '), 'company_invitation', v_id, '/join/' || v_id);
  end if;
  perform omelo_private.omelo_emit('TeamMemberInvited', 'company', p_company, p_company, v_person,
    jsonb_build_object('role', p_role));
  return v_id;
end;
$$;

create or replace function public.omelo_my_team_invitations()
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', ci.id, 'role', ci.role, 'expires_at', ci.expires_at, 'invited_at', ci.created_at,
      'invited_by', (select display_name from persons where id = ci.invited_by),
      'company', jsonb_build_object('id', c.id, 'name', c.display_name, 'kind', c.company_kind,
                                    'verified', c.is_verified, 'logo_url', c.logo_url))
      order by ci.created_at desc), '[]'::jsonb)
  from company_invitations ci
  join companies c on c.id = ci.company_id and c.deleted_at is null
  where ci.accepted_at is null and ci.expires_at > now()
    and ci.email = lower((select email from persons where id = (select auth.uid())));
$$;

create or replace function public.omelo_accept_team_invitation(p_invitation uuid)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare ci company_invitations; v_email text;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  select lower(email) into v_email from persons where id = auth.uid();
  select * into ci from company_invitations where id = p_invitation for update;
  if ci.id is null or ci.email is distinct from v_email then
    raise exception 'This invitation is for another email address' using errcode = '42501';
  end if;
  if ci.accepted_at is not null then
    raise exception 'This invitation was already used' using errcode = '22023';
  end if;
  if ci.expires_at <= now() then
    raise exception 'This invitation has expired. Ask for a new one.' using errcode = '22023';
  end if;
  if omelo_private.omelo_setting('require_verified_email_to_join_team', 'false') = 'true'
     and not exists (select 1 from verifications where person_id = auth.uid() and type = 'email'
                       and status = 'verified' and revoked_at is null) then
    raise exception 'Verify your email address first, then accept the invitation' using errcode = '42501';
  end if;
  insert into company_members (company_id, person_id, role, is_active, invited_by)
  values (ci.company_id, auth.uid(), ci.role, true, ci.invited_by)
  on conflict (company_id, person_id, role) do update set is_active = true;
  update company_invitations set accepted_at = now() where id = ci.id;
  perform omelo_private.omelo_emit('TeamMemberJoined', 'company', ci.company_id, ci.company_id, auth.uid(),
    jsonb_build_object('role', ci.role));
  if ci.invited_by is not null then
    perform omelo_private.omelo_notify(ci.invited_by, 'company_update'::notification_type,
      coalesce((select display_name from persons where id = auth.uid()), 'Someone') || ' joined your team',
      'Role: ' || replace(ci.role::text, '_', ' '), 'company', ci.company_id, '/dashboard/company');
  end if;
  return ci.company_id;
end;
$$;

create or replace function public.omelo_decline_team_invitation(p_invitation uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare ci company_invitations;
begin
  select * into ci from company_invitations where id = p_invitation;
  if ci.id is null or ci.email is distinct from lower((select email from persons where id = auth.uid())) then
    raise exception 'Invitation not found' using errcode = '42501';
  end if;
  delete from company_invitations where id = ci.id and accepted_at is null;
end;
$$;

do $$
declare fn text;
begin
  foreach fn in array array[
    'omelo_invite_team_member(uuid, text, text)',
    'omelo_my_team_invitations()',
    'omelo_accept_team_invitation(uuid)',
    'omelo_decline_team_invitation(uuid)'
  ] loop
    execute format('revoke execute on function public.%s from public, anon', fn);
    execute format('grant execute on function public.%s to authenticated', fn);
  end loop;
end;
$$;
