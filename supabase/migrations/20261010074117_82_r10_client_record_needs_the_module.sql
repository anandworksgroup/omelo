-- OMELO 82 — a client record needs the module turned on.
--
-- Migration 77 asked for the client_recruitment capability at the RPCs that
-- start client work: omelo_request_client_link, omelo_create_job_order,
-- omelo_create_rpo_engagement. It missed the plainest path of all — inserting
-- an agency_clients row straight through PostgREST, which the RLS policy
-- allows for any member with the right role.
--
-- tests/api/organization_e2e.py caught it: a private company with the module
-- switched off created a client record on the first try.
--
-- Nothing could be done with that record — a client relationship means nothing
-- until the client organization confirms it, and that call does check the
-- capability — so this was never an access hole. But it is the difference
-- between a module being off and a module being decorative, and the check
-- belongs where every writer passes rather than on the three doors somebody
-- remembered.
--
-- The capability is checked only when the row is created. An organization that
-- switches the module off keeps the clients it already has, and the records
-- stay readable: turning a switch off should not make real work disappear.
--
-- Rollback: restore the previous body of omelo_private.omelo_guard_agency_client.

do $m$
declare src text; out text;
begin
  src := pg_get_functiondef(
    (select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'omelo_private' and p.proname = 'omelo_guard_agency_client'));

  assert position('  if tg_op = ''INSERT'' then' in src) > 0,
    '82: omelo_guard_agency_client has no INSERT branch where expected';

  out := replace(src,
    '  if tg_op = ''INSERT'' then',
    '  if tg_op = ''INSERT'' then' || chr(10) ||
    '    -- R10: recruiting for clients is a module. Any organization may turn it' || chr(10) ||
    '    -- on; none of them keeps clients before it does.' || chr(10) ||
    '    if not omelo_private.omelo_has_capability(new.agency_id, ''client_recruitment'') then' || chr(10) ||
    '      raise exception ''Turn on client recruitment in your organization settings first''' || chr(10) ||
    '        using errcode = ''42501'';' || chr(10) ||
    '    end if;');

  assert out <> src, '82: omelo_guard_agency_client unchanged';
  execute out;
end
$m$;