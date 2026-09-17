-- rls_auto_enable() is an event-trigger helper. It has no business being
-- reachable over PostgREST by anon or authenticated.
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;