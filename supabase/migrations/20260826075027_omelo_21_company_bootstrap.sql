-- ============================================================
-- OMELO 21 — Company bootstrap
--
-- BUG: companies_insert allows a founder to create a company, but
-- company_members_manage requires an existing owner/admin role to insert
-- a membership row. A newly created company therefore had no owner and
-- no possible path to gaining one — the founder was locked out of their
-- own company immediately after creating it.
--
-- FIX: the database creates the owner membership and the free-tier
-- entitlement row itself. This is an invariant, not something the
-- application should be trusted to remember.
-- ============================================================

create or replace function omelo_bootstrap_company()
returns trigger
language plpgsql
security definer
set search_path = public, omelo_private
as $$
begin
  -- The creator becomes owner. Without this the company is unreachable.
  if new.created_by is not null then
    insert into company_members (company_id, person_id, role, is_active)
    values (new.id, new.created_by, 'owner', true)
    on conflict (company_id, person_id, role) do nothing;
  end if;

  -- Free tier. Deliberately generous enough that a restaurant hiring one
  -- cook never hits a paywall (A2 EC-1), and deliberately WITHOUT talent
  -- search, which requires verification (A2 §3.2).
  insert into company_entitlements (
    company_id, plan, recruiter_seats, active_job_slots,
    talent_search_enabled, talent_search_quota_monthly,
    outreach_quota_daily, ai_credits_monthly
  )
  values (new.id, 'free', 2, 3, false, 0, 0, 20)
  on conflict (company_id) do nothing;

  return new;
end;
$$;

revoke execute on function omelo_bootstrap_company() from public, anon, authenticated;

create trigger companies_bootstrap
  after insert on companies
  for each row execute function omelo_bootstrap_company();

-- A company slug must be unique and URL-safe. Generate it when the
-- caller does not supply one, so the client never has to guess.
create or replace function omelo_company_slug(p_name text)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  v_base text;
  v_slug text;
  v_n integer := 0;
begin
  v_base := regexp_replace(lower(trim(p_name)), '[^a-z0-9]+', '-', 'g');
  v_base := trim(both '-' from v_base);
  if v_base = '' then v_base := 'company'; end if;
  v_slug := v_base;
  while exists (select 1 from companies where slug = v_slug) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n::text;
  end loop;
  return v_slug;
end;
$$;

revoke execute on function omelo_company_slug(text) from public, anon;
grant execute on function omelo_company_slug(text) to authenticated;