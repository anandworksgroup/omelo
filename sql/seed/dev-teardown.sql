-- ============================================================
-- OMELO — Remove all development seed data
--
-- Deletes every demo employer and everything that cascades from it:
-- jobs, stages, skills, benefits, questions, applications, matches,
-- conversations, interviews and offers.
--
-- Does NOT touch real taxonomy (locations, skills, professions,
-- weight_profiles) — those are production data from migrations 15-17.
-- ============================================================

begin;

-- Everything hangs off companies via ON DELETE CASCADE.
delete from companies where slug like 'demo-%';

-- Verify nothing is left behind.
select
  (select count(*) from companies where slug like 'demo-%') as demo_companies,
  (select count(*) from jobs)                               as jobs,
  (select count(*) from job_stages)                         as stages,
  (select count(*) from applications)                       as applications;

commit;
