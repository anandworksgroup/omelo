-- OMELO 48 (Release 4 fix, found by tests/api/recruitment_e2e.py)
--
-- talent_pool_members' write check allowed only owner/admin/recruiter, so an
-- agency sourcer — whose job is sourcing — could not save anyone to a pool.
-- Agency roles with 'search_talent' may now add members too. The pool guard
-- (47) still requires the identity to be visible to the agency, and pool
-- membership still grants no access and no right to submit (R4-009).

drop policy if exists talent_pool_members_company on talent_pool_members;
create policy talent_pool_members_company on talent_pool_members for all to authenticated
  using (exists (select 1 from talent_pools tp
                  where tp.id = talent_pool_members.pool_id
                    and omelo_private.omelo_is_company_member(tp.company_id)))
  with check (exists (select 1 from talent_pools tp
                       where tp.id = talent_pool_members.pool_id
                         and (omelo_private.omelo_has_company_role(tp.company_id,
                                array['owner','admin','recruiter']::company_role[])
                              or omelo_private.omelo_agency_can(tp.company_id, 'search_talent'))));
