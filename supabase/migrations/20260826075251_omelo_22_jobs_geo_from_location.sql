-- ============================================================
-- OMELO 22 — Derive jobs.geo from the chosen location
--
-- BUG WAITING TO HAPPEN: omelo_nearby_jobs filters on `j.geo is not null`.
-- A job posted through the portal sets location_id (or company_location_id)
-- but has no way to send a PostGIS geography over PostgREST, so geo would
-- be NULL and the job would never appear in discovery — invisible to every
-- worker, with no error anywhere. The seed data only worked because it set
-- geo explicitly in SQL.
--
-- FIX: derive geo in the database, from the most specific source available.
-- ============================================================

create or replace function omelo_sync_job_geo()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
declare v_geo extensions.geography;
begin
  -- Explicit geo wins (ingestion may supply exact coordinates).
  if new.geo is not null then
    return new;
  end if;

  -- Otherwise prefer the company site, then the job's location node.
  if new.company_location_id is not null then
    select cl.geo into v_geo from company_locations cl where cl.id = new.company_location_id;
  end if;

  if v_geo is null and new.location_id is not null then
    select l.geo into v_geo from locations l where l.id = new.location_id;
  end if;

  new.geo := v_geo;

  -- Country follows the location so country_policies resolves correctly.
  if new.country_code is null and new.location_id is not null then
    select l.country_code into new.country_code from locations l where l.id = new.location_id;
  end if;

  return new;
end;
$$;

revoke execute on function omelo_sync_job_geo() from public, anon, authenticated;

create trigger jobs_sync_geo
  before insert or update of location_id, company_location_id, geo on jobs
  for each row execute function omelo_sync_job_geo();

-- A remote job has no coordinates but must still be discoverable. Relax the
-- discovery filter so remote work is returned regardless of distance.
create or replace function omelo_publish_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status = 'published' and old.status is distinct from 'published' then
    if new.geo is null and new.workplace_type not in ('remote') then
      raise exception
        'Cannot publish an on-site job without a location: workers find jobs by distance';
    end if;
    if new.published_at is null then
      new.published_at := now();
    end if;
    if new.expires_at is null then
      new.expires_at := now() + interval '30 days';
    end if;
  end if;
  return new;
end;
$$;

revoke execute on function omelo_publish_guard() from public, anon, authenticated;

create trigger jobs_publish_guard
  before update of status on jobs
  for each row execute function omelo_publish_guard();