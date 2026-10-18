-- OMELO 84 — a capability is something you turn on, never something you are.
--
-- omelo_has_capability fell back to organization_type when an organization had
-- made no explicit choice, so a new staffing firm started with client
-- recruitment already on. That is the last place a classification label
-- decided what an organization could do, and it goes.
--
-- Every organization can still turn on exactly the same capabilities. None of
-- them receives one for being called something.
--
-- Evidence gathered before writing this, as required (URS §11.4):
--
--   15 organizations, all organization_type = 'employer'
--   0 explicit capability rows
--   0 capabilities effectively enabled
--   0 organizations gain or lose anything
--
-- The first statement is nevertheless a real preservation step, not a comment.
-- It writes the current effective state into explicit rows for any
-- organization that is relying on the fallback, so that removing the fallback
-- cannot take a capability away from anyone. On this database it inserts
-- nothing; on any database where it matters, it is the whole point.
--
-- Rollback: restore the previous body of omelo_private.omelo_has_capability.
-- The rows inserted below are correct either way — they say what each
-- organization was actually using.

-- ---------------------------------------------------------------
-- 1. Preserve: make today's effective state explicit
-- ---------------------------------------------------------------

insert into company_capabilities (company_id, capability, is_enabled)
select c.id, cap.name, true
from companies c
cross join (values ('client_recruitment'), ('workforce'), ('rpo'), ('billing')) as cap(name)
where c.deleted_at is null
  -- only where the organization has not already chosen for itself
  and not exists (select 1 from company_capabilities cc
                   where cc.company_id = c.id and cc.capability = cap.name)
  -- ...and the type fallback is currently granting it
  and case cap.name
        when 'client_recruitment' then
          c.organization_type in ('recruitment_agency','staffing_agency','rpo_provider','workforce_provider')
        when 'workforce' then
          c.organization_type in ('staffing_agency','workforce_provider')
        when 'rpo' then
          c.organization_type = 'rpo_provider'
        when 'billing' then
          c.organization_type <> 'employer'
        else false
      end
on conflict (company_id, capability) do nothing;

-- ---------------------------------------------------------------
-- 2. Remove the fallback
-- ---------------------------------------------------------------
--
-- An explicit row or nothing. organization_type is now what it claims to be:
-- a description of the business, used for reporting and defaults offered in
-- the interface, and never consulted to decide what may happen.

create or replace function omelo_private.omelo_has_capability(p_company uuid, p_capability text)
returns boolean
language sql
stable
security definer
set search_path = public, omelo_private
as $$
  select coalesce(
    (select is_enabled from company_capabilities
      where company_id = p_company and capability = p_capability),
    false);
$$;

comment on function omelo_private.omelo_has_capability(uuid, text) is
  'True only when the organization has explicitly turned the capability on '
  'through omelo_set_capability. Business type grants nothing.';