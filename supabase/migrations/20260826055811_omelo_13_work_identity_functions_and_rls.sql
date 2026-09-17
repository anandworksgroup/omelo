-- ============================================================
-- OMELO 13 — Functions and RLS for multiple work identities
-- ============================================================

drop function if exists omelo_profile_schema_for(uuid);

-- ------------------------------------------------------------
-- Consent predicate, now two-level.
-- Person-level discoverability is a master switch; each identity
-- carries its own. This is what lets a teacher be findable as a
-- freelance designer while staying invisible as a teacher.
-- ------------------------------------------------------------

create or replace function omelo_is_identity_discoverable_to(
  p_work_identity_id uuid,
  p_company_id uuid
) returns boolean
language sql stable security definer set search_path = public as $$
  select
    exists (
      select 1
      from work_identities wi
      join persons p on p.id = wi.person_id
      where wi.id = p_work_identity_id
        and wi.status = 'active'
        and wi.discoverability <> 'private'
        and p.deleted_at is null
        and p.discoverability <> 'private'          -- master switch
    )
    and exists (select 1 from companies c
                where c.id = p_company_id and c.is_verified and c.deleted_at is null)
    and exists (select 1 from company_entitlements e
                where e.company_id = p_company_id and e.talent_search_enabled)
    and not exists (
      select 1 from blocks b
      join work_identities wi on wi.id = p_work_identity_id
      where b.person_id = wi.person_id
        and b.target_type = 'company' and b.target_id = p_company_id)
    and not exists (
      select 1 from blocks b
      join work_identities wi on wi.id = p_work_identity_id
      where b.person_id = wi.person_id
        and b.target_type = 'person' and b.target_id = auth.uid());
$$;

create or replace function omelo_is_discoverable_to(p_person_id uuid, p_company_id uuid)
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from work_identities wi
    where wi.person_id = p_person_id
      and omelo_is_identity_discoverable_to(wi.id, p_company_id)
  );
$$;

-- ------------------------------------------------------------
-- Adaptive profile schema, now resolved per identity.
-- ------------------------------------------------------------

create function omelo_profile_schema_for(p_work_identity_id uuid default null)
returns table (
  attribute_id uuid, slug text, label text, help_text text,
  data_type attribute_data_type, options jsonb,
  is_required boolean, sort_position smallint, scope text
)
language plpgsql stable security definer set search_path = public as $$
declare
  v_identity uuid;
  v_owner uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  v_identity := coalesce(
    p_work_identity_id,
    (select id from work_identities
      where person_id = auth.uid() and is_primary limit 1)
  );

  if v_identity is null then
    return;
  end if;

  select person_id into v_owner from work_identities where id = v_identity;

  if v_owner is null then
    raise exception 'Work identity not found';
  end if;
  if v_owner <> auth.uid() and not omelo_is_platform_admin() then
    raise exception 'Not authorised';
  end if;

  return query
  with identity_scope as (
    select
      coalesce(
        array_remove(array_agg(distinct coalesce(pr.category_id, wi.category_id)), null),
        '{}'::uuid[]) as category_ids,
      coalesce(
        array_remove(
          array_agg(distinct coalesce(pp.profession_id, wi.profession_id)), null),
        '{}'::uuid[]) as profession_ids
    from work_identities wi
    left join person_professions pp on pp.work_identity_id = wi.id
    left join professions pr
           on pr.id = coalesce(pp.profession_id, wi.profession_id)
    where wi.id = v_identity
  )
  select
    a.id, a.slug, a.label, a.help_text, a.data_type, a.options,
    a.is_required, a.position,
    case
      when a.profession_id is not null then 'profession'
      when a.category_id   is not null then 'category'
      else 'universal'
    end
  from profile_attributes a, identity_scope s
  where a.status = 'active'
    and (
      (a.category_id is null and a.profession_id is null)
      or a.category_id   = any(s.category_ids)
      or a.profession_id = any(s.profession_ids)
    )
  order by
    case when a.profession_id is not null then 0
         when a.category_id   is not null then 1
         else 2 end,
    a.position;
end;
$$;

-- ------------------------------------------------------------
-- Signup: every person starts with exactly one work identity.
-- ------------------------------------------------------------

create or replace function omelo_handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_identity uuid;
begin
  insert into persons (id, email, phone, display_name, locale)
  values (
    new.id,
    new.email,
    new.phone,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'),
    coalesce(new.raw_user_meta_data->>'locale', 'en')
  )
  on conflict (id) do nothing;

  insert into work_identities (person_id, label, is_primary)
  values (new.id, 'My work', true)
  on conflict (person_id, label) do nothing
  returning id into v_identity;

  if v_identity is null then
    select id into v_identity
    from work_identities where person_id = new.id and is_primary limit 1;
  end if;

  insert into person_work_preferences (person_id, work_identity_id)
  values (new.id, v_identity)
  on conflict (work_identity_id) do nothing;

  insert into notification_preferences (person_id) values (new.id)
  on conflict (person_id) do nothing;

  return new;
end;
$$;

-- ------------------------------------------------------------
-- RLS on work_identities
-- ------------------------------------------------------------

alter table work_identities enable row level security;

create policy work_identities_self on work_identities
  for all using (person_id = auth.uid()) with check (person_id = auth.uid());

create policy work_identities_via_application on work_identities
  for select using (omelo_has_application_from(person_id));

create policy work_identities_via_consent on work_identities
  for select using (
    exists (
      select 1 from company_members cm
      where cm.person_id = auth.uid()
        and cm.is_active
        and cm.role = any (array['owner','admin','recruiter']::company_role[])
        and omelo_is_identity_discoverable_to(work_identities.id, cm.company_id)
    )
  );

create policy work_identities_public on work_identities
  for select using (
    discoverability = 'public'
    and status = 'active'
    and exists (select 1 from persons p
                where p.id = work_identities.person_id
                  and p.deleted_at is null
                  and p.discoverability = 'public')
  );

create policy work_identities_admin on work_identities
  for select using (omelo_is_platform_admin());

-- ------------------------------------------------------------
-- Grants: the client-callable function surface stays at three
-- ------------------------------------------------------------

grant select, insert, update, delete on work_identities to authenticated;
grant select on work_identities to anon;

revoke execute on function omelo_is_identity_discoverable_to(uuid, uuid) from public, anon, authenticated;
revoke execute on function omelo_guard_work_identity() from public, anon, authenticated;
revoke execute on function omelo_single_primary_identity() from public, anon, authenticated;
revoke execute on function omelo_check_identity_owner() from public, anon, authenticated;

revoke execute on function omelo_profile_schema_for(uuid) from public, anon;
grant execute on function omelo_profile_schema_for(uuid) to authenticated;