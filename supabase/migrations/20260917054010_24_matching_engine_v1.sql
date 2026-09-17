create or replace function omelo_private.omelo_factor(
  p_score numeric, p_status text, p_explanation text
) returns jsonb
language sql immutable
set search_path = public, omelo_private
as $$
  select jsonb_build_object(
    'score', round(greatest(0, least(1, p_score))::numeric, 3),
    'status', p_status,
    'explanation', p_explanation);
$$;

create or replace function omelo_private.omelo_score_match(
  p_work_identity_id uuid,
  p_job_id uuid
) returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private, extensions
as $$
declare
  wi            record;
  pr            record;
  pref          record;
  j             record;
  wp            record;

  f             jsonb := '{}'::jsonb;
  gates         jsonb := '{}'::jsonb;
  gate_failures text[] := '{}';

  v_score numeric; v_status text; v_expl text;

  v_req_total numeric; v_req_have numeric; v_missing text[];
  v_pref_total numeric; v_pref_have numeric;
  v_person_skill_count int; v_depth numeric;

  v_months int; v_geo extensions.geography; v_km numeric; v_radius int;
  v_job_monthly numeric; v_worker_monthly numeric;

  v_total int; v_have int;
  v_prof_name text; v_job_prof_name text;

  k text; w numeric; sum_w numeric := 0; sum_sw numeric := 0;
  v_final int;
  strengths jsonb := '[]'::jsonb; gaps jsonb := '[]'::jsonb; unknowns jsonb := '[]'::jsonb;
begin
  select * into wi from work_identities where id = p_work_identity_id;
  if wi.id is null then raise exception 'work identity not found'; end if;
  select * into pr from persons where id = wi.person_id;
  select * into pref from person_work_preferences where work_identity_id = wi.id;
  select * into j from jobs where id = p_job_id;
  if j.id is null then raise exception 'job not found'; end if;

  select * into wp from weight_profiles
   where is_active and category_id = j.category_id
   order by created_at desc limit 1;
  if wp.id is null then
    select * into wp from weight_profiles where name = 'default' limit 1;
  end if;

  select name into v_job_prof_name from professions where id = j.profession_id;

  gates := gates || jsonb_build_object('job_open',
    case when j.status = 'published' then 'pass' else 'fail' end);
  if j.status <> 'published' then gate_failures := gate_failures || 'job_open'; end if;

  if j.country_code is not null and pr.country_code is not null
     and pr.country_code <> j.country_code
     and not exists (
       select 1 from work_authorizations a
        where a.person_id = pr.id and a.country_code = j.country_code
          and a.status in ('citizen','permanent_resident','work_permit','dependent_visa_work_rights'))
     and coalesce(j.visa_sponsorship, false) = false
     and coalesce(j.accepts_non_residents, false) = false then
    gates := gates || jsonb_build_object('work_authorization', 'fail');
    gate_failures := gate_failures || 'work_authorization';
  else
    gates := gates || jsonb_build_object('work_authorization', 'pass');
  end if;

  if exists (
    select 1 from job_licenses jl
     join person_licenses pl on pl.license_type_id = jl.license_type_id and pl.person_id = pr.id
    where jl.job_id = j.id and jl.requirement_level = 'required'
      and pl.expires_on is not null and pl.expires_on < current_date
      and not exists (select 1 from person_licenses pl2
                       where pl2.person_id = pr.id and pl2.license_type_id = jl.license_type_id
                         and (pl2.expires_on is null or pl2.expires_on >= current_date))) then
    gates := gates || jsonb_build_object('required_licence', 'fail');
    gate_failures := gate_failures || 'required_licence';
  else
    gates := gates || jsonb_build_object('required_licence', 'pass');
  end if;

  if wi.profession_id is null
     and not exists (select 1 from person_professions where work_identity_id = wi.id) then
    f := f || jsonb_build_object('profession_fit',
      omelo_factor(0.5, 'unknown', 'No profession on this work identity yet'));
  elsif wi.profession_id = j.profession_id
     or exists (select 1 from person_professions
                 where work_identity_id = wi.id and profession_id = j.profession_id) then
    f := f || jsonb_build_object('profession_fit',
      omelo_factor(1, 'strong', 'Same profession: ' || coalesce(v_job_prof_name, 'this role')));
  elsif exists (select 1 from experiences e
                 where e.person_id = pr.id and e.profession_id = j.profession_id) then
    f := f || jsonb_build_object('profession_fit',
      omelo_factor(0.75, 'partial', 'Has worked as ' || coalesce(v_job_prof_name, 'this role') || ' before'));
  elsif wi.category_id = j.category_id
     or exists (select 1 from professions p where p.id = wi.profession_id and p.category_id = j.category_id) then
    f := f || jsonb_build_object('profession_fit',
      omelo_factor(0.5, 'partial', 'Related work in the same category'));
  else
    select name into v_prof_name from professions where id = wi.profession_id;
    f := f || jsonb_build_object('profession_fit',
      omelo_factor(0.1, 'gap', 'Different profession' || coalesce(' (' || v_prof_name || ')', '')));
  end if;

  select count(*) into v_person_skill_count
    from person_skills ps
   where ps.person_id = pr.id and (ps.work_identity_id is null or ps.work_identity_id = wi.id);

  with req as (
    select js.skill_id, js.weight, js.requirement_level, s.name
      from job_skills js join skills s on s.id = js.skill_id
     where js.job_id = j.id),
  held as (
    select r.*,
      case
        when exists (select 1 from person_skills ps
                      where ps.person_id = pr.id and ps.skill_id = r.skill_id
                        and (ps.work_identity_id is null or ps.work_identity_id = wi.id)) then 1.0
        when exists (select 1 from person_skills ps
                       join skill_relations sr
                         on sr.kind in ('adjacent_to','substitutable_for')
                        and ((sr.from_skill_id = ps.skill_id and sr.to_skill_id = r.skill_id)
                          or (sr.to_skill_id = ps.skill_id and sr.from_skill_id = r.skill_id))
                      where ps.person_id = pr.id
                        and (ps.work_identity_id is null or ps.work_identity_id = wi.id)) then 0.5
        else 0 end as credit
    from req r)
  select
    coalesce(sum(weight) filter (where requirement_level = 'required'), 0),
    coalesce(sum(weight * credit) filter (where requirement_level = 'required'), 0),
    coalesce(array_agg(name order by weight desc) filter (where requirement_level = 'required' and credit = 0), '{}'),
    coalesce(sum(weight) filter (where requirement_level <> 'required'), 0),
    coalesce(sum(weight * credit) filter (where requirement_level <> 'required'), 0)
  into v_req_total, v_req_have, v_missing, v_pref_total, v_pref_have
  from held;

  if v_req_total = 0 then
    f := f || jsonb_build_object('skill_coverage_required',
      omelo_factor(1, 'strong', 'No required skills listed'));
  elsif v_person_skill_count = 0 then
    f := f || jsonb_build_object('skill_coverage_required',
      omelo_factor(0.5, 'unknown', 'No skills on profile yet — add them to improve this match'));
  else
    v_score := v_req_have / v_req_total;
    f := f || jsonb_build_object('skill_coverage_required', omelo_factor(
      v_score,
      case when v_score >= 0.85 then 'strong' when v_score >= 0.4 then 'partial' else 'gap' end,
      case when cardinality(v_missing) = 0 then 'Has all required skills'
           else 'Missing: ' || array_to_string(v_missing[1:3], ', ') end))
      || jsonb_build_object('_missing_skills', to_jsonb(v_missing));
  end if;

  if v_pref_total = 0 then
    f := f || jsonb_build_object('skill_coverage_preferred',
      omelo_factor(1, 'strong', 'No preferred skills listed'));
  elsif v_person_skill_count = 0 then
    f := f || jsonb_build_object('skill_coverage_preferred',
      omelo_factor(0.5, 'unknown', 'No skills on profile yet'));
  else
    v_score := v_pref_have / v_pref_total;
    f := f || jsonb_build_object('skill_coverage_preferred', omelo_factor(
      v_score, case when v_score >= 0.6 then 'strong' when v_score > 0 then 'partial' else 'gap' end,
      round(v_score * 100)::text || '% of helpful skills'));
  end if;

  select avg(case ps.proficiency
               when 'beginner' then 0.2 when 'basic' then 0.4 when 'intermediate' then 0.6
               when 'advanced' then 0.8 when 'expert' then 1.0 else 0.6 end)
    into v_depth
    from person_skills ps join job_skills js on js.skill_id = ps.skill_id and js.job_id = j.id
   where ps.person_id = pr.id and (ps.work_identity_id is null or ps.work_identity_id = wi.id);
  if v_depth is null then
    f := f || jsonb_build_object('skill_depth', omelo_factor(0.5, 'unknown', 'Skill level not stated'));
  else
    f := f || jsonb_build_object('skill_depth', omelo_factor(v_depth,
      case when v_depth >= 0.7 then 'strong' when v_depth >= 0.4 then 'partial' else 'gap' end,
      'Skill level on matching skills'));
  end if;

  v_months := coalesce(
    (select sum(coalesce(e.months_duration,
                  (extract(year from age(coalesce(e.ended_on, current_date), e.started_on)) * 12
                   + extract(month from age(coalesce(e.ended_on, current_date), e.started_on)))::int))
       from experiences e
      where e.person_id = pr.id and e.profession_id = j.profession_id and e.started_on is not null),
    (select months_experience from person_professions
      where work_identity_id = wi.id and profession_id = j.profession_id limit 1),
    wi.total_experience_months);

  if j.accepts_no_experience or coalesce(j.min_experience_months, 0) = 0 then
    f := f || jsonb_build_object('experience_fit', omelo_factor(1, 'strong', 'No experience required'));
  elsif v_months is null then
    f := f || jsonb_build_object('experience_fit',
      omelo_factor(0.5, 'unknown', 'Experience not stated (needs ' || j.min_experience_months || ' months)'));
  else
    v_score := least(1, v_months::numeric / j.min_experience_months);
    f := f || jsonb_build_object('experience_fit', omelo_factor(v_score,
      case when v_score >= 1 then 'strong' when v_score >= 0.5 then 'partial' else 'gap' end,
      case when v_months >= 12 then round(v_months / 12.0, 1)::text || ' years' else v_months || ' months' end
      || ' relevant experience (needs ' ||
      case when j.min_experience_months >= 12 then round(j.min_experience_months / 12.0, 1)::text || ' years'
           else j.min_experience_months || ' months' end || ')'));
  end if;

  v_geo := coalesce(pr.geo,
    (select l.geo from person_location_preferences plp join locations l on l.id = plp.location_id
      where plp.work_identity_id = wi.id order by plp.priority limit 1));
  v_radius := coalesce(
    (select radius_km from person_location_preferences
      where work_identity_id = wi.id and radius_km is not null order by priority limit 1), 15);

  if j.workplace_type = 'remote' then
    f := f || jsonb_build_object('distance_fit', omelo_factor(1, 'strong', 'Remote work'));
  elsif v_geo is null or j.geo is null then
    f := f || jsonb_build_object('distance_fit', omelo_factor(0.5, 'unknown', 'Location not set'));
  else
    v_km := round((extensions.st_distance(v_geo, j.geo) / 1000)::numeric, 1);
    if v_km <= v_radius then v_score := 1;
    else v_score := greatest(0, 1 - (v_km - v_radius) / (v_radius * 2.0));
    end if;
    if coalesce(pref.willing_to_relocate, false) then v_score := greatest(v_score, 0.6); end if;
    f := f || jsonb_build_object('distance_fit', omelo_factor(v_score,
      case when v_score >= 0.85 then 'strong' when v_score >= 0.4 then 'partial' else 'gap' end,
      v_km || ' km away' || case when v_km > v_radius then ' (beyond ' || v_radius || ' km radius)' else '' end));
  end if;

  v_job_monthly := omelo_pay_monthly(coalesce(j.pay_max, j.pay_min), j.pay_period, j.country_code);
  v_worker_monthly := coalesce(
    omelo_pay_monthly(pref.minimum_pay_amount, pref.minimum_pay_period, pr.country_code),
    omelo_pay_monthly(pref.expected_pay_amount, pref.expected_pay_period, pr.country_code));

  if v_job_monthly is null then
    f := f || jsonb_build_object('pay_fit', omelo_factor(0.5, 'unknown', 'Pay not shown on the job'));
  elsif v_worker_monthly is null then
    f := f || jsonb_build_object('pay_fit', omelo_factor(0.5, 'unknown', 'Pay expectation not set'));
  elsif v_job_monthly >= v_worker_monthly then
    f := f || jsonb_build_object('pay_fit', omelo_factor(1, 'strong', 'Pay meets expectation'));
  else
    v_score := greatest(0, 1 - ((v_worker_monthly - v_job_monthly) / v_worker_monthly) * 2);
    f := f || jsonb_build_object('pay_fit', omelo_factor(v_score,
      case when v_score >= 0.5 then 'partial' else 'gap' end,
      'Pays about ' || round(100 * v_job_monthly / v_worker_monthly) || '% of expectation'));
  end if;

  if coalesce(cardinality(j.shift_types), 0) = 0 then
    f := f || jsonb_build_object('shift_fit', omelo_factor(1, 'strong', 'No fixed shift'));
  elsif pref.work_identity_id is null or coalesce(cardinality(pref.shift_types), 0) = 0 then
    f := f || jsonb_build_object('shift_fit', omelo_factor(0.5, 'unknown', 'Shift preference not set'));
  elsif j.shift_types && pref.shift_types then
    f := f || jsonb_build_object('shift_fit', omelo_factor(1, 'strong', 'Shift matches preference'));
  elsif 'flexible' = any(pref.shift_types) or 'flexible' = any(j.shift_types) then
    f := f || jsonb_build_object('shift_fit', omelo_factor(0.8, 'partial', 'Flexible shifts'));
  else
    f := f || jsonb_build_object('shift_fit', omelo_factor(0, 'gap', 'Shift differs from preference'));
  end if;

  if pref.work_identity_id is null then
    f := f || jsonb_build_object('availability_fit', omelo_factor(0.5, 'unknown', 'Availability not set'));
  elsif pref.availability = 'not_available' then
    f := f || jsonb_build_object('availability_fit', omelo_factor(0, 'gap', 'Not currently available'));
  elsif not j.is_immediate_start then
    f := f || jsonb_build_object('availability_fit', omelo_factor(1, 'strong', 'Available'));
  else
    v_score := case pref.availability
      when 'immediate' then 1 when 'within_7_days' then 1 when 'flexible' then 0.9
      when 'within_15_days' then 0.8 when 'within_30_days' then 0.6
      when 'within_60_days' then 0.4 when 'within_90_days' then 0.2 else 0.5 end;
    f := f || jsonb_build_object('availability_fit', omelo_factor(v_score,
      case when v_score >= 0.8 then 'strong' when v_score >= 0.4 then 'partial' else 'gap' end,
      'Job starts immediately; available ' || replace(coalesce(pref.availability::text, 'unknown'), '_', ' ')));
  end if;

  if pref.work_identity_id is null or coalesce(cardinality(pref.work_types), 0) = 0 then
    f := f || jsonb_build_object('work_type_fit', omelo_factor(0.5, 'unknown', 'Work type preference not set'));
  elsif j.work_type = any(pref.work_types) then
    f := f || jsonb_build_object('work_type_fit', omelo_factor(1, 'strong', 'Wants ' || replace(j.work_type::text, '_', '-') || ' work'));
  else
    f := f || jsonb_build_object('work_type_fit', omelo_factor(0.2, 'gap', 'Prefers a different work type'));
  end if;

  select count(*), count(*) filter (where exists (
           select 1 from person_licenses pl
            where pl.person_id = pr.id and pl.license_type_id = jl.license_type_id
              and (pl.expires_on is null or pl.expires_on >= current_date)))
    into v_total, v_have
    from job_licenses jl where jl.job_id = j.id;
  if v_total = 0 then
    f := f || jsonb_build_object('licence_coverage', omelo_factor(1, 'strong', 'No licence required'));
  elsif v_have = v_total then
    f := f || jsonb_build_object('licence_coverage', omelo_factor(1, 'strong', 'Holds the required licence'));
  elsif not exists (select 1 from person_licenses where person_id = pr.id) then
    f := f || jsonb_build_object('licence_coverage',
      omelo_factor(0.3, 'gap', 'Licence not on profile — needs verification'));
  else
    f := f || jsonb_build_object('licence_coverage', omelo_factor(v_have::numeric / v_total, 'gap',
      'Holds ' || v_have || ' of ' || v_total || ' licences'));
  end if;

  select count(*), count(*) filter (where exists (
           select 1 from person_languages pl where pl.person_id = pr.id and pl.language_code = jl.language_code))
    into v_total, v_have
    from job_languages jl where jl.job_id = j.id and jl.requirement_level = 'required';
  if v_total = 0 then
    f := f || jsonb_build_object('language_fit', omelo_factor(1, 'strong', 'No language requirement'));
  elsif not exists (select 1 from person_languages where person_id = pr.id) then
    f := f || jsonb_build_object('language_fit', omelo_factor(0.5, 'unknown', 'Languages not on profile'));
  else
    f := f || jsonb_build_object('language_fit', omelo_factor(v_have::numeric / v_total,
      case when v_have = v_total then 'strong' else 'gap' end,
      'Speaks ' || v_have || ' of ' || v_total || ' required languages'));
  end if;

  if j.min_education is null or j.min_education = 'none' then
    f := f || jsonb_build_object('education_fit', omelo_factor(1, 'strong', 'No education requirement'));
  elsif pr.highest_education is null or pr.highest_education = 'other' then
    f := f || jsonb_build_object('education_fit', omelo_factor(
      case when j.education_negotiable then 0.7 else 0.5 end, 'unknown', 'Education not stated'));
  elsif pr.highest_education >= j.min_education then
    f := f || jsonb_build_object('education_fit', omelo_factor(1, 'strong', 'Meets education requirement'));
  else
    f := f || jsonb_build_object('education_fit', omelo_factor(
      case when j.education_negotiable then 0.6 else 0 end,
      case when j.education_negotiable then 'partial' else 'gap' end,
      case when j.education_negotiable then 'Below stated education, but the employer is flexible'
           else 'Below required education' end));
  end if;

  v_total := (case when coalesce(pref.needs_accommodation, false) then 1 else 0 end)
           + (case when coalesce(pref.needs_transport, false) then 1 else 0 end);
  if v_total = 0 then
    f := f || jsonb_build_object('benefit_fit', omelo_factor(1, 'strong', 'No specific needs'));
  else
    v_have := (case when coalesce(pref.needs_accommodation, false)
                     and exists (select 1 from job_benefits where job_id = j.id and benefit_type = 'accommodation') then 1 else 0 end)
            + (case when coalesce(pref.needs_transport, false)
                     and exists (select 1 from job_benefits where job_id = j.id and benefit_type = 'transport') then 1 else 0 end);
    f := f || jsonb_build_object('benefit_fit', omelo_factor(v_have::numeric / v_total,
      case when v_have = v_total then 'strong' when v_have > 0 then 'partial' else 'gap' end,
      case when v_have = v_total then 'Provides the transport/accommodation needed'
           else 'Does not provide all needed support' end));
  end if;

  select count(*),
         count(*) filter (where exists (
           select 1 from person_attributes pa
            where pa.work_identity_id = wi.id and pa.attribute_id = r.attribute_id
              and (r.value_bool is null or pa.value_bool = r.value_bool)
              and (r.value_number_min is null or pa.value_number >= r.value_number_min)
              and (r.value_number_max is null or pa.value_number <= r.value_number_max)
              and (r.value_text is null or lower(pa.value_text) = lower(r.value_text))))
    into v_total, v_have
    from job_attribute_requirements r where r.job_id = j.id;
  if v_total = 0 then
    f := f || jsonb_build_object('attribute_fit', omelo_factor(1, 'strong', 'No special requirements'));
  elsif not exists (select 1 from person_attributes where work_identity_id = wi.id) then
    f := f || jsonb_build_object('attribute_fit', omelo_factor(0.5, 'unknown', 'Profile details not filled in'));
  else
    f := f || jsonb_build_object('attribute_fit', omelo_factor(v_have::numeric / v_total,
      case when v_have = v_total then 'strong' when v_have > 0 then 'partial' else 'gap' end,
      'Meets ' || v_have || ' of ' || v_total || ' specific requirements'));
  end if;

  if exists (select 1 from career_goals where work_identity_id = wi.id and profession_id = j.profession_id) then
    f := f || jsonb_build_object('trajectory_fit', omelo_factor(1, 'strong', 'Matches a career goal'));
  else
    f := f || jsonb_build_object('trajectory_fit', omelo_factor(0.5, 'unknown', 'No related career goal'));
  end if;
  if exists (select 1 from follows where person_id = pr.id and target_type = 'company' and target_id = j.company_id) then
    f := f || jsonb_build_object('company_preference', omelo_factor(1, 'strong', 'Follows this employer'));
  else
    f := f || jsonb_build_object('company_preference', omelo_factor(0.5, 'unknown', 'No stated preference'));
  end if;

  for k, w in select key, value::numeric from jsonb_each_text(wp.weights) loop
    if f ? k and w > 0 then
      sum_w  := sum_w + w;
      sum_sw := sum_sw + w * (f -> k ->> 'score')::numeric;
      f := jsonb_set(f, array[k], (f -> k) || jsonb_build_object(
             'weight', w,
             'contribution', round(w * (f -> k ->> 'score')::numeric, 4)));
      case f -> k ->> 'status'
        when 'strong'  then strengths := strengths || jsonb_build_object('factor', k, 'weight', w, 'text', f -> k ->> 'explanation');
        when 'gap'     then gaps      := gaps      || jsonb_build_object('factor', k, 'weight', w, 'text', f -> k ->> 'explanation');
        when 'partial' then gaps      := gaps      || jsonb_build_object('factor', k, 'weight', w, 'text', f -> k ->> 'explanation');
        when 'unknown' then unknowns  := unknowns  || jsonb_build_object('factor', k, 'weight', w, 'text', f -> k ->> 'explanation');
        else null;
      end case;
    end if;
  end loop;

  v_final := case when sum_w = 0 then 50 else round(100 * sum_sw / sum_w) end;

  select coalesce(jsonb_agg(x order by (x->>'weight')::numeric desc), '[]') into strengths from jsonb_array_elements(strengths) x;
  select coalesce(jsonb_agg(x order by (x->>'weight')::numeric desc), '[]') into gaps      from jsonb_array_elements(gaps) x;
  select coalesce(jsonb_agg(x order by (x->>'weight')::numeric desc), '[]') into unknowns  from jsonb_array_elements(unknowns) x;

  return jsonb_build_object(
    'engine_version', 'v1.0',
    'score', v_final,
    'eligible', cardinality(gate_failures) = 0,
    'gate_failures', to_jsonb(gate_failures),
    'gates', gates,
    'weight_profile', wp.name,
    'weight_profile_id', wp.id,
    'factors', f - '_missing_skills',
    'missing_skills', coalesce(f -> '_missing_skills', '[]'::jsonb),
    'strengths', strengths,
    'gaps', gaps,
    'unknowns', unknowns,
    'computed_at', now());
end;
$$;

revoke execute on function omelo_private.omelo_score_match(uuid, uuid) from public, anon, authenticated;
revoke execute on function omelo_private.omelo_factor(numeric, text, text) from public, anon, authenticated;

create or replace function omelo_private.omelo_store_match(
  p_work_identity_id uuid, p_job_id uuid
) returns jsonb
language plpgsql volatile security definer
set search_path = public, omelo_private
as $$
declare r jsonb; v_person uuid;
begin
  r := omelo_score_match(p_work_identity_id, p_job_id);
  select person_id into v_person from work_identities where id = p_work_identity_id;

  insert into matches (person_id, work_identity_id, job_id, score, eligible, gate_failures,
                       feature_vector, weight_profile_id, engine_version, computed_at)
  values (v_person, p_work_identity_id, p_job_id, (r->>'score')::int, (r->>'eligible')::boolean,
          array(select jsonb_array_elements_text(r->'gate_failures')),
          r, (r->>'weight_profile_id')::uuid, r->>'engine_version', now())
  on conflict (person_id, job_id, engine_version) do update
     set score = excluded.score, eligible = excluded.eligible,
         gate_failures = excluded.gate_failures, feature_vector = excluded.feature_vector,
         weight_profile_id = excluded.weight_profile_id, work_identity_id = excluded.work_identity_id,
         computed_at = now();
  return r;
end;
$$;
revoke execute on function omelo_private.omelo_store_match(uuid, uuid) from public, anon, authenticated;

create or replace function omelo_private.omelo_score_application()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare r jsonb;
begin
  begin
    r := omelo_store_match(new.work_identity_id, new.job_id);
    new.match_score := (r->>'score')::int;
  exception when others then
    new.match_score := null;
  end;
  return new;
end;
$$;
revoke execute on function omelo_private.omelo_score_application() from public, anon, authenticated;

drop trigger if exists applications_score on applications;
create trigger applications_score
  before insert on applications
  for each row execute function omelo_private.omelo_score_application();

create or replace function public.omelo_rank_applicants(p_job_id uuid)
returns table (application_id uuid, score int, eligible boolean)
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare a record; r jsonb;
begin
  if not omelo_private.omelo_can_access_job(p_job_id) then
    raise exception 'Not authorised for this job' using errcode = '42501';
  end if;
  for a in select id, work_identity_id from applications where job_id = p_job_id loop
    r := omelo_private.omelo_store_match(a.work_identity_id, p_job_id);
    update applications set match_score = (r->>'score')::int where id = a.id;
    application_id := a.id; score := (r->>'score')::int; eligible := (r->>'eligible')::boolean;
    return next;
  end loop;
end;
$$;

create or replace function public.omelo_my_match(p_job_id uuid, p_work_identity_id uuid default null)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_identity uuid;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  v_identity := coalesce(p_work_identity_id,
    (select id from work_identities where person_id = auth.uid() and is_primary limit 1));
  if not exists (select 1 from work_identities where id = v_identity and person_id = auth.uid()) then
    raise exception 'Not your work identity' using errcode = '42501';
  end if;
  if not exists (select 1 from jobs where id = p_job_id and status = 'published') then
    raise exception 'Job not available';
  end if;
  return omelo_private.omelo_store_match(v_identity, p_job_id);
end;
$$;

create or replace function public.omelo_recommend_jobs(
  p_lat double precision, p_lng double precision,
  p_radius_km integer default 25, p_limit integer default 20,
  p_work_identity_id uuid default null
) returns table (job_id uuid, score int, eligible boolean, distance_km numeric,
                 strengths jsonb, gaps jsonb)
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_identity uuid; c record; r jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  v_identity := coalesce(p_work_identity_id,
    (select id from work_identities where person_id = auth.uid() and is_primary limit 1));
  if not exists (select 1 from work_identities where id = v_identity and person_id = auth.uid()) then
    raise exception 'Not your work identity' using errcode = '42501';
  end if;

  for c in
    select n.job_id as jid, n.distance_km as km
      from public.omelo_nearby_jobs(p_lat, p_lng, p_radius_km, null, null, 80) n
  loop
    r := omelo_private.omelo_store_match(v_identity, c.jid);
    job_id := c.jid; score := (r->>'score')::int; eligible := (r->>'eligible')::boolean;
    distance_km := c.km; strengths := r->'strengths'; gaps := r->'gaps';
    return next;
  end loop;
end;
$$;

revoke execute on function public.omelo_rank_applicants(uuid) from public, anon;
revoke execute on function public.omelo_my_match(uuid, uuid) from public, anon;
revoke execute on function public.omelo_recommend_jobs(double precision, double precision, integer, integer, uuid) from public, anon;
grant execute on function public.omelo_rank_applicants(uuid) to authenticated;
grant execute on function public.omelo_my_match(uuid, uuid) to authenticated;
grant execute on function public.omelo_recommend_jobs(double precision, double precision, integer, integer, uuid) to authenticated;