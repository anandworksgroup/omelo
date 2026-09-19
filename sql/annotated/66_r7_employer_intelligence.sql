-- OMELO 66 — Release 7: Employer intelligence — where is hiring for this job stuck?
--
--   Job -> talent supply -> available workers -> compensation -> match quality ->
--   application funnel -> interview funnel -> offer funnel -> hiring difficulty
--
--   omelo_job_intelligence(job)            one job, end to end, with a bottleneck and plain recommendations
--   omelo_company_intelligence(company)    every open job of a company ranked by difficulty
--
-- Rules:
--   * aggregates only — never a list of people (R7-004)
--   * market pay needs >= 3 comparable jobs; worker expectations need >= 5 workers (R7-005)
--   * all pay compared in the job's currency, with the rate's provenance from R6
--   * only the job's hiring team (or the agency working a job order for it) may see it
--
-- Rollback: drop the two functions and omelo_private.omelo_percentiles.

create or replace function omelo_private.omelo_percentiles(p_values numeric[], p_min integer)
returns jsonb
language sql immutable
set search_path = pg_catalog
as $$
  select case when coalesce(cardinality(array_remove(p_values, null)), 0) < p_min then null else (
    select jsonb_build_object('n', count(v),
                              'p25', round(percentile_cont(0.25) within group (order by v)::numeric),
                              'median', round(percentile_cont(0.5) within group (order by v)::numeric),
                              'p75', round(percentile_cont(0.75) within group (order by v)::numeric))
      from unnest(p_values) v where v is not null) end;
$$;

create or replace function public.omelo_job_intelligence(p_job uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private, extensions
as $$
declare
  j jobs; v_cur char(3); v_job_monthly numeric; v_days int; v_open int;
  v_supply jsonb; v_market jsonb; v_expect jsonb; v_share_ok numeric; v_comp jsonb;
  v_quality jsonb; v_funnel jsonb; v_int jsonb; v_off jsonb; v_timing jsonb;
  v_identities int; v_available int; v_nearby int; v_relocating int; v_competing int;
  v_scored int; v_eligible int; v_good int;
  v_score numeric := 0; v_label text; v_stage text; v_why text; v_recs jsonb := '[]'::jsonb;
  c_applied int; c_viewed int; c_short int; c_int int; c_off int; c_hired int; c_imp int;
  o_sent int; o_acc int; o_dec int;
begin
  select * into j from jobs where id = p_job;
  if j.id is null then raise exception 'Job not found' using errcode = '22023'; end if;
  if not (omelo_private.omelo_can_access_job(j.id)
          or exists (select 1 from job_orders jo join company_members cm on cm.company_id = jo.agency_id
                      where (jo.job_id = j.id or jo.client_job_id = j.id) and cm.person_id = auth.uid() and cm.is_active)) then
    raise exception 'Only the hiring team can see this job''s intelligence' using errcode = '42501';
  end if;
  v_cur := coalesce(j.pay_currency, (select default_currency from country_policies where country_code = j.country_code), 'USD');
  v_job_monthly := public.omelo_pay_monthly(coalesce(j.pay_max, j.pay_min), j.pay_period);
  v_days := case when j.published_at is not null then greatest(0, (current_date - j.published_at::date)) end;
  v_open := greatest(1, coalesce(j.openings, 1) - (select count(*) from applications a where a.job_id = j.id and a.state = 'hired'));

  -- 1. Talent supply ------------------------------------------------------------------------------------
  select count(*),
         count(*) filter (where pwp.availability in ('immediate','within_7_days','flexible')),
         count(*) filter (where j.workplace_type <> 'remote' and j.geo is not null and p.geo is not null
                            and st_dwithin(p.geo, j.geo, 25000)),
         count(*) filter (where j.workplace_type <> 'remote' and j.country_code is not null
                            and coalesce(mp.current_country, p.country_code) is distinct from j.country_code
                            and coalesce(mp.open_to_relocation, false)
                            and (cardinality(mp.preferred_countries) + cardinality(mp.countries_willing_to_work) = 0
                                 or j.country_code = any (mp.preferred_countries || mp.countries_willing_to_work)))
    into v_identities, v_available, v_nearby, v_relocating
    from work_identities wi
    join persons p on p.id = wi.person_id and p.deleted_at is null
    left join person_work_preferences pwp on pwp.work_identity_id = wi.id
    left join mobility_profiles mp on mp.person_id = wi.person_id
   where wi.status = 'active' and wi.profession_id = j.profession_id
     and (j.workplace_type = 'remote' or j.country_code is null
          or coalesce(mp.current_country, p.country_code) is null
          or coalesce(mp.current_country, p.country_code) = j.country_code
          or coalesce(mp.open_to_relocation, false));
  select count(*) into v_competing from jobs o
   where o.profession_id = j.profession_id and o.status = 'published' and o.id <> j.id
     and (j.country_code is null or o.country_code = j.country_code);
  v_supply := jsonb_build_object(
    'workers_in_profession', v_identities, 'available_soon', v_available,
    'within_25_km', case when j.workplace_type <> 'remote' then v_nearby end,
    'open_to_relocating_here', v_relocating, 'competing_jobs', v_competing,
    'workers_per_opening', round(v_available::numeric / v_open, 1),
    'workers_per_competing_job', round(v_identities::numeric / greatest(1, v_competing + 1), 1));

  -- 2. Compensation (job currency) -------------------------------------------------------------------------
  select omelo_private.omelo_percentiles(array_agg(omelo_private.omelo_convert(
           public.omelo_pay_monthly(coalesce(o.pay_max, o.pay_min), o.pay_period), o.pay_currency, v_cur)), 3)
    into v_market
    from jobs o
   where o.profession_id = j.profession_id and o.status = 'published' and o.id <> j.id
     and coalesce(o.pay_max, o.pay_min) is not null and o.pay_disclosed is distinct from false
     and (j.country_code is null or o.country_code = j.country_code);
  select omelo_private.omelo_percentiles(array_agg(omelo_private.omelo_convert(
           public.omelo_pay_monthly(coalesce(pwp.expected_pay_amount, pwp.minimum_pay_amount),
                                    coalesce(pwp.expected_pay_period, pwp.minimum_pay_period)), pwp.pay_currency, v_cur)), 5),
         case when count(pwp.minimum_pay_amount) >= 5 and v_job_monthly is not null then
           round(100.0 * count(*) filter (where omelo_private.omelo_convert(
             public.omelo_pay_monthly(pwp.minimum_pay_amount, pwp.minimum_pay_period), pwp.pay_currency, v_cur) <= v_job_monthly)
             / count(pwp.minimum_pay_amount)) end
    into v_expect, v_share_ok
    from work_identities wi
    join person_work_preferences pwp on pwp.work_identity_id = wi.id
   where wi.status = 'active' and wi.profession_id = j.profession_id and pwp.pay_currency is not null;
  v_comp := jsonb_build_object(
    'currency', v_cur, 'job_monthly', round(v_job_monthly),
    'market_jobs_monthly', v_market, 'worker_expectations_monthly', v_expect,
    'workers_whose_minimum_it_meets_pct', v_share_ok,
    'position', case when v_job_monthly is null then 'not_disclosed'
                     when coalesce(v_market->>'median', v_expect->>'median') is null then 'unknown'
                     when v_job_monthly < 0.9 * coalesce((v_market->>'median')::numeric, (v_expect->>'median')::numeric) then 'below_market'
                     when v_job_monthly > 1.1 * coalesce((v_market->>'median')::numeric, (v_expect->>'median')::numeric) then 'above_market'
                     else 'at_market' end,
    'rate_source', case when exists (select 1 from jobs o where o.profession_id = j.profession_id and o.status = 'published'
                                        and o.pay_currency is distinct from v_cur)
                        then (omelo_private.omelo_fx_rate('USD', v_cur))->>'source' end);

  -- 3. Match quality (stored matches for this job) ------------------------------------------------------------
  select count(*), count(*) filter (where eligible), count(*) filter (where eligible and score >= 70)
    into v_scored, v_eligible, v_good from matches where job_id = j.id;
  v_quality := jsonb_build_object(
    'scored', v_scored, 'eligible', v_eligible, 'strong_matches', v_good,
    'buckets', (select jsonb_build_object('80_plus', count(*) filter (where score >= 80),
                                          '60_79', count(*) filter (where score between 60 and 79),
                                          'under_60', count(*) filter (where score < 60))
                  from matches where job_id = j.id and eligible),
    'top_missing_skills', coalesce((select jsonb_agg(jsonb_build_object('skill', k, 'candidates', n) order by n desc)
                                      from (select k, count(*) n from matches m, jsonb_array_elements_text(m.feature_vector->'missing_skills') k
                                             where m.job_id = j.id group by k order by count(*) desc limit 5) x), '[]'::jsonb),
    'gate_failures', coalesce((select jsonb_object_agg(k, n)
                                 from (select k, count(*) n from matches m, unnest(m.gate_failures) k
                                        where m.job_id = j.id group by k) x), '{}'::jsonb));

  -- 4. Funnels -----------------------------------------------------------------------------------------------
  begin
    v_funnel := public.omelo_job_funnel(j.id);
  exception when insufficient_privilege then
    v_funnel := '{}'::jsonb;   -- an agency working the order sees the rest, not the client's funnel
  end;
  c_imp := coalesce((v_funnel->>'impressions')::int, 0);
  c_applied := coalesce((v_funnel->>'applied')::int, 0); c_viewed := coalesce((v_funnel->>'viewed')::int, 0);
  c_short := coalesce((v_funnel->>'shortlisted')::int, 0); c_int := coalesce((v_funnel->>'interviewed')::int, 0);
  c_off := coalesce((v_funnel->>'offered')::int, 0); c_hired := coalesce((v_funnel->>'hired')::int, 0);
  select jsonb_build_object('scheduled', count(*),
                            'completed', count(*) filter (where status = 'completed'),
                            'cancelled', count(*) filter (where status = 'cancelled'),
                            'no_show_candidate', count(*) filter (where status = 'no_show_candidate'),
                            'no_show_employer', count(*) filter (where status = 'no_show_employer'),
                            'upcoming', count(*) filter (where status in ('scheduled','rescheduled') and scheduled_at > now()))
    into v_int from interviews where job_id = j.id;
  select count(*) filter (where status <> 'draft'), count(*) filter (where status = 'accepted'),
         count(*) filter (where status = 'declined')
    into o_sent, o_acc, o_dec from offers where job_id = j.id;
  v_off := jsonb_build_object('sent', o_sent, 'accepted', o_acc, 'declined', o_dec,
                              'expired', (select count(*) from offers where job_id = j.id and status = 'expired'),
                              'withdrawn', (select count(*) from offers where job_id = j.id and status = 'withdrawn'),
                              'decline_reasons', coalesce((select jsonb_agg(distinct decline_reason) from offers
                                                            where job_id = j.id and decline_reason is not null), '[]'::jsonb));
  select jsonb_build_object(
           'days_open', v_days,
           'hours_to_first_application', (select round(extract(epoch from min(a.applied_at) - j.published_at) / 3600)
                                            from applications a where a.job_id = j.id),
           'median_hours_to_first_view', (select round(percentile_cont(0.5) within group
                                                  (order by extract(epoch from a.first_viewed_at - a.applied_at) / 3600)::numeric)
                                            from applications a where a.job_id = j.id and a.first_viewed_at is not null),
           'unreviewed_applications', (select count(*) from applications a where a.job_id = j.id and a.first_viewed_at is null
                                         and a.state not in ('withdrawn','rejected','hired')))
    into v_timing;

  -- 5. Difficulty and bottleneck ----------------------------------------------------------------------------------
  -- each part adds up to 25 points of difficulty
  v_score := v_score + case when v_available >= 10 * v_open then 0 when v_available >= 3 * v_open then 8
                            when v_available >= v_open then 16 else 25 end;
  v_score := v_score + case v_comp->>'position' when 'below_market' then 25 when 'not_disclosed' then 12
                                                 when 'unknown' then 8 when 'at_market' then 5 else 0 end;
  v_score := v_score + case when v_scored = 0 then 12 when v_good = 0 then 25
                            when v_good < 3 * v_open then 12 else 0 end;
  v_score := v_score + case when c_applied = 0 and coalesce(v_days, 0) >= 7 then 25
                            when c_applied > 0 and c_hired = 0 and coalesce(v_days, 0) >= 30 then 18
                            when c_applied = 0 then 10 else 0 end;
  v_label := case when v_score < 25 then 'easy' when v_score < 50 then 'moderate' when v_score < 75 then 'hard' else 'very_hard' end;

  if v_available < v_open and v_relocating = 0 then
    v_stage := 'supply'; v_why := 'Few available workers in this profession for the openings.';
  elsif v_comp->>'position' = 'below_market' then
    v_stage := 'compensation'; v_why := 'Pay is below comparable jobs and worker expectations.';
  elsif c_imp > 0 and c_applied::numeric / c_imp < 0.02 then
    v_stage := 'attraction'; v_why := 'Many workers see the job but very few apply.';
  elsif c_applied = 0 and coalesce(v_days, 0) >= 3 then
    v_stage := 'reach'; v_why := 'The job has not reached enough workers yet.';
  elsif c_applied > 0 and (v_timing->>'unreviewed_applications')::int > greatest(3, c_applied / 2) then
    v_stage := 'screening'; v_why := 'Applications are waiting to be reviewed.';
  elsif c_viewed > 0 and c_short = 0 and v_scored > 0 and v_good = 0 then
    v_stage := 'requirements'; v_why := 'Applicants do not meet the requirements as written.';
  elsif c_short > 0 and c_int = 0 then
    v_stage := 'interview_scheduling'; v_why := 'Shortlisted candidates are not being interviewed.';
  elsif c_int > 0 and c_off = 0 and (v_int->>'completed')::int > 0 then
    v_stage := 'selection'; v_why := 'Interviews happen but no offers are made.';
  elsif o_sent > 0 and o_acc = 0 and o_dec > 0 then
    v_stage := 'offer_acceptance'; v_why := 'Offers are being declined.';
  elsif c_hired >= v_open then
    v_stage := 'filled'; v_why := 'All openings are filled.';
  else
    v_stage := 'none'; v_why := 'No clear bottleneck yet.';
  end if;

  if v_comp->>'position' = 'below_market' then
    v_recs := v_recs || to_jsonb('Pay is below the market median (' || v_cur || ' ' || coalesce(v_market->>'median', v_expect->>'median')
                                 || ' a month). Consider raising it or adding benefits.'::text);
  elsif v_comp->>'position' = 'not_disclosed' then
    v_recs := v_recs || to_jsonb('Show the pay: jobs with pay attract more applicants.'::text);
  end if;
  if v_available < v_open and v_relocating > 0 and not coalesce(j.relocation_support, false) then
    v_recs := v_recs || to_jsonb(v_relocating || ' workers elsewhere would relocate here; relocation support would help reach them.');
  end if;
  if v_available < v_open and j.sponsorship = 'no' and j.workplace_type <> 'remote' then
    v_recs := v_recs || to_jsonb('Local supply is short; considering sponsorship or remote work widens the pool.'::text);
  end if;
  if jsonb_array_length(v_quality->'top_missing_skills') > 0 and v_good < v_open then
    v_recs := v_recs || to_jsonb('Most candidates lack ' || (v_quality->'top_missing_skills'->0->>'skill')
                                 || '; consider training for it or making it preferred rather than required.');
  end if;
  if (v_timing->>'unreviewed_applications')::int > 0 then
    v_recs := v_recs || to_jsonb((v_timing->>'unreviewed_applications') || ' applications have not been opened yet.');
  end if;
  if v_stage = 'reach' or (c_applied < v_open and v_scored > 0) then
    v_recs := v_recs || to_jsonb('Invite strong matches from talent search to apply.'::text);
  end if;
  if c_short > 0 and c_int = 0 then
    v_recs := v_recs || to_jsonb('Schedule interviews with shortlisted candidates.'::text);
  end if;
  if o_dec > 0 then
    v_recs := v_recs || to_jsonb('Review why offers were declined and adjust the offer.'::text);
  end if;

  return jsonb_build_object(
    'job_id', j.id, 'title', j.title, 'status', j.status, 'openings', j.openings, 'open_openings', v_open,
    'supply', v_supply, 'compensation', v_comp, 'match_quality', v_quality,
    'application_funnel', jsonb_build_object('impressions', c_imp, 'applied', c_applied, 'viewed', c_viewed,
                                             'shortlisted', c_short, 'interviewed', c_int, 'offered', c_off, 'hired', c_hired),
    'interview_funnel', v_int, 'offer_funnel', v_off, 'timing', v_timing,
    'difficulty', jsonb_build_object('score', round(v_score), 'label', v_label),
    'bottleneck', jsonb_build_object('stage', v_stage, 'explanation', v_why),
    'recommendations', v_recs,
    'computed_at', now(),
    'note', 'Counts are aggregates over Omelo. Pay ranges need at least 3 jobs; worker expectations need at least 5 workers.');
end;
$$;

create or replace function public.omelo_company_intelligence(p_company uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare v jsonb;
begin
  if not omelo_private.omelo_has_company_role(p_company, array['owner','admin','recruiter','hiring_manager','hr']::company_role[]) then
    raise exception 'Only the hiring team can see this' using errcode = '42501';
  end if;
  select coalesce(jsonb_agg(x order by (x->'difficulty'->>'score')::int desc), '[]'::jsonb) into v
    from (select jsonb_build_object(
                   'job_id', i->>'job_id', 'title', i->>'title', 'difficulty', i->'difficulty', 'bottleneck', i->'bottleneck',
                   'applied', i->'application_funnel'->'applied', 'hired', i->'application_funnel'->'hired',
                   'days_open', i->'timing'->'days_open', 'pay_position', i->'compensation'->>'position',
                   'top_recommendation', i->'recommendations'->0) x
            from (select public.omelo_job_intelligence(j.id) i
                    from jobs j where j.company_id = p_company and j.status = 'published'
                   order by j.published_at desc limit 50) s) t;
  return jsonb_build_object(
    'jobs', v,
    'summary', jsonb_build_object(
      'open_jobs', jsonb_array_length(v),
      'hard_or_very_hard', (select count(*) from jsonb_array_elements(v) x where x->'difficulty'->>'label' in ('hard','very_hard')),
      'bottlenecks', coalesce((select jsonb_object_agg(stage, n) from (select x->'bottleneck'->>'stage' stage, count(*) n
                                                                         from jsonb_array_elements(v) x group by 1) b), '{}'::jsonb)));
end;
$$;

revoke all on function omelo_private.omelo_percentiles(numeric[], integer) from public, anon, authenticated;
revoke all on function public.omelo_job_intelligence(uuid) from public, anon;
revoke all on function public.omelo_company_intelligence(uuid) from public, anon;
grant execute on function public.omelo_job_intelligence(uuid) to authenticated;
grant execute on function public.omelo_company_intelligence(uuid) to authenticated;
