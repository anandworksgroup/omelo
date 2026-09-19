-- OMELO 61 — Release 6: jobs created before 58 have visa_sponsorship = null. The job trigger keeps
-- it derived from `sponsorship` for every new write; this aligns the existing rows (R6-010).
-- Rollback: not needed (the value is derived).

alter table jobs alter column visa_sponsorship set default false;
update jobs set visa_sponsorship = (sponsorship in ('yes','case_by_case'))
 where visa_sponsorship is distinct from (sponsorship in ('yes','case_by_case'));
