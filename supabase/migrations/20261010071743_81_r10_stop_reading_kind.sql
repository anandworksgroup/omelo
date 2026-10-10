-- OMELO 81 — the last read of company_kind in the assignment path.
--
-- Migration 78 moved the three branches of omelo_offer_assignment_core onto
-- the client, and left the line that loads v_kind behind because replacing it
-- was not what that migration was about. It is dead now: v_kind is written and
-- never read. It also stops invariant 91 from being able to say something
-- simple and true — that no function decides anything by the organization's
-- business type — so it goes.
--
-- The same statement loads v_company_name, which is used on the agreement, so
-- the line stays and only the column goes.
--
-- Rollback: restore the previous body of omelo_private.omelo_offer_assignment_core.

do $m$
declare src text; out text;
begin
  src := pg_get_functiondef(
    (select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'omelo_private' and p.proname = 'omelo_offer_assignment_core'));

  assert position('  select company_kind, display_name into v_kind, v_company_name from companies where id = r.company_id;' in src) > 0,
    '81: the v_kind load is not where it was';

  out := replace(src,
    '  select company_kind, display_name into v_kind, v_company_name from companies where id = r.company_id;',
    '  select display_name into v_company_name from companies where id = r.company_id;');

  out := replace(out,
    '  r workforce_requirements; wi work_identities; v_kind text; a assignments; f jsonb := coalesce(p_fields, ''{}''::jsonb);',
    '  r workforce_requirements; wi work_identities; a assignments; f jsonb := coalesce(p_fields, ''{}''::jsonb);');

  assert out <> src, '81: omelo_offer_assignment_core unchanged';
  assert position('v_kind' in out) = 0, '81: v_kind still referenced somewhere';
  execute out;
end
$m$;