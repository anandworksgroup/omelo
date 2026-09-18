-- OMELO 36: correct funnel KPIs, outbox retention.
--
-- 1. The first KPI version counted EVENTS, so "shortlist -> interview" read
--    4.75 (several interviews per application, interviews without a
--    shortlist). The funnel is now a cohort: applications that applied in the
--    window, each counted once at the furthest stage it reached, where each
--    stage includes everyone who went further (a hire was also shortlisted,
--    interviewed and offered). Conversions are therefore always <= 1.
-- 2. Retention: sent / cancelled / failed messages are purged after 30 days,
--    and an address belonging to a deleted account is removed once its last
--    message is sent. Runs daily with the account-deletion job.

create or replace function public.omelo_admin_kpis(p_days integer default 30)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare
  v_days int := greatest(1, least(coalesce(p_days, 30), 365));
  v_since timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 365)));
  f record; t record; o record;
begin
  if not omelo_private.omelo_is_platform_admin() then
    raise exception 'Platform administrators only' using errcode = '42501';
  end if;

  with cohort as (
    select e.aggregate_id,
           min(e.occurred_at) filter (where e.event_type = 'WorkerApplied')         as applied_at,
           min(e.occurred_at) filter (where e.event_type = 'CandidateShortlisted')  as shortlisted_at,
           min(e.occurred_at) filter (where e.event_type = 'InterviewScheduled')    as interview_at,
           min(e.occurred_at) filter (where e.event_type = 'OfferSent')             as offer_at,
           min(e.occurred_at) filter (where e.event_type = 'WorkerHired')           as hired_at
      from domain_events e
     where e.aggregate_type = 'application'
       and e.aggregate_id in (select aggregate_id from domain_events
                               where event_type = 'WorkerApplied' and occurred_at >= v_since)
     group by e.aggregate_id),
  staged as (
    select *,
           (hired_at is not null)                                                   as r_hired,
           (offer_at is not null or hired_at is not null)                           as r_offer,
           (interview_at is not null or offer_at is not null or hired_at is not null) as r_interview,
           (shortlisted_at is not null or interview_at is not null
              or offer_at is not null or hired_at is not null)                      as r_shortlist
      from cohort where applied_at is not null)
  select count(*) as applied,
         count(*) filter (where r_shortlist) as shortlisted,
         count(*) filter (where r_interview) as interviewed,
         count(*) filter (where r_offer)     as offered,
         count(*) filter (where r_hired)     as hired,
         percentile_cont(0.5) within group (order by extract(epoch from coalesce(shortlisted_at, interview_at, offer_at, hired_at) - applied_at) / 3600)
           filter (where r_shortlist) as h_shortlist,
         percentile_cont(0.5) within group (order by extract(epoch from coalesce(interview_at, offer_at, hired_at) - applied_at) / 3600)
           filter (where r_interview) as h_interview,
         percentile_cont(0.5) within group (order by extract(epoch from coalesce(offer_at, hired_at) - applied_at) / 3600)
           filter (where r_offer) as h_offer,
         percentile_cont(0.5) within group (order by extract(epoch from hired_at - applied_at) / 3600)
           filter (where r_hired) as h_hire
    into f
    from staged;

  select count(*) filter (where event_type = 'OfferAccepted') as accepted,
         count(*) filter (where event_type = 'OfferDeclined') as declined
    into o
    from domain_events where occurred_at >= v_since;

  return jsonb_build_object(
    'window_days', v_days,
    'definition', 'Cohort of applications submitted in the window; each stage counts applications that reached it or went further.',
    'marketplace', jsonb_build_object(
      'active_workers', (select count(distinct person_id) from domain_events
                          where occurred_at >= v_since and person_id is not null
                            and event_type in ('WorkerApplied','ProfileUpdated','SkillAdded','IdentityCreated','WorkerRegistered','InterviewJoined')),
      'active_employers', (select count(distinct company_id) from domain_events where occurred_at >= v_since and company_id is not null),
      'published_jobs', (select count(*) from jobs where status = 'published'),
      'job_fill_rate', (select round(count(*) filter (where exists (select 1 from applications a where a.job_id = j.id and a.state = 'hired'))::numeric
                                     / nullif(count(*), 0), 3)
                          from jobs j where j.status in ('closed','expired') and coalesce(j.closed_at, j.updated_at) >= v_since)),
    'funnel', jsonb_build_object('applied', f.applied, 'shortlisted', f.shortlisted, 'interviewed', f.interviewed,
                                 'offered', f.offered, 'hired', f.hired),
    'conversion', jsonb_build_object(
      'apply_to_shortlist', round(f.shortlisted::numeric / nullif(f.applied, 0), 3),
      'shortlist_to_interview', round(f.interviewed::numeric / nullif(f.shortlisted, 0), 3),
      'interview_to_offer', round(f.offered::numeric / nullif(f.interviewed, 0), 3),
      'offer_to_hire', round(f.hired::numeric / nullif(f.offered, 0), 3),
      'apply_to_hire', round(f.hired::numeric / nullif(f.applied, 0), 3),
      'offer_acceptance', round(o.accepted::numeric / nullif(o.accepted + o.declined, 0), 3)),
    'median_hours', jsonb_build_object('to_shortlist', round(f.h_shortlist::numeric, 1), 'to_interview', round(f.h_interview::numeric, 1),
                                       'to_offer', round(f.h_offer::numeric, 1), 'to_hire', round(f.h_hire::numeric, 1)),
    'workers', jsonb_build_object(
      'email_verified', (select count(distinct person_id) from verifications where type = 'email' and status = 'verified' and revoked_at is null),
      'with_verified_employment', (select count(distinct person_id) from experiences where is_verified))
  );
end;
$$;
revoke execute on function public.omelo_admin_kpis(integer) from public, anon;
grant execute on function public.omelo_admin_kpis(integer) to authenticated;

create or replace function omelo_private.omelo_purge_outbox()
returns integer
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_count int;
begin
  delete from outbound_messages
   where status in ('sent','cancelled','failed','skipped') and created_at < now() - interval '30 days';
  get diagnostics v_count = row_count;
  update outbound_messages set to_address = null, payload = '{}'::jsonb
   where person_id is null and status in ('sent','cancelled','failed','skipped') and to_address is not null;
  return v_count;
end;
$$;
revoke execute on function omelo_private.omelo_purge_outbox() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'omelo-outbox-retention';
select cron.schedule('omelo-outbox-retention', '41 3 * * *', $$ select omelo_private.omelo_purge_outbox() $$);
