-- OMELO 79 — One organization model, part 4: one way in.
--
-- Omelo has two entry options. A person signs up and gets a Personal Profile.
-- If they want to publish opportunities or manage hiring, they create one
-- Organization Workspace — whatever business they are in. There is no longer
-- an employer sign-up and an agency sign-up.
--
-- The bypass this closes
--
-- R4 refused a company row whose `company_kind` was not 'employer', so that
-- becoming an agency had to go through omelo_create_agency. R8 then added
-- `organization_type`, with a trigger that derives company_kind from it. Both
-- triggers are BEFORE INSERT and Postgres fires them in name order:
-- companies_guard_trust before companies_sync_organization_type. The guard
-- therefore saw company_kind still at its 'employer' default, passed, and the
-- sync then rewrote it to 'agency'.
--
-- The same hole existed on UPDATE, and was wider: the guard never listed
-- organization_type among the columns it protects, so anyone who could update
-- the row at all could reclassify the organization and flip company_kind with
-- it.
--
-- Two doors, one of them locked. tests/api/recruitment_e2e.py asserts the
-- locked one; tests/api/enterprise_e2e.py walks through the open one and
-- asserts that it works.
--
-- How it is closed, and why that is not a loosening
--
-- The lock is removed from both doors rather than added to both, deliberately.
-- That refusal existed when being an agency was a privilege: an agency could
-- see workers an employer could not, and could represent candidates. After
-- migrations 76-78 the business type grants nothing. It no longer decides who
-- may find a worker, who may recruit for a client, or which roles exist. It
-- supplies a default for the optional modules and describes the business.
--
-- So declaring yourself a recruitment agency now gains you exactly nothing you
-- could not already do: you still cannot see a worker who has not made an
-- identity discoverable, you still cannot attach yourself to a client until
-- that client confirms it, and you still cannot represent anyone without their
-- consent. What remains protected is what was always worth protecting, and it
-- is now protected on both paths and on update as well as insert:
-- verification, the independent-recruiter flag, and the hiring statistics
-- Omelo computes.
--
-- Changing the type later is a real thing a business does — a company that
-- starts recruiting for others does not need a second organization — so it is
-- allowed, through an owner/admin function rather than a bare UPDATE.
--
-- Rollback: restore omelo_guard_company_trust and omelo_create_agency, and
-- drop omelo_create_organization and omelo_set_organization_type.

-- ---------------------------------------------------------------
-- 1. The guard protects what is worth protecting, on both paths
-- ---------------------------------------------------------------

create or replace function omelo_private.omelo_guard_company_trust()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if omelo_private.omelo_is_privileged() then return new; end if;

  if tg_op = 'INSERT' then
    if coalesce(new.is_verified, false) or new.verified_at is not null
       or new.verification_method is not null then
      raise exception 'Company verification is done by Omelo' using errcode = '42501';
    end if;
    -- An independent recruiter is a shape Omelo sets up, not a flag you claim.
    if coalesce(new.is_independent_recruiter, false) then
      raise exception 'Create an organization with Omelo''s organization sign-up'
        using errcode = '42501';
    end if;
    new.response_rate_pct := null;
    new.median_response_hours := null;
    new.total_hires := 0;
    new.stats_computed_at := null;
    return new;
  end if;

  if new.is_verified is distinct from old.is_verified
     or new.verified_at is distinct from old.verified_at
     or new.verification_method is distinct from old.verification_method
     or new.is_independent_recruiter is distinct from old.is_independent_recruiter then
    raise exception 'Company verification is managed by Omelo' using errcode = '42501';
  end if;

  -- Closing the update path: organization_type was never listed here, and
  -- company_kind is derived from it, so a bare PATCH could reclassify the
  -- organization. It goes through omelo_set_organization_type now, which asks
  -- whether you own the place.
  if new.organization_type is distinct from old.organization_type
     or new.company_kind is distinct from old.company_kind then
    raise exception 'Change the organization type with omelo_set_organization_type'
      using errcode = '42501';
  end if;

  if new.response_rate_pct is distinct from old.response_rate_pct
     or new.median_response_hours is distinct from old.median_response_hours
     or new.total_hires is distinct from old.total_hires
     or new.stats_computed_at is distinct from old.stats_computed_at then
    raise exception 'Hiring statistics are computed by Omelo' using errcode = '42501';
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------
-- 2. One organization sign-up
-- ---------------------------------------------------------------

create or replace function public.omelo_create_organization(
  p_name text,
  p_type text default 'employer',
  p_country text default null,
  p_independent boolean default false)
returns uuid
language plpgsql
security definer
set search_path = public, omelo_private
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_name text := trim(coalesce(p_name, ''));
  v_type text := coalesce(nullif(trim(p_type), ''), 'employer');
begin
  if v_uid is null then
    raise exception 'Sign in required' using errcode = '42501';
  end if;
  if length(v_name) not between 2 and 120 then
    raise exception 'Give the organization a name between 2 and 120 characters'
      using errcode = '22023';
  end if;
  if v_type not in ('employer','recruitment_agency','staffing_agency','rpo_provider','workforce_provider') then
    raise exception 'Unknown organization type %', v_type using errcode = '22023';
  end if;
  -- One limit for everyone, and it is about stopping a flood of workspaces,
  -- not about what sort of business this is.
  if (select count(*) from companies c
        join company_members cm on cm.company_id = c.id
       where cm.person_id = v_uid and cm.role = 'owner' and cm.is_active
         and c.deleted_at is null) >= 5 then
    raise exception 'You can own at most 5 organizations' using errcode = '22023';
  end if;

  insert into companies (slug, display_name, country_code, organization_type,
                         is_independent_recruiter, created_by)
  values (public.omelo_company_slug(v_name), v_name,
          upper(coalesce(nullif(p_country, ''),
                         (select country_code from persons where id = v_uid), 'IN')),
          v_type, coalesce(p_independent, false), v_uid)
  returning id into v_id;

  perform omelo_private.omelo_emit('OrganizationCreated', 'company', v_id, v_id, v_uid,
                                   jsonb_build_object('organization_type', v_type,
                                                      'independent', coalesce(p_independent, false)));
  return v_id;
end;
$$;

revoke execute on function public.omelo_create_organization(text, text, text, boolean) from public;
grant execute on function public.omelo_create_organization(text, text, text, boolean) to authenticated;

-- The agency sign-up becomes one word for the same thing. Kept so that
-- anything still calling it keeps working; the portal calls the new one.
create or replace function public.omelo_create_agency(
  p_name text, p_independent boolean default false, p_country text default null)
returns uuid
language sql
security definer
set search_path = public, omelo_private
as $$
  select public.omelo_create_organization(p_name, 'staffing_agency', p_country, p_independent);
$$;

-- ---------------------------------------------------------------
-- 3. A business can change what it does
-- ---------------------------------------------------------------
--
-- A company that starts recruiting for clients should not have to create a
-- second organization, re-invite its team and lose its page. Note what this
-- does NOT do: it never moves a record from one organization to another. A
-- recruitment agency and its client stay two organizations with their own
-- pages, memberships and permissions.

create or replace function public.omelo_set_organization_type(p_company uuid, p_type text)
returns void
language plpgsql
security definer
set search_path = public, omelo_private
as $$
declare v_type text := coalesce(nullif(trim(p_type), ''), '');
begin
  if not omelo_private.omelo_has_company_role(p_company, array['owner','admin']::company_role[]) then
    raise exception 'Only owners and admins can change the organization type'
      using errcode = '42501';
  end if;
  if v_type not in ('employer','recruitment_agency','staffing_agency','rpo_provider','workforce_provider') then
    raise exception 'Unknown organization type %', v_type using errcode = '22023';
  end if;

  update companies set organization_type = v_type, updated_at = now()
   where id = p_company and deleted_at is null;

  perform omelo_private.omelo_emit('OrganizationTypeChanged', 'company', p_company, p_company,
                                   auth.uid(), jsonb_build_object('organization_type', v_type));
end;
$$;

revoke execute on function public.omelo_set_organization_type(uuid, text) from public;
grant execute on function public.omelo_set_organization_type(uuid, text) to authenticated;