-- OMELO 57 — Release 6 prerequisites: work-authorization states (enum values on their own).
-- Existing: citizen, permanent_resident, work_permit, dependent_visa_work_rights,
-- student_visa_limited, requires_sponsorship, no_right_to_work.
-- Added:   employer_sponsored (a permit tied to a sponsoring employer),
--          other_authorization, unknown.
-- Rollback: enum values cannot be dropped in place; unused values are inert.

alter type work_auth_status add value if not exists 'employer_sponsored';
alter type work_auth_status add value if not exists 'other_authorization';
alter type work_auth_status add value if not exists 'unknown';
