-- OMELO 56 (hardening, from the Supabase security advisor after R4/R5)
--
-- Three small helpers had no fixed search_path (function_search_path_mutable).
-- They only use built-ins, so pin them to pg_catalog: a caller can then never
-- shadow a function they call.

alter function omelo_private.omelo_agency_roles(text) set search_path = pg_catalog;
alter function omelo_private.omelo_workforce_roles(text, text) set search_path = pg_catalog;
alter function omelo_private.omelo_local_today(text) set search_path = pg_catalog;
