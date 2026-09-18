-- OMELO 37: a cheap "am I a platform admin?" check for UI gating.
-- The portal layout previously ran the full system-health report on every
-- page load just to decide whether to show the Admin link. Showing the link
-- is not authorisation: every admin function still checks for itself.

create or replace function public.omelo_am_i_platform_admin()
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select omelo_private.omelo_is_platform_admin();
$$;
revoke execute on function public.omelo_am_i_platform_admin() from public, anon;
grant execute on function public.omelo_am_i_platform_admin() to authenticated;
