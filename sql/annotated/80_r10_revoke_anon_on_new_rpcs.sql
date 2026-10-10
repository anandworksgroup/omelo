-- OMELO 80 — the three R10 functions are for signed-in callers only.
--
-- Supabase's default privileges grant EXECUTE on a new function in `public`
-- to `anon` by name, so `revoke execute ... from public` in migrations 76 and
-- 79 did not take it away. Nothing could be done with it: all three ask
-- auth.uid() or omelo_has_company_role first and refuse a caller who is not
-- signed in. But the refusal should be a 404 from PostgREST before the
-- function is ever entered, the way every other member-only RPC behaves, not
-- an error raised from inside it.
--
-- Rollback: grant execute on the three functions to anon.

revoke execute on function public.omelo_create_organization(text, text, text, boolean) from anon;
revoke execute on function public.omelo_set_organization_type(uuid, text) from anon;
revoke execute on function public.omelo_set_capability(uuid, text, boolean) from anon;
