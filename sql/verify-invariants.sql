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
    and p.proname in ('omelo_is_company_member','omelo_has_company_role',
                      'omelo_can_access_job','omelo_has_application_from',
                      'omelo_is_interviewer_for','omelo_is_platform_admin',
                      'omelo_is_discoverable_to','omelo_is_identity_discoverable_to')
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
  --   omelo_rank_applicants / omelo_my_match / omelo_recommend_jobs
  --                                Matching v1 (24), each authorises first
  --   omelo_move_application / reject / withdraw_application,
  --   omelo_schedule / reschedule / confirm / cancel / complete_interview,
  --   omelo_send / withdraw / view_offer, omelo_respond_to_offer
  --                                the hiring loop (25) — the ONLY way state moves
  --   omelo_meet_* / save_interview_feedback / question_suggestions / report_meet_abuse
  --                                Omelo Meet (28). omelo_comms_claim/mark are service_role ONLY
  --                                and must never appear here.
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
                          'omelo_pay_monthly',
                          'omelo_rank_applicants','omelo_my_match','omelo_recommend_jobs',
                          'omelo_move_application','omelo_reject_application','omelo_withdraw_application',
                          'omelo_schedule_interview','omelo_reschedule_interview','omelo_confirm_interview',
                          'omelo_cancel_interview','omelo_complete_interview',
                          'omelo_send_offer','omelo_withdraw_offer','omelo_view_offer',
                          'omelo_respond_to_offer',
                          -- Omelo Meet (28)
                          'omelo_save_interview_feedback','omelo_interview_question_suggestions',
                          'omelo_meet_join','omelo_meet_admit','omelo_meet_leave','omelo_meet_remove',
                          'omelo_meet_end','omelo_report_meet_abuse',
                          -- Messaging (32)
                          'omelo_start_conversation','omelo_send_message','omelo_mark_conversation_read',
                          -- Release 1 (35): trust, sessions, account lifecycle, admin observability
                          'omelo_my_trust_status','omelo_request_email_verification','omelo_request_phone_verification',
                          'omelo_confirm_verification','omelo_my_sessions','omelo_revoke_session','omelo_revoke_other_sessions',
                          'omelo_request_account_deletion','omelo_cancel_account_deletion',
                          'omelo_admin_system_health','omelo_admin_kpis','omelo_am_i_platform_admin',
                          -- Release 2 (38): professional identity
                          'omelo_create_work_identity','omelo_set_primary_identity','omelo_archive_work_identity',
                          'omelo_delete_work_identity','omelo_identity_profile','omelo_save_identity_profile',
                          'omelo_identity_evidence')

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

  -- ---------------------------------------------------------------
  -- HIRING LOOP INTEGRITY (migration 25). Each was exploited with real
  -- logins before the fix: see sql/README.md.
  -- ---------------------------------------------------------------
  union all
  select 15, 'Hiring guard triggers are installed',
         case when count(*) = 12 then 'OK'
              else 'FAIL: only ' || count(*)::text || ' of 12 guard triggers present' end
  from pg_trigger
  where not tgisinternal and tgname in (
    'applications_guard_transitions','applications_guard_insert','offers_guard','interviews_guard',
    'employments_guard','companies_guard_trust','experiences_guard_trust','person_skills_guard_trust',
    'educations_guard_trust','person_credentials_guard_trust','person_licenses_guard_trust',
    'work_authorizations_guard_trust')

  union all
  select 16, 'Guards are SECURITY INVOKER (current_user must be the caller)',
         case when count(*) = 0 then 'OK'
              else 'FAIL: definer guard — ' || string_agg(p.proname, ', ') end
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'omelo_private' and p.prosecdef
    and (p.proname like 'omelo_guard_%' or p.proname = 'omelo_is_privileged')

  union all
  select 17, 'Clients cannot write the audit trail or create employments',
         case when count(*) = 0 then 'OK'
              else 'FAIL: ' || string_agg(tablename || '.' || policyname, ', ') end
  from pg_policies
  where schemaname = 'public'
    and ((tablename = 'application_events' and cmd in ('INSERT','ALL','UPDATE','DELETE'))
      or (tablename = 'employments' and cmd in ('INSERT','ALL')))

  union all
  select 18, 'Every hire went through an accepted offer',
         case when count(*) = 0 then 'OK'
              else 'FAIL: ' || count(*)::text || ' hired applications with no accepted offer + employment' end
  from applications a
  where a.state = 'hired'
    and not exists (select 1 from offers o join employments e on e.offer_id = o.id
                     where o.application_id = a.id and o.status = 'accepted')

  union all
  select 19, 'Verified experiences trace to a real employment',
         case when count(*) = 0 then 'OK'
              else 'FAIL: ' || count(*)::text || ' verified experiences with no employment' end
  from experiences x
  where x.is_verified
    and not exists (select 1 from employments e where e.id = x.verified_employment_id)

  union all
  select 20, 'Domain events are not reachable from the client API',
         case when not has_table_privilege('anon', 'public.domain_events', 'select')
               and not has_table_privilege('authenticated', 'public.domain_events', 'select')
               and not has_table_privilege('authenticated', 'public.domain_events', 'insert')
              then 'OK' else 'FAIL: client role has privileges on domain_events' end

  -- ---------------------------------------------------------------
  -- OMELO MEET (migration 28)
  -- ---------------------------------------------------------------
  union all
  select 21, 'Interviews cannot be recorded (no consent flow exists yet)',
         case when exists (select 1 from pg_constraint
                            where conrelid = 'public.interview_rooms'::regclass
                              and pg_get_constraintdef(oid) ilike '%recording_enabled = false%')
               and not exists (select 1 from interview_rooms where recording_enabled)
              then 'OK' else 'FAIL: recording can be enabled' end

  union all
  select 22, 'Candidates have no read path to questions, feedback or answers',
         case when count(*) = 0 then 'OK'
              else 'FAIL: ' || string_agg(tablename || '.' || policyname, ', ') end
  from pg_policies
  where schemaname = 'public'
    and tablename in ('interview_feedback','interview_answers','interview_questions')
    and (coalesce(qual, '') || coalesce(with_check, '')) ~* '(is_interview_candidate|person_id = (\( SELECT )?auth\.uid\(\)|was_admitted)'

  union all
  select 23, 'Email outbox is server-only',
         case when not has_table_privilege('authenticated', 'public.outbound_messages', 'select')
               and not has_table_privilege('anon', 'public.outbound_messages', 'select')
               and not has_function_privilege('authenticated', 'public.omelo_comms_claim(integer)', 'execute')
               and not has_function_privilege('authenticated', 'public.omelo_comms_mark(uuid, boolean, text, text)', 'execute')
              then 'OK' else 'FAIL: clients can reach the outbox' end

  union all
  select 24, 'Every Omelo Meet interview has exactly one room',
         case when count(*) = 0 then 'OK'
              else 'FAIL: ' || count(*)::text || ' Omelo Meet interviews without a room' end
  from interviews i
  where i.meeting_mode = 'omelo_meet' and not exists (select 1 from interview_rooms r where r.interview_id = i.id)

  union all
  select 25, 'No room stays joinable after it closes',
         case when count(*) = 0 then 'OK'
              else 'FAIL: ' || count(*)::text || ' rooms past closes_at still open (is omelo-meet-housekeeping scheduled?)' end
  from interview_rooms
  where status in ('scheduled','live') and closes_at < now() - interval '10 minutes'

  -- ---------------------------------------------------------------
  -- MESSAGING + NOTIFICATIONS (migration 32)
  -- ---------------------------------------------------------------
  union all
  select 26, 'Conversations and messages are only written through functions',
         case when count(*) = 0 then 'OK'
              else 'FAIL: ' || string_agg(tablename || '.' || policyname, ', ') end
  from pg_policies
  where schemaname = 'public'
    and ((tablename = 'messages' and cmd in ('INSERT','UPDATE','DELETE','ALL'))
      or (tablename = 'conversations' and cmd in ('INSERT','DELETE','ALL'))
      or (tablename = 'notifications' and cmd in ('INSERT','ALL')))

  union all
  select 27, 'Policies evaluate auth.uid() once per statement, not per row',
         case when count(*) = 0 then 'OK'
              else 'FAIL: ' || string_agg(tablename || '.' || policyname, ', ') end
  from pg_policies
  where schemaname = 'public'
    and (coalesce(qual, '') || coalesce(with_check, '')) ~ '(?<!SELECT )auth\.uid\(\)'

  -- ---------------------------------------------------------------
  -- RELEASE 1 (migrations 35-36)
  -- ---------------------------------------------------------------
  union all
  select 28, 'Deleting an account is never blocked by a foreign key',
         case when count(*) = 0 then 'OK'
              else 'FAIL: NO ACTION/RESTRICT FKs to persons — ' || string_agg(c.conrelid::regclass::text || '.' || c.conname, ', ') end
  from pg_constraint c
  where c.contype = 'f' and c.confdeltype in ('a','r')
    and c.confrelid in ('public.persons'::regclass, 'auth.users'::regclass)

  union all
  select 29, 'Verification codes are hashed and unreachable from the API',
         case when not has_table_privilege('authenticated', 'omelo_private.verification_challenges', 'select')
               and not has_table_privilege('anon', 'omelo_private.verification_challenges', 'select')
               and not exists (select 1 from information_schema.columns
                                where table_schema = 'omelo_private' and table_name = 'verification_challenges'
                                  and column_name in ('code','plain_code'))
              then 'OK' else 'FAIL: verification codes exposed or stored in clear' end

  union all
  select 30, 'Scheduled jobs are installed',
         case when count(*) = 4 then 'OK'
              else 'FAIL: only ' || count(*)::text || ' of 4 cron jobs present and active' end
  from cron.job
  where active and jobname in ('omelo-comms-dispatch','omelo-meet-housekeeping',
                               'omelo-account-deletions','omelo-outbox-retention')

  -- ---------------------------------------------------------------
  -- RELEASE 2 (migrations 38-39): professional identity
  -- ---------------------------------------------------------------
  union all
  select 31, 'Employers read identity-scoped rows only for identities they may see',
         case when count(*) = 0 then 'OK'
              else 'FAIL: ' || string_agg(tablename || '.' || policyname, ', ') end
  from pg_policies
  where schemaname = 'public'
    and tablename in ('person_skills','experiences','person_attributes','person_professions',
                      'person_work_preferences','person_location_preferences','projects')
    and policyname not like '%\_self'
    and cmd = 'SELECT'
    and coalesce(qual, '') not like '%omelo_can_view_person_row%'
    and policyname not in ('person_skills_admin','experiences_admin')

  union all
  select 32, 'Deleting an identity takes its rows with it (no leak into shared rows)',
         case when count(*) = 0 then 'OK'
              else 'FAIL: ' || string_agg(conrelid::regclass::text, ', ') end
  from pg_constraint
  where contype = 'f' and confrelid = 'public.work_identities'::regclass
    and conrelid in ('public.person_skills'::regclass, 'public.experiences'::regclass, 'public.projects'::regclass)
    and confdeltype <> 'c'

  union all
  select 33, 'Identity completeness and status are server-controlled',
         case when exists (select 1 from pg_trigger where tgname = 'work_identities_guard_fields' and not tgisinternal)
               and exists (select 1 from pg_trigger where tgname = 'person_attributes_validate' and not tgisinternal)
              then 'OK' else 'FAIL: identity guard or attribute validation trigger missing' end
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
--        PATCH state / stage_id        -> rejected (use omelo_move_application)
--   8. python tests/api/hiring_loop_e2e.py, messaging_e2e.py, meet_e2e.py -> ALL PASSED
-- ============================================================
