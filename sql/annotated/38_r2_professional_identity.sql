-- OMELO 38 (Release 2): Universal Professional Identity.
--
-- A person holds up to five work identities (Driver, Electrician, Cook,
-- Software Engineer...). Each identity is a lens with its own skills,
-- experience, preferences, adaptive profile answers, visibility and
-- evidence. Rows with work_identity_id = NULL are shared by all identities.
--
-- Fixes found while building this:
-- 1. person_skills / person_attributes were UNIQUE per person, so a skill or
--    an adaptive answer could exist only once across all identities.
--    Now unique per (person, identity) with NULLS NOT DISTINCT.
-- 2. Deleting an identity SET NULL on its skills/experiences/projects, which
--    turned them into "shared" rows visible on every other identity. They
--    now go with the identity (CASCADE). Identities with applications cannot
--    be deleted at all (existing NO ACTION FK) — they are archived instead.
-- 3. An employer who received an application could read the candidate's
--    rows for ALL identities. Employer reads of identity-scoped tables now
--    go through omelo_can_view_person_row(person, identity): shared rows as
--    before, identity rows only for the identity that applied (or that is
--    discoverable to the employer).
-- 4. Visibility had 3 levels; it now has 5:
--      private | matched_only | discoverable (employers) | recruiters | public
--    'recruiters' additionally opens the identity to agencies
--    (companies.company_kind = 'agency', introduced here, used from R4).
--
-- Rollback: additive except the unique-key and FK changes, which are
-- reversible while no duplicate per-identity rows exist.

alter type discoverability add value if not exists 'matched_only' before 'discoverable';
alter type discoverability add value if not exists 'recruiters' after 'discoverable';

-- 1 ---------------------------------------------------------------------------
alter table person_skills drop constraint if exists person_skills_person_id_skill_id_key;
alter table person_skills add constraint person_skills_identity_skill_key
  unique nulls not distinct (person_id, work_identity_id, skill_id);
alter table person_attributes drop constraint if exists person_attributes_person_id_attribute_id_key;
alter table person_attributes add constraint person_attributes_identity_attribute_key
  unique nulls not distinct (person_id, work_identity_id, attribute_id);

-- 2 ---------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in
    select c.conname, c.conrelid::regclass as tbl, pg_get_constraintdef(c.oid) as def
      from pg_constraint c
     where c.contype = 'f' and c.confrelid = 'public.work_identities'::regclass
       and c.conrelid in ('public.person_skills'::regclass, 'public.experiences'::regclass, 'public.projects'::regclass)
  loop
    execute format('alter table %s drop constraint %I', r.tbl, r.conname);
    execute format('alter table %s add constraint %I %s',
                   r.tbl, r.conname, regexp_replace(r.def, '\s+ON DELETE SET NULL', '') || ' on delete cascade');
  end loop;
end;
$$;

-- 4 (company kind) ------------------------------------------------------------
alter table companies add column if not exists company_kind text not null default 'employer';
alter table companies drop constraint if exists companies_company_kind_check;
alter table companies add constraint companies_company_kind_check check (company_kind in ('employer','agency'));

create or replace function omelo_private.omelo_guard_company_trust()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if omelo_private.omelo_is_privileged() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if coalesce(new.is_verified, false) or new.verified_at is not null or new.verification_method is not null then
      raise exception 'Company verification is done by Omelo' using errcode = '42501';
    end if;
    if new.company_kind <> 'employer' then
      raise exception 'Recruitment agencies are onboarded by Omelo' using errcode = '42501';
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
  or new.company_kind is distinct from old.company_kind then
    raise exception 'Company verification and type are managed by Omelo' using errcode = '42501';
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

-- Visibility, five levels. Text comparisons: the new enum values cannot be
-- referenced as enum literals inside the transaction that adds them.
create or replace function omelo_private.omelo_is_identity_discoverable_to(p_work_identity_id uuid, p_company_id uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select
    exists (
      select 1
        from work_identities wi
        join persons p on p.id = wi.person_id
        join companies c on c.id = p_company_id
       where wi.id = p_work_identity_id
         and wi.status = 'active'
         and p.deleted_at is null
         and p.discoverability::text <> 'private'          -- master switch
         and case wi.discoverability::text
               when 'private'      then false
               when 'matched_only' then exists (
                 select 1 from matches m join jobs j on j.id = m.job_id
                  where m.work_identity_id = wi.id and j.company_id = p_company_id
                    and j.status = 'published' and m.eligible and m.score >= 70)
               when 'discoverable' then c.company_kind = 'employer'
               when 'recruiters'   then c.company_kind in ('employer','agency')
               when 'public'       then true
               else false
             end)
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

-- 3 ---------------------------------------------------------------------------
-- Can the caller (an employer / panel member) see this identity?
create or replace function omelo_private.omelo_can_view_identity(p_identity uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select exists (
           select 1 from applications a
            where a.work_identity_id = p_identity
              and (omelo_private.omelo_can_access_job(a.job_id)
                   or exists (select 1 from interviews i
                                join interview_interviewers ii on ii.interview_id = i.id and ii.person_id = auth.uid()
                                join company_members cm on cm.company_id = i.company_id and cm.person_id = auth.uid() and cm.is_active
                               where i.application_id = a.id and i.status <> 'cancelled')))
      or exists (
           select 1 from company_members cm
            where cm.person_id = auth.uid() and cm.is_active
              and cm.role in ('owner','admin','recruiter')
              and omelo_private.omelo_is_identity_discoverable_to(p_identity, cm.company_id));
$$;

-- A row of an identity-scoped table: shared rows follow the person-level
-- rules; identity rows follow the identity.
create or replace function omelo_private.omelo_can_view_person_row(p_person uuid, p_identity uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select case
    when p_identity is null then
      omelo_private.omelo_has_application_from(p_person)
      or exists (select 1 from company_members cm
                  where cm.person_id = auth.uid() and cm.is_active
                    and cm.role in ('owner','admin','recruiter')
                    and omelo_private.omelo_is_discoverable_to(p_person, cm.company_id))
    else omelo_private.omelo_can_view_identity(p_identity)
  end;
$$;

grant execute on function omelo_private.omelo_can_view_identity(uuid) to authenticated;
grant execute on function omelo_private.omelo_can_view_person_row(uuid, uuid) to authenticated;

do $$
declare t text;
begin
  foreach t in array array['person_skills','experiences','person_attributes','person_professions',
                           'person_work_preferences','person_location_preferences','projects'] loop
    execute format('drop policy if exists %I on %I', t || '_employer_read', t);
    execute format('create policy %I on %I for select to authenticated using (omelo_private.omelo_can_view_person_row(person_id, work_identity_id))',
                   t || '_employer_read', t);
  end loop;
end;
$$;

drop policy if exists work_identities_via_application on work_identities;
create policy work_identities_via_application on work_identities for select to authenticated
  using (omelo_private.omelo_can_view_identity(id));

drop policy if exists project_skills_read on project_skills;
create policy project_skills_read on project_skills for select to authenticated
  using (exists (select 1 from projects p
                  where p.id = project_skills.project_id
                    and omelo_private.omelo_can_view_person_row(p.person_id, p.work_identity_id)));

-- Applications must come from an active identity.
create or replace function omelo_private.omelo_check_identity_active()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if not exists (select 1 from work_identities where id = new.work_identity_id and status = 'active') then
    raise exception 'Choose an active work identity to apply with' using errcode = '22023';
  end if;
  return new;
end;
$$;
revoke execute on function omelo_private.omelo_check_identity_active() from public, anon, authenticated;
drop trigger if exists applications_identity_active on applications;
create trigger applications_identity_active before insert on applications
  for each row execute function omelo_private.omelo_check_identity_active();

-- Adaptive attributes ------------------------------------------------------------
-- New attributes for the reference workers that had none or too few.
insert into profile_attributes (slug, label, help_text, data_type, category_id, profession_id, options, unit,
                                is_required, is_filterable, usable_as_requirement, position, status)
select v.slug, v.label, v.help, v.dt::attribute_data_type,
       (select id from job_categories where slug = v.cat),
       (select id from professions where slug = v.prof),
       coalesce(v.opts, '[]')::jsonb, v.unit, v.req, true, v.as_req, v.pos, 'active'
  from (values
    -- Electrician (profession-level, construction category already has trade level, tools, sites, safety)
    ('electrical-licence', 'Electrical licence', 'Your licence or wireman permit class', 'single_select', null, 'electrician',
     '["None yet","Wireman permit","Supervisor licence","Contractor licence"]', null, true, true, 1),
    ('wiring-work', 'Wiring work you do', null, 'multi_select', null, 'electrician',
     '["Homes","Shops and offices","Factories","Solar","Panels and DB","Repairs and fault finding"]', null, false, true, 2),
    -- Nurse
    ('nursing-registration', 'Nursing registration', 'Registered with a nursing council', 'single_select', null, 'nurse',
     '["Registered","Registration in progress","Not registered"]', null, true, true, 1),
    ('nursing-qualification', 'Nursing qualification', null, 'single_select', null, 'nurse',
     '["ANM","GNM","B.Sc Nursing","Post-basic B.Sc","M.Sc Nursing","Other"]', null, true, true, 2),
    -- Retail
    ('cash-handling', 'Comfortable handling cash', null, 'boolean', 'retail', null, null, null, false, true, 1),
    ('billing-systems', 'Billing systems used', null, 'multi_select', 'retail', null,
     '["Cash register","POS software","UPI / card machine","Inventory scanner","None yet"]', null, false, true, 2),
    ('retail-sections', 'Store sections', null, 'multi_select', 'retail', null,
     '["Grocery","Fashion","Electronics","Pharmacy","Home goods","Supermarket floor"]', null, false, true, 3),
    -- Technology
    ('primary-stack', 'Main technologies', null, 'multi_select', 'technology', null,
     '["JavaScript/TypeScript","Python","Java","Go","C#/.NET","PHP","Kotlin/Swift","Flutter/Dart","SQL","Cloud (AWS/GCP/Azure)","DevOps"]', null, false, true, 3),
    ('seniority', 'Level', null, 'single_select', 'technology', null,
     '["Intern","Junior","Mid-level","Senior","Lead / Staff"]', null, true, true, 4),
    -- Warehousing
    ('equipment-operated', 'Equipment you can operate', null, 'multi_select', 'warehousing', null,
     '["Hand pallet truck","Forklift","Reach truck","Barcode scanner","None yet"]', null, false, true, 1),
    ('can-lift-heavy', 'Can lift heavy items (20 kg+)', null, 'boolean', 'warehousing', null, null, null, false, true, 2)
  ) as v(slug, label, help, dt, cat, prof, opts, unit, req, as_req, pos)
 where not exists (select 1 from profile_attributes a where a.slug = v.slug);

-- Does an attribute apply to an identity?
create or replace function omelo_private.omelo_attribute_applies(p_attribute uuid, p_identity uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select exists (
    select 1 from profile_attributes a, work_identities wi
     where a.id = p_attribute and wi.id = p_identity and a.status = 'active'
       and (  (a.category_id is null and a.profession_id is null)
           or a.profession_id = wi.profession_id
           or a.profession_id in (select profession_id from person_professions where work_identity_id = wi.id)
           or a.category_id = coalesce(wi.category_id, (select category_id from professions where id = wi.profession_id))
           or a.category_id in (select pr.category_id from person_professions pp join professions pr on pr.id = pp.profession_id
                                 where pp.work_identity_id = wi.id)));
$$;
revoke execute on function omelo_private.omelo_attribute_applies(uuid, uuid) from public, anon, authenticated;

-- Values must match their attribute's type and options.
create or replace function omelo_private.omelo_validate_person_attribute()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare a profile_attributes; v_opt jsonb; e jsonb;
begin
  select * into a from profile_attributes where id = new.attribute_id;
  if a.id is null or a.status <> 'active' then
    raise exception 'Unknown profile field' using errcode = '22023';
  end if;
  if new.work_identity_id is not null and not omelo_private.omelo_attribute_applies(a.id, new.work_identity_id) then
    raise exception '"%" does not apply to this work identity', a.label using errcode = '22023';
  end if;
  v_opt := coalesce(a.options, '[]'::jsonb);
  case a.data_type::text
    when 'text' then
      if new.value_text is null or length(trim(new.value_text)) = 0 or length(new.value_text) > 300 then
        raise exception '"%" must be text up to 300 characters', a.label using errcode = '22023'; end if;
    when 'long_text' then
      if new.value_text is null or length(new.value_text) > 2000 then
        raise exception '"%" must be text up to 2000 characters', a.label using errcode = '22023'; end if;
    when 'single_select' then
      if new.value_text is null or not v_opt ? new.value_text then
        raise exception 'Choose one of the options for "%"', a.label using errcode = '22023'; end if;
    when 'multi_select' then
      if new.value_json is null or jsonb_typeof(new.value_json) <> 'array' or jsonb_array_length(new.value_json) = 0 then
        raise exception 'Choose at least one option for "%"', a.label using errcode = '22023'; end if;
      for e in select * from jsonb_array_elements(new.value_json) loop
        if jsonb_typeof(e) <> 'string' or not v_opt ? (e #>> '{}') then
          raise exception 'Choose from the listed options for "%"', a.label using errcode = '22023'; end if;
      end loop;
    when 'boolean' then
      if new.value_bool is null then
        raise exception '"%" needs a yes or no', a.label using errcode = '22023'; end if;
    when 'number' then
      if new.value_number is null or new.value_number < 0 or new.value_number > 100000 then
        raise exception '"%" must be a number', a.label using errcode = '22023'; end if;
    when 'years' then
      if new.value_number is null or new.value_number < 0 or new.value_number > 70 then
        raise exception '"%" must be between 0 and 70 years', a.label using errcode = '22023'; end if;
    when 'date' then
      if new.value_date is null then
        raise exception '"%" needs a date', a.label using errcode = '22023'; end if;
    else null;   -- file, location: stored as given
  end case;
  return new;
end;
$$;
revoke execute on function omelo_private.omelo_validate_person_attribute() from public, anon, authenticated;
drop trigger if exists person_attributes_validate on person_attributes;
create trigger person_attributes_validate before insert or update on person_attributes
  for each row execute function omelo_private.omelo_validate_person_attribute();

-- Completeness (server-computed) -------------------------------------------------
create or replace function omelo_private.omelo_identity_completeness(p_identity uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare
  wi work_identities; v_score int := 0; v_missing text[] := '{}';
  v_skills int; v_req int; v_req_done int; v_first_job boolean;
begin
  select * into wi from work_identities where id = p_identity;
  if wi.id is null then return jsonb_build_object('score', 0, 'missing', '[]'::jsonb); end if;

  if wi.profession_id is not null then v_score := v_score + 15; else v_missing := array_append(v_missing, 'profession'); end if;
  if length(coalesce(wi.headline, '')) >= 10 then v_score := v_score + 10; else v_missing := array_append(v_missing, 'headline'); end if;
  if length(coalesce(wi.about, '')) >= 30 then v_score := v_score + 5; else v_missing := array_append(v_missing, 'about'); end if;

  select count(*) into v_skills from person_skills
   where person_id = wi.person_id and (work_identity_id is null or work_identity_id = wi.id);
  v_score := v_score + least(v_skills, 5) * 4;
  if v_skills < 3 then v_missing := array_append(v_missing, 'skills'); end if;

  -- First-job seekers are not penalised for having no experience.
  select exists (select 1 from person_attributes pa join profile_attributes a on a.id = pa.attribute_id
                  where a.slug = 'first-job' and pa.person_id = wi.person_id and pa.value_bool
                    and (pa.work_identity_id is null or pa.work_identity_id = wi.id)) into v_first_job;
  if v_first_job or wi.total_experience_months is not null
     or exists (select 1 from experiences where person_id = wi.person_id
                  and (work_identity_id is null or work_identity_id = wi.id)) then
    v_score := v_score + 15;
  else v_missing := array_append(v_missing, 'experience'); end if;

  if exists (select 1 from person_work_preferences where work_identity_id = wi.id
               and (availability is not null or coalesce(cardinality(work_types), 0) > 0)) then
    v_score := v_score + 10;
  else v_missing := array_append(v_missing, 'preferences'); end if;

  if exists (select 1 from person_location_preferences where work_identity_id = wi.id)
     or exists (select 1 from persons where id = wi.person_id and (location_id is not null or geo is not null)) then
    v_score := v_score + 10;
  else v_missing := array_append(v_missing, 'location'); end if;

  select count(*), count(*) filter (where exists (
           select 1 from person_attributes pa
            where pa.attribute_id = a.id and pa.person_id = wi.person_id
              and (pa.work_identity_id is null or pa.work_identity_id = wi.id)))
    into v_req, v_req_done
    from profile_attributes a
   where a.is_required and omelo_private.omelo_attribute_applies(a.id, wi.id);
  if v_req = 0 then v_score := v_score + 15;
  else
    v_score := v_score + round(15.0 * v_req_done / v_req)::int;
    if v_req_done < v_req then v_missing := array_append(v_missing, 'profile_questions'); end if;
  end if;

  return jsonb_build_object('score', least(v_score, 100), 'missing', to_jsonb(v_missing));
end;
$$;
revoke execute on function omelo_private.omelo_identity_completeness(uuid) from public, anon, authenticated;

create or replace function omelo_private.omelo_recompute_completeness(p_person uuid, p_identity uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare r record;
begin
  for r in select id from work_identities
            where person_id = p_person and (p_identity is null or id = p_identity) loop
    update work_identities
       set completeness_score = (omelo_private.omelo_identity_completeness(r.id)->>'score')::int
     where id = r.id
       and completeness_score is distinct from (omelo_private.omelo_identity_completeness(r.id)->>'score')::int;
  end loop;
end;
$$;
revoke execute on function omelo_private.omelo_recompute_completeness(uuid, uuid) from public, anon, authenticated;

create or replace function omelo_private.omelo_completeness_trigger()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if tg_table_name = 'work_identities' then
    if tg_op = 'INSERT'
       or new.profession_id is distinct from old.profession_id or new.headline is distinct from old.headline
       or new.about is distinct from old.about or new.total_experience_months is distinct from old.total_experience_months then
      perform omelo_private.omelo_recompute_completeness(new.person_id, new.id);
    end if;
    return null;
  end if;
  if tg_op in ('INSERT','UPDATE') then
    perform omelo_private.omelo_recompute_completeness(new.person_id, new.work_identity_id);
  end if;
  if tg_op in ('UPDATE','DELETE') then
    perform omelo_private.omelo_recompute_completeness(old.person_id, old.work_identity_id);
  end if;
  return null;
end;
$$;
revoke execute on function omelo_private.omelo_completeness_trigger() from public, anon, authenticated;

do $$
declare t text;
begin
  foreach t in array array['person_skills','experiences','person_attributes','person_work_preferences',
                           'person_location_preferences','person_professions'] loop
    execute format('drop trigger if exists %I on %I', t || '_completeness', t);
    execute format('create trigger %I after insert or update or delete on %I for each row execute function omelo_private.omelo_completeness_trigger()',
                   t || '_completeness', t);
  end loop;
end;
$$;
drop trigger if exists work_identities_completeness on work_identities;
create trigger work_identities_completeness after insert or update on work_identities
  for each row execute function omelo_private.omelo_completeness_trigger();

-- Fields only Omelo sets; primary / archive go through functions.
create or replace function omelo_private.omelo_guard_identity_fields()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if omelo_private.omelo_is_privileged() then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.completeness_score := 0;
    new.identity_embedding := null;
    if new.status <> 'active' then
      raise exception 'New work identities start active' using errcode = '22023';
    end if;
    return new;
  end if;
  new.completeness_score := old.completeness_score;
  new.identity_embedding := old.identity_embedding;
  if old.is_primary and not new.is_primary then
    raise exception 'Choose another identity as your main one instead' using errcode = '22023';
  end if;
  if new.status is distinct from old.status then
    raise exception 'Use archive / restore to change an identity''s status' using errcode = '22023';
  end if;
  if new.person_id is distinct from old.person_id then
    raise exception 'A work identity cannot change owner' using errcode = '42501';
  end if;
  if length(trim(coalesce(new.label, ''))) not between 2 and 60 then
    raise exception 'Give this identity a name between 2 and 60 characters' using errcode = '22023';
  end if;
  return new;
end;
$$;
drop trigger if exists work_identities_guard_fields on work_identities;
create trigger work_identities_guard_fields before insert or update on work_identities
  for each row execute function omelo_private.omelo_guard_identity_fields();

-- Identity management -------------------------------------------------------------
create or replace function public.omelo_create_work_identity(
  p_label text, p_profession_id uuid default null, p_copy_from uuid default null,
  p_copy text[] default '{skills,preferences,locations}'
) returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_uid uuid := auth.uid(); v_id uuid;
begin
  if v_uid is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  if length(trim(coalesce(p_label, ''))) not between 2 and 60 then
    raise exception 'Give this identity a name between 2 and 60 characters' using errcode = '22023';
  end if;
  if (select count(*) from work_identities where person_id = v_uid) >= 5 then
    raise exception 'You can have up to 5 work identities. Archive or delete one first.' using errcode = '22023';
  end if;
  if exists (select 1 from work_identities where person_id = v_uid and lower(label) = lower(trim(p_label))) then
    raise exception 'You already have an identity called "%"', trim(p_label) using errcode = '22023';
  end if;
  if p_copy_from is not null and not exists (select 1 from work_identities where id = p_copy_from and person_id = v_uid) then
    raise exception 'Work identity not found' using errcode = '42501';
  end if;

  insert into work_identities (person_id, label, profession_id, category_id, profession_source)
  values (v_uid, trim(p_label), p_profession_id, (select category_id from professions where id = p_profession_id), 'user')
  returning id into v_id;

  insert into person_work_preferences (person_id, work_identity_id)
  select v_uid, v_id where p_copy_from is null or not ('preferences' = any(p_copy))
  on conflict (work_identity_id) do nothing;

  if p_copy_from is not null then
    if 'skills' = any(p_copy) then
      insert into person_skills (person_id, work_identity_id, skill_id, proficiency, months_used, last_used_on,
                                 evidence_type, source, is_verified)
      select v_uid, v_id, skill_id, proficiency, months_used, last_used_on, 'self_declared', 'user', false
        from person_skills where work_identity_id = p_copy_from
      on conflict do nothing;
    end if;
    if 'preferences' = any(p_copy) then
      insert into person_work_preferences
      select (jsonb_populate_record(null::person_work_preferences,
                to_jsonb(p) || jsonb_build_object('work_identity_id', v_id, 'updated_at', now()))).*
        from person_work_preferences p where p.work_identity_id = p_copy_from
      on conflict (work_identity_id) do nothing;
      insert into person_work_preferences (person_id, work_identity_id) values (v_uid, v_id)
      on conflict (work_identity_id) do nothing;
    end if;
    if 'locations' = any(p_copy) then
      insert into person_location_preferences (person_id, work_identity_id, kind, location_id, country_code, radius_km, priority)
      select v_uid, v_id, kind, location_id, country_code, radius_km, priority
        from person_location_preferences where work_identity_id = p_copy_from;
    end if;
  end if;
  return v_id;
end;
$$;

create or replace function public.omelo_set_primary_identity(p_identity uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if not exists (select 1 from work_identities where id = p_identity and person_id = auth.uid() and status = 'active') then
    raise exception 'Choose one of your active work identities' using errcode = '22023';
  end if;
  update work_identities set is_primary = true where id = p_identity;
  perform omelo_private.omelo_emit('PrimaryIdentityChanged', 'work_identity', p_identity, null, auth.uid(), '{}'::jsonb);
end;
$$;

create or replace function public.omelo_archive_work_identity(p_identity uuid, p_archive boolean default true)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare wi work_identities; v_next uuid;
begin
  select * into wi from work_identities where id = p_identity and person_id = auth.uid();
  if wi.id is null then raise exception 'Work identity not found' using errcode = '42501'; end if;
  if p_archive then
    if wi.status = 'archived' then return; end if;
    select id into v_next from work_identities
     where person_id = wi.person_id and id <> wi.id and status = 'active'
     order by is_primary desc, updated_at desc limit 1;
    if v_next is null then
      raise exception 'You need at least one active work identity' using errcode = '22023';
    end if;
    if wi.is_primary then
      update work_identities set is_primary = true where id = v_next;
    end if;
    update work_identities set status = 'archived', is_primary = false, discoverability = 'private' where id = wi.id;
    perform omelo_private.omelo_emit('IdentityArchived', 'work_identity', wi.id, null, wi.person_id, '{}'::jsonb);
  else
    if (select count(*) from work_identities where person_id = wi.person_id and status = 'active') >= 5 then
      raise exception 'You already have 5 active work identities' using errcode = '22023';
    end if;
    update work_identities set status = 'active' where id = wi.id;
    perform omelo_private.omelo_emit('IdentityRestored', 'work_identity', wi.id, null, wi.person_id, '{}'::jsonb);
  end if;
end;
$$;

create or replace function public.omelo_delete_work_identity(p_identity uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare wi work_identities; v_next uuid;
begin
  select * into wi from work_identities where id = p_identity and person_id = auth.uid();
  if wi.id is null then raise exception 'Work identity not found' using errcode = '42501'; end if;
  if exists (select 1 from applications where work_identity_id = wi.id) then
    raise exception 'You applied to jobs with this identity, so it is kept as your record. Archive it instead.' using errcode = '22023';
  end if;
  select id into v_next from work_identities
   where person_id = wi.person_id and id <> wi.id and status = 'active'
   order by updated_at desc limit 1;
  if v_next is null then
    raise exception 'You need at least one active work identity' using errcode = '22023';
  end if;
  if wi.is_primary then
    update work_identities set is_primary = true where id = v_next;
  end if;
  perform omelo_private.omelo_emit('IdentityDeleted', 'work_identity', wi.id, null, wi.person_id, '{}'::jsonb);
  delete from work_identities where id = wi.id;
end;
$$;

-- The adaptive profile for one identity: schema + current values + completeness.
create or replace function public.omelo_identity_profile(p_identity uuid default null)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare v_identity uuid; wi work_identities;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  v_identity := coalesce(p_identity, (select id from work_identities where person_id = auth.uid() and is_primary limit 1));
  select * into wi from work_identities where id = v_identity and person_id = auth.uid();
  if wi.id is null then raise exception 'Work identity not found' using errcode = '42501'; end if;

  return jsonb_build_object(
    'identity', jsonb_build_object('id', wi.id, 'label', wi.label, 'profession_id', wi.profession_id,
      'profession', (select name from professions where id = wi.profession_id),
      'headline', wi.headline, 'about', wi.about, 'is_primary', wi.is_primary, 'status', wi.status,
      'discoverability', wi.discoverability, 'total_experience_months', wi.total_experience_months),
    'completeness', omelo_private.omelo_identity_completeness(wi.id),
    'fields', coalesce((
      select jsonb_agg(jsonb_build_object(
               'attribute_id', a.id, 'slug', a.slug, 'label', a.label, 'help_text', a.help_text,
               'data_type', a.data_type, 'options', a.options, 'unit', a.unit, 'is_required', a.is_required,
               'scope', case when a.profession_id is not null then 'profession'
                             when a.category_id is not null then 'category' else 'universal' end,
               'value', (select case a.data_type::text
                                  when 'multi_select' then pa.value_json
                                  when 'boolean' then to_jsonb(pa.value_bool)
                                  when 'number' then to_jsonb(pa.value_number)
                                  when 'years' then to_jsonb(pa.value_number)
                                  when 'date' then to_jsonb(pa.value_date)
                                  when 'location' then coalesce(pa.value_json, to_jsonb(pa.value_text))
                                  else to_jsonb(pa.value_text) end
                           from person_attributes pa
                          where pa.attribute_id = a.id and pa.person_id = wi.person_id
                            and (pa.work_identity_id = wi.id or pa.work_identity_id is null)
                          order by pa.work_identity_id nulls last limit 1))
             order by case when a.profession_id is not null then 0 when a.category_id is not null then 1 else 2 end, a.position)
        from profile_attributes a
       where omelo_private.omelo_attribute_applies(a.id, wi.id)), '[]'::jsonb));
end;
$$;

-- Save adaptive answers: {slug: value, ...}; null removes. Per-field errors.
create or replace function public.omelo_save_identity_profile(p_identity uuid, p_values jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare
  wi work_identities; k text; v jsonb; a profile_attributes;
  v_saved int := 0; v_errors jsonb := '{}'::jsonb; v_universal boolean;
begin
  select * into wi from work_identities where id = p_identity and person_id = auth.uid();
  if wi.id is null then raise exception 'Work identity not found' using errcode = '42501'; end if;
  if p_values is null or jsonb_typeof(p_values) <> 'object' then
    raise exception 'Send the answers as an object' using errcode = '22023';
  end if;

  for k, v in select key, value from jsonb_each(p_values) loop
    select * into a from profile_attributes where slug = k and status = 'active';
    if a.id is null or not omelo_private.omelo_attribute_applies(a.id, wi.id) then
      v_errors := v_errors || jsonb_build_object(k, 'This question does not apply to this identity');
      continue;
    end if;
    -- Universal questions (e.g. "has a smartphone") are shared by all identities.
    v_universal := a.category_id is null and a.profession_id is null;
    begin
      if v is null or jsonb_typeof(v) = 'null' then
        delete from person_attributes
         where person_id = wi.person_id and attribute_id = a.id
           and work_identity_id is not distinct from (case when v_universal then null else wi.id end);
      else
        insert into person_attributes (person_id, work_identity_id, attribute_id, value_text, value_number, value_bool,
                                       value_date, value_json, source)
        values (wi.person_id, case when v_universal then null else wi.id end, a.id,
                case when jsonb_typeof(v) = 'string' then v #>> '{}' end,
                case when jsonb_typeof(v) = 'number' then (v #>> '{}')::numeric end,
                case when jsonb_typeof(v) = 'boolean' then (v #>> '{}')::boolean end,
                case when a.data_type::text = 'date' and jsonb_typeof(v) = 'string' then (v #>> '{}')::date end,
                case when jsonb_typeof(v) in ('array','object') then v end,
                'user')
        on conflict (person_id, work_identity_id, attribute_id) do update
           set value_text = excluded.value_text, value_number = excluded.value_number, value_bool = excluded.value_bool,
               value_date = excluded.value_date, value_json = excluded.value_json;
      end if;
      v_saved := v_saved + 1;
    exception when others then
      v_errors := v_errors || jsonb_build_object(k, sqlerrm);
    end;
  end loop;

  return jsonb_build_object('saved', v_saved, 'errors', v_errors,
                            'completeness', omelo_private.omelo_identity_completeness(wi.id));
end;
$$;

-- Evidence ---------------------------------------------------------------------------
-- What backs each skill on an identity. Visible to the owner and to employers
-- who may see this identity.
create or replace function public.omelo_identity_evidence(p_identity uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare wi work_identities;
begin
  select * into wi from work_identities where id = p_identity;
  if wi.id is null or not (wi.person_id = auth.uid() or omelo_private.omelo_can_view_identity(wi.id)) then
    raise exception 'Work identity not found' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'identity', jsonb_build_object('id', wi.id, 'label', wi.label,
                                   'profession', (select name from professions where id = wi.profession_id),
                                   'completeness', wi.completeness_score),
    'skills', coalesce((
      select jsonb_agg(jsonb_build_object(
        'skill_id', ps.skill_id, 'name', s.name, 'proficiency', ps.proficiency, 'months_used', ps.months_used,
        'verified', ps.is_verified or ps.evidence_type in ('employer_verified','assessment'),
        'evidence', (
          select coalesce(jsonb_agg(ev order by ev->>'rank'), '[]'::jsonb) from (
            select jsonb_build_object('rank', '1', 'type', 'verified_employment', 'verified', true,
                     'label', 'Verified employment: ' || x.title || ' at ' || x.employer_name
                              || coalesce(' (' || round(x.months_duration / 12.0, 1) || ' yr)', '')) as ev
              from experiences x
             where x.person_id = wi.person_id and x.is_verified
               and (x.work_identity_id is null or x.work_identity_id = wi.id)
               and exists (select 1 from profession_skills pk where pk.profession_id = x.profession_id
                             and pk.skill_id = ps.skill_id and pk.importance >= 0.5)
            union all
            select jsonb_build_object('rank', '2', 'type', ps.evidence_type::text, 'verified', true,
                     'label', case ps.evidence_type::text when 'assessment' then 'Passed an assessment'
                                                          else 'Confirmed by an employer' end)
             where ps.evidence_type in ('employer_verified','assessment')
            union all
            select jsonb_build_object('rank', '3', 'type', 'experience', 'verified', false,
                     'label', case when ps.months_used >= 12 then round(ps.months_used / 12.0, 1) || ' years using it'
                                   else ps.months_used || ' months using it' end)
             where ps.months_used is not null and ps.months_used > 0
            union all
            select jsonb_build_object('rank', '4', 'type', 'project', 'verified', false,
                     'label', count(*) || case when count(*) = 1 then ' project' else ' projects' end)
              from project_skills pk join projects p on p.id = pk.project_id
             where pk.skill_id = ps.skill_id and p.person_id = wi.person_id
               and (p.work_identity_id is null or p.work_identity_id = wi.id)
            having count(*) > 0
            union all
            select jsonb_build_object('rank', '5', 'type', 'self_declared', 'verified', false, 'label', 'Added by the worker')
          ) e)
        ) order by (ps.is_verified or ps.evidence_type in ('employer_verified','assessment')) desc, ps.months_used desc nulls last, s.name)
        from person_skills ps join skills s on s.id = ps.skill_id
       where ps.person_id = wi.person_id and (ps.work_identity_id is null or ps.work_identity_id = wi.id)), '[]'::jsonb),
    'verified_employment', coalesce((
      select jsonb_agg(jsonb_build_object('employer', x.employer_name, 'title', x.title, 'started_on', x.started_on,
                                          'ended_on', x.ended_on, 'is_current', x.is_current) order by x.started_on desc)
        from experiences x
       where x.person_id = wi.person_id and x.is_verified
         and (x.work_identity_id is null or x.work_identity_id = wi.id)), '[]'::jsonb),
    'licences', coalesce((
      select jsonb_agg(jsonb_build_object('name', coalesce(l.name, lt.name), 'class', l.license_class,
                                          'verified', l.is_verified, 'expires_on', l.expires_on))
        from person_licenses l left join license_types lt on lt.id = l.license_type_id
       where l.person_id = wi.person_id), '[]'::jsonb),
    'credentials', coalesce((
      select jsonb_agg(jsonb_build_object('name', c.name, 'issuer', c.issuer, 'verified', c.is_verified,
                                          'expires_on', c.expires_on))
        from person_credentials c where c.person_id = wi.person_id), '[]'::jsonb),
    'trust', jsonb_build_object(
      'email_verified', exists (select 1 from verifications where person_id = wi.person_id and type = 'email'
                                  and status = 'verified' and revoked_at is null),
      'phone_verified', exists (select 1 from verifications where person_id = wi.person_id and type = 'phone'
                                  and status = 'verified' and revoked_at is null),
      'identity_verified', exists (select 1 from verifications where person_id = wi.person_id and type = 'identity'
                                     and status = 'verified' and revoked_at is null))
  );
end;
$$;

-- Backfill completeness for existing identities.
do $$
declare r record;
begin
  for r in select id, person_id from work_identities loop
    perform omelo_private.omelo_recompute_completeness(r.person_id, r.id);
  end loop;
end;
$$;

do $$
declare fn text;
begin
  foreach fn in array array[
    'omelo_create_work_identity(text, uuid, uuid, text[])',
    'omelo_set_primary_identity(uuid)',
    'omelo_archive_work_identity(uuid, boolean)',
    'omelo_delete_work_identity(uuid)',
    'omelo_identity_profile(uuid)',
    'omelo_save_identity_profile(uuid, jsonb)',
    'omelo_identity_evidence(uuid)'
  ] loop
    execute format('revoke execute on function public.%s from public, anon', fn);
    execute format('grant execute on function public.%s to authenticated', fn);
  end loop;
end;
$$;
