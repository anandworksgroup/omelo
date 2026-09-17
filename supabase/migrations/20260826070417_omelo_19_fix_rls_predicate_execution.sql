-- ============================================================
-- OMELO 19 — Fix RLS predicate execution
--
-- BUG: migration 11 revoked EXECUTE on the RLS helper predicates from
-- anon and authenticated. RLS policies invoke those helpers AS THE
-- CALLING ROLE, so every policy on ~40 tables failed with
--   "permission denied for function omelo_is_company_member"
-- for every real user. It went unnoticed because all prior testing ran
-- as service_role, which bypasses RLS entirely.
--
-- FIX: move the predicates into a private schema that PostgREST does not
-- expose, and grant EXECUTE there. Policies reference functions by OID,
-- so ALTER FUNCTION ... SET SCHEMA keeps every policy working.
--
-- Net effect: RLS works for real users, and the client-callable RPC
-- surface stays at exactly three (A4 §5).
-- ============================================================

create schema if not exists omelo_private;
grant usage on schema omelo_private to anon, authenticated;

-- Move the eight predicates out of the PostgREST-exposed schema.
alter function public.omelo_is_company_member(uuid)                    set schema omelo_private;
alter function public.omelo_has_company_role(uuid, company_role[])     set schema omelo_private;
alter function public.omelo_can_access_job(uuid)                       set schema omelo_private;
alter function public.omelo_has_application_from(uuid)                 set schema omelo_private;
alter function public.omelo_is_interviewer_for(uuid)                   set schema omelo_private;
alter function public.omelo_is_platform_admin(text[])                  set schema omelo_private;
alter function public.omelo_is_discoverable_to(uuid, uuid)             set schema omelo_private;
alter function public.omelo_is_identity_discoverable_to(uuid, uuid)    set schema omelo_private;

-- They resolve public tables and each other, so both schemas must be on
-- the pinned search_path.
alter function omelo_private.omelo_is_company_member(uuid)                 set search_path = public, omelo_private;
alter function omelo_private.omelo_has_company_role(uuid, company_role[])  set search_path = public, omelo_private;
alter function omelo_private.omelo_can_access_job(uuid)                    set search_path = public, omelo_private;
alter function omelo_private.omelo_has_application_from(uuid)              set search_path = public, omelo_private;
alter function omelo_private.omelo_is_interviewer_for(uuid)                set search_path = public, omelo_private;
alter function omelo_private.omelo_is_platform_admin(text[])               set search_path = public, omelo_private;
alter function omelo_private.omelo_is_discoverable_to(uuid, uuid)          set search_path = public, omelo_private;
alter function omelo_private.omelo_is_identity_discoverable_to(uuid, uuid) set search_path = public, omelo_private;

-- RLS evaluates these as the calling role, so the calling role needs EXECUTE.
grant execute on function omelo_private.omelo_is_company_member(uuid)                 to anon, authenticated;
grant execute on function omelo_private.omelo_has_company_role(uuid, company_role[])  to anon, authenticated;
grant execute on function omelo_private.omelo_can_access_job(uuid)                    to anon, authenticated;
grant execute on function omelo_private.omelo_has_application_from(uuid)              to anon, authenticated;
grant execute on function omelo_private.omelo_is_interviewer_for(uuid)                to anon, authenticated;
grant execute on function omelo_private.omelo_is_platform_admin(text[])               to anon, authenticated;
grant execute on function omelo_private.omelo_is_discoverable_to(uuid, uuid)          to anon, authenticated;
grant execute on function omelo_private.omelo_is_identity_discoverable_to(uuid, uuid) to anon, authenticated;

-- The two client RPCs that remain in public call the moved predicates.
alter function public.omelo_profile_schema_for(uuid)      set search_path = public, omelo_private;
alter function public.omelo_mark_application_viewed(uuid) set search_path = public, omelo_private;

-- Trigger bodies do the same.
alter function public.omelo_sync_application_state()  set search_path = public, omelo_private;
alter function public.omelo_log_application_event()   set search_path = public, omelo_private;
alter function public.omelo_employment_to_experience() set search_path = public, omelo_private;
alter function public.omelo_check_legal_restriction()  set search_path = public, omelo_private;
alter function public.omelo_handle_new_user()          set search_path = public, omelo_private;