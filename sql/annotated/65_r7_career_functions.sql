-- OMELO 65 — Release 7: Career intelligence — functions.
--
--   Current identity -> skills -> experience -> evidence -> career goal -> skill gap ->
--   recommended development -> assessments -> better jobs -> interview -> employment
--
--   omelo_career_path(goal?, identity?)   the whole picture for one goal: where you are, readiness, what is
--                                         missing or weak (by evidence), what to do next, licensing, the market,
--                                         and the best open jobs for the target role (scored by the matcher)
--   omelo_suggest_career_goals(identity?) typical next roles from the current one, with skill overlap
--   omelo_save_career_goal(p)             create/update a goal; optionally generate the development plan
--   omelo_start_skill_assessment(skill)   questions WITHOUT answers (R7-002); resumes an open attempt; cooldown
--   omelo_submit_skill_assessment(...)    graded on the server; a pass adds 'assessment' evidence to the skill
--   omelo_market_insights(profession, country?)   open jobs, pay ranges (min cohort 3), skills employers ask for
--
-- Evidence weights (how much a skill counts toward readiness):
--   employer_verified 1.0 · assessment 0.95 · license/credential 0.9 · experience 0.85 · reference 0.8 ·
--   project 0.75 · self_declared 0.6 — and proficiency beginner/basic halves nothing but marks the skill 'weak'.
--
-- Rollback: drop the functions and the person_skills assessment guard.

create or replace function omelo_private.omelo_evidence_weight(p_evidence evidence_type, p_verified boolean)
returns numeric
language sql immutable
set search_path = public, omelo_private
as $$
  select case when p_verified then 1.0 else case p_evidence
    when 'employer_verified' then 1.0 when 'assessment' then 0.95 when 'license' then 0.9 when 'credential' then 0.9
    when 'experience' then 0.85 when 'reference' then 0.8 when 'project' then 0.75 else 0.6 end end;
$$;

-- R7-003: 'assessment' evidence only through a passed Omelo assessment (the grading function is privileged).
create or replace function omelo_private.omelo_guard_assessment_evidence()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if omelo_private.omelo_is_privileged() then return new; end if;
  if new.evidence_type = 'assessment' and (tg_op = 'INSERT' or old.evidence_type is distinct from 'assessment') then
    raise exception 'Assessment evidence comes from passing an Omelo assessment' using errcode = '42501';
  end if;
  return new;
end;
$$;
drop trigger if exists person_skills_guard_assessment on person_skills;
create trigger person_skills_guard_assessment before insert or update on person_skills
  for each row execute function omelo_private.omelo_guard_assessment_evidence();

create or replace function omelo_private.omelo_resolve_identity(p_identity uuid)
returns uuid
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare v uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if p_identity is not null then
    if not exists (select 1 from work_identities where id = p_identity and person_id = auth.uid()) then
      raise exception 'That work identity is not yours' using errcode = '42501';
    end if;
    return p_identity;
  end if;
  select id into v from work_identities where person_id = auth.uid() and status = 'active'
   order by is_primary desc, created_at limit 1;
  if v is null then raise exception 'Create a work identity first' using errcode = '22023'; end if;
  return v;
end;
$$;

-- Skill picture of one identity against one profession.
create or replace function omelo_private.omelo_skill_gap(p_identity uuid, p_profession uuid)
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  with wi as (select * from work_identities where id = p_identity),
  req as (
    select ps.skill_id, ps.importance, s.name, s.slug
      from profession_skills ps join skills s on s.id = ps.skill_id
     where ps.profession_id = p_profession and s.status = 'active'),
  held as (
    select r.*, best.proficiency, best.evidence_type, best.is_verified,
           coalesce(omelo_private.omelo_evidence_weight(best.evidence_type, best.is_verified), 0) as weight
      from req r
      left join lateral (
        select ps.proficiency, ps.evidence_type, ps.is_verified
          from person_skills ps, wi
         where ps.person_id = wi.person_id and ps.skill_id = r.skill_id
           and (ps.work_identity_id is null or ps.work_identity_id = wi.id)
         order by omelo_private.omelo_evidence_weight(ps.evidence_type, ps.is_verified) desc limit 1) best on true),
  scored as (
    select h.*,
           case when h.proficiency is null then 'missing'
                when h.weight >= 0.85 and h.proficiency not in ('beginner','basic') then 'strong'
                else 'weak' end as status,
           case when h.proficiency is null then 0
                when h.weight >= 0.85 and h.proficiency not in ('beginner','basic') then 1
                else 0.6 * h.weight end as credit
      from held h)
  select jsonb_build_object(
    'readiness', case when coalesce(sum(importance), 0) = 0 then null
                      else round(100 * sum(importance * credit) / sum(importance)) end,
    'skills', coalesce(jsonb_agg(jsonb_build_object(
                'skill_id', skill_id, 'name', name, 'slug', slug, 'importance', importance, 'status', status,
                'proficiency', proficiency, 'evidence', evidence_type, 'verified', coalesce(is_verified, false))
              order by (status = 'missing') desc, (status = 'weak') desc, importance desc), '[]'::jsonb),
    'missing', coalesce(jsonb_agg(name order by importance desc) filter (where status = 'missing'), '[]'::jsonb),
    'weak', coalesce(jsonb_agg(name order by importance desc) filter (where status = 'weak'), '[]'::jsonb),
    'strong', coalesce(jsonb_agg(name order by importance desc) filter (where status = 'strong'), '[]'::jsonb))
  from scored;
$$;

create or replace function public.omelo_suggest_career_goals(p_identity uuid default null)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare v_identity uuid := omelo_private.omelo_resolve_identity(p_identity); wi record; v jsonb;
begin
  select * into wi from work_identities where id = v_identity;
  select coalesce(jsonb_agg(x order by (x->>'rank')::numeric desc), '[]'::jsonb) into v
    from (select jsonb_build_object(
                   'profession_id', p.id, 'name', p.name, 'slug', p.slug,
                   'typical_months', t.median_months,
                   'readiness', (omelo_private.omelo_skill_gap(v_identity, p.id))->'readiness',
                   'missing', (omelo_private.omelo_skill_gap(v_identity, p.id))->'missing',
                   'open_jobs', (select count(*) from jobs j where j.profession_id = p.id and j.status = 'published'),
                   'rank', t.prior_strength * 0.6
                           + coalesce(((omelo_private.omelo_skill_gap(v_identity, p.id))->>'readiness')::numeric, 0) / 100 * 0.4) x
            from profession_transitions t join professions p on p.id = t.to_profession_id
           where t.from_profession_id = wi.profession_id and p.status = 'active'
           order by t.prior_strength desc limit 8) s;
  return jsonb_build_object('work_identity_id', v_identity,
                            'current', (select name from professions where id = wi.profession_id),
                            'suggestions', v);
end;
$$;

create or replace function public.omelo_career_path(p_goal uuid default null, p_identity uuid default null)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare
  g career_goals; v_identity uuid; wi record; pr record; v_gap jsonb; v_home char(2); v_cur char(3);
  v_months int; v_jobs jsonb; v_recs jsonb; v_market jsonb; v_trans record; v_lic jsonb; v_plan jsonb; r jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if p_goal is not null then
    select * into g from career_goals where id = p_goal and person_id = auth.uid();
    if g.id is null then raise exception 'Goal not found' using errcode = '22023'; end if;
    v_identity := omelo_private.omelo_resolve_identity(coalesce(g.work_identity_id, p_identity));
  else
    v_identity := omelo_private.omelo_resolve_identity(p_identity);
    select * into g from career_goals
     where person_id = auth.uid() and status = 'active' and (work_identity_id = v_identity or work_identity_id is null)
     order by (work_identity_id = v_identity) desc nulls last, priority nulls last, created_at desc limit 1;
  end if;
  select * into wi from work_identities where id = v_identity;
  select * into pr from persons where id = auth.uid();
  v_home := coalesce((select current_country from mobility_profiles where person_id = pr.id), pr.country_code);
  v_cur := coalesce((select pay_currency from person_work_preferences where work_identity_id = v_identity),
                    (select default_currency from country_policies where country_code = v_home), 'USD');
  v_months := coalesce((select sum(coalesce(e.months_duration,
                  (extract(year from age(coalesce(e.ended_on, current_date), e.started_on)) * 12
                   + extract(month from age(coalesce(e.ended_on, current_date), e.started_on)))::int))
                  from experiences e where e.person_id = pr.id and e.profession_id = wi.profession_id and e.started_on is not null),
                wi.total_experience_months);

  if g.id is null or g.profession_id is null then
    return jsonb_build_object(
      'work_identity_id', v_identity,
      'current', jsonb_build_object('profession', (select name from professions where id = wi.profession_id),
                                    'experience_months', v_months),
      'goal', case when g.id is not null then to_jsonb(g) end,
      'suggestions', (public.omelo_suggest_career_goals(v_identity))->'suggestions',
      'message', case when g.id is null then 'Choose a career goal to see your path' else 'Choose a target role for this goal' end);
  end if;

  v_gap := omelo_private.omelo_skill_gap(v_identity, g.profession_id);
  select * into v_trans from profession_transitions where from_profession_id = wi.profession_id and to_profession_id = g.profession_id;

  -- what to do next, for each missing or weak skill
  select coalesce(jsonb_agg(jsonb_build_object(
           'skill_id', s->>'skill_id', 'skill', s->>'name', 'status', s->>'status',
           'assessment', (select jsonb_build_object('id', a.id, 'title', a.title, 'questions', a.questions_per_attempt,
                                                     'pass_percent', a.pass_percent,
                                                     'last', (select jsonb_build_object('status', t.status, 'score', t.score_percent,
                                                                                        'at', coalesce(t.completed_at, t.started_at))
                                                                from skill_assessment_attempts t
                                                               where t.assessment_id = a.id and t.person_id = auth.uid()
                                                               order by t.started_at desc limit 1))
                            from skill_assessments a where a.skill_id = (s->>'skill_id')::uuid and a.active),
           'resources', coalesce((select jsonb_agg(jsonb_build_object('id', lr.id, 'kind', lr.kind, 'title', lr.title,
                                                                      'description', lr.description, 'provider', lr.provider,
                                                                      'url', lr.url, 'cost', lr.cost, 'hours', lr.duration_hours)
                                                   order by lr.kind = 'omelo_assessment' desc, lr.duration_hours nulls last)
                                    from learning_resources lr
                                   where lr.skill_id = (s->>'skill_id')::uuid and lr.active
                                     and (cardinality(lr.country_codes) = 0 or v_home = any (lr.country_codes))), '[]'::jsonb))
         order by (s->>'status') = 'missing' desc, (s->>'importance')::numeric desc), '[]'::jsonb)
    into v_recs
    from jsonb_array_elements(v_gap->'skills') s
   where s->>'status' in ('missing','weak');

  -- licensing in the countries the goal targets (or home)
  select coalesce(jsonb_agg(jsonb_build_object('country', lr.country_code, 'name', lr.name, 'description', lr.description,
                                               'url', lr.official_url, 'source', lr.source)), '[]'::jsonb)
    into v_lic
    from license_requirements lr
   where lr.profession_id = g.profession_id
     and lr.country_code = any (case when cardinality(g.target_countries) > 0 then g.target_countries else array[v_home]::char(2)[] end);

  -- the market for the target role (pay only when at least 3 jobs, converted to the worker's currency)
  select jsonb_build_object(
           'open_jobs', count(*),
           'pay_monthly', case when count(m) >= 3 then jsonb_build_object(
                               'currency', v_cur,
                               'p25', round(percentile_cont(0.25) within group (order by m)),
                               'median', round(percentile_cont(0.5) within group (order by m)),
                               'p75', round(percentile_cont(0.75) within group (order by m)),
                               'jobs', count(m)) end)
    into v_market
    from (select omelo_private.omelo_convert(public.omelo_pay_monthly(coalesce(j.pay_max, j.pay_min), j.pay_period),
                                             j.pay_currency, v_cur) m
            from jobs j where j.profession_id = g.profession_id and j.status = 'published'
             and (cardinality(g.target_countries) = 0 or j.country_code = any (g.target_countries) or j.workplace_type = 'remote')) s;

  -- the best open jobs for the target role, scored by the matcher for this identity
  select coalesce(jsonb_agg(x order by (x->>'score')::int desc), '[]'::jsonb) into v_jobs
    from (select jsonb_build_object('job_id', j.id, 'title', j.title, 'company', c.display_name, 'country', j.country_code,
                                    'location_text', j.location_text, 'score', (m->>'score')::int,
                                    'eligible', (m->>'eligible')::boolean,
                                    'eligibility', m->'eligibility'->>'status',
                                    'missing_skills', m->'missing_skills') x
            from (select j.* from jobs j
                   where j.profession_id = g.profession_id and j.status = 'published'
                     and not exists (select 1 from applications a where a.job_id = j.id and a.person_id = auth.uid())
                     and (cardinality(g.target_countries) = 0 or j.country_code = any (g.target_countries) or j.workplace_type = 'remote')
                   order by j.published_at desc limit 20) j
            join companies c on c.id = j.company_id and c.deleted_at is null
            cross join lateral (select omelo_private.omelo_store_match(v_identity, j.id) m) mm
           order by (m->>'score')::int desc limit 5) s;

  select coalesce(jsonb_agg(to_jsonb(i) - 'person_id' order by i.position, i.created_at), '[]'::jsonb) into v_plan
    from career_plan_items i where i.goal_id = g.id;

  return jsonb_build_object(
    'work_identity_id', v_identity,
    'current', jsonb_build_object('profession', (select name from professions where id = wi.profession_id),
                                  'profession_id', wi.profession_id, 'experience_months', v_months,
                                  'verified_employers', (select count(distinct coalesce(x.company_id::text, lower(x.employer_name)))
                                                           from experiences x where x.person_id = pr.id and x.is_verified)),
    'goal', to_jsonb(g) - 'person_id' || jsonb_build_object('profession', (select name from professions where id = g.profession_id)),
    'transition', case when v_trans.from_profession_id is not null then
                    jsonb_build_object('typical_months', v_trans.median_months, 'common', v_trans.prior_strength >= 0.5,
                                       'observed', v_trans.observed_count) end,
    'readiness', v_gap->'readiness',
    'skills', v_gap->'skills',
    'missing', v_gap->'missing',
    'weak', v_gap->'weak',
    'strong', v_gap->'strong',
    'recommended', v_recs,
    'licences', v_lic,
    'market', v_market,
    'jobs', v_jobs,
    'plan', v_plan,
    'note', 'Readiness weighs each skill by how much the role needs it and by the evidence behind it.');
end;
$$;

create or replace function public.omelo_save_career_goal(p jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare g career_goals; v_id uuid := nullif(p->>'id', '')::uuid; v_identity uuid; v_gap jsonb; s jsonb; v_pos int := 0;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  v_identity := omelo_private.omelo_resolve_identity(nullif(p->>'work_identity_id', '')::uuid);
  begin
    if v_id is null then
      insert into career_goals (person_id, work_identity_id, profession_id, goal_text, target_countries,
                                target_pay_amount, target_pay_period, target_currency, target_date, priority, status)
      values (auth.uid(), v_identity, nullif(p->>'profession_id', '')::uuid, nullif(trim(p->>'goal_text'), ''),
              coalesce(array(select upper(x) from jsonb_array_elements_text(p->'target_countries') x), '{}'),
              nullif(p->>'target_pay_amount', '')::numeric, nullif(p->>'target_pay_period', '')::pay_period,
              upper(nullif(p->>'target_currency', '')), nullif(p->>'target_date', '')::date,
              coalesce(nullif(p->>'priority', '')::smallint, 1), 'active')
      returning * into g;
    else
      update career_goals set
        profession_id = case when p ? 'profession_id' then nullif(p->>'profession_id', '')::uuid else profession_id end,
        goal_text = case when p ? 'goal_text' then nullif(trim(p->>'goal_text'), '') else goal_text end,
        target_countries = case when p ? 'target_countries'
                                then coalesce(array(select upper(x) from jsonb_array_elements_text(p->'target_countries') x), '{}')
                                else target_countries end,
        target_pay_amount = case when p ? 'target_pay_amount' then nullif(p->>'target_pay_amount', '')::numeric else target_pay_amount end,
        target_pay_period = case when p ? 'target_pay_period' then nullif(p->>'target_pay_period', '')::pay_period else target_pay_period end,
        target_currency = case when p ? 'target_currency' then upper(nullif(p->>'target_currency', '')) else target_currency end,
        target_date = case when p ? 'target_date' then nullif(p->>'target_date', '')::date else target_date end,
        priority = coalesce(nullif(p->>'priority', '')::smallint, priority),
        status = coalesce(nullif(p->>'status', ''), status),
        work_identity_id = v_identity
       where id = v_id and person_id = auth.uid()
      returning * into g;
      if g.id is null then raise exception 'Goal not found' using errcode = '22023'; end if;
    end if;
  exception
    when check_violation or foreign_key_violation or invalid_text_representation or invalid_datetime_format then
      raise exception 'Check the goal: %', sqlerrm using errcode = '22023';
  end;
  if g.target_currency is not null and not exists (select 1 from currencies where code = g.target_currency) then
    raise exception 'Unknown currency' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(g.target_countries) c where not exists (select 1 from country_policies where country_code = c)) then
    raise exception 'Unknown country in the goal' using errcode = '22023';
  end if;

  -- a development plan from the gap (only for new steps; existing steps are kept)
  if coalesce((p->>'generate_plan')::boolean, false) and g.profession_id is not null then
    v_gap := omelo_private.omelo_skill_gap(v_identity, g.profession_id);
    select coalesce(max(position), 0) into v_pos from career_plan_items where goal_id = g.id;
    for s in select x from jsonb_array_elements(v_gap->'skills') x where x->>'status' in ('missing','weak') loop
      continue when exists (select 1 from career_plan_items i where i.goal_id = g.id and i.skill_id = (s->>'skill_id')::uuid);
      v_pos := v_pos + 1;
      insert into career_plan_items (person_id, goal_id, kind, skill_id, title, position)
      values (auth.uid(), g.id,
              case when exists (select 1 from skill_assessments a where a.skill_id = (s->>'skill_id')::uuid and a.active)
                   then 'assessment' else 'skill' end,
              (s->>'skill_id')::uuid,
              case when s->>'status' = 'missing' then 'Learn ' || (s->>'name') else 'Show evidence of ' || (s->>'name') end,
              v_pos);
    end loop;
  end if;
  perform omelo_private.omelo_emit('CareerGoalSet', 'career_goal', g.id, null, auth.uid(),
                                   jsonb_build_object('profession_id', g.profession_id, 'status', g.status));
  return to_jsonb(g) - 'person_id';
end;
$$;

-- Omelo skill assessments ----------------------------------------------------------------------------
create or replace function public.omelo_start_skill_assessment(p_skill uuid, p_identity uuid default null)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare a skill_assessments; t skill_assessment_attempts; v_identity uuid; v_last skill_assessment_attempts; v_qs uuid[];
begin
  v_identity := omelo_private.omelo_resolve_identity(p_identity);
  select * into a from skill_assessments where skill_id = p_skill and active;
  if a.id is null then raise exception 'There is no Omelo assessment for this skill yet' using errcode = '22023'; end if;
  update skill_assessment_attempts set status = 'expired', completed_at = now()
   where person_id = auth.uid() and assessment_id = a.id and status = 'in_progress' and expires_at <= now();
  select * into t from skill_assessment_attempts
   where person_id = auth.uid() and assessment_id = a.id and status = 'in_progress';
  if t.id is null then
    select * into v_last from skill_assessment_attempts
     where person_id = auth.uid() and assessment_id = a.id and status in ('passed','failed')
     order by completed_at desc limit 1;
    if v_last.id is not null and v_last.completed_at > now() - make_interval(hours => a.cooldown_hours) then
      raise exception 'You can take this assessment again after %',
        to_char(v_last.completed_at + make_interval(hours => a.cooldown_hours), 'DD Mon HH24:MI "UTC"') using errcode = '22023';
    end if;
    select array_agg(id) into v_qs
      from (select id from skill_assessment_questions where assessment_id = a.id and active
             order by random() limit a.questions_per_attempt) q;
    if coalesce(cardinality(v_qs), 0) < 3 then raise exception 'This assessment is not ready yet' using errcode = '22023'; end if;
    insert into skill_assessment_attempts (assessment_id, person_id, work_identity_id, question_ids, expires_at)
    values (a.id, auth.uid(), v_identity, v_qs, now() + make_interval(mins => a.time_limit_minutes))
    returning * into t;
  end if;
  return jsonb_build_object(
    'attempt_id', t.id, 'title', a.title, 'expires_at', t.expires_at, 'pass_percent', a.pass_percent,
    'questions', (select jsonb_agg(jsonb_build_object('id', q.id, 'prompt', q.prompt, 'options', q.options) order by x.ord)
                    from unnest(t.question_ids) with ordinality x(qid, ord)
                    join skill_assessment_questions q on q.id = x.qid));
end;
$$;

create or replace function public.omelo_submit_skill_assessment(p_attempt uuid, p_answers integer[])
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare t skill_assessment_attempts; a skill_assessments; v_correct int := 0; v_total int; v_pct int; v_status text;
        v_review jsonb := '[]'::jsonb; q record; v_ps person_skills;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  select * into t from skill_assessment_attempts where id = p_attempt and person_id = auth.uid() for update;
  if t.id is null then raise exception 'Attempt not found' using errcode = '22023'; end if;
  if t.status <> 'in_progress' then raise exception 'This attempt is already finished' using errcode = '22023'; end if;
  if t.expires_at <= now() then
    update skill_assessment_attempts set status = 'expired', completed_at = now() where id = t.id;
    raise exception 'Time ran out for this attempt; start again' using errcode = '22023';
  end if;
  v_total := cardinality(t.question_ids);
  if p_answers is null or cardinality(p_answers) <> v_total then
    raise exception 'Answer all % questions', v_total using errcode = '22023';
  end if;
  select * into a from skill_assessments where id = t.assessment_id;
  for q in select x.ord, sq.id, sq.answer_index from unnest(t.question_ids) with ordinality x(qid, ord)
             join skill_assessment_questions sq on sq.id = x.qid order by x.ord loop
    if p_answers[q.ord] = q.answer_index then v_correct := v_correct + 1; end if;
    v_review := v_review || jsonb_build_object('question_id', q.id, 'correct', p_answers[q.ord] = q.answer_index);
  end loop;
  v_pct := round(100.0 * v_correct / v_total);
  v_status := case when v_pct >= a.pass_percent then 'passed' else 'failed' end;
  update skill_assessment_attempts set answers = p_answers::smallint[], status = v_status, score_percent = v_pct,
         completed_at = now() where id = t.id;

  if v_status = 'passed' then
    select * into v_ps from person_skills
     where person_id = auth.uid() and skill_id = a.skill_id and work_identity_id is not distinct from t.work_identity_id;
    if v_ps.id is null then
      insert into person_skills (person_id, work_identity_id, skill_id, proficiency, evidence_type, evidence_refs, source)
      values (auth.uid(), t.work_identity_id, a.skill_id, a.proficiency_on_pass, 'assessment',
              jsonb_build_array(jsonb_build_object('kind', 'omelo_assessment', 'attempt_id', t.id, 'score', v_pct, 'at', now())),
              'user');
    else
      update person_skills set
        proficiency = greatest(proficiency, a.proficiency_on_pass),
        evidence_type = case when omelo_private.omelo_evidence_weight(evidence_type, is_verified) < 0.95 then 'assessment'::evidence_type
                             else evidence_type end,
        evidence_refs = coalesce(evidence_refs, '[]'::jsonb)
                        || jsonb_build_array(jsonb_build_object('kind', 'omelo_assessment', 'attempt_id', t.id, 'score', v_pct, 'at', now()))
       where id = v_ps.id;
    end if;
  end if;
  perform omelo_private.omelo_emit(case when v_status = 'passed' then 'SkillAssessmentPassed' else 'SkillAssessmentFailed' end,
                                   'skill_assessment_attempt', t.id, null, auth.uid(),
                                   jsonb_build_object('skill_id', a.skill_id, 'score', v_pct));
  return jsonb_build_object('status', v_status, 'score_percent', v_pct, 'pass_percent', a.pass_percent,
                            'correct', v_correct, 'total', v_total, 'review', v_review,
                            'retry_after', case when v_status = 'failed' then now() + make_interval(hours => a.cooldown_hours) end);
end;
$$;

-- Market insights for a role (aggregates only) ---------------------------------------------------------
create or replace function public.omelo_market_insights(p_profession uuid, p_country text default null, p_currency text default null)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare v_country char(2) := upper(nullif(p_country, '')); v_cur char(3); v jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  v_cur := coalesce(upper(nullif(p_currency, '')),
                    (select default_currency from country_policies where country_code = v_country), 'USD');
  if not exists (select 1 from currencies where code = v_cur) then raise exception 'Unknown currency' using errcode = '22023'; end if;
  with jobs_in as (
    select j.* from jobs j where j.profession_id = p_profession and j.status = 'published'
       and (v_country is null or j.country_code = v_country)),
  pay as (
    select omelo_private.omelo_convert(public.omelo_pay_monthly(coalesce(pay_max, pay_min), pay_period), pay_currency, v_cur) m
      from jobs_in where coalesce(pay_max, pay_min) is not null and pay_disclosed is distinct from false)
  select jsonb_build_object(
    'profession', (select name from professions where id = p_profession),
    'country', v_country,
    'open_jobs', (select count(*) from jobs_in),
    'openings', (select coalesce(sum(openings), 0) from jobs_in),
    'remote_jobs', (select count(*) from jobs_in where workplace_type = 'remote'),
    'sponsored_jobs', (select count(*) from jobs_in where sponsorship in ('yes','case_by_case')),
    'pay_monthly', case when (select count(m) from pay) >= 3 then
                     (select jsonb_build_object('currency', v_cur, 'jobs', count(m),
                                                'p25', round(percentile_cont(0.25) within group (order by m)),
                                                'median', round(percentile_cont(0.5) within group (order by m)),
                                                'p75', round(percentile_cont(0.75) within group (order by m))) from pay) end,
    'skills_in_demand', coalesce((select jsonb_agg(jsonb_build_object('skill_id', s.id, 'name', s.name, 'jobs', n) order by n desc, s.name)
                                    from (select js.skill_id, count(*) n from job_skills js join jobs_in j on j.id = js.job_id
                                           group by js.skill_id order by count(*) desc limit 8) x
                                    join skills s on s.id = x.skill_id), '[]'::jsonb),
    'workers', (select count(*) from work_identities wi where wi.profession_id = p_profession and wi.status = 'active'),
    'note', case when (select count(m) from pay) < 3 then 'Too few jobs with pay to show a reliable range.' end)
  into v;
  return v;
end;
$$;

-- Grants -----------------------------------------------------------------------------------------------
revoke all on function omelo_private.omelo_evidence_weight(evidence_type, boolean) from public, anon, authenticated;
revoke all on function omelo_private.omelo_resolve_identity(uuid) from public, anon, authenticated;
revoke all on function omelo_private.omelo_skill_gap(uuid, uuid) from public, anon, authenticated;

revoke all on function public.omelo_suggest_career_goals(uuid) from public, anon;
revoke all on function public.omelo_career_path(uuid, uuid) from public, anon;
revoke all on function public.omelo_save_career_goal(jsonb) from public, anon;
revoke all on function public.omelo_start_skill_assessment(uuid, uuid) from public, anon;
revoke all on function public.omelo_submit_skill_assessment(uuid, integer[]) from public, anon;
revoke all on function public.omelo_market_insights(uuid, text, text) from public, anon;
grant execute on function public.omelo_suggest_career_goals(uuid) to authenticated;
grant execute on function public.omelo_career_path(uuid, uuid) to authenticated;
grant execute on function public.omelo_save_career_goal(jsonb) to authenticated;
grant execute on function public.omelo_start_skill_assessment(uuid, uuid) to authenticated;
grant execute on function public.omelo_submit_skill_assessment(uuid, integer[]) to authenticated;
grant execute on function public.omelo_market_insights(uuid, text, text) to authenticated;
