-- OMELO 62 — Release 6: global recruiter search for employers.
-- omelo_search_talent gains an optional p_filters (the same filters the agency search has, plus
-- R6's eligibility / open_to_relocation / language / current_country / work_auth_country).
-- Existing callers are unaffected (the new argument has a default). The query and radius arguments
-- still win over the same keys inside p_filters.
-- Rollback: recreate the 5-argument version from 41.

drop function if exists public.omelo_search_talent(uuid, text, integer, integer, integer);

create or replace function public.omelo_search_talent(p_job_id uuid, p_query text default null, p_radius_km integer default 50,
                                                      p_limit integer default 25, p_offset integer default 0,
                                                      p_filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private, extensions
as $$
declare j jobs; e company_entitlements; v_used int; v jsonb; v_filters jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required' using errcode = '42501'; end if;
  select * into j from jobs where id = p_job_id;
  if j.id is null or not omelo_private.omelo_has_company_role(j.company_id, array['owner','admin','recruiter']::company_role[]) then
    raise exception 'Only the hiring team can search for this job' using errcode = '42501';
  end if;
  if j.status <> 'published' then
    raise exception 'Publish the job before searching for candidates' using errcode = '22023';
  end if;
  if p_filters is not null and jsonb_typeof(p_filters) <> 'object' then
    raise exception 'Filters must be an object' using errcode = '22023';
  end if;
  e := omelo_private.omelo_require_talent_access(j.company_id);
  select count(*) into v_used from domain_events
   where event_type = 'TalentSearched' and company_id = j.company_id and occurred_at >= date_trunc('month', now());
  if e.talent_search_quota_monthly > 0 and v_used >= e.talent_search_quota_monthly then
    raise exception 'Your company has used its % talent searches for this month', e.talent_search_quota_monthly
      using errcode = '22023';
  end if;
  -- consent filters belong to agency job orders; an employer search never carries them
  v_filters := (coalesce(p_filters, '{}'::jsonb) - 'consent_status' - 'previous_relationship')
               || jsonb_build_object('query', p_query, 'radius_km', p_radius_km);
  v := omelo_private.omelo_talent_search_core(j.id, j.company_id, v_filters, p_limit, p_offset, null);
  perform omelo_private.omelo_emit('TalentSearched', 'job', j.id, j.company_id, auth.uid(),
    jsonb_build_object('query', nullif(trim(coalesce(p_query, '')), ''), 'radius_km', p_radius_km, 'found', v->'total',
                       'filters', v_filters - 'query' - 'radius_km'));
  return v || jsonb_build_object('quota', jsonb_build_object('used', v_used + 1,
                                                             'limit', nullif(e.talent_search_quota_monthly, 0)));
end;
$$;

revoke all on function public.omelo_search_talent(uuid, text, integer, integer, integer, jsonb) from public, anon;
grant execute on function public.omelo_search_talent(uuid, text, integer, integer, integer, jsonb) to authenticated;
