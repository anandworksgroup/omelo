-- =====================================================================
-- OMELO 10 — Auth wiring, product functions, grants
-- =====================================================================

create or replace function omelo_handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
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

  insert into person_work_preferences (person_id) values (new.id)
  on conflict (person_id) do nothing;

  insert into notification_preferences (person_id) values (new.id)
  on conflict (person_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function omelo_handle_new_user();

-- ---------------------------------------------------------------
-- ADAPTIVE PROFILE RESOLVER
-- Returns exactly which profile fields this person should be shown,
-- based on the work they are looking for. A driver gets vehicle
-- classes; a nurse gets specialisations; nobody gets both.
-- ---------------------------------------------------------------
create or replace function omelo_profile_schema_for(p_person_id uuid)
returns table (
  attribute_id  uuid,
  slug          text,
  label         text,
  help_text     text,
  data_type     attribute_data_type,
  options       jsonb,
  is_required   boolean,
  sort_position smallint,
  scope         text
)
language sql stable security definer set search_path = public as $$
  with person_scope as (
    select
      coalesce(array_agg(distinct pr.category_id) filter (where pr.category_id is not null),
               '{}'::uuid[]) as category_ids,
      coalesce(array_agg(distinct pp.profession_id) filter (where pp.profession_id is not null),
               '{}'::uuid[]) as profession_ids
    from persons p
    left join person_professions pp on pp.person_id = p.id
    left join professions pr on pr.id = pp.profession_id
    where p.id = p_person_id
  )
  select
    a.id, a.slug, a.label, a.help_text, a.data_type, a.options,
    a.is_required, a.position,
    case
      when a.profession_id is not null then 'profession'
      when a.category_id   is not null then 'category'
      else 'universal'
    end
  from profile_attributes a, person_scope s
  where a.status = 'active'
    and (
      (a.category_id is null and a.profession_id is null)
      or a.category_id = any(s.category_ids)
      or a.profession_id = any(s.profession_ids)
    )
  order by
    case when a.profession_id is not null then 0
         when a.category_id is not null then 1
         else 2 end,
    a.position;
$$;

comment on function omelo_profile_schema_for is
  'The adaptive profile. The Flutter app calls this to decide which fields to render. No profession-specific columns exist anywhere in the person tables.';

-- ---------------------------------------------------------------
-- NEARBY JOBS
-- "2.4 km away" is the primary discovery mode for a large share of
-- the workforce. Geo is a first-class query, not a filter afterthought.
-- ---------------------------------------------------------------
create or replace function omelo_nearby_jobs(
  p_lat double precision,
  p_lng double precision,
  p_radius_km integer default 25,
  p_category_id uuid default null,
  p_work_types work_type[] default null,
  p_limit integer default 50
)
returns table (
  job_id         uuid,
  title          text,
  company_name   text,
  distance_km    numeric,
  pay_min        numeric,
  pay_max        numeric,
  job_pay_period pay_period,
  pay_currency   char(3),
  job_work_type  work_type,
  job_workplace  workplace_type,
  published_at   timestamptz
)
language sql stable security definer set search_path = public as $$
  select
    j.id,
    j.title,
    c.display_name,
    round((extensions.st_distance(
      j.geo,
      extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography
    ) / 1000)::numeric, 1),
    j.pay_min, j.pay_max, j.pay_period, j.pay_currency,
    j.work_type, j.workplace_type, j.published_at
  from jobs j
  join companies c on c.id = j.company_id
  where j.status = 'published'
    and j.geo is not null
    and extensions.st_dwithin(
          j.geo,
          extensions.st_setsrid(extensions.st_makepoint(p_lng, p_lat), 4326)::extensions.geography,
          p_radius_km * 1000
        )
    and (p_category_id is null or j.category_id = p_category_id)
    and (p_work_types is null or j.work_type = any(p_work_types))
    and (j.expires_at is null or j.expires_at > now())
  order by 4 asc
  limit p_limit;
$$;

-- ---------------------------------------------------------------
-- Honest "viewed" state. Cannot be suppressed by the employer.
-- ---------------------------------------------------------------
create or replace function omelo_mark_application_viewed(p_application_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_app applications%rowtype;
begin
  select * into v_app from applications where id = p_application_id;
  if not found then
    raise exception 'Application not found';
  end if;

  if not omelo_can_access_job(v_app.job_id) then
    raise exception 'Not authorised';
  end if;

  if v_app.first_viewed_at is null then
    update applications
      set first_viewed_at = now(),
          state = case when state = 'applied' then 'viewed'::application_state else state end,
          last_activity_at = now()
      where id = p_application_id;

    insert into application_events (application_id, event_type, actor_type, actor_id)
    values (p_application_id, 'viewed', 'recruiter', auth.uid());
  end if;

  insert into profile_views (person_id, viewer_company_id, viewer_person_id, context_job_id)
  values (v_app.person_id, v_app.company_id, auth.uid(), v_app.job_id);
end;
$$;

comment on function omelo_mark_application_viewed is
  'The only path to reading an application detail. Writing the viewed state is not optional and cannot be suppressed by the employer.';

-- ---------------------------------------------------------------
-- Grants. RLS still governs row visibility.
-- ---------------------------------------------------------------
grant usage on schema public to anon, authenticated, service_role;

grant select on all tables in schema public to anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to authenticated, service_role;
grant execute on all functions in schema public to authenticated, service_role;

alter default privileges in schema public grant select on tables to anon;
alter default privileges in schema public grant select, insert, update, delete on tables to authenticated;
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant usage, select on sequences to authenticated, service_role;

-- Append-only / steward-only enforcement at the grant level too.
revoke update, delete on application_events from authenticated, anon;
revoke insert, update, delete on audit_log from authenticated, anon;
revoke update, delete on fraud_signals from authenticated, anon;
revoke insert, delete on automated_decision_log from authenticated, anon;

revoke insert, update, delete on
  job_categories, professions, profession_aliases, profession_transitions,
  skills, skill_aliases, skill_relations, profession_skills,
  license_types, credential_types, institutions, industries, languages,
  locations, country_policies, profile_attributes, weight_profiles
from authenticated, anon;