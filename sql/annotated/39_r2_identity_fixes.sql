-- OMELO 39 (Release 2 fixes, found by tests/api/identity_e2e.py)
--
-- 1. person_attributes.work_identity_id is NOT NULL (every answer belongs to
--    an identity), so "shared" universal answers could not be stored.
--    Universal questions (has a smartphone, first job, ...) are now written
--    to EVERY identity of the person, and a new identity inherits them.
-- 2. A partial unique index allows one primary identity per person; setting
--    the new primary before clearing the old one violated it. Clear first.

create or replace function omelo_private.omelo_make_primary(p_identity uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_person uuid;
begin
  select person_id into v_person from work_identities where id = p_identity;
  update work_identities set is_primary = false where person_id = v_person and is_primary and id <> p_identity;
  update work_identities set is_primary = true where id = p_identity and not is_primary;
end;
$$;
revoke execute on function omelo_private.omelo_make_primary(uuid) from public, anon, authenticated;

create or replace function public.omelo_set_primary_identity(p_identity uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if not exists (select 1 from work_identities where id = p_identity and person_id = auth.uid() and status = 'active') then
    raise exception 'Choose one of your active work identities' using errcode = '22023';
  end if;
  perform omelo_private.omelo_make_primary(p_identity);
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
      perform omelo_private.omelo_make_primary(v_next);
    end if;
    update work_identities set status = 'archived', discoverability = 'private' where id = wi.id;
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
    perform omelo_private.omelo_make_primary(v_next);
  end if;
  perform omelo_private.omelo_emit('IdentityDeleted', 'work_identity', wi.id, null, wi.person_id, '{}'::jsonb);
  delete from work_identities where id = wi.id;
end;
$$;

-- Universal answers go to every identity.
create or replace function public.omelo_save_identity_profile(p_identity uuid, p_values jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare
  wi work_identities; k text; v jsonb; a profile_attributes; t uuid;
  v_saved int := 0; v_errors jsonb := '{}'::jsonb; v_targets uuid[];
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
    if a.category_id is null and a.profession_id is null then
      select array_agg(id) into v_targets from work_identities where person_id = wi.person_id;
    else
      v_targets := array[wi.id];
    end if;
    begin
      foreach t in array v_targets loop
        if v is null or jsonb_typeof(v) = 'null' then
          delete from person_attributes where work_identity_id = t and attribute_id = a.id;
        else
          insert into person_attributes (person_id, work_identity_id, attribute_id, value_text, value_number, value_bool,
                                         value_date, value_json, source)
          values (wi.person_id, t, a.id,
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
      end loop;
      v_saved := v_saved + 1;
    exception when others then
      v_errors := v_errors || jsonb_build_object(k, sqlerrm);
    end;
  end loop;

  return jsonb_build_object('saved', v_saved, 'errors', v_errors,
                            'completeness', omelo_private.omelo_identity_completeness(wi.id));
end;
$$;

-- New identities inherit the person's universal answers.
create or replace function omelo_private.omelo_inherit_universal_answers()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  insert into person_attributes (person_id, work_identity_id, attribute_id, value_text, value_number, value_bool,
                                 value_date, value_json, source)
  select distinct on (pa.attribute_id)
         new.person_id, new.id, pa.attribute_id, pa.value_text, pa.value_number, pa.value_bool,
         pa.value_date, pa.value_json, pa.source
    from person_attributes pa
    join profile_attributes a on a.id = pa.attribute_id and a.category_id is null and a.profession_id is null
   where pa.person_id = new.person_id and pa.work_identity_id <> new.id
   order by pa.attribute_id, pa.created_at desc
  on conflict do nothing;
  return null;
end;
$$;
revoke execute on function omelo_private.omelo_inherit_universal_answers() from public, anon, authenticated;
drop trigger if exists work_identities_inherit_universal on work_identities;
create trigger work_identities_inherit_universal after insert on work_identities
  for each row execute function omelo_private.omelo_inherit_universal_answers();
