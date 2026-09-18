-- OMELO 43 (Release 3 fix, found by tests/api/talent_e2e.py)
--
-- Talent search cards promised "first name + last initial" before a
-- candidate applies, but signup fills only persons.display_name, so the full
-- name was shown. The short form is now derived from display_name as well.

create or replace function omelo_private.omelo_talent_card(p_identity uuid, p_job uuid, p_company uuid)
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select jsonb_build_object(
    'work_identity_id', wi.id,
    'name', coalesce(
              nullif(trim(coalesce(p.given_name, '') || coalesce(' ' || left(p.family_name, 1) || '.', '')), ''),
              case when trim(coalesce(p.display_name, '')) ~ '\s'
                   then split_part(trim(p.display_name), ' ', 1) || ' '
                        || left(regexp_replace(trim(p.display_name), '^.*\s', ''), 1) || '.'
                   else nullif(trim(p.display_name), '') end,
              'Candidate'),
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
