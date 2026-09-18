-- OMELO 41 — Release 3: Marketplace (measured matching + two-sided discovery)
--
-- Gate: funnel measured end to end; talent search with consent; the
-- invite-to-apply loop closed.
--
-- 1. Funnel measurement
--    match_events (server-written only): impression / view / click / save /
--    apply / invite, attributed to a surface, rank and the match score and
--    engine version at the time. omelo_track_job_events() is the only client
--    entry point (batched, de-duplicated, rate limited). Applications are
--    attributed automatically (last touch in 30 days, or the invitation).
--    jobs.view_count is finally maintained; JobViewed is emitted.
--    omelo_job_funnel() for the hiring team, omelo_admin_matching_metrics()
--    for Omelo (by surface, by score band, talent search, engine versions).
-- 2. Consent fix (found while designing talent search)
--    persons.discoverability was a "master switch" defaulting to private that
--    no app ever changed, so no identity could ever be found. It is now
--    derived: the most open level among the person's active identities.
-- 3. Talent search
--    omelo_search_talent(): the reverse matcher. Same engine
--    (omelo_score_match), candidates limited to the job's profession /
--    category, radius and optional text, then filtered by
--    omelo_is_identity_discoverable_to (verified company, entitlement,
--    visibility level, blocks). Monthly quota from company_entitlements.
--    omelo_talent_profile(): one visible identity in full (evidence, answers,
--    experience, match), and records a profile view.
-- 4. Invite to apply
--    Invitations are created only by omelo_invite_to_apply() (consent,
--    allow_invitations, daily outreach quota, at most 5 inbound per person per
--    day, one per job). Workers see them with omelo_my_invitations(), decline
--    with omelo_respond_to_invitation(); applying marks the invitation
--    applied (InvitationAccepted). In-app notification + email.
-- 5. Talent pools: members can only be identities visible to the company.
-- 6. Holes closed: profile_views accepted any INSERT (anyone could forge
--    "viewed by company X"); employers could INSERT/UPDATE invitations
--    directly and workers could rewrite them. Now server-written only.
-- 7. Admin: verify a company, set entitlements (employers cannot self-grant).
--
-- Rollback: drop the new functions, match_events, the new columns and
-- triggers; restore the previous candidate_invitations / profile_views
-- policies (see 06/07 annotated files). No existing data is rewritten except
-- persons.discoverability (re-derivable at any time).

alter type notification_type add value if not exists 'job_invitation';

-- 1. match_events ------------------------------------------------------------------
create table if not exists public.match_events (
  id               bigint generated always as identity primary key,
  person_id        uuid references persons(id) on delete set null,
  work_identity_id uuid references work_identities(id) on delete set null,
  job_id           uuid not null references jobs(id) on delete cascade,
  company_id       uuid not null references companies(id) on delete cascade,
  event            text not null check (event in ('impression','view','click','save','apply','invite')),
  surface          text not null check (surface in ('recommended','nearby','search','job_page','invitation',
                                                    'talent_search','notification','email','saved','other')),
  rank             smallint check (rank between 1 and 1000),
  score            smallint check (score between 0 and 100),
  engine_version   text,
  occurred_at      timestamptz not null default now()
);
create index if not exists match_events_job_idx on match_events (job_id, event, occurred_at);
create index if not exists match_events_person_job_idx on match_events (person_id, job_id, occurred_at desc);
create index if not exists match_events_time_idx on match_events (occurred_at);
alter table match_events enable row level security;
revoke all on match_events from anon, authenticated;

create or replace function public.omelo_track_job_events(p_events jsonb)
returns integer
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare
  v_uid uuid := auth.uid(); ev jsonb; v_job uuid; j jobs; m matches;
  v_event text; v_surface text; v_rank int; v_n int := 0; v_first_view boolean;
begin
  if v_uid is null then return 0; end if;               -- anonymous browsing is not tracked
  if p_events is null or jsonb_typeof(p_events) <> 'array' or jsonb_array_length(p_events) > 100 then
    raise exception 'Send up to 100 events as an array' using errcode = '22023';
  end if;
  if (select count(*) from match_events where person_id = v_uid and occurred_at > now() - interval '1 hour') > 1000 then
    return 0;
  end if;
  for ev in select * from jsonb_array_elements(p_events) loop
    continue when jsonb_typeof(ev) <> 'object';
    v_event := ev->>'event';
    v_surface := coalesce(ev->>'surface', 'other');
    continue when v_event is null or v_event not in ('impression','view','click','save');
    continue when v_surface not in ('recommended','nearby','search','job_page','invitation',
                                    'talent_search','notification','email','saved','other');
    begin
      v_job := (ev->>'job_id')::uuid;
    exception when others then
      continue;
    end;
    select * into j from jobs where id = v_job and status = 'published';
    continue when j.id is null;
    continue when exists (
      select 1 from match_events
       where person_id = v_uid and job_id = j.id and event = v_event and surface = v_surface
         and occurred_at > now() - case when v_event = 'impression' then interval '6 hours' else interval '30 minutes' end);
    v_rank := case when (ev->>'rank') ~ '^[0-9]{1,4}$' then nullif(least((ev->>'rank')::int, 1000), 0) end;
    select * into m from matches where person_id = v_uid and job_id = j.id order by computed_at desc limit 1;
    v_first_view := v_event = 'view' and not exists (
      select 1 from match_events where person_id = v_uid and job_id = j.id and event = 'view'
         and occurred_at > now() - interval '1 day');
    insert into match_events (person_id, work_identity_id, job_id, company_id, event, surface, rank, score, engine_version)
    values (v_uid, m.work_identity_id, j.id, j.company_id, v_event, v_surface, v_rank, m.score, m.engine_version);
    v_n := v_n + 1;
    if v_first_view then
      update jobs set view_count = coalesce(view_count, 0) + 1 where id = j.id;
      perform omelo_private.omelo_emit('JobViewed', 'job', j.id, j.company_id, v_uid,
                                       jsonb_build_object('surface', v_surface, 'rank', v_rank));
    end if;
  end loop;
  return v_n;
end;
$$;

-- 2. persons.discoverability is derived from the identities ---------------------------
create or replace function omelo_private.omelo_sync_person_discoverability(p_person uuid)
returns void
language sql security definer
set search_path = public, omelo_private
as $$
  update persons p
     set discoverability = coalesce((select max(wi.discoverability) from work_identities wi
                                      where wi.person_id = p.id and wi.status = 'active'), 'private')
   where p.id = p_person
     and p.discoverability is distinct from coalesce((select max(wi.discoverability) from work_identities wi
                                                       where wi.person_id = p.id and wi.status = 'active'), 'private');
$$;
revoke execute on function omelo_private.omelo_sync_person_discoverability(uuid) from public, anon, authenticated;

create or replace function omelo_private.omelo_identity_visibility_changed()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if tg_op = 'DELETE' then
    perform omelo_private.omelo_sync_person_discoverability(old.person_id);
    return null;
  end if;
  perform omelo_private.omelo_sync_person_discoverability(new.person_id);
  return null;
end;
$$;
revoke execute on function omelo_private.omelo_identity_visibility_changed() from public, anon, authenticated;
drop trigger if exists work_identities_sync_person_visibility on work_identities;
create trigger work_identities_sync_person_visibility
  after insert or delete or update of discoverability, status on work_identities
  for each row execute function omelo_private.omelo_identity_visibility_changed();

-- The identity decides; the person row only mirrors it.
create or replace function omelo_private.omelo_is_identity_discoverable_to(p_work_identity_id uuid, p_company_id uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select
    exists (
      select 1
        from work_identities wi
        join persons p on p.id = wi.person_id
        join companies c on c.id = p_company_id
       where wi.id = p_work_identity_id
         and wi.status = 'active'
         and p.deleted_at is null
         and case wi.discoverability::text
               when 'private'      then false
               when 'matched_only' then exists (
                 select 1 from matches m join jobs j on j.id = m.job_id
                  where m.work_identity_id = wi.id and j.company_id = p_company_id
                    and j.status = 'published' and m.eligible and m.score >= 70)
               when 'discoverable' then c.company_kind = 'employer'
               when 'recruiters'   then c.company_kind in ('employer','agency')
               when 'public'       then true
               else false
             end)
    and exists (select 1 from companies c
                where c.id = p_company_id and c.is_verified and c.deleted_at is null)
    and exists (select 1 from company_entitlements e
                where e.company_id = p_company_id and e.talent_search_enabled
                  and (e.valid_until is null or e.valid_until >= current_date))
    and not exists (
      select 1 from blocks b
      join work_identities wi on wi.id = p_work_identity_id
      where b.person_id = wi.person_id
        and b.target_type = 'company' and b.target_id = p_company_id)
    and not exists (
      select 1 from blocks b
      join work_identities wi on wi.id = p_work_identity_id
      where b.person_id = wi.person_id
        and b.target_type = 'person' and b.target_id = (select auth.uid()));
$$;

update persons p
   set discoverability = coalesce((select max(wi.discoverability) from work_identities wi
                                    where wi.person_id = p.id and wi.status = 'active'), 'private')
 where p.discoverability is distinct from coalesce((select max(wi.discoverability) from work_identities wi
                                                     where wi.person_id = p.id and wi.status = 'active'), 'private');

-- Worker control: may employers invite this identity to apply?
alter table work_identities add column if not exists allow_invitations boolean not null default true;

-- Invitation lifecycle columns (used by the talent card below).
alter table candidate_invitations
  add column if not exists expires_at timestamptz not null default now() + interval '14 days',
  add column if not exists viewed_at timestamptz,
  add column if not exists decline_reason text check (decline_reason is null or length(decline_reason) <= 300);
alter table candidate_invitations drop constraint if exists candidate_invitations_response_check;
alter table candidate_invitations add constraint candidate_invitations_response_check
  check (response is null or response in ('applied','declined','ignored','withdrawn'));
alter table candidate_invitations drop constraint if exists candidate_invitations_message_length;
alter table candidate_invitations add constraint candidate_invitations_message_length
  check (message is null or length(message) <= 1000);
create index if not exists candidate_invitations_person_idx on candidate_invitations (person_id, sent_at desc);
create index if not exists candidate_invitations_company_idx on candidate_invitations (company_id, sent_at desc);

-- 3. Talent search -------------------------------------------------------------------
create or replace function omelo_private.omelo_require_talent_access(p_company uuid)
returns company_entitlements
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare e company_entitlements;
begin
  if not exists (select 1 from companies where id = p_company and is_verified and deleted_at is null) then
    raise exception 'Talent search is available once Omelo has verified your company' using errcode = '42501';
  end if;
  select * into e from company_entitlements where company_id = p_company;
  if e.company_id is null or not e.talent_search_enabled
     or (e.valid_until is not null and e.valid_until < current_date) then
    raise exception 'Talent search is not included in your plan. Contact Omelo to enable it.' using errcode = '42501';
  end if;
  return e;
end;
$$;
revoke execute on function omelo_private.omelo_require_talent_access(uuid) from public, anon, authenticated;

-- One candidate row as the hiring team sees it in lists.
create or replace function omelo_private.omelo_talent_card(p_identity uuid, p_job uuid, p_company uuid)
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select jsonb_build_object(
    'work_identity_id', wi.id,
    'name', coalesce(nullif(trim(coalesce(p.given_name, '') || ' ' ||
                                 coalesce(left(p.family_name, 1) || '.', '')), ''), p.display_name, 'Candidate'),
    'avatar_url', p.avatar_url,
    'label', wi.label,
    'profession', pr.name,
    'headline', wi.headline,
    'location_text', p.location_text,
    'experience_months', wi.total_experience_months,
    'completeness', wi.completeness_score,
    'active', case when p.last_active_at > now() - interval '7 days' then 'this_week'
                   when p.last_active_at > now() - interval '30 days' then 'this_month'
                   else 'earlier' end,
    'top_skills', coalesce((select jsonb_agg(x.name order by x.v desc, x.pr desc) from (
                     select s.name, ps.is_verified as v,
                            array_position(array['beginner','basic','intermediate','advanced','expert'], ps.proficiency::text) as pr
                       from person_skills ps join skills s on s.id = ps.skill_id
                      where ps.person_id = wi.person_id
                        and (ps.work_identity_id = wi.id or ps.work_identity_id is null)
                      order by ps.is_verified desc, 3 desc nulls last limit 6) x), '[]'::jsonb),
    'verified_skills', (select count(*) from person_skills ps
                         where ps.person_id = wi.person_id and ps.is_verified
                           and (ps.work_identity_id = wi.id or ps.work_identity_id is null)),
    'invitation', (select jsonb_build_object('id', ci.id, 'sent_at', ci.sent_at,
                           'status', case when ci.response is not null then ci.response
                                          when ci.expires_at < now() then 'expired' else 'pending' end)
                     from candidate_invitations ci where ci.job_id = p_job and ci.person_id = wi.person_id),
    'pools', coalesce((select jsonb_agg(tp.id) from talent_pool_members m join talent_pools tp on tp.id = m.pool_id
                        where m.person_id = wi.person_id and tp.company_id = p_company), '[]'::jsonb),
    'allow_invitations', wi.allow_invitations)
  from work_identities wi
  join persons p on p.id = wi.person_id
  left join professions pr on pr.id = wi.profession_id
  where wi.id = p_identity;
$$;
revoke execute on function omelo_private.omelo_talent_card(uuid, uuid, uuid) from public, anon, authenticated;

create or replace function public.omelo_search_talent(
  p_job_id uuid, p_query text default null, p_radius_km integer default 50,
  p_limit integer default 25, p_offset integer default 0)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare
  j jobs; e company_entitlements; v_used int; v_q text; v_like text; v_radius int;
  c record; r jsonb; v_found jsonb := '[]'::jsonb; v_page jsonb; v_total int;
  v_limit int := greatest(1, least(coalesce(p_limit, 25), 50));
  v_offset int := greatest(0, least(coalesce(p_offset, 0), 500));
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  select * into j from jobs where id = p_job_id;
  if j.id is null or not omelo_private.omelo_has_company_role(j.company_id, array['owner','admin','recruiter']::company_role[]) then
    raise exception 'Only the hiring team can search for this job' using errcode = '42501';
  end if;
  if j.status <> 'published' then
    raise exception 'Publish the job before searching for candidates' using errcode = '22023';
  end if;
  e := omelo_private.omelo_require_talent_access(j.company_id);
  select count(*) into v_used from domain_events
   where event_type = 'TalentSearched' and company_id = j.company_id and occurred_at >= date_trunc('month', now());
  if e.talent_search_quota_monthly > 0 and v_used >= e.talent_search_quota_monthly then
    raise exception 'Your company has used its % talent searches for this month', e.talent_search_quota_monthly
      using errcode = '22023';
  end if;

  v_q := nullif(trim(coalesce(p_query, '')), '');
  if v_q is not null and length(v_q) > 80 then
    raise exception 'Keep the search under 80 characters' using errcode = '22023';
  end if;
  v_like := case when v_q is not null
                 then '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
  v_radius := greatest(1, least(coalesce(p_radius_km, 50), 500));

  for c in
    select wi.id,
           case when j.geo is null or j.workplace_type = 'remote' then null
                else round((least(
                       case when p.geo is not null then st_distance(p.geo, j.geo) end,
                       (select min(st_distance(l.geo, j.geo))
                          from person_location_preferences plp join locations l on l.id = plp.location_id
                         where plp.work_identity_id = wi.id and l.geo is not null)) / 1000.0)::numeric, 1)
           end as km
      from work_identities wi
      join persons p on p.id = wi.person_id and p.deleted_at is null
     where wi.status = 'active'
       and wi.discoverability::text <> 'private'
       and wi.person_id <> (select auth.uid())
       and (wi.profession_id = j.profession_id or wi.category_id = j.category_id)
       and not exists (select 1 from applications a where a.job_id = j.id and a.person_id = wi.person_id)
       and (v_like is null
            or wi.label ilike v_like or wi.headline ilike v_like
            or exists (select 1 from person_skills ps join skills s on s.id = ps.skill_id
                        where ps.person_id = wi.person_id
                          and (ps.work_identity_id = wi.id or ps.work_identity_id is null)
                          and s.name ilike v_like))
     order by (wi.profession_id is not distinct from j.profession_id) desc,
              wi.completeness_score desc, p.last_active_at desc nulls last
     limit 150
  loop
    continue when c.km is not null and c.km > v_radius;
    r := omelo_private.omelo_store_match(c.id, j.id);
    continue when not omelo_private.omelo_is_identity_discoverable_to(c.id, j.company_id);
    v_found := v_found || jsonb_build_array(
      omelo_private.omelo_talent_card(c.id, j.id, j.company_id)
      || jsonb_build_object('distance_km', c.km,
                            'score', (r->>'score')::int, 'eligible', (r->>'eligible')::boolean,
                            'strengths', coalesce(r->'strengths', '[]'::jsonb),
                            'gaps', coalesce(r->'gaps', '[]'::jsonb)));
  end loop;

  v_total := jsonb_array_length(v_found);
  select coalesce(jsonb_agg(x order by o), '[]'::jsonb) into v_page
    from (select x, row_number() over (order by (x->>'eligible')::boolean desc, (x->>'score')::int desc,
                                                (x->>'distance_km')::numeric asc nulls last) as o
            from jsonb_array_elements(v_found) x) s
   where o > v_offset and o <= v_offset + v_limit;

  perform omelo_private.omelo_emit('TalentSearched', 'job', j.id, j.company_id, auth.uid(),
    jsonb_build_object('query', v_q, 'radius_km', v_radius, 'found', v_total));

  return jsonb_build_object('results', v_page, 'total', v_total,
    'quota', jsonb_build_object('used', v_used + 1,
                                'limit', nullif(e.talent_search_quota_monthly, 0)));
end;
$$;

create or replace function public.omelo_talent_profile(p_identity uuid, p_job_id uuid default null)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare wi work_identities; v_company uuid; m matches; v_ev jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  select * into wi from work_identities where id = p_identity;
  if wi.id is null or not omelo_private.omelo_can_view_identity(p_identity) then
    raise exception 'This profile is not visible to you' using errcode = '42501';
  end if;
  if p_job_id is not null then
    select company_id into v_company from jobs where id = p_job_id
       and omelo_private.omelo_is_company_member(company_id);
  end if;
  if v_company is null then
    select cm.company_id into v_company from company_members cm
     where cm.person_id = auth.uid() and cm.is_active
       and cm.role in ('owner','admin','recruiter')
       and (omelo_private.omelo_is_identity_discoverable_to(p_identity, cm.company_id)
            or exists (select 1 from applications a where a.work_identity_id = p_identity and a.company_id = cm.company_id))
     limit 1;
  end if;

  if v_company is not null and not exists (
       select 1 from profile_views where work_identity_id = p_identity and viewer_company_id = v_company
          and viewed_at > now() - interval '1 day') then
    insert into profile_views (person_id, work_identity_id, viewer_company_id, viewer_person_id, context_job_id)
    values (wi.person_id, wi.id, v_company, auth.uid(), p_job_id);
  end if;

  if p_job_id is not null then
    select * into m from matches where person_id = wi.person_id and job_id = p_job_id order by computed_at desc limit 1;
  end if;
  v_ev := public.omelo_identity_evidence(p_identity);

  return jsonb_build_object(
    'card', omelo_private.omelo_talent_card(p_identity, p_job_id, v_company),
    'about', wi.about,
    'evidence', v_ev,
    'answers', coalesce((
      select jsonb_agg(jsonb_build_object('label', a.label, 'data_type', a.data_type, 'unit', a.unit,
               'value', coalesce(pa.value_json, to_jsonb(pa.value_text), to_jsonb(pa.value_number),
                                 to_jsonb(pa.value_bool), to_jsonb(pa.value_date)))
               order by a.position)
        from person_attributes pa join profile_attributes a on a.id = pa.attribute_id
       where pa.work_identity_id = wi.id), '[]'::jsonb),
    'experiences', coalesce((
      select jsonb_agg(jsonb_build_object('title', x.title, 'employer', x.employer_name,
               'started_on', x.started_on, 'ended_on', x.ended_on, 'is_current', x.is_current,
               'verified', x.is_verified, 'description', left(x.description, 600))
               order by x.is_current desc, x.started_on desc nulls last)
        from experiences x
       where x.person_id = wi.person_id and (x.work_identity_id = wi.id or x.work_identity_id is null)), '[]'::jsonb),
    'match', case when m.id is null then null else jsonb_build_object(
               'score', m.score, 'eligible', m.eligible,
               'strengths', m.feature_vector->'strengths', 'gaps', m.feature_vector->'gaps',
               'missing_skills', m.feature_vector->'missing_skills') end);
end;
$$;

-- 4. Invitations ---------------------------------------------------------------------
drop policy if exists candidate_invitations_company on candidate_invitations;
drop policy if exists candidate_invitations_respond on candidate_invitations;
drop policy if exists candidate_invitations_company_read on candidate_invitations;
create policy candidate_invitations_company_read on candidate_invitations for select to authenticated
  using (omelo_private.omelo_is_company_member(company_id));
revoke insert, update, delete on candidate_invitations from anon, authenticated;

create or replace function public.omelo_invite_to_apply(p_job_id uuid, p_identity uuid, p_message text default null)
returns uuid
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare
  j jobs; wi work_identities; e company_entitlements; v_id uuid; m matches;
  v_company_name text; v_msg text := nullif(trim(coalesce(p_message, '')), '');
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  select * into j from jobs where id = p_job_id;
  if j.id is null or not omelo_private.omelo_has_company_role(j.company_id, array['owner','admin','recruiter']::company_role[]) then
    raise exception 'Only the hiring team can invite candidates to this job' using errcode = '42501';
  end if;
  if j.status <> 'published' then
    raise exception 'Only published jobs can receive invitations' using errcode = '22023';
  end if;
  e := omelo_private.omelo_require_talent_access(j.company_id);
  select * into wi from work_identities where id = p_identity;
  if wi.id is null or not omelo_private.omelo_is_identity_discoverable_to(wi.id, j.company_id) then
    raise exception 'This candidate is not visible to your company' using errcode = '42501';
  end if;
  if not wi.allow_invitations then
    raise exception 'This candidate is not accepting invitations' using errcode = '22023';
  end if;
  if v_msg is not null and length(v_msg) > 1000 then
    raise exception 'Keep the message under 1000 characters' using errcode = '22023';
  end if;
  if exists (select 1 from applications where job_id = j.id and person_id = wi.person_id) then
    raise exception 'This candidate has already applied to this job' using errcode = '22023';
  end if;
  if exists (select 1 from candidate_invitations where job_id = j.id and person_id = wi.person_id) then
    raise exception 'This candidate was already invited to this job' using errcode = '22023';
  end if;
  if e.outreach_quota_daily > 0 and (select count(*) from candidate_invitations
        where company_id = j.company_id and sent_at > now() - interval '1 day') >= e.outreach_quota_daily then
    raise exception 'Your company has sent its % invitations for today', e.outreach_quota_daily using errcode = '22023';
  end if;
  if (select count(*) from candidate_invitations
       where person_id = wi.person_id and sent_at > now() - interval '1 day') >= 5 then
    raise exception 'This candidate has received several invitations today. Try again tomorrow.' using errcode = '22023';
  end if;

  insert into candidate_invitations (company_id, job_id, person_id, work_identity_id, sent_by, message)
  values (j.company_id, j.id, wi.person_id, wi.id, auth.uid(), v_msg)
  returning id into v_id;

  select display_name into v_company_name from companies where id = j.company_id;
  select * into m from matches where person_id = wi.person_id and job_id = j.id order by computed_at desc limit 1;
  insert into match_events (person_id, work_identity_id, job_id, company_id, event, surface, score, engine_version)
  values (wi.person_id, wi.id, j.id, j.company_id, 'invite', 'talent_search', m.score, m.engine_version);

  perform omelo_private.omelo_notify(wi.person_id, 'job_invitation'::notification_type,
    v_company_name || ' invited you to apply',
    j.title || coalesce(' · ' || j.location_text, ''),
    'candidate_invitation', v_id, '/invitations/' || v_id);
  perform omelo_private.omelo_enqueue_email(wi.person_id, 'job_invitation',
    v_company_name || ' invited you to apply: ' || j.title,
    jsonb_build_object('invitation_id', v_id, 'job_title', j.title, 'company_name', v_company_name,
                       'location_text', j.location_text, 'message', v_msg,
                       'pay_min', j.pay_min, 'pay_max', j.pay_max, 'pay_period', j.pay_period,
                       'pay_currency', j.pay_currency, 'identity_label', wi.label),
    'invite:' || v_id, null);
  perform omelo_private.omelo_emit('CandidateInvited', 'candidate_invitation', v_id, j.company_id, wi.person_id,
    jsonb_build_object('job_id', j.id, 'work_identity_id', wi.id, 'score', m.score));
  return v_id;
end;
$$;

create or replace function public.omelo_withdraw_invitation(p_invitation uuid)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare ci candidate_invitations;
begin
  select * into ci from candidate_invitations where id = p_invitation;
  if ci.id is null or not omelo_private.omelo_has_company_role(ci.company_id, array['owner','admin','recruiter']::company_role[]) then
    raise exception 'Invitation not found' using errcode = '42501';
  end if;
  if ci.response is not null then
    raise exception 'This invitation was already answered' using errcode = '22023';
  end if;
  update candidate_invitations set response = 'withdrawn', responded_at = now() where id = ci.id;
  perform omelo_private.omelo_emit('InvitationWithdrawn', 'candidate_invitation', ci.id, ci.company_id, ci.person_id, '{}'::jsonb);
end;
$$;

create or replace function public.omelo_respond_to_invitation(p_invitation uuid, p_reason text default null)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare ci candidate_invitations;
begin
  select * into ci from candidate_invitations where id = p_invitation and person_id = auth.uid();
  if ci.id is null then raise exception 'Invitation not found' using errcode = '42501'; end if;
  if ci.response is not null then
    raise exception 'You already answered this invitation' using errcode = '22023';
  end if;
  update candidate_invitations
     set response = 'declined', responded_at = now(),
         decline_reason = left(nullif(trim(coalesce(p_reason, '')), ''), 300),
         viewed_at = coalesce(viewed_at, now())
   where id = ci.id;
  perform omelo_private.omelo_emit('InvitationDeclined', 'candidate_invitation', ci.id, ci.company_id, ci.person_id,
    jsonb_build_object('job_id', ci.job_id));
end;
$$;

create or replace function public.omelo_mark_invitation_viewed(p_invitation uuid)
returns void
language sql security definer
set search_path = public, omelo_private
as $$
  update candidate_invitations set viewed_at = now()
   where id = p_invitation and person_id = auth.uid() and viewed_at is null;
$$;

create or replace function public.omelo_my_invitations()
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select coalesce(jsonb_agg(x order by (x->>'status' = 'pending') desc, x->>'sent_at' desc), '[]'::jsonb)
  from (
    select jsonb_build_object(
      'id', ci.id, 'job_id', j.id, 'job_title', j.title, 'job_status', j.status,
      'company_name', co.display_name, 'company_verified', co.is_verified, 'company_logo', co.logo_url,
      'location_text', j.location_text, 'work_type', j.work_type, 'workplace_type', j.workplace_type,
      'pay_min', j.pay_min, 'pay_max', j.pay_max, 'pay_period', j.pay_period, 'pay_currency', j.pay_currency,
      'message', ci.message, 'sent_at', ci.sent_at, 'expires_at', ci.expires_at, 'viewed_at', ci.viewed_at,
      'work_identity_id', ci.work_identity_id, 'identity_label', wi.label,
      'application_id', (select a.id from applications a where a.job_id = j.id and a.person_id = ci.person_id),
      'status', case when ci.response is not null then ci.response
                     when j.status <> 'published' then 'closed'
                     when ci.expires_at < now() then 'expired' else 'pending' end) as x
      from candidate_invitations ci
      join jobs j on j.id = ci.job_id
      join companies co on co.id = ci.company_id
      left join work_identities wi on wi.id = ci.work_identity_id
     where ci.person_id = (select auth.uid())
     order by ci.sent_at desc
     limit 100) s;
$$;

create or replace function public.omelo_job_invitations(p_job_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare v_company uuid;
begin
  select company_id into v_company from jobs where id = p_job_id;
  if v_company is null or not omelo_private.omelo_is_company_member(v_company) then
    raise exception 'Only the hiring team can see invitations for this job' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', ci.id, 'sent_at', ci.sent_at, 'responded_at', ci.responded_at, 'viewed', ci.viewed_at is not null,
      'status', case when ci.response is not null then ci.response
                     when ci.expires_at < now() then 'expired' else 'pending' end,
      'decline_reason', ci.decline_reason,
      'sent_by', (select display_name from persons where id = ci.sent_by),
      'application_id', (select a.id from applications a where a.job_id = ci.job_id and a.person_id = ci.person_id),
      'candidate', case when ci.work_identity_id is not null and omelo_private.omelo_can_view_identity(ci.work_identity_id)
                        then omelo_private.omelo_talent_card(ci.work_identity_id, ci.job_id, ci.company_id)
                        else jsonb_build_object('name', 'Candidate (no longer visible)') end)
      order by ci.sent_at desc)
      from candidate_invitations ci where ci.job_id = p_job_id), '[]'::jsonb);
end;
$$;

-- Applying closes the loop and attributes the application to its source.
create or replace function omelo_private.omelo_attribute_application()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare src match_events; m matches; v_inv candidate_invitations;
begin
  select * into v_inv from candidate_invitations
   where job_id = new.job_id and person_id = new.person_id and response is null;
  select * into src from match_events
   where person_id = new.person_id and job_id = new.job_id
     and event in ('click','view','save','impression') and occurred_at > now() - interval '30 days'
   order by (event <> 'impression') desc, occurred_at desc limit 1;
  select * into m from matches where person_id = new.person_id and job_id = new.job_id
   order by computed_at desc limit 1;
  insert into match_events (person_id, work_identity_id, job_id, company_id, event, surface, rank, score, engine_version)
  values (new.person_id, new.work_identity_id, new.job_id, new.company_id, 'apply',
          case when v_inv.id is not null then 'invitation' else coalesce(src.surface, 'other') end,
          src.rank, m.score, m.engine_version);
  if v_inv.id is not null then
    update candidate_invitations set response = 'applied', responded_at = now(),
           viewed_at = coalesce(viewed_at, now())
     where id = v_inv.id;
    perform omelo_private.omelo_emit('InvitationAccepted', 'candidate_invitation', v_inv.id, v_inv.company_id,
      new.person_id, jsonb_build_object('job_id', new.job_id, 'application_id', new.id));
  end if;
  return null;
end;
$$;
revoke execute on function omelo_private.omelo_attribute_application() from public, anon, authenticated;
drop trigger if exists applications_attribute on applications;
create trigger applications_attribute after insert on applications
  for each row execute function omelo_private.omelo_attribute_application();

-- 5. Talent pools: only identities the company may see ---------------------------------
create or replace function omelo_private.omelo_guard_pool_member()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if omelo_private.omelo_is_privileged() then
    return new;
  end if;
  if new.work_identity_id is null then
    raise exception 'Choose which work identity to save' using errcode = '22023';
  end if;
  if not exists (select 1 from work_identities where id = new.work_identity_id and person_id = new.person_id) then
    raise exception 'That work identity does not belong to this person' using errcode = '22023';
  end if;
  if not omelo_private.omelo_can_view_identity(new.work_identity_id) then
    raise exception 'You can only save candidates who are visible to your company' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' then
    new.added_by := auth.uid();
    new.added_at := now();
  end if;
  if new.note is not null and length(new.note) > 500 then
    raise exception 'Keep the note under 500 characters' using errcode = '22023';
  end if;
  return new;
end;
$$;
drop trigger if exists talent_pool_members_guard on talent_pool_members;
create trigger talent_pool_members_guard before insert or update on talent_pool_members
  for each row execute function omelo_private.omelo_guard_pool_member();

create or replace function public.omelo_pool_members(p_pool uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare tp talent_pools;
begin
  select * into tp from talent_pools where id = p_pool;
  if tp.id is null or not omelo_private.omelo_is_company_member(tp.company_id) then
    raise exception 'Pool not found' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'person_id', m.person_id, 'work_identity_id', m.work_identity_id, 'note', m.note, 'added_at', m.added_at,
      'visible', m.work_identity_id is not null and omelo_private.omelo_can_view_identity(m.work_identity_id),
      'candidate', case when m.work_identity_id is not null and omelo_private.omelo_can_view_identity(m.work_identity_id)
                        then omelo_private.omelo_talent_card(m.work_identity_id, null, tp.company_id)
                        else jsonb_build_object('name', 'Candidate (no longer visible)') end)
      order by m.added_at desc)
      from talent_pool_members m where m.pool_id = p_pool), '[]'::jsonb);
end;
$$;

-- 6. Profile views are recorded by the server only -----------------------------------
drop policy if exists profile_views_insert on profile_views;
revoke insert, update, delete on profile_views from anon, authenticated;

create or replace function public.omelo_my_profile_views(p_days integer default 30)
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select coalesce(jsonb_agg(x order by x->>'last_viewed_at' desc), '[]'::jsonb)
  from (
    select jsonb_build_object('company_name', co.display_name, 'company_verified', co.is_verified,
             'company_logo', co.logo_url, 'identity_label', wi.label,
             'views', count(*), 'last_viewed_at', max(pv.viewed_at)) as x
      from profile_views pv
      join companies co on co.id = pv.viewer_company_id
      left join work_identities wi on wi.id = pv.work_identity_id
     where pv.person_id = (select auth.uid())
       and pv.viewed_at > now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 365)))
     group by co.id, co.display_name, co.is_verified, co.logo_url, wi.label) s;
$$;

-- Funnel metrics ----------------------------------------------------------------------
create or replace function public.omelo_job_funnel(p_job_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare v jsonb; s jsonb; inv jsonb; f record;
begin
  if not omelo_private.omelo_can_access_job(p_job_id) then
    raise exception 'Only the hiring team can see this job''s funnel' using errcode = '42501';
  end if;
  with cohort as (
    select a.id,
           bool_or(e.event_type = 'ApplicationViewed')    or a.first_viewed_at is not null as viewed,
           bool_or(e.event_type = 'CandidateShortlisted') as shortlisted,
           bool_or(e.event_type = 'InterviewScheduled')   as interviewed,
           bool_or(e.event_type = 'OfferSent')            as offered,
           bool_or(e.event_type = 'WorkerHired')          as hired
      from applications a
      left join domain_events e on e.aggregate_type = 'application' and e.aggregate_id = a.id
     where a.job_id = p_job_id
     group by a.id, a.first_viewed_at)
  select count(*) as applied,
         count(*) filter (where viewed or shortlisted or interviewed or offered or hired) as viewed,
         count(*) filter (where shortlisted or interviewed or offered or hired) as shortlisted,
         count(*) filter (where interviewed or offered or hired) as interviewed,
         count(*) filter (where offered or hired) as offered,
         count(*) filter (where hired) as hired
    into f from cohort;

  select coalesce(jsonb_agg(jsonb_build_object('surface', surface, 'impressions', imp, 'views', vw, 'applications', ap)
                            order by ap desc, vw desc), '[]'::jsonb) into s
    from (select surface,
                 count(distinct person_id) filter (where event = 'impression') as imp,
                 count(distinct person_id) filter (where event in ('view','click')) as vw,
                 count(*) filter (where event = 'apply') as ap
            from match_events where job_id = p_job_id group by surface) t;

  select jsonb_build_object(
           'sent', count(*),
           'viewed', count(*) filter (where viewed_at is not null),
           'applied', count(*) filter (where response = 'applied'),
           'declined', count(*) filter (where response = 'declined'),
           'pending', count(*) filter (where response is null and expires_at >= now())) into inv
    from candidate_invitations where job_id = p_job_id;

  select jsonb_build_object(
    'impressions', (select count(distinct person_id) from match_events where job_id = p_job_id and event = 'impression'),
    'views', (select count(distinct person_id) from match_events where job_id = p_job_id and event in ('view','click')),
    'view_count', (select view_count from jobs where id = p_job_id),
    'applied', f.applied, 'viewed', f.viewed, 'shortlisted', f.shortlisted,
    'interviewed', f.interviewed, 'offered', f.offered, 'hired', f.hired,
    'by_surface', s, 'invitations', inv,
    'talent_searches', (select count(*) from domain_events where event_type = 'TalentSearched' and aggregate_id = p_job_id))
  into v;
  return v;
end;
$$;

create or replace function public.omelo_admin_matching_metrics(p_days integer default 30)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare
  v_since timestamptz := now() - make_interval(days => greatest(1, least(coalesce(p_days, 30), 365)));
  v_surface jsonb; v_band jsonb; v_talent jsonb; v_engine jsonb;
begin
  if not omelo_private.omelo_is_platform_admin() then
    raise exception 'Platform administrators only' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('surface', surface, 'impressions', imp, 'views', vw, 'applications', ap,
            'view_rate', case when imp > 0 then round(vw::numeric / imp, 3) end,
            'apply_rate', case when vw > 0 then round(ap::numeric / vw, 3) end) order by imp desc), '[]'::jsonb)
    into v_surface
    from (select surface,
                 count(distinct (person_id, job_id)) filter (where event = 'impression') as imp,
                 count(distinct (person_id, job_id)) filter (where event in ('view','click')) as vw,
                 count(*) filter (where event = 'apply') as ap
            from match_events where occurred_at >= v_since group by surface) t;

  with apps as (
    select a.id, me.score,
           exists (select 1 from domain_events e where e.aggregate_id = a.id
                     and e.event_type in ('CandidateShortlisted','InterviewScheduled','OfferSent','WorkerHired')) as progressed,
           exists (select 1 from domain_events e where e.aggregate_id = a.id and e.event_type = 'WorkerHired') as hired
      from applications a
      join match_events me on me.event = 'apply' and me.job_id = a.job_id and me.person_id = a.person_id
     where me.occurred_at >= v_since)
  select coalesce(jsonb_agg(jsonb_build_object('band', band, 'applications', n,
            'progressed_rate', round(pr::numeric / nullif(n, 0), 3),
            'hire_rate', round(h::numeric / nullif(n, 0), 3)) order by band), '[]'::jsonb)
    into v_band
    from (select case when score is null then 'unscored'
                      when score >= 85 then '85-100' when score >= 70 then '70-84'
                      when score >= 50 then '50-69' else '0-49' end as band,
                 count(*) as n, count(*) filter (where progressed) as pr, count(*) filter (where hired) as h
            from apps group by 1) b;

  select jsonb_build_object(
    'searches', (select count(*) from domain_events where event_type = 'TalentSearched' and occurred_at >= v_since),
    'companies_searching', (select count(distinct company_id) from domain_events
                             where event_type = 'TalentSearched' and occurred_at >= v_since),
    'invitations_sent', count(*),
    'invitations_applied', count(*) filter (where response = 'applied'),
    'invitations_declined', count(*) filter (where response = 'declined'),
    'invitation_apply_rate', round(count(*) filter (where response = 'applied')::numeric / nullif(count(*), 0), 3))
    into v_talent
    from candidate_invitations where sent_at >= v_since;

  select coalesce(jsonb_agg(jsonb_build_object('engine_version', engine_version, 'matches', n) order by n desc), '[]'::jsonb)
    into v_engine
    from (select engine_version, count(*) as n from matches where computed_at >= v_since group by 1) x;

  return jsonb_build_object('days', greatest(1, least(coalesce(p_days, 30), 365)),
    'by_surface', v_surface, 'by_score_band', v_band, 'talent', v_talent, 'engines', v_engine);
end;
$$;

-- 7. Admin: company verification and entitlements -----------------------------------
create or replace function public.omelo_admin_set_company_verification(p_company uuid, p_verified boolean,
                                                                       p_method text default 'manual_review')
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if not omelo_private.omelo_is_platform_admin(array['superadmin','trust_safety']) then
    raise exception 'Trust & Safety administrators only' using errcode = '42501';
  end if;
  update companies
     set is_verified = p_verified,
         verified_at = case when p_verified then now() end,
         verification_method = case when p_verified then left(coalesce(p_method, 'manual_review'), 40) end
   where id = p_company and deleted_at is null;
  if not found then raise exception 'Company not found' using errcode = '22023'; end if;
  insert into audit_log (actor_type, actor_id, action, subject_type, subject_id, company_id, metadata)
  values ('admin', auth.uid(), case when p_verified then 'company.verified' else 'company.unverified' end,
          'company', p_company, p_company, jsonb_build_object('method', p_method));
  perform omelo_private.omelo_emit(case when p_verified then 'CompanyVerified' else 'CompanyUnverified' end,
                                   'company', p_company, p_company, null, '{}'::jsonb);
end;
$$;

create or replace function public.omelo_admin_set_entitlements(
  p_company uuid, p_plan text, p_talent_search boolean,
  p_search_quota_monthly integer default 0, p_outreach_quota_daily integer default 0,
  p_valid_until date default null)
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if not omelo_private.omelo_is_platform_admin(array['superadmin']) then
    raise exception 'Superadministrators only' using errcode = '42501';
  end if;
  if coalesce(p_search_quota_monthly, 0) < 0 or coalesce(p_outreach_quota_daily, 0) < 0 then
    raise exception 'Quotas cannot be negative' using errcode = '22023';
  end if;
  insert into company_entitlements (company_id, plan, talent_search_enabled, talent_search_quota_monthly,
                                    outreach_quota_daily, valid_until, updated_at)
  values (p_company, coalesce(p_plan, 'free'), coalesce(p_talent_search, false), coalesce(p_search_quota_monthly, 0),
          coalesce(p_outreach_quota_daily, 0), p_valid_until, now())
  on conflict (company_id) do update
     set plan = excluded.plan, talent_search_enabled = excluded.talent_search_enabled,
         talent_search_quota_monthly = excluded.talent_search_quota_monthly,
         outreach_quota_daily = excluded.outreach_quota_daily, valid_until = excluded.valid_until,
         updated_at = now();
  insert into audit_log (actor_type, actor_id, action, subject_type, subject_id, company_id, metadata)
  values ('admin', auth.uid(), 'company.entitlements_set', 'company', p_company, p_company,
          jsonb_build_object('plan', p_plan, 'talent_search', p_talent_search,
                             'search_quota_monthly', p_search_quota_monthly, 'outreach_quota_daily', p_outreach_quota_daily,
                             'valid_until', p_valid_until));
end;
$$;

-- Grants: signed-in users only -------------------------------------------------------
do $$
declare fn text;
begin
  foreach fn in array array[
    'omelo_track_job_events(jsonb)',
    'omelo_search_talent(uuid, text, integer, integer, integer)',
    'omelo_talent_profile(uuid, uuid)',
    'omelo_invite_to_apply(uuid, uuid, text)',
    'omelo_withdraw_invitation(uuid)',
    'omelo_respond_to_invitation(uuid, text)',
    'omelo_mark_invitation_viewed(uuid)',
    'omelo_my_invitations()',
    'omelo_job_invitations(uuid)',
    'omelo_pool_members(uuid)',
    'omelo_my_profile_views(integer)',
    'omelo_job_funnel(uuid)',
    'omelo_admin_matching_metrics(integer)',
    'omelo_admin_set_company_verification(uuid, boolean, text)',
    'omelo_admin_set_entitlements(uuid, text, boolean, integer, integer, date)'
  ] loop
    execute format('revoke execute on function public.%s from public, anon', fn);
    execute format('grant execute on function public.%s to authenticated', fn);
  end loop;
end;
$$;
