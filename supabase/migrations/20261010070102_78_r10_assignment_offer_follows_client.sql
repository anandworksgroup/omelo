-- OMELO 78 — One organization model, part 3: the assignment offer, too.
--
-- omelo_offer_assignment_core branched on `company_kind = 'agency'` in three
-- places, and all three are the same question as migration 77 answered
-- elsewhere: is this assignment worked for a client, or for ourselves?
--
--   1. An organization offering its OWN work may only offer it to someone it
--      already has a relationship with — they applied, they were employed, or
--      they made themselves discoverable. An agency skipped that check because
--      its authority comes from the worker's consent instead. Keyed on type,
--      a private company recruiting for a client was about to be held to the
--      wrong rule: it would have been refused a worker it legitimately
--      represented. Keyed on the work, both are right.
--   2. Client work attaches the consent and the submission it came from and
--      names the client on the agreement; own work attaches the application.
--   3. A bill rate belongs to work done for a client.
--
-- The worker's protection is unchanged and now reaches further: whoever offers
-- an assignment for a client still has to hold a live consent for that worker
-- and that job order, because omelo_validate_assignment says so (migration 77)
-- and it fires for every writer.
--
-- Rollback: restore the previous body of omelo_private.omelo_offer_assignment_core.

do $m$
declare src text; out text; needle text;
begin
  src := pg_get_functiondef(
    (select p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'omelo_private' and p.proname = 'omelo_offer_assignment_core'));

  -- 1. Own work needs a prior relationship; client work needs consent.
  needle := '  if v_kind <> ''agency'' and not (';
  assert position(needle in src) > 0, '78: relationship check not found';
  out := replace(src, needle,
    '  -- R10: own work needs an existing relationship. Work for a client rests' || chr(10) ||
    '  -- on consent instead, which omelo_validate_assignment enforces.' || chr(10) ||
    '  if r.client_id is null and not (');

  -- 2. What the assignment is attached to, and whose name is on the agreement.
  needle := '  if v_kind = ''agency'' then';
  assert position(needle in out) > 0, '78: consent/submission branch not found';
  out := replace(out, needle, '  if r.client_id is not null then');

  -- 3. A bill rate is a client's rate.
  needle := '  if f ? ''bill_rate'' and v_kind = ''agency'' then';
  assert position(needle in out) > 0, '78: bill_rate branch not found';
  out := replace(out, needle, '  if f ? ''bill_rate'' and r.client_id is not null then');

  assert out <> src, '78: omelo_offer_assignment_core unchanged';
  execute out;
end
$m$;

-- v_kind is now written but never read. Left in place deliberately: removing
-- the declaration and its assignment would mean rewriting the whole function
-- body here rather than replacing the three lines this migration is about,
-- and the next edit of that function can drop it.