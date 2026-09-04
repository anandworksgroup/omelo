-- ============================================================
-- OMELO — Invariant verification
--
-- Run this after EVERY migration. Each check corresponds to a bug that
-- actually shipped into the database and was caught later, usually because
-- the earlier testing ran as `service_role` and therefore bypassed RLS
-- entirely.
--
-- Every row should read OK. Anything else is a regression.
--
-- These are structural checks. They are necessary but NOT sufficient —
-- the RLS bug below passed every structural check while being completely
-- broken for real users. Always also test with an `anon` / `authenticated`
-- key. See "Behavioural checks" at the bottom.
-- ============================================================

with checks as (

  -- ---------------------------------------------------------------
  -- BUG 1 (migration 19)
  -- Migration 11 revoked EXECUTE on the RLS helper predicates from anon
  -- AND authenticated. RLS invokes those helpers as the CALLING role, so
  -- every policy on ~40 tables failed for every real user.
  -- ---------------------------------------------------------------
  select 1 as n, 'RLS predicates are executable by real roles' as invariant,
         case when count(*) = 8 then 'OK' else
              'FAIL: only ' || count(*)::text || ' of 8 are callable' end as result
  from pg_proc p
  join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'omelo_private'
    and has_function_privilege('authenticated', p.oid, 'execute')
    and has_function_privilege('anon', p.oid, 'execute')

  union all
  select 2, 'RLS predicates stay off the public API',
         case when count(*) = 0 then 'OK'
              else 'FAIL: exposed — ' || string_agg(p.proname, ', ') end
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public'
    and p.proname in ('omelo_is_company_member','omelo_has_company_role',
                      'omelo_can_access_job','omelo_has_application_from',
                      'omelo_is_interviewer_for','omelo_is_platform_admin',
                      'omelo_is_discoverable_to','omelo_is_identity_discoverable_to')

  union all
  select 3, 'Every table has row level security enabled',
         case when count(*) = 0 then 'OK'
              else 'FAIL: ' || string_agg(c.relname, ', ') end
  from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
  where ns.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity

  -- The client-callable surface is deliberately tiny and enumerated here by
  -- name. A new exposed function should be a conscious decision, so this
  -- check fails on ANY addition rather than counting to a number.
  --   omelo_nearby_jobs            discovery, SECURITY INVOKER, RLS governs it
  --   omelo_profile_schema_for     adaptive profile fields, self-only
  --   omelo_mark_application_viewed the only path to opening an application
  --   omelo_company_slug           slug generation, INVOKER, reads public data
  --   omelo_pay_monthly            pure arithmetic helper
  union all
  select 4, 'Client-callable RPC surface is exactly the approved set',
         case when count(*) = 0 then 'OK'
              else 'FAIL: unapproved — ' || string_agg(p.proname, ', ') end
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public'
    and p.proname like 'omelo_%'
    and (has_function_privilege('anon', p.oid, 'execute')
         or has_function_privilege('authenticated', p.oid, 'execute'))
    and p.proname not in ('omelo_nearby_jobs','omelo_profile_schema_for',
                          'omelo_mark_application_viewed','omelo_company_slug',
                          'omelo_pay_monthly')

  -- ---------------------------------------------------------------
  -- BUG 2 (migration 21)
  -- companies_insert let a founder create a company, but
  -- company_members_manage required an existing owner role to insert the
  -- first owner. Founders were locked out of companies they just made.
  -- ---------------------------------------------------------------
  union all
  select 5, 'Creating a company grants the founder ownership',
         case when count(*) = 1 then 'OK' else 'FAIL: companies_bootstrap missing' end
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
  where c.relname = 'companies' and t.tgname = 'companies_bootstrap'
    and not t.tgisinternal

  -- Scoped to companies with a creator. Seeded demo companies deliberately
  -- have created_by = NULL and therefore no owner — nobody signed up for
  -- them. The invariant that matters is: if a founder created it, they own it.
  union all
  select 6, 'Every founder-created company has its owner',
         case when count(*) = 0 then 'OK'
              else 'FAIL: ' || count(*)::text || ' ownerless companies' end
  from companies co
  where co.deleted_at is null
    and co.created_by is not null
    and not exists (select 1 from company_members m
                    where m.company_id = co.id and m.role = 'owner' and m.is_active)

  -- ---------------------------------------------------------------
  -- BUG 3 (migration 22)
  -- omelo_nearby_jobs filters on `geo is not null`. A job posted through
  -- the portal sets location_id but cannot send PostGIS geography over
  -- PostgREST, so geo was NULL and the job was invisible to every worker
  -- with no error anywhere.
  -- ---------------------------------------------------------------
  union all
  select 7, 'jobs.geo is derived automatically',
         case when count(*) = 1 then 'OK' else 'FAIL: jobs_sync_geo missing' end
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
  where c.relname = 'jobs' and t.tgname = 'jobs_sync_geo' and not t.tgisinternal

  union all
  select 8, 'No published on-site job is invisible to workers',
         case when count(*) = 0 then 'OK'
              else 'FAIL: ' || count(*)::text || ' published jobs have NULL geo' end
  from jobs
  where status = 'published' and geo is null and workplace_type <> 'remote'

  -- ---------------------------------------------------------------
  -- BUG 4 (migration 23)
  -- Employers could PATCH first_viewed_at back to NULL and erase the fact
  -- that they had opened an application, breaking the core promise that
  -- "viewed" cannot be suppressed.
  -- ---------------------------------------------------------------
  union all
  select 9, 'Application record is immutable where it must be',
         case when count(*) = 1 then 'OK'
              else 'FAIL: applications_guard_immutables missing' end
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
  where c.relname = 'applications' and t.tgname = 'applications_guard_immutables'
    and not t.tgisinternal

  union all
  select 10, 'Application history is append-only',
         case when count(*) = 0 then 'OK'
              else 'FAIL: UPDATE/DELETE policies exist on application_events' end
  from pg_policies
  where schemaname = 'public' and tablename = 'application_events'
    and cmd in ('UPDATE','DELETE')

  union all
  select 11, 'Employers cannot invent a candidate-visible state',
         case when count(*) = 0 then 'OK'
              else 'FAIL: ' || count(*)::text || ' stages with no state mapping' end
  from job_stages where maps_to_state is null

  -- ---------------------------------------------------------------
  -- Consent and money invariants
  -- ---------------------------------------------------------------
  union all
  select 12, 'Discoverability defaults to private',
         case when (select column_default from information_schema.columns
                    where table_name = 'work_identities' and column_name = 'discoverability')
                   like '%private%'
              then 'OK' else 'FAIL: default is not private' end

  union all
  select 13, 'Pay always carries a currency and a period',
         case when count(*) = 0 then 'OK'
              else 'FAIL: ' || count(*)::text || ' jobs have an amount but no currency/period' end
  from jobs
  where pay_min is not null and (pay_currency is null or pay_period is null)

  union all
  select 14, 'Match weight profiles each sum to exactly 1.0',
         case when count(*) = 0 then 'OK'
              else 'FAIL: ' || string_agg(name, ', ') end
  from (
    select w.name, round(sum(v.value::numeric), 4) as total
    from weight_profiles w, jsonb_each_text(w.weights) v
    group by w.name
    having round(sum(v.value::numeric), 4) <> 1.0000
  ) bad
)
select n as "#", invariant, result from checks order by n;

-- ============================================================
-- Behavioural checks — the structural ones above are not enough
--
-- The RLS bug passed every structural check while being totally broken.
-- Run these with a PUBLISHABLE key, never the service role:
--
--   1. Signed out, POST /rest/v1/rpc/omelo_nearby_jobs  -> returns jobs
--   2. Signed out, GET  /rest/v1/persons                -> returns 0 rows
--   3. Signed out, POST /rest/v1/rpc/omelo_is_company_member -> 404
--   4. Signed in as an employer, create a company       -> auto owner + free tier
--   5. Create a job with only location_id               -> geo is populated
--   6. Publish it, then search as anon                  -> the job is found
--   7. Mark an application viewed, then as the employer:
--        PATCH first_viewed_at = null  -> rejected, value unchanged
--        PATCH identity_snapshot       -> rejected
--        PATCH person_id               -> rejected
--        DELETE application_events     -> 403
--        PATCH stage_id                -> succeeds, state follows the mapping
-- ============================================================
