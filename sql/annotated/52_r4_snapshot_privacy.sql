-- OMELO 52 (Release 4 fix, found while building the agency portal)
--
-- candidate_submissions was readable by every agency member, so sourcers and
-- coordinators could read the full submitted snapshot — contact details
-- included — although the consent RBAC gives them only a limited view.
-- Full rows are now readable only by roles with view_candidate_details
-- (owner, admin, recruiter). Everyone in the agency still sees submission
-- status through omelo_agency_submissions(), which returns only the
-- candidate's name, identity label and profession.

drop policy if exists candidate_submissions_agency on candidate_submissions;
create policy candidate_submissions_agency on candidate_submissions for select to authenticated
  using (omelo_private.omelo_agency_can(agency_id, 'view_candidate_details'));
