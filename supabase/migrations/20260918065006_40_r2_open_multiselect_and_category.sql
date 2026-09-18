-- OMELO 40 (Release 2 follow-ups, found while building the worker app)
--
-- 1. A multi_select question with no listed options (e.g. "Routes / areas you
--    know well") could never be answered: every value had to be one of the
--    options. Open multi_selects now accept short free-text items
--    (1-80 characters each, at most 20, no duplicates).
-- 2. work_identities.category_id decides which profile questions apply. A
--    client could set it to any category, independent of the profession.
--    For non-privileged writers it is now always derived from the profession
--    (kept as-is when the identity has no profession).

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
      if jsonb_array_length(v_opt) = 0 then
        -- Open list: short free-text items.
        if jsonb_array_length(new.value_json) > 20 then
          raise exception 'Add at most 20 items for "%"', a.label using errcode = '22023'; end if;
        if (select count(distinct lower(trim(x))) from jsonb_array_elements_text(new.value_json) x)
           <> jsonb_array_length(new.value_json) then
          raise exception 'Remove repeated items from "%"', a.label using errcode = '22023'; end if;
        for e in select * from jsonb_array_elements(new.value_json) loop
          if jsonb_typeof(e) <> 'string' or length(trim(e #>> '{}')) not between 1 and 80 then
            raise exception 'Each item in "%" must be 1 to 80 characters', a.label using errcode = '22023'; end if;
        end loop;
      else
        for e in select * from jsonb_array_elements(new.value_json) loop
          if jsonb_typeof(e) <> 'string' or not v_opt ? (e #>> '{}') then
            raise exception 'Choose from the listed options for "%"', a.label using errcode = '22023'; end if;
        end loop;
      end if;
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

create or replace function omelo_private.omelo_guard_identity_fields()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if omelo_private.omelo_is_privileged() then
    return new;
  end if;
  -- category follows the profession
  if new.profession_id is not null then
    new.category_id := (select category_id from professions where id = new.profession_id);
  elsif tg_op = 'UPDATE' then
    new.category_id := old.category_id;
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
