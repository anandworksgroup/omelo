-- =====================================================================
-- OMELO 11 — Function surface hardening
--
-- SECURITY DEFINER functions bypass RLS. Only three are meant to be
-- called from a client. Everything else is an internal predicate or a
-- trigger body and must not be reachable over PostgREST.
-- =====================================================================

-- ---------------------------------------------------------------
-- FIX: omelo_profile_schema_for accepted an arbitrary person_id while
-- running as definer, which would have let any signed-in user read
-- another person's profession scope. Now self-only.
-- ---------------------------------------------------------------
create or replace function omelo_profile_schema_for(p_person_id uuid default null)
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
language plpgsql stable security definer set search_path = public as $$
declare
  v_person uuid := coalesce(p_person_id, auth.uid());
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if v_person <> auth.uid() and not omelo_is_platform_admin() then
    raise exception 'Not authorised';
  end if;

  return query
  with person_scope as (
    select
      coalesce(array_agg(distinct pr.category_id) filter (where pr.category_id is not null),
               '{}'::uuid[]) as category_ids,
      coalesce(array_agg(distinct pp.profession_id) filter (where pp.profession_id is not null),
               '{}'::uuid[]) as profession_ids
    from persons p
    left join person_professions pp on pp.person_id = p.id
    left join professions pr on pr.id = pp.profession_id
    where p.id = v_person
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
end;
$$;

-- ---------------------------------------------------------------
-- Nearby jobs reads only published jobs and companies, both of which
-- are already anon-readable. It does not need definer rights.
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
language sql stable security invoker set search_path = public as $$
  select
    j.id, j.title, c.display_name,
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
  limit coalesce(p_limit, 50);
$$;

-- ---------------------------------------------------------------
-- Revoke the entire function surface, then re-grant only the three
-- functions a client is meant to call.
-- ---------------------------------------------------------------
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname like 'omelo\_%'
  loop
    execute format('revoke all on function %s from anon, authenticated, public', r.sig);
  end loop;
end $$;

-- Public API surface
grant execute on function omelo_nearby_jobs(
  double precision, double precision, integer, uuid, work_type[], integer
) to anon, authenticated;

grant execute on function omelo_profile_schema_for(uuid) to authenticated;

grant execute on function omelo_mark_application_viewed(uuid) to authenticated;

comment on function omelo_nearby_jobs is
  'Public API. Security invoker: RLS on jobs/companies governs what is returned.';
comment on function omelo_profile_schema_for is
  'Authenticated API. Self-only. Returns the adaptive profile fields for the calling user.';
comment on function omelo_mark_application_viewed is
  'Authenticated API. The only path to opening an application. Writing the viewed state is mandatory and cannot be suppressed by the employer.';
