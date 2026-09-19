-- OMELO 60 — Release 6: matcher v1.2, global talent search, hiring-side eligibility wording.
--
-- Matcher v1.2 (omelo_score_match, patched in place like 47 and 55):
--   * the work-authorization gate now uses omelo_eligibility: only "not eligible" (a hard blocker)
--     fails it; "potentially eligible" never rejects anyone
--   * pay fit compares in one currency (the worker's expectation converted to the job's currency)
--   * distance: someone open to relocating to the job's country is not penalised for distance
--   * new factors outside the weight profile: mobility_fit (0.06: relocation, remote time zones)
--     and eligibility_fit (0.08, only when it matters: another country or something missing)
--   * the result carries `eligibility`
-- Talent search (omelo_talent_search_core): filters eligibility / open_to_relocation / language /
--   current_country; relocators are not cut by the radius; the work-authorization filter respects a
--   worker's private setting; cards carry the eligibility result (never authorization details).
-- Hiring-side eligibility never shows dates, visa types or restriction text (the worker's own view does).
-- Language codes on countries use the same codes as `languages` (ISO 639-3).
--
-- Rollback: re-run 55's matcher patch source (v1.1) and 45's talent search core; revert the
-- eligibility wording with the inverse replacements.

update country_policies c set default_language = v.l3
  from (values ('en','eng'),('hi','hin'),('ar','ara'),('de','deu'),('nl','nld'),('pt','por'),('es','spa'),('fr','fra'),
               ('it','ita'),('pl','pol'),('sv','swe'),('no','nor'),('da','dan'),('tr','tur'),('ja','jpn'),('ko','kor'),
               ('zh','zho'),('ms','msa'),('th','tha'),('vi','vie'),('id','ind'),('ur','urd'),('bn','ben'),('si','sin'),
               ('ne','nep'),('he','heb')) v(l2, l3)
 where c.default_language = v.l2;
update locations l set language_code = cp.default_language
  from country_policies cp where l.kind = 'country' and cp.country_code = l.country_code;

create or replace function omelo_private.omelo_patch_text(p_src text, p_from text, p_to text, p_what text)
returns text
language plpgsql immutable
set search_path = pg_catalog
as $$
begin
  if position(p_from in p_src) = 0 then
    raise exception 'Patch "%" did not find its anchor', p_what;
  end if;
  return replace(p_src, p_from, p_to);
end;
$$;

-- 1. Hiring-side wording ------------------------------------------------------------------------
do $$
declare d text;
begin
  d := pg_get_functiondef('omelo_private.omelo_eligibility(uuid,uuid,boolean)'::regprocedure);
  if position('has expired' in d) > 0 then return; end if;
  d := omelo_private.omelo_patch_text(d,
    $a$'Work authorization starts ' || to_char(v_auth.valid_from, 'DD Mon YYYY'));$a$,
    $a$case when p_for_worker then 'Work authorization starts ' || to_char(v_auth.valid_from, 'DD Mon YYYY')
                   else 'Work authorization not yet valid for the start date' end);$a$, 'starts');
  d := omelo_private.omelo_patch_text(d,
    $a$notes := notes || to_jsonb('Authorization has restrictions: ' || v_auth.work_restrictions);$a$,
    $a$notes := notes || to_jsonb(case when p_for_worker then 'Authorization has restrictions: ' || v_auth.work_restrictions
                                             else 'Authorization has restrictions' end);$a$, 'restrictions');
  d := omelo_private.omelo_patch_text(d,
    $a$notes := notes || to_jsonb('Authorization expires ' || to_char(v_auth.expires_on, 'DD Mon YYYY'));$a$,
    $a$notes := notes || to_jsonb(case when p_for_worker then 'Authorization expires ' || to_char(v_auth.expires_on, 'DD Mon YYYY')
                                             else 'Authorization expires within six months of the start' end);$a$, 'expires');
  d := omelo_private.omelo_patch_text(d,
    $a$'Current permit is tied to another employer — a transfer or new sponsorship may be needed');$a$,
    $a$case when p_for_worker then 'Current permit is tied to another employer — a transfer or new sponsorship may be needed'
                 else 'May need a new sponsorship' end);$a$, 'tied');
  d := omelo_private.omelo_patch_text(d,
    $a$' expired on ' || to_char(v_auth.expires_on, 'DD Mon YYYY'));$a$,
    $a$case when p_for_worker then ' expired on ' || to_char(v_auth.expires_on, 'DD Mon YYYY') else ' has expired' end);$a$, 'expired');
  d := omelo_private.omelo_patch_text(d,
    $a$'Student visa: limited working hours');$a$,
    $a$case when p_for_worker then 'Student visa: limited working hours' else 'Limited working hours allowed' end);$a$, 'student');
  execute d;
end;
$$;

-- 2. Matcher v1.2 -------------------------------------------------------------------------------
do $$
declare d text;
begin
  d := pg_get_functiondef('omelo_private.omelo_score_match(uuid,uuid)'::regprocedure);
  if position('''v1.2''' in d) > 0 then return; end if;

  d := omelo_private.omelo_patch_text(d,
    $a$  wr record; v_sched numeric; v_sched_notes text[] := '{}';$a$,
    $a$  wr record; v_sched numeric; v_sched_notes text[] := '{}';
  mp record; v_elig jsonb; v_mob numeric; v_mob_notes text[] := '{}'; v_home char(2); v_tzo int; v_cname text;$a$, 'declare');

  d := omelo_private.omelo_patch_text(d,
    $a$  select name into v_job_prof_name from professions where id = j.profession_id;
$a$,
    $a$  select name into v_job_prof_name from professions where id = j.profession_id;
  select * into mp from mobility_profiles where person_id = pr.id;
  v_elig := omelo_private.omelo_eligibility(wi.id, j.id, false);
$a$, 'load');

  d := omelo_private.omelo_patch_text(d,
    $a$  if j.country_code is not null and pr.country_code is not null
     and pr.country_code <> j.country_code
     and not exists (
       select 1 from work_authorizations a
        where a.person_id = pr.id and a.country_code = j.country_code
          and a.status in ('citizen','permanent_resident','work_permit','dependent_visa_work_rights'))
     and coalesce(j.visa_sponsorship, false) = false
     and coalesce(j.accepts_non_residents, false) = false then$a$,
    $a$  -- R6: only a hard blocker fails the gate; "potentially eligible" is scored, never rejected
  if v_elig->>'status' = 'not_eligible' then$a$, 'gate');

  d := omelo_private.omelo_patch_text(d,
    $a$    if coalesce(pref.willing_to_relocate, false) then v_score := greatest(v_score, 0.6); end if;$a$,
    $a$    if coalesce(pref.willing_to_relocate, false) then v_score := greatest(v_score, 0.6); end if;
    if coalesce(mp.open_to_relocation, false) and j.country_code is not null
       and (cardinality(mp.preferred_countries) + cardinality(mp.countries_willing_to_work) = 0
            or j.country_code = any (mp.preferred_countries || mp.countries_willing_to_work)) then
      v_score := greatest(v_score, 0.7);
    end if;$a$, 'distance');

  d := omelo_private.omelo_patch_text(d,
    $a$  if v_job_monthly is null then
    f := f || jsonb_build_object('pay_fit'$a$,
    $a$  -- R6: compare in one currency
  if v_worker_monthly is not null and pref.pay_currency is not null and j.pay_currency is not null
     and pref.pay_currency <> j.pay_currency then
    v_worker_monthly := omelo_private.omelo_convert(v_worker_monthly, pref.pay_currency, j.pay_currency);
  end if;

  if v_job_monthly is null then
    f := f || jsonb_build_object('pay_fit'$a$, 'pay');

  d := omelo_private.omelo_patch_text(d,
    $a$  for k, w in select key, value::numeric from jsonb_each_text(wp.weights) loop$a$,
    $a$  -- R6: mobility (relocation, remote time zones) and eligibility
  v_home := coalesce(mp.current_country, pr.country_code);
  if j.workplace_type = 'remote' and j.remote_scope = 'timezone' then
    v_tzo := omelo_private.omelo_tz_offset(coalesce(mp.timezone, pr.timezone));
    if v_tzo is null then
      f := f || jsonb_build_object('mobility_fit', omelo_factor(0.5, 'unknown', 'Time zone not set'));
    elsif v_tzo between j.remote_tz_min_offset and j.remote_tz_max_offset then
      f := f || jsonb_build_object('mobility_fit', omelo_factor(1, 'strong', 'Works in the team''s time zones'));
    else
      v_mob := greatest(0, 1 - least(abs(v_tzo - j.remote_tz_min_offset), abs(v_tzo - j.remote_tz_max_offset)) / 240.0);
      f := f || jsonb_build_object('mobility_fit', omelo_factor(v_mob, case when v_mob >= 0.4 then 'partial' else 'gap' end,
             'About ' || round(least(abs(v_tzo - j.remote_tz_min_offset), abs(v_tzo - j.remote_tz_max_offset)) / 60.0, 1)
             || ' h outside the team''s time zones'));
    end if;
  elsif j.workplace_type <> 'remote' and j.country_code is not null and v_home is not null and v_home <> j.country_code then
    select name into v_cname from country_policies where country_code = j.country_code;
    if mp.person_id is not null and mp.open_to_relocation
       and (cardinality(mp.preferred_countries) + cardinality(mp.countries_willing_to_work) = 0
            or j.country_code = any (mp.preferred_countries || mp.countries_willing_to_work)) then
      v_mob := 1; v_mob_notes := array_append(v_mob_notes, 'Open to relocating to ' || coalesce(v_cname, j.country_code));
    elsif mp.person_id is not null and mp.open_to_relocation then
      v_mob := 0.6; v_mob_notes := array_append(v_mob_notes, 'Open to relocating, though not to a preferred country');
    elsif coalesce(pref.willing_to_relocate, false) then
      v_mob := 0.6; v_mob_notes := array_append(v_mob_notes, 'Willing to relocate');
    else
      v_mob := 0.1; v_mob_notes := array_append(v_mob_notes, 'Not looking to relocate to ' || coalesce(v_cname, j.country_code));
    end if;
    if coalesce(mp.relocation_assistance_required, false)
       and not (j.relocation_support or j.travel_assistance or j.accommodation_assistance) then
      v_mob := v_mob - 0.3; v_mob_notes := array_append(v_mob_notes, 'Needs relocation support the job does not offer');
    end if;
    if mp.earliest_relocation_date is not null and j.start_date is not null and mp.earliest_relocation_date > j.start_date then
      v_mob := v_mob - 0.2; v_mob_notes := array_append(v_mob_notes, 'Can move from ' || to_char(mp.earliest_relocation_date, 'DD Mon YYYY'));
    end if;
    v_mob := greatest(0, v_mob);
    f := f || jsonb_build_object('mobility_fit', omelo_factor(v_mob,
           case when v_mob >= 0.85 then 'strong' when v_mob >= 0.4 then 'partial' else 'gap' end,
           array_to_string(v_mob_notes, '; ')));
  end if;
  if v_elig is not null and (v_elig->>'status' <> 'eligible'
                             or (j.country_code is not null and j.workplace_type <> 'remote' and v_home is distinct from j.country_code)) then
    f := f || jsonb_build_object('eligibility_fit', omelo_factor(
           case v_elig->>'status' when 'eligible' then 1 when 'potentially_eligible' then 0.5 else 0 end,
           case v_elig->>'status' when 'eligible' then 'strong' when 'potentially_eligible' then 'partial' else 'gap' end,
           case when jsonb_array_length(v_elig->'missing') = 0 then 'Eligible to work there'
                else (v_elig->>'summary') || ' — missing: '
                     || (select string_agg(m->>'text', '; ') from jsonb_array_elements(v_elig->'missing') m) end));
  end if;

  for k, w in select key, value::numeric from jsonb_each_text(wp.weights) loop$a$, 'factors');

  d := omelo_private.omelo_patch_text(d,
    $a$  v_final := case when sum_w = 0 then 50 else round(100 * sum_sw / sum_w) end;$a$,
    $a$  for k, w in select x.k, x.w from (values ('mobility_fit', 0.06::numeric), ('eligibility_fit', 0.08::numeric)) x(k, w) loop
    if f ? k then
      sum_w := sum_w + w;
      sum_sw := sum_sw + w * (f -> k ->> 'score')::numeric;
      f := jsonb_set(f, array[k], (f -> k) || jsonb_build_object('weight', w,
             'contribution', round(w * (f -> k ->> 'score')::numeric, 4)));
      case f -> k ->> 'status'
        when 'strong' then strengths := strengths || jsonb_build_object('factor', k, 'weight', w, 'text', f -> k ->> 'explanation');
        when 'unknown' then unknowns := unknowns || jsonb_build_object('factor', k, 'weight', w, 'text', f -> k ->> 'explanation');
        else gaps := gaps || jsonb_build_object('factor', k, 'weight', w, 'text', f -> k ->> 'explanation');
      end case;
    end if;
  end loop;

  v_final := case when sum_w = 0 then 50 else round(100 * sum_sw / sum_w) end;$a$, 'weights');

  d := omelo_private.omelo_patch_text(d, $a$'engine_version', 'v1.1',$a$, $a$'engine_version', 'v1.2',$a$, 'version');
  d := omelo_private.omelo_patch_text(d, $a$    'gates', gates,$a$,
    $a$    'gates', gates,
    'eligibility', case when v_elig is not null then v_elig - 'disclaimer' - 'checked_at' end,$a$, 'output');
  execute d;
end;
$$;

-- 3. Talent search: global filters ------------------------------------------------------------------
do $$
declare d text;
begin
  d := pg_get_functiondef('omelo_private.omelo_talent_search_core(uuid,uuid,jsonb,integer,integer,uuid)'::regprocedure);
  if position('v_elig_f' in d) > 0 then return; end if;

  d := omelo_private.omelo_patch_text(d, $a$  v_prev boolean; v_pool uuid;$a$,
    $a$  v_prev boolean; v_pool uuid;
  v_elig_f text; v_reloc boolean; v_lang text; v_cur text; e jsonb;$a$, 'declare');
  d := omelo_private.omelo_patch_text(d, $a$    v_pool := nullif(f->>'pool_id', '')::uuid;$a$,
    $a$    v_pool := nullif(f->>'pool_id', '')::uuid;
    v_elig_f := nullif(f->>'eligibility', '');
    v_reloc := nullif(f->>'open_to_relocation', '')::boolean;
    v_lang := lower(nullif(f->>'language', ''));
    v_cur := upper(nullif(f->>'current_country', ''));$a$, 'parse');
  d := omelo_private.omelo_patch_text(d, $a$  v_like := case when v_q is not null$a$,
    $a$  if v_elig_f is not null and v_elig_f not in ('eligible','potentially_eligible','any') then
    raise exception 'Unknown eligibility filter %', v_elig_f using errcode = '22023';
  end if;
  v_like := case when v_q is not null$a$, 'validate');
  d := omelo_private.omelo_patch_text(d, $a$           pwp.pay_currency as expected_currency
      from work_identities wi$a$,
    $a$           pwp.pay_currency as expected_currency,
           coalesce(mp.open_to_relocation, false)
             and (j.country_code is null
                  or cardinality(mp.preferred_countries) + cardinality(mp.countries_willing_to_work) = 0
                  or j.country_code = any (mp.preferred_countries || mp.countries_willing_to_work)) as relocates,
           coalesce(mp.current_country, p.country_code) as current_country,
           coalesce(mp.open_to_relocation, false) as open_to_relocation
      from work_identities wi$a$, 'select');
  d := omelo_private.omelo_patch_text(d, $a$      left join person_work_preferences pwp on pwp.work_identity_id = wi.id
$a$,
    $a$      left join person_work_preferences pwp on pwp.work_identity_id = wi.id
      left join mobility_profiles mp on mp.person_id = wi.person_id
$a$, 'join');
  d := omelo_private.omelo_patch_text(d, $a$            or exists (select 1 from work_authorizations wa
                        where wa.person_id = wi.person_id and wa.country_code = v_auth
$a$,
    $a$            or (coalesce(mp.authorization_visibility, 'eligibility_only') <> 'private'
                and v_auth = any (coalesce(mp.citizenships, '{}')))
            or exists (select 1 from work_authorizations wa
                        where coalesce(mp.authorization_visibility, 'eligibility_only') <> 'private'
                          and wa.person_id = wi.person_id and wa.country_code = v_auth
$a$, 'auth');
  d := omelo_private.omelo_patch_text(d, $a$       and (v_pool is null or exists$a$,
    $a$       and (v_reloc is null or coalesce(mp.open_to_relocation, false) = v_reloc)
       and (v_lang is null or exists (select 1 from person_languages pl
                                       where pl.person_id = wi.person_id and lower(pl.language_code) = v_lang))
       and (v_cur is null or coalesce(mp.current_country, p.country_code) = v_cur)
       and (v_pool is null or exists$a$, 'filters');
  d := omelo_private.omelo_patch_text(d, $a$    continue when c.km is not null and c.km > v_radius;$a$,
    $a$    continue when c.km is not null and c.km > v_radius and not c.relocates;$a$, 'radius');
  d := omelo_private.omelo_patch_text(d, $a$    continue when not omelo_private.omelo_is_identity_discoverable_to(c.id, p_company);$a$,
    $a$    continue when not omelo_private.omelo_is_identity_discoverable_to(c.id, p_company);
    e := omelo_private.omelo_eligibility(c.id, j.id, false);
    continue when v_elig_f = 'eligible' and e->>'status' <> 'eligible';
    continue when v_elig_f = 'potentially_eligible' and e->>'status' = 'not_eligible';$a$, 'eligibility');
  d := omelo_private.omelo_patch_text(d, $a$           'availability', c.availability,$a$,
    $a$           'availability', c.availability,
           'eligibility', jsonb_build_object('status', e->>'status', 'summary', e->>'summary', 'missing', e->'missing'),
           'open_to_relocation', c.open_to_relocation, 'current_country', c.current_country,$a$, 'card');
  execute d;
end;
$$;

drop function omelo_private.omelo_patch_text(text, text, text, text);
