-- ============================================================
-- OMELO 18 — richer nearby-jobs discovery + pay normalisation
--
-- Extends the existing client RPC rather than adding a fourth one, so
-- the client-callable surface stays at three (A4 §5).
-- ============================================================

-- ------------------------------------------------------------
-- Pay normalisation to a monthly figure.
-- docs/12 Q8: these constants are per-country and currently India
-- defaults (8h day, 26-day month). Wrong constants make daily-wage
-- jobs rank incorrectly against monthly ones — a failure that would
-- hit exactly the workers Omelo exists for, so they live in one
-- function rather than scattered through queries.
-- ------------------------------------------------------------
create or replace function omelo_pay_monthly(
  p_amount numeric,
  p_period pay_period,
  p_country char(2) default 'IN'
) returns numeric
language sql immutable as $$
  select case p_period
    when 'hour'      then p_amount * 8 * 26
    when 'day'       then p_amount * 26
    when 'week'      then p_amount * 4.333
    when 'fortnight' then p_amount * 2
    when 'month'     then p_amount
    when 'year'      then p_amount / 12
    else null                      -- per_task has no meaningful monthly value
  end;
$$;
revoke execute on function omelo_pay_monthly(numeric, pay_period, char) from public;
grant execute on function omelo_pay_monthly(numeric, pay_period, char) to anon, authenticated;

-- ------------------------------------------------------------
-- Nearby jobs, v2
-- ------------------------------------------------------------
drop function if exists omelo_nearby_jobs(double precision, double precision, integer, uuid, work_type[], integer);

create function omelo_nearby_jobs(
  p_lat              double precision,
  p_lng              double precision,
  p_radius_km        integer default 25,
  p_category_id      uuid default null,
  p_work_types       work_type[] default null,
  p_limit            integer default 50,
  p_search           text default null,
  p_no_experience    boolean default false,
  p_min_pay_monthly  numeric default null,
  p_shift_types      shift_type[] default null,
  p_offset           integer default 0
)
returns table (
  job_id uuid,
  title text,
  company_id uuid,
  company_name text,
  company_slug text,
  company_verified boolean,
  company_response_hours integer,
  distance_km numeric,
  location_text text,
  pay_min numeric,
  pay_max numeric,
  job_pay_period pay_period,
  pay_currency character,
  pay_negotiable boolean,
  pay_monthly_min numeric,
  job_work_type work_type,
  job_workplace workplace_type,
  shift_types shift_type[],
  accepts_no_experience boolean,
  min_experience_months smallint,
  is_immediate_start boolean,
  quick_apply_enabled boolean,
  openings smallint,
  category_slug text,
  profession_name text,
  benefits text[],
  published_at timestamptz
)
language sql stable
set search_path to 'public'
as $$
  with origin as (
    select extensions.st_setsrid(
             extensions.st_makepoint(p_lng, p_lat), 4326
           )::extensions.geography as g
  )
  select
    j.id, j.title,
    c.id, c.display_name, c.slug, c.is_verified, c.median_response_hours,
    round((extensions.st_distance(j.geo, o.g) / 1000)::numeric, 1),
    j.location_text,
    j.pay_min, j.pay_max, j.pay_period, j.pay_currency, j.pay_negotiable,
    omelo_pay_monthly(j.pay_min, j.pay_period, j.country_code),
    j.work_type, j.workplace_type, j.shift_types,
    j.accepts_no_experience, j.min_experience_months, j.is_immediate_start,
    j.quick_apply_enabled, j.openings,
    cat.slug, prof.name,
    coalesce((
      select array_agg(b.benefit_type::text order by b.benefit_type)
      from job_benefits b where b.job_id = j.id
    ), '{}'::text[]),
    j.published_at
  from jobs j
  cross join origin o
  join companies c   on c.id = j.company_id and c.deleted_at is null
  left join job_categories cat on cat.id = j.category_id
  left join professions prof   on prof.id = j.profession_id
  where j.status = 'published'
    and j.geo is not null
    and extensions.st_dwithin(j.geo, o.g, p_radius_km * 1000)
    and (j.expires_at is null or j.expires_at > now())
    and (p_category_id is null or j.category_id = p_category_id)
    and (p_work_types is null  or j.work_type = any(p_work_types))
    and (p_shift_types is null or j.shift_types && p_shift_types)
    and (p_no_experience is not true or j.accepts_no_experience)
    and (p_min_pay_monthly is null
         or omelo_pay_monthly(j.pay_min, j.pay_period, j.country_code) >= p_min_pay_monthly)
    and (
      p_search is null or p_search = ''
      or j.title ilike '%' || p_search || '%'
      or c.display_name ilike '%' || p_search || '%'
      or prof.name ilike '%' || p_search || '%'
      or cat.name ilike '%' || p_search || '%'
      or exists (
        select 1 from profession_aliases pa
        where pa.profession_id = j.profession_id
          and pa.alias ilike '%' || p_search || '%'
      )
    )
    -- Gates: a worker never sees a job they hid, or one from a company
    -- they blocked. Enforced in the query, never as a post-filter.
    and not exists (
      select 1 from hidden_jobs h
      where h.person_id = auth.uid() and h.job_id = j.id
    )
    and not exists (
      select 1 from blocks bl
      where bl.person_id = auth.uid()
        and bl.target_type = 'company' and bl.target_id = c.id
    )
  order by 8 asc, j.published_at desc
  limit coalesce(p_limit, 50)
  offset coalesce(p_offset, 0);
$$;

grant execute on function omelo_nearby_jobs(
  double precision, double precision, integer, uuid, work_type[], integer,
  text, boolean, numeric, shift_type[], integer
) to anon, authenticated;