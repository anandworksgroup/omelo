-- OMELO 67 — Release 7 fix (found while building the worker app): updating a career goal without
-- naming its work identity moved the goal to the worker's main identity. An update now keeps the
-- goal's identity unless a new one is given, and the generated plan uses the goal's own identity.
-- Rollback: re-run omelo_save_career_goal from 65.

do $$
declare d text;
begin
  d := pg_get_functiondef('public.omelo_save_career_goal(jsonb)'::regprocedure);
  if position('keeps its identity' in d) > 0 then return; end if;
  if position('        work_identity_id = v_identity' in d) = 0
     or position('  if coalesce((p->>''generate_plan'')::boolean, false) and g.profession_id is not null then' in d) = 0 then
    raise exception 'save_career_goal patch did not find its anchors';
  end if;
  d := replace(d, '        work_identity_id = v_identity',
    '        work_identity_id = case when p ? ''work_identity_id'' then v_identity else work_identity_id end  -- keeps its identity');
  d := replace(d, '  if coalesce((p->>''generate_plan'')::boolean, false) and g.profession_id is not null then',
    '  v_identity := coalesce(g.work_identity_id, v_identity);' || chr(10) ||
    '  if coalesce((p->>''generate_plan'')::boolean, false) and g.profession_id is not null then');
  execute d;
end;
$$;
