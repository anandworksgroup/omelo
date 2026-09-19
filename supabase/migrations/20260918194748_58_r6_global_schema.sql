-- OMELO 58 — Release 6: Global Employment & Mobility — schema, reference data, security.
--
-- Reused and extended (nothing duplicated):
--   country_policies  = the country table (now: language, time zone, calling
--                       code, region; 50 countries)
--   locations         = the hierarchy country -> region -> city -> area
--                       (+ currency / language overrides; world cities seeded)
--   work_authorizations, person_licenses, license_types, person_languages,
--   job_languages, job_licenses, company_locations, jobs.visa_sponsorship /
--   relocation_support / accepts_non_residents, employments, experiences
--
-- New:
--   currencies                 ISO 4217 codes; every money column now references it (R6-001)
--   exchange_rates             rate + effective_at + source, append-only (R6-011)
--   mobility_profiles          the worker's global mobility; self-only (R6-007)
--   license_requirements       profession x country -> required registration
--   country_employment_info    official-source guidance, marked "not legal advice"
--   company_legal_entities     multi-country employers (entity per country)
--   jobs: sponsorship yes/no/case_by_case + support flags + remote scope / time zones
--   employments: country + original pay currency (R6-012); experiences: country
--
-- Security changes:
--   * work_authorizations were readable by any company that could find the
--     worker. Now: nobody but the worker by default; a worker may share details
--     with companies they applied to, or with companies that can find them.
--     Employers otherwise see only the eligibility result (functions, 59).
--   * reference tables are read-only for clients (R6-003: countries must exist
--     before anything country-specific can point at them).
--
-- Exchange rates seeded here are INDICATIVE (source says so) so that
-- comparisons work in development; production must load rates from a provider
-- through omelo_admin_set_exchange_rate (59). Each conversion reports the rate,
-- its effective time and its source.
--
-- Rollback: drop the new tables/columns/FKs below; restore
-- work_authorizations_employer_read from 08_rls_policies.

-- 1. Countries (country_policies is the country table) ---------------------------------
alter table country_policies
  add column if not exists default_language text,
  add column if not exists default_timezone text,
  add column if not exists calling_code text,
  add column if not exists world_region text;

insert into country_policies (country_code, name, default_currency, default_pay_period, supported,
                              default_language, default_timezone, calling_code, world_region)
values
  ('IE','Ireland','EUR','month',false,'en','Europe/Dublin','+353','Europe'),
  ('FR','France','EUR','month',false,'fr','Europe/Paris','+33','Europe'),
  ('ES','Spain','EUR','month',false,'es','Europe/Madrid','+34','Europe'),
  ('IT','Italy','EUR','month',false,'it','Europe/Rome','+39','Europe'),
  ('PT','Portugal','EUR','month',false,'pt','Europe/Lisbon','+351','Europe'),
  ('BE','Belgium','EUR','month',false,'nl','Europe/Brussels','+32','Europe'),
  ('AT','Austria','EUR','month',false,'de','Europe/Vienna','+43','Europe'),
  ('CH','Switzerland','CHF','month',false,'de','Europe/Zurich','+41','Europe'),
  ('PL','Poland','PLN','month',false,'pl','Europe/Warsaw','+48','Europe'),
  ('SE','Sweden','SEK','month',false,'sv','Europe/Stockholm','+46','Europe'),
  ('NO','Norway','NOK','month',false,'no','Europe/Oslo','+47','Europe'),
  ('DK','Denmark','DKK','month',false,'da','Europe/Copenhagen','+45','Europe'),
  ('TR','Turkey','TRY','month',false,'tr','Europe/Istanbul','+90','Europe'),
  ('JP','Japan','JPY','month',false,'ja','Asia/Tokyo','+81','Asia'),
  ('KR','South Korea','KRW','month',false,'ko','Asia/Seoul','+82','Asia'),
  ('CN','China','CNY','month',false,'zh','Asia/Shanghai','+86','Asia'),
  ('HK','Hong Kong','HKD','month',false,'zh','Asia/Hong_Kong','+852','Asia'),
  ('MY','Malaysia','MYR','month',false,'ms','Asia/Kuala_Lumpur','+60','Asia'),
  ('TH','Thailand','THB','month',false,'th','Asia/Bangkok','+66','Asia'),
  ('VN','Vietnam','VND','month',false,'vi','Asia/Ho_Chi_Minh','+84','Asia'),
  ('ID','Indonesia','IDR','month',false,'id','Asia/Jakarta','+62','Asia'),
  ('PK','Pakistan','PKR','month',false,'ur','Asia/Karachi','+92','Asia'),
  ('BD','Bangladesh','BDT','month',false,'bn','Asia/Dhaka','+880','Asia'),
  ('LK','Sri Lanka','LKR','month',false,'si','Asia/Colombo','+94','Asia'),
  ('NP','Nepal','NPR','month',false,'ne','Asia/Kathmandu','+977','Asia'),
  ('QA','Qatar','QAR','month',false,'ar','Asia/Qatar','+974','Middle East'),
  ('KW','Kuwait','KWD','month',false,'ar','Asia/Kuwait','+965','Middle East'),
  ('BH','Bahrain','BHD','month',false,'ar','Asia/Bahrain','+973','Middle East'),
  ('OM','Oman','OMR','month',false,'ar','Asia/Muscat','+968','Middle East'),
  ('IL','Israel','ILS','month',false,'he','Asia/Jerusalem','+972','Middle East'),
  ('EG','Egypt','EGP','month',false,'ar','Africa/Cairo','+20','Africa'),
  ('NG','Nigeria','NGN','month',false,'en','Africa/Lagos','+234','Africa'),
  ('KE','Kenya','KES','month',false,'en','Africa/Nairobi','+254','Africa'),
  ('NZ','New Zealand','NZD','month',false,'en','Pacific/Auckland','+64','Oceania')
on conflict (country_code) do nothing;

update country_policies c set default_language = v.lang, default_timezone = v.tz, calling_code = v.cc, world_region = v.wr
  from (values ('IN','hi','Asia/Kolkata','+91','Asia'), ('AE','ar','Asia/Dubai','+971','Middle East'),
               ('SA','ar','Asia/Riyadh','+966','Middle East'), ('DE','de','Europe/Berlin','+49','Europe'),
               ('NL','nl','Europe/Amsterdam','+31','Europe'), ('GB','en','Europe/London','+44','Europe'),
               ('US','en','America/New_York','+1','Americas'), ('CA','en','America/Toronto','+1','Americas'),
               ('AU','en','Australia/Sydney','+61','Oceania'), ('SG','en','Asia/Singapore','+65','Asia'),
               ('PH','en','Asia/Manila','+63','Asia'), ('BR','pt','America/Sao_Paulo','+55','Americas'),
               ('MX','es','America/Mexico_City','+52','Americas'), ('ZA','en','Africa/Johannesburg','+27','Africa'))
       as v(code, lang, tz, cc, wr)
 where c.country_code = v.code;

-- 2. Currencies and exchange rates -------------------------------------------------------
create table if not exists public.currencies (
  code         char(3) primary key check (code ~ '^[A-Z]{3}$'),
  name         text not null,
  symbol       text not null,
  minor_units  smallint not null default 2 check (minor_units between 0 and 4),
  active       boolean not null default true
);
insert into currencies (code, name, symbol, minor_units) values
  ('INR','Indian rupee','₹',2), ('USD','US dollar','$',2), ('EUR','Euro','€',2), ('GBP','Pound sterling','£',2),
  ('AED','UAE dirham','AED',2), ('SAR','Saudi riyal','SAR',2), ('CAD','Canadian dollar','CA$',2),
  ('AUD','Australian dollar','A$',2), ('SGD','Singapore dollar','S$',2), ('PHP','Philippine peso','₱',2),
  ('BRL','Brazilian real','R$',2), ('MXN','Mexican peso','MX$',2), ('ZAR','South African rand','R',2),
  ('JPY','Japanese yen','¥',0), ('CNY','Chinese yuan','CN¥',2), ('CHF','Swiss franc','CHF',2),
  ('SEK','Swedish krona','kr',2), ('NOK','Norwegian krone','kr',2), ('DKK','Danish krone','kr',2),
  ('PLN','Polish zloty','zł',2), ('NZD','New Zealand dollar','NZ$',2), ('QAR','Qatari riyal','QAR',2),
  ('KWD','Kuwaiti dinar','KWD',3), ('BHD','Bahraini dinar','BHD',3), ('OMR','Omani rial','OMR',3),
  ('MYR','Malaysian ringgit','RM',2), ('THB','Thai baht','฿',2), ('VND','Vietnamese dong','₫',0),
  ('IDR','Indonesian rupiah','Rp',2), ('KRW','South Korean won','₩',0), ('HKD','Hong Kong dollar','HK$',2),
  ('PKR','Pakistani rupee','Rs',2), ('BDT','Bangladeshi taka','৳',2), ('LKR','Sri Lankan rupee','Rs',2),
  ('NPR','Nepalese rupee','Rs',2), ('TRY','Turkish lira','₺',2), ('ILS','Israeli new shekel','₪',2),
  ('EGP','Egyptian pound','E£',2), ('NGN','Nigerian naira','₦',2), ('KES','Kenyan shilling','KSh',2)
on conflict (code) do nothing;
alter table currencies enable row level security;
drop policy if exists currencies_read on currencies;
create policy currencies_read on currencies for select to anon, authenticated using (true);
revoke insert, update, delete on currencies from anon, authenticated;

create table if not exists public.exchange_rates (
  id            bigint generated always as identity primary key,
  base          char(3) not null references currencies(code),
  quote         char(3) not null references currencies(code),
  rate          numeric(20,10) not null check (rate > 0),
  effective_at  timestamptz not null,
  source        text not null check (length(trim(source)) between 3 and 200),
  created_by    uuid references persons(id) on delete set null,
  created_at    timestamptz not null default now(),
  unique (base, quote, effective_at),
  check (base <> quote)
);
create index if not exists exchange_rates_lookup on exchange_rates (base, quote, effective_at desc);
alter table exchange_rates enable row level security;
drop policy if exists exchange_rates_read on exchange_rates;
create policy exchange_rates_read on exchange_rates for select to anon, authenticated using (true);
revoke insert, update, delete on exchange_rates from anon, authenticated;

-- R6-011: rates are history; a rate is never edited or removed, a newer one is added.
create or replace function omelo_private.omelo_exchange_rates_append_only()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  raise exception 'Exchange rates are history: add a newer rate instead of changing one' using errcode = '23514';
end;
$$;
drop trigger if exists exchange_rates_append_only on exchange_rates;
create trigger exchange_rates_append_only before update or delete on exchange_rates
  for each row execute function omelo_private.omelo_exchange_rates_append_only();

insert into exchange_rates (base, quote, rate, effective_at, source)
select 'USD', q, r, '2026-09-18 00:00:00+00', 'Indicative seed rate (Omelo, Sep 2026) — not for payments; load a live provider'
  from (values ('INR',88.0),('EUR',0.86),('GBP',0.74),('AED',3.6725),('SAR',3.75),('CAD',1.38),('AUD',1.52),
               ('SGD',1.29),('PHP',57.0),('BRL',5.4),('MXN',18.5),('ZAR',17.8),('JPY',147.0),('CNY',7.12),
               ('CHF',0.80),('SEK',9.4),('NOK',10.0),('DKK',6.4),('PLN',3.65),('NZD',1.68),('QAR',3.64),
               ('KWD',0.305),('BHD',0.376),('OMR',0.3845),('MYR',4.2),('THB',32.5),('VND',26000),('IDR',16300),
               ('KRW',1380),('HKD',7.8),('PKR',281),('BDT',122),('LKR',300),('NPR',141),('TRY',41),('ILS',3.35),
               ('EGP',48.5),('NGN',1500),('KES',129)) v(q, r)
on conflict (base, quote, effective_at) do nothing;

-- R6-001: every money column names a real currency
do $$
declare t record;
begin
  for t in select * from (values
      ('jobs','pay_currency'), ('job_orders','pay_currency'), ('workforce_requirements','currency'),
      ('assignments','currency'), ('assignment_billing','currency'), ('earnings','currency'),
      ('payment_records','currency'), ('billing_records','currency'), ('person_work_preferences','pay_currency'),
      ('offers','pay_currency'), ('experiences','pay_currency'), ('country_policies','default_currency'),
      ('placements','fee_currency')) v(tbl, col) loop
    execute format('alter table public.%I drop constraint if exists %I', t.tbl, t.tbl || '_' || t.col || '_currency_fk');
    execute format('alter table public.%I add constraint %I foreign key (%I) references currencies(code)',
                   t.tbl, t.tbl || '_' || t.col || '_currency_fk', t.col);
  end loop;
end;
$$;

-- 3. Locations: currency / language per location; world cities ---------------------------
alter table locations add column if not exists currency_code char(3) references currencies(code),
                      add column if not exists language_code text;

do $$
declare c record; v_country uuid;
begin
  for c in select * from (values
      ('DE','Germany','Berlin','BE',52.5200,13.4050,'Europe/Berlin'),
      ('DE','Germany','Munich','BY',48.1351,11.5820,'Europe/Berlin'),
      ('NL','Netherlands','Amsterdam','NH',52.3676,4.9041,'Europe/Amsterdam'),
      ('GB','United Kingdom','London','ENG',51.5074,-0.1278,'Europe/London'),
      ('IE','Ireland','Dublin','D',53.3498,-6.2603,'Europe/Dublin'),
      ('CA','Canada','Toronto','ON',43.6532,-79.3832,'America/Toronto'),
      ('AE','United Arab Emirates','Dubai','DU',25.2048,55.2708,'Asia/Dubai'),
      ('AU','Australia','Sydney','NSW',-33.8688,151.2093,'Australia/Sydney'),
      ('SG','Singapore','Singapore','SG',1.3521,103.8198,'Asia/Singapore'),
      ('US','United States','New York','NY',40.7128,-74.0060,'America/New_York'),
      ('SA','Saudi Arabia','Riyadh','01',24.7136,46.6753,'Asia/Riyadh'),
      ('QA','Qatar','Doha','DA',25.2854,51.5310,'Asia/Qatar')) v(cc, cname, city, region, lat, lng, tz) loop
    select id into v_country from locations where kind = 'country' and country_code = c.cc limit 1;
    if v_country is null then
      insert into locations (kind, name, country_code, timezone, status, currency_code, language_code)
      values ('country', c.cname, c.cc, c.tz, 'active',
              (select default_currency from country_policies where country_code = c.cc),
              (select default_language from country_policies where country_code = c.cc))
      returning id into v_country;
    end if;
    if not exists (select 1 from locations where kind = 'city' and country_code = c.cc and name = c.city) then
      insert into locations (parent_id, kind, name, country_code, admin_code, latitude, longitude, geo, timezone, status)
      values (v_country, 'city', c.city, c.cc, c.region, c.lat, c.lng,
              extensions.st_setsrid(extensions.st_makepoint(c.lng, c.lat), 4326)::extensions.geography, c.tz, 'active');
    end if;
  end loop;
end;
$$;
update locations l set currency_code = cp.default_currency, language_code = coalesce(l.language_code, cp.default_language)
  from country_policies cp where l.kind = 'country' and cp.country_code = l.country_code and l.currency_code is null;

-- R6-003: countries exist before anything country-specific points at them
do $$
declare t record;
begin
  for t in select * from (values ('jobs'), ('license_types'), ('work_authorizations'), ('persons'), ('companies'),
                                 ('locations'), ('workforce_requirements'), ('person_licenses'), ('overtime_policies'),
                                 ('person_location_preferences')) v(tbl) loop
    execute format('alter table public.%I drop constraint if exists %I', t.tbl, t.tbl || '_country_fk');
    execute format('alter table public.%I add constraint %I foreign key (country_code) references country_policies(country_code)',
                   t.tbl, t.tbl || '_country_fk');
  end loop;
end;
$$;

-- 4. Work authorization: validity period + restrictions; worker-controlled visibility ----
alter table work_authorizations
  add column if not exists valid_from date,
  add column if not exists work_restrictions text check (work_restrictions is null or length(work_restrictions) <= 500),
  add column if not exists updated_at timestamptz not null default now();
alter table work_authorizations drop constraint if exists work_authorizations_dates_check;
alter table work_authorizations add constraint work_authorizations_dates_check
  check (expires_on is null or valid_from is null or expires_on >= valid_from);

create table if not exists public.mobility_profiles (
  person_id                       uuid primary key references persons(id) on delete cascade,
  current_country                 char(2) references country_policies(country_code),
  citizenships                    char(2)[] not null default '{}',
  timezone                        text,
  open_to_relocation              boolean not null default false,
  preferred_countries             char(2)[] not null default '{}',
  preferred_city_ids              uuid[] not null default '{}',
  countries_willing_to_work       char(2)[] not null default '{}',
  relocation_assistance_required  boolean not null default false,
  earliest_relocation_date        date,
  remote_preference               text not null default 'any'
                                  check (remote_preference in ('onsite_only','hybrid','remote_only','any')),
  requires_sponsorship            boolean,
  -- R6-007: who may see the underlying authorization records
  authorization_visibility        text not null default 'eligibility_only'
                                  check (authorization_visibility in ('private','eligibility_only',
                                                                      'details_with_applications','details_with_visible')),
  updated_at                      timestamptz not null default now(),
  check (cardinality(preferred_countries) <= 30 and cardinality(countries_willing_to_work) <= 60
         and cardinality(citizenships) <= 5 and cardinality(preferred_city_ids) <= 30)
);
alter table mobility_profiles enable row level security;
drop policy if exists mobility_profiles_self on mobility_profiles;
create policy mobility_profiles_self on mobility_profiles for all to authenticated
  using (person_id = (select auth.uid())) with check (person_id = (select auth.uid()));

create or replace function omelo_private.omelo_validate_mobility()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare c text;
begin
  foreach c in array (new.citizenships || new.preferred_countries || new.countries_willing_to_work)::text[] loop
    if not exists (select 1 from country_policies where country_code = c) then
      raise exception 'Unknown country %', c using errcode = '22023';
    end if;
  end loop;
  if new.timezone is not null and not exists (select 1 from pg_timezone_names where name = new.timezone) then
    raise exception 'Unknown time zone %', new.timezone using errcode = '22023';
  end if;
  if exists (select 1 from unnest(new.preferred_city_ids) x where not exists (select 1 from locations l where l.id = x)) then
    raise exception 'Unknown city' using errcode = '22023';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists mobility_profiles_validate on mobility_profiles;
create trigger mobility_profiles_validate before insert or update on mobility_profiles
  for each row execute function omelo_private.omelo_validate_mobility();

-- The worker decides who sees authorization records (default: nobody; employers see eligibility only).
drop policy if exists work_authorizations_employer_read on work_authorizations;
create policy work_authorizations_employer_read on work_authorizations for select to authenticated
  using (exists (select 1 from mobility_profiles mp
                  where mp.person_id = work_authorizations.person_id
                    and ((mp.authorization_visibility = 'details_with_applications'
                          and omelo_private.omelo_has_application_from(work_authorizations.person_id))
                      or (mp.authorization_visibility = 'details_with_visible'
                          and (omelo_private.omelo_has_application_from(work_authorizations.person_id)
                               or exists (select 1 from company_members cm
                                           where cm.person_id = (select auth.uid()) and cm.is_active
                                             and cm.role in ('owner','admin','recruiter')
                                             and omelo_private.omelo_is_discoverable_to(work_authorizations.person_id, cm.company_id)))))));

-- 5. Jobs: sponsorship and remote scope -------------------------------------------------------
alter table jobs
  add column if not exists sponsorship text not null default 'no' check (sponsorship in ('yes','no','case_by_case')),
  add column if not exists sponsorship_type text check (sponsorship_type is null or length(sponsorship_type) <= 80),
  add column if not exists immigration_support boolean not null default false,
  add column if not exists legal_support boolean not null default false,
  add column if not exists visa_fees_covered boolean not null default false,
  add column if not exists travel_assistance boolean not null default false,
  add column if not exists accommodation_assistance boolean not null default false,
  add column if not exists remote_scope text check (remote_scope is null or remote_scope in ('country','worldwide','timezone','countries')),
  add column if not exists remote_countries char(2)[] not null default '{}',
  add column if not exists remote_tz_min_offset integer check (remote_tz_min_offset is null or remote_tz_min_offset between -720 and 840),
  add column if not exists remote_tz_max_offset integer check (remote_tz_max_offset is null or remote_tz_max_offset between -720 and 840),
  add column if not exists legal_entity_id uuid;
update jobs set sponsorship = 'yes' where visa_sponsorship and sponsorship = 'no';

-- visa_sponsorship stays the matcher's boolean, derived from sponsorship
create or replace function omelo_private.omelo_sync_job_sponsorship()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  new.visa_sponsorship := new.sponsorship in ('yes','case_by_case');
  if new.remote_scope = 'timezone' and (new.remote_tz_min_offset is null or new.remote_tz_max_offset is null
                                        or new.remote_tz_max_offset < new.remote_tz_min_offset) then
    raise exception 'Give the time-zone range for a time-zone-bound remote job' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(new.remote_countries) c where not exists (select 1 from country_policies where country_code = c)) then
    raise exception 'Unknown country in the remote countries' using errcode = '22023';
  end if;
  return new;
end;
$$;
drop trigger if exists jobs_sync_sponsorship on jobs;
create trigger jobs_sync_sponsorship before insert or update on jobs
  for each row execute function omelo_private.omelo_sync_job_sponsorship();

-- 6. Multi-country employers -------------------------------------------------------------------
create table if not exists public.company_legal_entities (
  id                   uuid primary key default gen_random_uuid(),
  company_id           uuid not null references companies(id) on delete cascade,
  country_code         char(2) not null references country_policies(country_code),
  legal_name           text not null check (length(trim(legal_name)) between 2 and 200),
  registration_number  text check (registration_number is null or length(registration_number) <= 80),
  currency             char(3) not null references currencies(code),
  timezone             text not null,
  hiring_notes         text check (hiring_notes is null or length(hiring_notes) <= 2000),
  is_default           boolean not null default false,
  created_at           timestamptz not null default now(),
  unique (company_id, country_code, legal_name)
);
create unique index if not exists company_legal_entities_default on company_legal_entities (company_id, country_code) where is_default;
alter table company_legal_entities enable row level security;
drop policy if exists company_legal_entities_read on company_legal_entities;
drop policy if exists company_legal_entities_write on company_legal_entities;
create policy company_legal_entities_read on company_legal_entities for select to authenticated
  using (omelo_private.omelo_is_company_member(company_id));
create policy company_legal_entities_write on company_legal_entities for all to authenticated
  using (omelo_private.omelo_has_company_role(company_id, array['owner','admin']::company_role[]))
  with check (omelo_private.omelo_has_company_role(company_id, array['owner','admin']::company_role[]));
alter table company_locations add column if not exists legal_entity_id uuid references company_legal_entities(id) on delete set null;
alter table jobs drop constraint if exists jobs_legal_entity_fk;
alter table jobs add constraint jobs_legal_entity_fk foreign key (legal_entity_id) references company_legal_entities(id) on delete set null;

-- 7. Professional licensing by country --------------------------------------------------------
create table if not exists public.license_requirements (
  id                  uuid primary key default gen_random_uuid(),
  profession_id       uuid not null references professions(id) on delete cascade,
  country_code        char(2) not null references country_policies(country_code),
  region_code         text,
  name                text not null check (length(trim(name)) between 2 and 200),
  description         text check (description is null or length(description) <= 2000),
  license_type_id     uuid references license_types(id) on delete set null,
  credential_type_id  uuid references credential_types(id) on delete set null,
  requirement_level   text not null default 'required' check (requirement_level in ('required','recommended')),
  official_url        text check (official_url is null or official_url ~ '^https://'),
  source              text not null,
  reviewed_at         date,
  unique (profession_id, country_code, name)
);
alter table license_requirements enable row level security;
drop policy if exists license_requirements_read on license_requirements;
create policy license_requirements_read on license_requirements for select to anon, authenticated using (true);
revoke insert, update, delete on license_requirements from anon, authenticated;

-- 8. Country employment information (official sources; informational, not legal advice) ------
create table if not exists public.country_employment_info (
  id             uuid primary key default gen_random_uuid(),
  country_code   char(2) not null references country_policies(country_code),
  topic          text not null check (topic in ('work_authorization','documents','licensing','hiring','worker_rights','tax_payroll','official_portal')),
  title          text not null,
  summary        text not null,
  official_url   text not null check (official_url ~ '^https://'),
  source_name    text not null,
  reviewed_at    date not null,
  unique (country_code, topic, official_url)
);
alter table country_employment_info enable row level security;
drop policy if exists country_employment_info_read on country_employment_info;
create policy country_employment_info_read on country_employment_info for select to anon, authenticated using (true);
revoke insert, update, delete on country_employment_info from anon, authenticated;

insert into country_employment_info (country_code, topic, title, summary, official_url, source_name, reviewed_at) values
  ('DE','official_portal','Working in Germany','The German federal government''s portal for skilled workers: visas, recognition of qualifications and job search.','https://www.make-it-in-germany.com','Make it in Germany (Federal Government of Germany)','2026-09-18'),
  ('DE','licensing','Recognition of foreign professional qualifications','Regulated professions (for example nursing) need recognition of a foreign qualification before working in them.','https://www.anerkennung-in-deutschland.de','Recognition in Germany (Federal Institute for Vocational Education and Training)','2026-09-18'),
  ('NL','work_authorization','Residence and work permits','Immigration and Naturalisation Service: permits for work, including highly skilled migrants.','https://ind.nl','IND — Immigration and Naturalisation Service','2026-09-18'),
  ('GB','work_authorization','Visas and immigration','UK Government guidance on work visas, including the Skilled Worker visa.','https://www.gov.uk/browse/visas-immigration/work-visas','GOV.UK','2026-09-18'),
  ('IE','work_authorization','Employment permits','Department of Enterprise guidance on employment permits in Ireland.','https://enterprise.gov.ie/en/what-we-do/workplace-and-skills/employment-permits/','Department of Enterprise, Trade and Employment','2026-09-18'),
  ('CA','work_authorization','Work in Canada','Government of Canada: work permits and immigration programmes.','https://www.canada.ca/en/immigration-refugees-citizenship/services/work-canada.html','Government of Canada','2026-09-18'),
  ('US','work_authorization','Working in the United States','U.S. Citizenship and Immigration Services: employment-based options and work authorization.','https://www.uscis.gov/working-in-the-united-states','USCIS','2026-09-18'),
  ('AU','work_authorization','Visas for working in Australia','Department of Home Affairs: work visas.','https://immi.homeaffairs.gov.au/visas/working-in-australia','Department of Home Affairs','2026-09-18'),
  ('SG','work_authorization','Work passes','Ministry of Manpower: passes for foreign workers.','https://www.mom.gov.sg/passes-and-permits','Ministry of Manpower','2026-09-18'),
  ('AE','official_portal','Working in the UAE','The UAE government portal: work permits, visas and employment.','https://u.ae/en/information-and-services/jobs','The Official Portal of the UAE Government','2026-09-18'),
  ('IN','documents','Emigration clearance for overseas employment','Ministry of External Affairs e-Migrate: registered recruiting agents and emigration clearance for workers going abroad.','https://emigrate.gov.in','e-Migrate, Ministry of External Affairs','2026-09-18')
on conflict do nothing;

insert into license_requirements (profession_id, country_code, name, description, requirement_level, official_url, source, reviewed_at)
select p.id, v.cc, v.name, v.descr, 'required', v.url, v.src, date '2026-09-18'
  from (values
    ('nurse','DE','Recognition as a nurse (Pflegefachfrau/-mann) and a licence to use the title',
     'A foreign nursing qualification must be recognised by the responsible state authority before working as a registered nurse.',
     'https://www.anerkennung-in-deutschland.de','Recognition in Germany'),
    ('nurse','CA','Registration with the provincial or territorial nursing regulator',
     'Nurses must register with the regulator of the province or territory where they will work.',
     'https://www.canada.ca/en/immigration-refugees-citizenship/services/work-canada.html','Government of Canada'),
    ('nurse','GB','Registration with the Nursing and Midwifery Council',
     'Nurses must be on the NMC register to practise in the UK.',
     'https://www.nmc.org.uk','Nursing and Midwifery Council'),
    ('electrician','DE','Recognition of the electrician qualification',
     'Electrical work in Germany is a regulated trade; foreign qualifications are assessed for equivalence.',
     'https://www.anerkennung-in-deutschland.de','Recognition in Germany')) v(slug, cc, name, descr, url, src)
  join professions p on p.slug = v.slug
on conflict (profession_id, country_code, name) do nothing;

-- 9. Global employment record (R6-012) --------------------------------------------------------
alter table employments
  add column if not exists country_code char(2) references country_policies(country_code),
  add column if not exists pay_amount numeric,
  add column if not exists pay_period pay_period,
  add column if not exists pay_currency char(3) references currencies(code),
  add column if not exists employment_type text;
alter table experiences add column if not exists country_code char(2) references country_policies(country_code);
