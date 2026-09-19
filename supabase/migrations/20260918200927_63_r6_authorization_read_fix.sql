-- OMELO 63 — Release 6 fixes found by tests/api/global_e2e.py.
--
-- 1. work_authorizations_employer_read looked up the worker's mobility profile inside the policy,
--    but mobility_profiles is readable only by its owner, so the lookup always failed for an
--    employer: the worker's "share with jobs I apply to" choice was never honoured (it failed
--    closed). The decision now lives in a definer helper that reads the setting.
-- 2. The pre-application check converted pay only when the worker had a pay currency on the
--    identity; it now falls back to the currency of the country the worker lives in.
-- 3. Talent search for an on-site job: a worker known to live in another country is included only
--    if they are open to relocating (mobility profile, or willing_to_relocate on the identity).
--
-- Rollback: recreate the policy from 58, the function from 59, and the search core from 60.

create or replace function omelo_private.omelo_can_read_authorizations(p_person_id uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select case coalesce((select authorization_visibility from mobility_profiles where person_id = p_person_id), 'eligibility_only')
           when 'details_with_applications' then omelo_private.omelo_has_application_from(p_person_id)
           when 'details_with_visible' then omelo_private.omelo_has_application_from(p_person_id)
                or exists (select 1 from company_members cm
                            where cm.person_id = auth.uid() and cm.is_active
                              and cm.role in ('owner','admin','recruiter')
                              and omelo_private.omelo_is_discoverable_to(p_person_id, cm.company_id))
           else false end;
$$;
revoke all on function omelo_private.omelo_can_read_authorizations(uuid) from public, anon;
grant execute on function omelo_private.omelo_can_read_authorizations(uuid) to authenticated;

drop policy if exists work_authorizations_employer_read on work_authorizations;
create policy work_authorizations_employer_read on work_authorizations for select to authenticated
  using (omelo_private.omelo_can_read_authorizations(person_id));

do $$
declare d text;
begin
  d := pg_get_functiondef('public.omelo_job_eligibility(uuid,uuid)'::regprocedure);
  if position('default_currency' in d) = 0 then
    if position('(select pay_currency from person_work_preferences where work_identity_id = v_identity)));' in d) = 0 then
      raise exception 'job_eligibility patch did not find its anchor';
    end if;
    d := replace(d, '(select pay_currency from person_work_preferences where work_identity_id = v_identity)));',
      'coalesce((select pay_currency from person_work_preferences where work_identity_id = v_identity),' || chr(10) ||
      '                      (select cp.default_currency from persons p left join mobility_profiles m on m.person_id = p.id' || chr(10) ||
      '                         join country_policies cp on cp.country_code = coalesce(m.current_country, p.country_code)' || chr(10) ||
      '                        where p.id = auth.uid()))));');
    execute d;
  end if;

  d := pg_get_functiondef('omelo_private.omelo_talent_search_core(uuid,uuid,jsonb,integer,integer,uuid)'::regprocedure);
  if position('lives abroad' in d) = 0 then
    if position('       and (v_reloc is null or coalesce(mp.open_to_relocation, false) = v_reloc)' in d) = 0 then
      raise exception 'talent search patch did not find its anchor';
    end if;
    d := replace(d, '       and (v_reloc is null or coalesce(mp.open_to_relocation, false) = v_reloc)',
      '       -- on-site work: someone who lives abroad is a candidate only if open to relocating' || chr(10) ||
      '       and (j.workplace_type = ''remote'' or j.country_code is null' || chr(10) ||
      '            or coalesce(mp.current_country, p.country_code) is null' || chr(10) ||
      '            or coalesce(mp.current_country, p.country_code) = j.country_code' || chr(10) ||
      '            or coalesce(mp.open_to_relocation, false) or coalesce(pwp.willing_to_relocate, false))' || chr(10) ||
      '       and (v_reloc is null or coalesce(mp.open_to_relocation, false) = v_reloc)');
    execute d;
  end if;
end;
$$;
