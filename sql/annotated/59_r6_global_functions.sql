-- OMELO 59 — Release 6: Global Employment & Mobility — functions.
--
--   omelo_fx_rate / omelo_convert        latest rate at a moment (direct, inverse, or through USD)
--   omelo_convert_currency (RPC)         amount + rate + effective time + source (R6-002)
--   omelo_normalized_pay                 hourly / monthly / yearly in the original and a target currency
--   omelo_eligibility (private)          eligible | potentially_eligible | not_eligible, with what is missing.
--                                        Only hard blockers make someone not eligible; everything else is
--                                        "potentially eligible — missing: …" (R6-004)
--   omelo_job_eligibility (worker)       pre-application check, with the official sources for that country
--   omelo_candidate_eligibility (hiring) the result, plus authorization details only if the worker shares them
--   omelo_global_jobs                    near me, remote, relocation, visa sponsorship, international, work abroad
--   omelo_country_guide / omelo_license_requirements   official information, never legal advice
--   omelo_save_mobility / omelo_my_mobility
--   omelo_admin_add_exchange_rate        platform admins add rates (append-only)
--   integrity triggers: jobs (sponsorship, remote scope, legal entity), legal entities,
--   employments (country + original pay; currency never changes, R6-012), experiences (country + pay)
--
-- Rollback: drop the functions and triggers below; recreate jobs_sync_sponsorship from 58.

-- 1. Currency ----------------------------------------------------------------------------------
create or replace function omelo_private.omelo_fx_rate(p_from char(3), p_to char(3), p_at timestamptz default now())
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare d record; i record; a jsonb; b jsonb;
begin
  if p_from is null or p_to is null then return null; end if;
  if p_from = p_to then
    return jsonb_build_object('rate', 1, 'effective_at', p_at, 'source', 'same currency', 'via', null);
  end if;
  select rate, effective_at, source into d from exchange_rates
   where base = p_from and quote = p_to and effective_at <= p_at order by effective_at desc limit 1;
  select rate, effective_at, source into i from exchange_rates
   where base = p_to and quote = p_from and effective_at <= p_at order by effective_at desc limit 1;
  if d.rate is not null and (i.rate is null or d.effective_at >= i.effective_at) then
    return jsonb_build_object('rate', d.rate, 'effective_at', d.effective_at, 'source', d.source, 'via', null);
  elsif i.rate is not null then
    return jsonb_build_object('rate', round(1 / i.rate, 10), 'effective_at', i.effective_at, 'source', i.source, 'via', null);
  end if;
  -- cross through USD
  if p_from <> 'USD' and p_to <> 'USD' then
    a := omelo_private.omelo_fx_rate('USD', p_from, p_at);
    b := omelo_private.omelo_fx_rate('USD', p_to, p_at);
    if a is not null and b is not null then
      return jsonb_build_object('rate', round((b->>'rate')::numeric / (a->>'rate')::numeric, 10),
                                'effective_at', least((a->>'effective_at')::timestamptz, (b->>'effective_at')::timestamptz),
                                'source', case when a->>'source' = b->>'source' then a->>'source'
                                               else (a->>'source') || '; ' || (b->>'source') end,
                                'via', 'USD');
    end if;
  end if;
  return null;
end;
$$;

create or replace function omelo_private.omelo_convert(p_amount numeric, p_from char(3), p_to char(3), p_at timestamptz default now())
returns numeric
language sql stable security definer
set search_path = public, omelo_private
as $$
  select case when p_amount is null then null
              when p_from = p_to then p_amount
              else round(p_amount * (omelo_private.omelo_fx_rate(p_from, p_to, p_at)->>'rate')::numeric, 2) end;
$$;

create or replace function public.omelo_convert_currency(p_amount numeric, p_from text, p_to text)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare r jsonb; v_from char(3) := upper(p_from); v_to char(3) := upper(p_to);
begin
  if not exists (select 1 from currencies where code = v_from) or not exists (select 1 from currencies where code = v_to) then
    raise exception 'Unknown currency' using errcode = '22023';
  end if;
  r := omelo_private.omelo_fx_rate(v_from, v_to);
  if r is null then
    return jsonb_build_object('amount', p_amount, 'from', v_from, 'to', v_to, 'converted', null,
                              'note', 'No exchange rate available for this pair');
  end if;
  return jsonb_build_object('amount', p_amount, 'from', v_from, 'to', v_to,
                            'converted', round(p_amount * (r->>'rate')::numeric, 2),
                            'rate', (r->>'rate')::numeric, 'effective_at', r->'effective_at', 'source', r->>'source',
                            'via', r->'via',
                            'note', 'Converted for comparison only; the original amount and currency are what counts.');
end;
$$;

-- Hours per period (for hourly/monthly/yearly views). The same working-time assumptions as
-- omelo_pay_monthly: 8 h days, 26 days a month.
create or replace function public.omelo_normalized_pay(p_amount numeric, p_period pay_period, p_currency text,
                                                       p_target text default null)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare v_month numeric; v_target char(3) := upper(coalesce(p_target, p_currency)); r jsonb;
begin
  if p_amount is null or p_period is null or p_currency is null then return null; end if;
  v_month := public.omelo_pay_monthly(p_amount, p_period);
  if v_month is null then
    return jsonb_build_object('amount', p_amount, 'period', p_period, 'currency', upper(p_currency),
                              'note', 'Paid per task: no hourly or monthly equivalent');
  end if;
  r := omelo_private.omelo_fx_rate(upper(p_currency), v_target);
  return jsonb_build_object(
    'amount', p_amount, 'period', p_period, 'currency', upper(p_currency),
    'hourly', round(v_month / 208, 2), 'monthly', round(v_month, 2), 'yearly', round(v_month * 12, 2),
    'target', case when v_target <> upper(p_currency) and r is not null then jsonb_build_object(
                'currency', v_target,
                'hourly', round(v_month / 208 * (r->>'rate')::numeric, 2),
                'monthly', round(v_month * (r->>'rate')::numeric, 2),
                'yearly', round(v_month * 12 * (r->>'rate')::numeric, 2),
                'rate', (r->>'rate')::numeric, 'effective_at', r->'effective_at', 'source', r->>'source') end);
end;
$$;

create or replace function public.omelo_admin_add_exchange_rate(p_base text, p_quote text, p_rate numeric,
                                                                p_effective_at timestamptz, p_source text)
returns bigint
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_id bigint;
begin
  if not omelo_private.omelo_is_platform_admin(array['superadmin','analyst']) then
    raise exception 'Platform administrators only' using errcode = '42501';
  end if;
  if p_rate is null or p_rate <= 0 then raise exception 'The rate must be positive' using errcode = '22023'; end if;
  if p_effective_at is null or p_effective_at > now() + interval '1 day' then
    raise exception 'Give when the rate takes effect (not in the future)' using errcode = '22023';
  end if;
  insert into exchange_rates (base, quote, rate, effective_at, source, created_by)
  values (upper(p_base), upper(p_quote), p_rate, p_effective_at, trim(p_source), auth.uid())
  returning id into v_id;
  insert into audit_log (actor_type, actor_id, action, subject_type, subject_id, metadata)
  values ('admin', auth.uid(), 'exchange_rate.added', 'exchange_rate', null,
          jsonb_build_object('id', v_id, 'base', upper(p_base), 'quote', upper(p_quote), 'rate', p_rate, 'source', p_source));
  return v_id;
end;
$$;

-- 2. Integrity triggers -------------------------------------------------------------------------
drop trigger if exists jobs_sync_sponsorship on jobs;
drop function if exists omelo_private.omelo_sync_job_sponsorship();

create or replace function omelo_private.omelo_validate_job_global()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  -- visa_sponsorship stays the matcher's boolean, derived from sponsorship
  if tg_op = 'UPDATE' and new.visa_sponsorship is distinct from old.visa_sponsorship
     and new.sponsorship is not distinct from old.sponsorship then
    new.sponsorship := case when new.visa_sponsorship then 'yes' else 'no' end;
  elsif tg_op = 'INSERT' and new.visa_sponsorship and new.sponsorship = 'no' then
    new.sponsorship := 'yes';
  end if;
  new.visa_sponsorship := new.sponsorship in ('yes','case_by_case');
  if new.sponsorship = 'no' then
    new.sponsorship_type := null;
  end if;
  if new.workplace_type <> 'remote' then
    new.remote_scope := null; new.remote_countries := '{}'; new.remote_tz_min_offset := null; new.remote_tz_max_offset := null;
  end if;
  if new.remote_scope = 'timezone' and (new.remote_tz_min_offset is null or new.remote_tz_max_offset is null
                                        or new.remote_tz_max_offset < new.remote_tz_min_offset) then
    raise exception 'Give the time-zone range for a time-zone-bound remote job' using errcode = '22023';
  end if;
  if new.remote_scope = 'countries' and cardinality(new.remote_countries) = 0 then
    raise exception 'Name the countries this remote job is open to' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(new.remote_countries) c where not exists (select 1 from country_policies where country_code = c)) then
    raise exception 'Unknown country in the remote countries' using errcode = '22023';
  end if;
  if new.legal_entity_id is not null and not exists (
       select 1 from company_legal_entities le where le.id = new.legal_entity_id and le.company_id = new.company_id) then
    raise exception 'That legal entity belongs to another company' using errcode = '42501';
  end if;
  if new.legal_entity_id is not null and new.country_code is null then
    new.country_code := (select country_code from company_legal_entities where id = new.legal_entity_id);
  end if;
  return new;
end;
$$;
drop trigger if exists jobs_validate_global on jobs;
create trigger jobs_validate_global before insert or update on jobs
  for each row execute function omelo_private.omelo_validate_job_global();

create or replace function omelo_private.omelo_validate_legal_entity()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if not exists (select 1 from pg_timezone_names where name = new.timezone) then
    raise exception 'Unknown time zone %', new.timezone using errcode = '22023';
  end if;
  if tg_op = 'UPDATE' and new.company_id is distinct from old.company_id then
    raise exception 'A legal entity cannot move to another company' using errcode = '42501';
  end if;
  new.legal_name := trim(new.legal_name);
  return new;
end;
$$;
drop trigger if exists company_legal_entities_validate on company_legal_entities;
create trigger company_legal_entities_validate before insert or update on company_legal_entities
  for each row execute function omelo_private.omelo_validate_legal_entity();

-- R6-012: an employment keeps its country and its original pay currency
create or replace function omelo_private.omelo_validate_employment_global()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare o record;
begin
  if tg_op = 'INSERT' then
    if new.offer_id is not null and new.pay_amount is null then
      select pay_amount, pay_period, pay_currency into o from offers where id = new.offer_id;
      new.pay_amount := o.pay_amount; new.pay_period := o.pay_period; new.pay_currency := o.pay_currency;
    end if;
    if new.pay_amount is null and new.job_id is not null then
      select coalesce(pay_max, pay_min) amt, pay_period, pay_currency into o from jobs where id = new.job_id;
      if o.amt is not null then
        new.pay_amount := o.amt; new.pay_period := o.pay_period; new.pay_currency := o.pay_currency;
      end if;
    end if;
    new.country_code := coalesce(new.country_code,
      (select country_code from jobs where id = new.job_id),
      (select country_code from locations where id = new.location_id),
      (select country_code from companies where id = new.company_id));
    new.employment_type := coalesce(new.employment_type, new.work_type::text);
  else
    if old.pay_currency is not null and new.pay_currency is distinct from old.pay_currency then
      raise exception 'An employment keeps its original pay currency' using errcode = '23514';
    end if;
    if old.country_code is not null and new.country_code is distinct from old.country_code then
      raise exception 'An employment keeps its country' using errcode = '23514';
    end if;
  end if;
  if new.pay_amount is not null and new.pay_currency is null then
    raise exception 'Pay needs a currency' using errcode = '23514';
  end if;
  return new;
end;
$$;
drop trigger if exists employments_validate_global on employments;
create trigger employments_validate_global before insert or update on employments
  for each row execute function omelo_private.omelo_validate_employment_global();

-- Employers may only end an employment; pay and country are part of the record.
do $$
declare d text;
begin
  d := pg_get_functiondef('omelo_private.omelo_guard_employment()'::regprocedure);
  if position('new.pay_amount is distinct from old.pay_amount' in d) = 0 then
    d := replace(d, '  or new.is_omelo_hire is distinct from old.is_omelo_hire then',
                    '  or new.is_omelo_hire is distinct from old.is_omelo_hire' || chr(10) ||
                    '  or new.pay_amount is distinct from old.pay_amount' || chr(10) ||
                    '  or new.pay_period is distinct from old.pay_period' || chr(10) ||
                    '  or new.pay_currency is distinct from old.pay_currency' || chr(10) ||
                    '  or new.country_code is distinct from old.country_code then');
    if position('new.pay_amount is distinct from old.pay_amount' in d) = 0 then
      raise exception 'guard_employment patch did not apply';
    end if;
    execute d;
  end if;
end;
$$;

create or replace function omelo_private.omelo_validate_experience_global()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare e record;
begin
  if new.verified_employment_id is not null then
    select country_code, pay_amount, pay_period, pay_currency into e from employments where id = new.verified_employment_id;
    new.country_code := coalesce(new.country_code, e.country_code);
    if new.pay_amount is null and e.pay_amount is not null then
      new.pay_amount := e.pay_amount; new.pay_period := e.pay_period; new.pay_currency := e.pay_currency;
    end if;
  end if;
  if new.country_code is null and new.location_id is not null then
    new.country_code := (select country_code from locations where id = new.location_id);
  end if;
  if new.pay_amount is not null and new.pay_currency is null then
    raise exception 'Pay needs a currency' using errcode = '23514';
  end if;
  return new;
end;
$$;
drop trigger if exists experiences_validate_global on experiences;
create trigger experiences_validate_global before insert on experiences
  for each row execute function omelo_private.omelo_validate_experience_global();

-- Assignments carry pay into the employment they create.
do $$
declare d text;
begin
  d := pg_get_functiondef('omelo_private.omelo_activate_assignment(uuid)'::regprocedure);
  if position('pay_currency' in d) = 0 then
    d := replace(d, 'started_on, status, is_omelo_hire)', 'started_on, status, is_omelo_hire, pay_amount, pay_period, pay_currency, country_code, employment_type)');
    d := replace(d, 'a.location_id, a.start_date, ''active'', true)',
                    'a.location_id, a.start_date, ''active'', true, a.pay_rate, a.pay_period, a.currency,' || chr(10) ||
                    '            (select country_code from workforce_requirements where id = a.requirement_id), a.employment_type)');
    if position('a.pay_rate, a.pay_period, a.currency' in d) = 0 then
      raise exception 'activate_assignment patch did not apply';
    end if;
    execute d;
  end if;
end;
$$;

-- 3. Eligibility ----------------------------------------------------------------------------------
-- Offset of a time zone from UTC, in minutes, now.
create or replace function omelo_private.omelo_tz_offset(p_tz text)
returns integer
language sql stable
set search_path = pg_catalog
as $$
  select case when p_tz is null or not exists (select 1 from pg_timezone_names where name = p_tz) then null
              else (extract(epoch from (now() at time zone p_tz) - (now() at time zone 'UTC')) / 60)::int end;
$$;

-- p_for_worker = true: the worker's own view (everything). false: what hiring may rely on — if the worker
-- keeps authorization private, it is treated as "not shared" (never as a blocker).
create or replace function omelo_private.omelo_eligibility(p_identity uuid, p_job uuid, p_for_worker boolean default false)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare
  wi record; pr record; mp record; j record; pref record;
  v_country char(2); v_home char(2); v_private boolean; v_auth record; v_tz int; v_name text;
  missing jsonb := '[]'::jsonb; notes jsonb := '[]'::jsonb; v_hard boolean := false; v_right boolean := false;
  r record;
begin
  select * into wi from work_identities where id = p_identity;
  select * into j from jobs where id = p_job;
  if wi.id is null or j.id is null then return null; end if;
  select * into pr from persons where id = wi.person_id;
  select * into mp from mobility_profiles where person_id = pr.id;
  select * into pref from person_work_preferences where work_identity_id = wi.id;
  v_home := coalesce(mp.current_country, pr.country_code);
  v_private := not p_for_worker and coalesce(mp.authorization_visibility, 'eligibility_only') = 'private';
  v_country := j.country_code;
  select name into v_name from country_policies where country_code = v_country;

  -- Work authorization -------------------------------------------------------------
  if j.workplace_type = 'remote' and coalesce(j.remote_scope, 'country') = 'worldwide' then
    notes := notes || to_jsonb('Remote from anywhere: no work authorization for ' || coalesce(v_name, 'the employer''s country') || ' needed'::text);
  elsif j.workplace_type = 'remote' and j.remote_scope = 'countries' then
    if v_home is null then
      missing := missing || jsonb_build_object('kind', 'location', 'text', 'Country you work from not stated');
    elsif not (v_home = any (j.remote_countries)) then
      v_hard := true;
      missing := missing || jsonb_build_object('kind', 'location', 'text',
        'Open only to people working from ' || (select string_agg(name, ', ' order by name) from country_policies where country_code = any (j.remote_countries)));
    end if;
  elsif j.workplace_type = 'remote' and j.remote_scope = 'timezone' then
    v_tz := omelo_private.omelo_tz_offset(coalesce(mp.timezone, pr.timezone));
    if v_tz is null then
      missing := missing || jsonb_build_object('kind', 'timezone', 'text', 'Time zone not stated');
    elsif v_tz < j.remote_tz_min_offset or v_tz > j.remote_tz_max_offset then
      missing := missing || jsonb_build_object('kind', 'timezone', 'text', 'Outside the time zones this team works in');
    end if;
  elsif v_country is not null then
    if v_private then
      if v_home is distinct from v_country then
        missing := missing || jsonb_build_object('kind', 'work_authorization', 'text',
          'Work authorization for ' || coalesce(v_name, v_country) || ' not shared');
      end if;
    else
      select * into v_auth from work_authorizations a
       where a.person_id = pr.id and a.country_code = v_country
       order by (a.expires_on is null or a.expires_on >= current_date) desc, a.created_at desc limit 1;
      if v_country = any (coalesce(mp.citizenships, '{}')) then
        v_right := true;
      elsif v_auth.id is not null then
        if v_auth.status in ('citizen','permanent_resident','work_permit','dependent_visa_work_rights','other_authorization')
           and (v_auth.expires_on is null or v_auth.expires_on >= current_date) then
          if v_auth.valid_from is not null and v_auth.valid_from > coalesce(j.start_date, current_date) then
            missing := missing || jsonb_build_object('kind', 'work_authorization', 'text',
              'Work authorization starts ' || to_char(v_auth.valid_from, 'DD Mon YYYY'));
          else
            v_right := true;
          end if;
          if v_auth.work_restrictions is not null then
            notes := notes || to_jsonb('Authorization has restrictions: ' || v_auth.work_restrictions);
          end if;
          if v_auth.expires_on is not null and v_auth.expires_on < coalesce(j.start_date, current_date) + 180 then
            notes := notes || to_jsonb('Authorization expires ' || to_char(v_auth.expires_on, 'DD Mon YYYY'));
          end if;
        elsif v_auth.status = 'employer_sponsored' and (v_auth.expires_on is null or v_auth.expires_on >= current_date) then
          missing := missing || jsonb_build_object('kind', 'work_authorization', 'text',
            'Current permit is tied to another employer — a transfer or new sponsorship may be needed');
        elsif v_auth.expires_on is not null and v_auth.expires_on < current_date then
          missing := missing || jsonb_build_object('kind', 'work_authorization', 'text',
            'Work authorization for ' || coalesce(v_name, v_country) || ' expired on ' || to_char(v_auth.expires_on, 'DD Mon YYYY'));
        elsif v_auth.status = 'student_visa_limited' then
          missing := missing || jsonb_build_object('kind', 'work_authorization', 'text', 'Student visa: limited working hours');
        end if;
      elsif v_home = v_country then
        v_right := true;   -- lives there; nothing says otherwise
        notes := notes || to_jsonb('Lives in ' || coalesce(v_name, v_country) || '; work authorization not stated'::text);
      end if;

      if not v_right and not exists (select 1 from jsonb_array_elements(missing) m where m->>'kind' = 'work_authorization') then
        if j.sponsorship in ('yes','case_by_case') then
          missing := missing || jsonb_build_object('kind', 'work_authorization', 'text',
            'Work authorization for ' || coalesce(v_name, v_country) ||
            case when j.sponsorship = 'yes' then ' — the employer sponsors visas' else ' — the employer considers sponsorship case by case' end);
        elsif coalesce(j.accepts_non_residents, false) then
          missing := missing || jsonb_build_object('kind', 'work_authorization', 'text',
            'Work authorization for ' || coalesce(v_name, v_country) || ' — the employer accepts applicants from abroad');
        elsif v_home is null and v_auth.id is null then
          missing := missing || jsonb_build_object('kind', 'work_authorization', 'text',
            'Work authorization for ' || coalesce(v_name, v_country) || ' not stated');
        else
          v_hard := true;
          missing := missing || jsonb_build_object('kind', 'work_authorization', 'text',
            'Work authorization for ' || coalesce(v_name, v_country) || ' (this job does not offer sponsorship)');
        end if;
      end if;
    end if;
  end if;

  -- Licences required by the job, and registration required by the country for the profession ----------
  for r in select lt.name, lt.id from job_licenses jl join license_types lt on lt.id = jl.license_type_id
            where jl.job_id = j.id and jl.requirement_level = 'required'
              and not exists (select 1 from person_licenses pl where pl.person_id = pr.id and pl.license_type_id = jl.license_type_id
                                 and (pl.expires_on is null or pl.expires_on >= current_date)) loop
    missing := missing || jsonb_build_object('kind', 'licence', 'text', 'Licence: ' || r.name);
  end loop;
  if v_country is not null and j.workplace_type <> 'remote' then
    for r in select lr.name, lr.license_type_id from license_requirements lr
              where lr.profession_id = j.profession_id and lr.country_code = v_country and lr.requirement_level = 'required'
                and not exists (select 1 from person_licenses pl where pl.person_id = pr.id
                                   and (pl.expires_on is null or pl.expires_on >= current_date)
                                   and (pl.license_type_id = lr.license_type_id
                                        or (lr.license_type_id is null and pl.country_code = lr.country_code))) loop
      missing := missing || jsonb_build_object('kind', 'licence', 'text', r.name);
    end loop;
  end if;

  -- Languages ------------------------------------------------------------------------------
  for r in select l.name, jl.min_proficiency from job_languages jl left join languages l on l.code = jl.language_code
            where jl.job_id = j.id and jl.requirement_level = 'required'
              and not exists (select 1 from person_languages pl where pl.person_id = pr.id and pl.language_code = jl.language_code
                                 and (jl.min_proficiency is null or pl.proficiency >= jl.min_proficiency)) loop
    missing := missing || jsonb_build_object('kind', 'language', 'text',
      coalesce(r.name, 'Language') || coalesce(' (' || replace(r.min_proficiency::text, '_', ' ') || ' or better)', ''));
  end loop;

  -- Relocation (preferences: notes, never blockers) --------------------------------------------------
  if j.workplace_type <> 'remote' and v_country is not null and v_home is not null and v_home <> v_country then
    if mp.person_id is null or not mp.open_to_relocation then
      if not coalesce(pref.willing_to_relocate, false) then
        notes := notes || to_jsonb('Would need to relocate to ' || coalesce(v_name, v_country));
      end if;
    elsif cardinality(mp.preferred_countries) + cardinality(mp.countries_willing_to_work) > 0
          and not (v_country = any (mp.preferred_countries || mp.countries_willing_to_work)) then
      notes := notes || to_jsonb(coalesce(v_name, v_country) || ' is not among the preferred countries'::text);
    end if;
    if mp.relocation_assistance_required and not (j.relocation_support or j.travel_assistance or j.accommodation_assistance) then
      notes := notes || to_jsonb('Relocation support needed; this job does not offer it'::text);
    end if;
    if mp.earliest_relocation_date is not null and j.start_date is not null and mp.earliest_relocation_date > j.start_date then
      notes := notes || to_jsonb('Can relocate from ' || to_char(mp.earliest_relocation_date, 'DD Mon YYYY') ||
                                 '; the job starts ' || to_char(j.start_date, 'DD Mon YYYY'));
    end if;
  end if;

  return jsonb_build_object(
    'status', case when v_hard then 'not_eligible' when jsonb_array_length(missing) > 0 then 'potentially_eligible' else 'eligible' end,
    'summary', case when v_hard then 'Not currently eligible'
                    when jsonb_array_length(missing) > 0 then 'Potentially eligible'
                    else 'Eligible' end,
    'missing', missing,
    'notes', notes,
    'country', v_country,
    'sponsorship', j.sponsorship,
    'relocation_support', j.relocation_support,
    'checked_at', now(),
    'disclaimer', 'Based on what is on the profile and the job. Not legal advice; the official sources decide.');
end;
$$;

-- Worker: pre-application check for one of their identities (default: the primary one).
create or replace function public.omelo_job_eligibility(p_job uuid, p_identity uuid default null)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare v_identity uuid := p_identity; j record; e jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if v_identity is null then
    select id into v_identity from work_identities where person_id = auth.uid() and status = 'active'
     order by is_primary desc, created_at limit 1;
  elsif not exists (select 1 from work_identities where id = v_identity and person_id = auth.uid()) then
    raise exception 'That work identity is not yours' using errcode = '42501';
  end if;
  select * into j from jobs where id = p_job;
  if j.id is null or (j.status <> 'published' and not exists (select 1 from applications a where a.job_id = j.id and a.person_id = auth.uid())) then
    raise exception 'Job not found' using errcode = '22023';
  end if;
  if v_identity is null then
    return jsonb_build_object('status', 'potentially_eligible', 'summary', 'Potentially eligible',
      'missing', jsonb_build_array(jsonb_build_object('kind', 'profile', 'text', 'Create a work identity first')), 'notes', '[]'::jsonb);
  end if;
  e := omelo_private.omelo_eligibility(v_identity, j.id, true);
  return e || jsonb_build_object(
    'work_identity_id', v_identity,
    'official_sources', coalesce((select jsonb_agg(jsonb_build_object('title', i.title, 'url', i.official_url, 'source', i.source_name,
                                                                     'topic', i.topic, 'reviewed_at', i.reviewed_at) order by i.topic)
                                    from country_employment_info i where i.country_code = j.country_code), '[]'::jsonb),
    'licence_requirements', coalesce((select jsonb_agg(jsonb_build_object('name', lr.name, 'description', lr.description,
                                                                         'url', lr.official_url, 'source', lr.source, 'level', lr.requirement_level))
                                        from license_requirements lr where lr.profession_id = j.profession_id and lr.country_code = j.country_code), '[]'::jsonb),
    'pay', public.omelo_normalized_pay(coalesce(j.pay_max, j.pay_min), j.pay_period, j.pay_currency,
             (select pay_currency from person_work_preferences where work_identity_id = v_identity)));
end;
$$;

-- Hiring side: the eligibility result; authorization details only when the worker shares them.
create or replace function public.omelo_candidate_eligibility(p_job uuid, p_identity uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare wi record; j record; e jsonb; v_vis text; v_applied boolean; v_details jsonb;
begin
  select * into j from jobs where id = p_job;
  select * into wi from work_identities where id = p_identity;
  if j.id is null or wi.id is null then raise exception 'Not found' using errcode = '22023'; end if;
  if not (omelo_private.omelo_can_access_job(j.id)
          or exists (select 1 from job_orders jo join company_members cm on cm.company_id = jo.agency_id
                      where jo.job_id = j.id and cm.person_id = auth.uid() and cm.is_active)) then
    raise exception 'Only the hiring team can check this' using errcode = '42501';
  end if;
  v_applied := exists (select 1 from applications a where a.job_id = j.id and a.person_id = wi.person_id);
  if not v_applied
     and not exists (select 1 from company_members cm where cm.person_id = auth.uid() and cm.is_active
                        and omelo_private.omelo_is_identity_discoverable_to(wi.id, cm.company_id))
     and not exists (select 1 from candidate_consents cc join company_members cm on cm.company_id = cc.agency_id
                      where cc.person_id = wi.person_id and cm.person_id = auth.uid() and cm.is_active
                        and cc.status = 'accepted') then
    raise exception 'This person is not visible to you' using errcode = '42501';
  end if;
  e := omelo_private.omelo_eligibility(wi.id, j.id, false);
  select authorization_visibility into v_vis from mobility_profiles where person_id = wi.person_id;
  v_vis := coalesce(v_vis, 'eligibility_only');
  if v_vis = 'details_with_visible' or (v_vis = 'details_with_applications' and v_applied) then
    select jsonb_agg(jsonb_build_object('country', a.country_code, 'status', a.status, 'valid_from', a.valid_from,
                                        'expires_on', a.expires_on, 'requires_sponsorship', a.requires_sponsorship,
                                        'restrictions', a.work_restrictions, 'is_verified', a.is_verified))
      into v_details
      from work_authorizations a where a.person_id = wi.person_id and a.country_code = j.country_code;
  end if;
  return e || jsonb_build_object('authorization_visibility', v_vis, 'authorizations', v_details);
end;
$$;

-- 4. Global job discovery ------------------------------------------------------------------------
create or replace function public.omelo_global_jobs(p_tab text default 'international', p_filters jsonb default '{}'::jsonb,
                                                     p_limit integer default 25, p_offset integer default 0)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private, extensions
as $$
declare
  f jsonb := coalesce(p_filters, '{}'::jsonb); v_uid uuid := auth.uid();
  v_identity uuid; v_home char(2); mp record; pr record; v_cur char(3);
  v_country char(2); v_city uuid; v_prof uuid; v_cat uuid; v_q text; v_like text; v_work text[];
  v_min_pay numeric; v_lat float8; v_lng float8; v_radius int; v_origin geography;
  v_limit int := greatest(1, least(coalesce(p_limit, 25), 50));
  v_offset int := greatest(0, least(coalesce(p_offset, 0), 1000));
  v_total int; v_rows jsonb;
begin
  if v_uid is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if p_tab not in ('near_me','remote','relocation','visa_sponsorship','international','work_abroad') then
    raise exception 'Unknown tab %', p_tab using errcode = '22023';
  end if;
  begin
    v_country := upper(nullif(f->>'country', ''));
    v_city := nullif(f->>'city_id', '')::uuid;
    v_prof := nullif(f->>'profession_id', '')::uuid;
    v_cat := nullif(f->>'category_id', '')::uuid;
    v_q := nullif(trim(coalesce(f->>'query', '')), '');
    if jsonb_typeof(f->'work_types') = 'array' and jsonb_array_length(f->'work_types') > 0 then
      v_work := array(select jsonb_array_elements_text(f->'work_types'));
      perform v_work::work_type[];
    end if;
    v_min_pay := nullif(f->>'min_pay_monthly', '')::numeric;
    v_lat := nullif(f->>'lat', '')::float8; v_lng := nullif(f->>'lng', '')::float8;
    v_radius := greatest(1, least(coalesce(nullif(f->>'radius_km', '')::int, 25), 500));
    v_identity := nullif(f->>'work_identity_id', '')::uuid;
  exception when others then
    raise exception 'Check the filters: %', sqlerrm using errcode = '22023';
  end;
  if v_q is not null and length(v_q) > 80 then raise exception 'Keep the search under 80 characters' using errcode = '22023'; end if;
  v_like := case when v_q is not null then '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%' end;

  select * into pr from persons where id = v_uid;
  select * into mp from mobility_profiles where person_id = v_uid;
  v_home := coalesce(mp.current_country, pr.country_code);
  if v_identity is not null and not exists (select 1 from work_identities where id = v_identity and person_id = v_uid) then
    raise exception 'That work identity is not yours' using errcode = '42501';
  end if;
  if v_identity is null then
    select id into v_identity from work_identities where person_id = v_uid and status = 'active' order by is_primary desc, created_at limit 1;
  end if;
  v_cur := coalesce((select pay_currency from person_work_preferences where work_identity_id = v_identity),
                    (select default_currency from country_policies where country_code = v_home), 'USD');
  if p_tab = 'near_me' then
    if v_lat is not null and v_lng is not null then
      v_origin := st_setsrid(st_makepoint(v_lng, v_lat), 4326)::geography;
    else
      v_origin := pr.geo;
    end if;
    if v_origin is null then raise exception 'Share a location or set one on the profile' using errcode = '22023'; end if;
  end if;

  with base as (
    select j.*, c.display_name company_name, c.is_verified company_verified, cp.name country_name,
           case when v_origin is not null and j.geo is not null then round((st_distance(j.geo, v_origin) / 1000)::numeric, 1) end km
      from jobs j
      join companies c on c.id = j.company_id and c.deleted_at is null
      left join country_policies cp on cp.country_code = j.country_code
     where j.status = 'published' and (j.expires_at is null or j.expires_at > now())
       and not exists (select 1 from hidden_jobs h where h.person_id = v_uid and h.job_id = j.id)
       and not exists (select 1 from blocks bl where bl.person_id = v_uid and bl.target_type = 'company' and bl.target_id = c.id)
       and (v_country is null or j.country_code = v_country)
       and (v_city is null or j.location_id = v_city
            or exists (select 1 from locations l where l.id = j.location_id and l.parent_id = v_city))
       and (v_prof is null or j.profession_id = v_prof)
       and (v_cat is null or j.category_id = v_cat)
       and (v_work is null or j.work_type = any (v_work::work_type[]))
       and (v_like is null or j.title ilike v_like or c.display_name ilike v_like)
       and (v_min_pay is null or omelo_private.omelo_convert(public.omelo_pay_monthly(coalesce(j.pay_max, j.pay_min), j.pay_period),
                                                              j.pay_currency, v_cur) >= v_min_pay)
       and case p_tab
             when 'near_me' then j.geo is not null and st_dwithin(j.geo, v_origin, v_radius * 1000)
             when 'remote' then j.workplace_type = 'remote'
                                 and (coalesce(j.remote_scope, 'country') = 'worldwide'
                                      or (j.remote_scope = 'countries' and v_home = any (j.remote_countries))
                                      or (j.remote_scope = 'timezone'
                                          and omelo_private.omelo_tz_offset(coalesce(mp.timezone, pr.timezone))
                                              between j.remote_tz_min_offset and j.remote_tz_max_offset)
                                      or (coalesce(j.remote_scope, 'country') = 'country' and (v_home is null or j.country_code = v_home))
                                      or (j.remote_scope = 'timezone' and coalesce(mp.timezone, pr.timezone) is null))
             when 'relocation' then j.workplace_type <> 'remote'
                                 and (j.relocation_support or j.travel_assistance or j.accommodation_assistance)
             when 'visa_sponsorship' then j.sponsorship in ('yes','case_by_case')
             when 'international' then j.country_code is not null and j.country_code is distinct from v_home
             when 'work_abroad' then j.workplace_type <> 'remote' and j.country_code is not null
                                 and j.country_code is distinct from v_home
                                 and (j.sponsorship in ('yes','case_by_case') or j.accepts_non_residents or j.relocation_support)
                                 and (mp.person_id is null
                                      or cardinality(mp.preferred_countries) + cardinality(mp.countries_willing_to_work) = 0
                                      or j.country_code = any (mp.preferred_countries || mp.countries_willing_to_work))
           end
  ), counted as (select count(*) n from base),
  page as (
    select * from base
     order by case when p_tab = 'near_me' then km end asc nulls last, published_at desc
     limit v_limit offset v_offset)
  select (select n from counted),
         coalesce(jsonb_agg(jsonb_build_object(
           'job_id', p.id, 'title', p.title, 'company_id', p.company_id, 'company_name', p.company_name,
           'company_verified', p.company_verified, 'country', p.country_code, 'country_name', p.country_name,
           'location_text', p.location_text, 'distance_km', p.km, 'workplace_type', p.workplace_type,
           'work_type', p.work_type, 'remote_scope', p.remote_scope, 'remote_countries', to_jsonb(p.remote_countries),
           'sponsorship', p.sponsorship, 'relocation_support', p.relocation_support,
           'support', jsonb_build_object('immigration', p.immigration_support, 'legal', p.legal_support,
                                         'visa_fees', p.visa_fees_covered, 'travel', p.travel_assistance,
                                         'accommodation', p.accommodation_assistance),
           'pay', case when p.pay_disclosed is distinct from false and coalesce(p.pay_max, p.pay_min) is not null then
                    jsonb_build_object('min', p.pay_min, 'max', p.pay_max, 'period', p.pay_period, 'currency', p.pay_currency,
                                       'normalized', public.omelo_normalized_pay(coalesce(p.pay_max, p.pay_min), p.pay_period, p.pay_currency, v_cur)) end,
           'published_at', p.published_at,
           'eligibility', case when v_identity is not null then
                            (select jsonb_build_object('status', e->>'status', 'summary', e->>'summary', 'missing', e->'missing', 'notes', e->'notes')
                               from (select omelo_private.omelo_eligibility(v_identity, p.id, true) e) s) end)
           order by case when p_tab = 'near_me' then p.km end asc nulls last, p.published_at desc), '[]'::jsonb)
    into v_total, v_rows
    from page p;
  return jsonb_build_object('tab', p_tab, 'total', coalesce(v_total, 0), 'results', v_rows,
                            'viewer_currency', v_cur, 'home_country', v_home);
end;
$$;

-- 5. Country guide and licensing ----------------------------------------------------------------
create or replace function public.omelo_country_guide(p_country text, p_profession uuid default null)
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select case when cp.country_code is null then null else jsonb_build_object(
    'country', cp.country_code, 'name', cp.name, 'currency', cp.default_currency,
    'currency_name', (select name from currencies where code = cp.default_currency),
    'language', cp.default_language, 'timezone', cp.default_timezone, 'calling_code', cp.calling_code,
    'region', cp.world_region, 'omelo_supported', cp.supported,
    'information', coalesce((select jsonb_agg(jsonb_build_object('topic', i.topic, 'title', i.title, 'summary', i.summary,
                                                                'url', i.official_url, 'source', i.source_name,
                                                                'reviewed_at', i.reviewed_at) order by i.topic, i.title)
                               from country_employment_info i where i.country_code = cp.country_code), '[]'::jsonb),
    'licence_requirements', coalesce((select jsonb_agg(jsonb_build_object('profession', pf.name, 'profession_id', pf.id,
                                                                         'name', lr.name, 'description', lr.description,
                                                                         'level', lr.requirement_level, 'url', lr.official_url,
                                                                         'source', lr.source, 'reviewed_at', lr.reviewed_at)
                                                       order by pf.name, lr.name)
                                        from license_requirements lr join professions pf on pf.id = lr.profession_id
                                       where lr.country_code = cp.country_code
                                         and (p_profession is null or lr.profession_id = p_profession)), '[]'::jsonb),
    'disclaimer', 'Information only, from the official sources linked. Not legal or immigration advice — rules change; check the official source or a licensed adviser before acting.')
  end
  from (select 1) one left join country_policies cp on cp.country_code = upper(p_country);
$$;

create or replace function public.omelo_license_requirements(p_profession uuid, p_country text default null)
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select coalesce(jsonb_agg(jsonb_build_object('country', lr.country_code, 'country_name', cp.name, 'name', lr.name,
                                               'description', lr.description, 'level', lr.requirement_level,
                                               'url', lr.official_url, 'source', lr.source, 'reviewed_at', lr.reviewed_at)
                            order by cp.name, lr.name), '[]'::jsonb)
    from license_requirements lr join country_policies cp on cp.country_code = lr.country_code
   where lr.profession_id = p_profession and (p_country is null or lr.country_code = upper(p_country));
$$;

-- 6. Mobility profile -----------------------------------------------------------------------------
create or replace function public.omelo_save_mobility(p jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_uid uuid := auth.uid(); m mobility_profiles;
begin
  if v_uid is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  begin
    insert into mobility_profiles as t (person_id, current_country, citizenships, timezone, open_to_relocation,
                                   preferred_countries, preferred_city_ids, countries_willing_to_work,
                                   relocation_assistance_required, earliest_relocation_date, remote_preference,
                                   requires_sponsorship, authorization_visibility)
    values (v_uid,
            upper(nullif(p->>'current_country', '')),
            coalesce(array(select upper(x) from jsonb_array_elements_text(p->'citizenships') x), '{}'),
            nullif(p->>'timezone', ''),
            coalesce((p->>'open_to_relocation')::boolean, false),
            coalesce(array(select upper(x) from jsonb_array_elements_text(p->'preferred_countries') x), '{}'),
            coalesce(array(select x::uuid from jsonb_array_elements_text(p->'preferred_city_ids') x), '{}'),
            coalesce(array(select upper(x) from jsonb_array_elements_text(p->'countries_willing_to_work') x), '{}'),
            coalesce((p->>'relocation_assistance_required')::boolean, false),
            nullif(p->>'earliest_relocation_date', '')::date,
            coalesce(nullif(p->>'remote_preference', ''), 'any'),
            (p->>'requires_sponsorship')::boolean,
            coalesce(nullif(p->>'authorization_visibility', ''), 'eligibility_only'))
    on conflict (person_id) do update set
      current_country = excluded.current_country, citizenships = excluded.citizenships, timezone = excluded.timezone,
      open_to_relocation = excluded.open_to_relocation, preferred_countries = excluded.preferred_countries,
      preferred_city_ids = excluded.preferred_city_ids, countries_willing_to_work = excluded.countries_willing_to_work,
      relocation_assistance_required = excluded.relocation_assistance_required,
      earliest_relocation_date = excluded.earliest_relocation_date, remote_preference = excluded.remote_preference,
      requires_sponsorship = excluded.requires_sponsorship, authorization_visibility = excluded.authorization_visibility
    returning * into m;
  exception
    when check_violation or foreign_key_violation or invalid_text_representation or datetime_field_overflow or invalid_datetime_format then
      raise exception 'Check the mobility details: %', sqlerrm using errcode = '22023';
  end;
  perform omelo_private.omelo_emit('MobilityProfileUpdated', 'person', v_uid, null, v_uid,
                                   jsonb_build_object('open_to_relocation', m.open_to_relocation,
                                                      'authorization_visibility', m.authorization_visibility));
  return to_jsonb(m);
end;
$$;

create or replace function public.omelo_my_mobility()
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select jsonb_build_object(
    'mobility', (select to_jsonb(m) from mobility_profiles m where m.person_id = auth.uid()),
    'defaults', jsonb_build_object('authorization_visibility', 'eligibility_only'),
    'authorizations', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'country', a.country_code, 'country_name', cp.name,
                                                                    'status', a.status, 'valid_from', a.valid_from,
                                                                    'expires_on', a.expires_on, 'restrictions', a.work_restrictions,
                                                                    'requires_sponsorship', a.requires_sponsorship,
                                                                    'is_verified', a.is_verified, 'has_document', a.document_id is not null)
                                                  order by cp.name)
                                  from work_authorizations a left join country_policies cp on cp.country_code = a.country_code
                                 where a.person_id = auth.uid()), '[]'::jsonb))
  where auth.uid() is not null;
$$;

-- 7. Grants ---------------------------------------------------------------------------------------
revoke all on function omelo_private.omelo_fx_rate(char, char, timestamptz) from public, anon, authenticated;
revoke all on function omelo_private.omelo_convert(numeric, char, char, timestamptz) from public, anon, authenticated;
revoke all on function omelo_private.omelo_eligibility(uuid, uuid, boolean) from public, anon, authenticated;
revoke all on function omelo_private.omelo_tz_offset(text) from public, anon, authenticated;

revoke all on function public.omelo_convert_currency(numeric, text, text) from public;
revoke all on function public.omelo_normalized_pay(numeric, pay_period, text, text) from public;
revoke all on function public.omelo_admin_add_exchange_rate(text, text, numeric, timestamptz, text) from public, anon;
revoke all on function public.omelo_job_eligibility(uuid, uuid) from public, anon;
revoke all on function public.omelo_candidate_eligibility(uuid, uuid) from public, anon;
revoke all on function public.omelo_global_jobs(text, jsonb, integer, integer) from public, anon;
revoke all on function public.omelo_country_guide(text, uuid) from public;
revoke all on function public.omelo_license_requirements(uuid, text) from public;
revoke all on function public.omelo_save_mobility(jsonb) from public, anon;
revoke all on function public.omelo_my_mobility() from public, anon;

grant execute on function public.omelo_convert_currency(numeric, text, text) to anon, authenticated;
grant execute on function public.omelo_normalized_pay(numeric, pay_period, text, text) to anon, authenticated;
grant execute on function public.omelo_country_guide(text, uuid) to anon, authenticated;
grant execute on function public.omelo_license_requirements(uuid, text) to anon, authenticated;
grant execute on function public.omelo_admin_add_exchange_rate(text, text, numeric, timestamptz, text) to authenticated;
grant execute on function public.omelo_job_eligibility(uuid, uuid) to authenticated;
grant execute on function public.omelo_candidate_eligibility(uuid, uuid) to authenticated;
grant execute on function public.omelo_global_jobs(text, jsonb, integer, integer) to authenticated;
grant execute on function public.omelo_save_mobility(jsonb) to authenticated;
grant execute on function public.omelo_my_mobility() to authenticated;
