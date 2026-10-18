-- OMELO 83 — tax and registration identifiers stop being public.
--
-- `companies_public_read` is `using (deleted_at is null)`. RLS is row-level
-- only, and Supabase grants SELECT on every column to anon and authenticated,
-- so all 31 columns of every organization were readable by anyone with the
-- publishable key and no account at all. Verified live before this migration:
-- an anonymous GET /rest/v1/companies?select=* returned, among others,
-- tax_id, registration_number, created_by, verification_method and
-- stats_computed_at.
--
-- Nothing was leaking tax numbers today only because no organization has
-- filled one in yet (0 of 15). The column was public and waiting. created_by
-- (3 of 15) and verification_method (12 of 15) were live.
--
-- The fix is a grant, not a policy: RLS cannot express column rules. Table
-- SELECT is taken back from both client roles and re-granted column by column,
-- so the public contract is now an allowlist that has to be edited on purpose
-- rather than a table that happens to be readable.
--
-- Checked immediately before applying: no query anywhere reads these five
-- columns from `companies` — not the portal, not the Flutter app, not any of
-- the thirteen E2E suites — and nothing anywhere does `select *` or embeds
-- `companies(*)`. The eight `registration_number` references in the portal are
-- all `company_legal_entities`, a different table this migration does not
-- touch.
--
-- Two authorized read paths replace the open one:
--   * omelo_admin_companies — the platform admin list, which does read
--     verification_method and needs PostgREST filtering and search. A view
--     gated on omelo_is_platform_admin() keeps that working and returns
--     nothing to everybody else.
--   * omelo_organization_private_details — the organization's own identifiers,
--     for owner, admin and finance only. Membership alone is not enough: an
--     ordinary recruiter or viewer is refused.
--
-- What this does NOT fix, deliberately: `companies_public_read` still lets any
-- signed-in person read the public columns of any organization, which is what
-- a public directory is for. The confidential columns are no longer among
-- them, so the cross-organization exposure that mattered is closed.
--
-- Rollback:
--   grant select on public.companies to anon, authenticated;
--   drop view public.omelo_admin_companies;
--   drop function public.omelo_organization_private_details(uuid);

-- ---------------------------------------------------------------
-- 1. The public column contract
-- ---------------------------------------------------------------

revoke select on public.companies from anon, authenticated;

grant select (
  id, slug, display_name, legal_name, about, culture, media,
  logo_url, cover_url, website, industry_id, size_band, founded_year,
  country_code, hq_location_id,
  company_kind, organization_type, is_independent_recruiter,
  is_verified, verified_at,
  response_rate_pct, median_response_hours, total_hires,
  created_at, updated_at, deleted_at
) on public.companies to anon, authenticated;

comment on column public.companies.tax_id is
  'Confidential. Not selectable by anon or authenticated; read through '
  'omelo_organization_private_details (owner, admin, finance).';
comment on column public.companies.registration_number is
  'Confidential. Not selectable by anon or authenticated; read through '
  'omelo_organization_private_details (owner, admin, finance).';
comment on column public.companies.verification_method is
  'Internal. Read through omelo_admin_companies (platform admin) or '
  'omelo_organization_private_details.';

-- ---------------------------------------------------------------
-- 2. The platform admin list
-- ---------------------------------------------------------------
--
-- Deliberately not security_invoker: the view runs as its owner so it can read
-- the columns the client roles just lost, and its own WHERE clause is what
-- decides who may see anything. A caller who is not a platform admin gets zero
-- rows, not an error — the same answer they would get from an empty table.

create or replace view public.omelo_admin_companies
with (security_invoker = false) as
  select c.id, c.slug, c.display_name, c.legal_name,
         c.is_verified, c.verified_at, c.verification_method,
         c.company_kind, c.organization_type, c.is_independent_recruiter,
         c.country_code, c.size_band, c.created_at, c.deleted_at
    from public.companies c
   where omelo_private.omelo_is_platform_admin();

comment on view public.omelo_admin_companies is
  'Platform admin view of organizations, including the internal verification '
  'method. Returns nothing unless omelo_is_platform_admin() is true.';

revoke all on public.omelo_admin_companies from anon;
grant select on public.omelo_admin_companies to authenticated;

-- ---------------------------------------------------------------
-- 3. The organization's own identifiers
-- ---------------------------------------------------------------
--
-- Membership is not the test. Tax and registration identifiers go to the
-- people who have a reason to handle them, and every read is recorded.

create or replace function public.omelo_organization_private_details(p_company uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, omelo_private
as $$
declare r companies;
begin
  if not omelo_private.omelo_has_company_role(
       p_company, array['owner','admin','finance']::company_role[]) then
    raise exception 'Only an owner, admin or finance member can see these details'
      using errcode = '42501';
  end if;

  select * into r from companies where id = p_company and deleted_at is null;
  if r.id is null then
    raise exception 'Organization not found' using errcode = '42704';
  end if;

  perform omelo_private.omelo_emit('OrganizationPrivateDetailsViewed', 'company',
                                   p_company, p_company, auth.uid(), '{}'::jsonb);

  return jsonb_build_object(
    'tax_id', r.tax_id,
    'registration_number', r.registration_number,
    'verification_method', r.verification_method,
    'created_by', r.created_by,
    'stats_computed_at', r.stats_computed_at);
end;
$$;

revoke execute on function public.omelo_organization_private_details(uuid) from public, anon;
grant execute on function public.omelo_organization_private_details(uuid) to authenticated;
