-- OMELO 42 (Release 3 fixes, found by tests/api/talent_e2e.py)
--
-- 1. omelo_search_talent measures distance with PostGIS, which lives in the
--    extensions schema: add it to the function's search_path.
-- 2. omelo_enqueue_email stored p_send_after as given; an explicit NULL
--    violated outbound_messages.send_after NOT NULL. NULL now means "now".
-- 3. companies.verification_method is an enum; the admin function now takes
--    one of its values (default manual_admin) and rejects anything else.

alter function public.omelo_search_talent(uuid, text, integer, integer, integer)
  set search_path = public, omelo_private, extensions;

create or replace function omelo_private.omelo_enqueue_email(
  p_person uuid, p_template text, p_subject text, p_payload jsonb,
  p_dedupe text default null, p_send_after timestamptz default now()
) returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_email text;
begin
  select email into v_email from persons where id = p_person;
  if v_email is null or position('@' in v_email) = 0 then
    return;   -- no address: the in-app notification still reaches them
  end if;
  insert into outbound_messages (person_id, channel, template, to_address, subject, payload, dedupe_key, send_after)
  values (p_person, 'email', p_template, v_email, p_subject, coalesce(p_payload, '{}'), p_dedupe,
          coalesce(p_send_after, now()))
  on conflict (dedupe_key) do nothing;
end;
$$;
revoke execute on function omelo_private.omelo_enqueue_email(uuid, text, text, jsonb, text, timestamptz) from public, anon, authenticated;

create or replace function public.omelo_admin_set_company_verification(p_company uuid, p_verified boolean,
                                                                       p_method text default 'manual_admin')
returns void
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_method verification_method;
begin
  if not omelo_private.omelo_is_platform_admin(array['superadmin','trust_safety']) then
    raise exception 'Trust & Safety administrators only' using errcode = '42501';
  end if;
  if p_verified then
    if not exists (select 1 from pg_enum e join pg_type t on t.oid = e.enumtypid
                    where t.typname = 'verification_method' and e.enumlabel = coalesce(p_method, 'manual_admin')) then
      raise exception 'Unknown verification method %', p_method using errcode = '22023';
    end if;
    v_method := coalesce(p_method, 'manual_admin')::verification_method;
  end if;
  update companies
     set is_verified = p_verified,
         verified_at = case when p_verified then now() end,
         verification_method = v_method
   where id = p_company and deleted_at is null;
  if not found then raise exception 'Company not found' using errcode = '22023'; end if;
  insert into audit_log (actor_type, actor_id, action, subject_type, subject_id, company_id, metadata)
  values ('admin', auth.uid(), case when p_verified then 'company.verified' else 'company.unverified' end,
          'company', p_company, p_company, jsonb_build_object('method', v_method));
  perform omelo_private.omelo_emit(case when p_verified then 'CompanyVerified' else 'CompanyUnverified' end,
                                   'company', p_company, p_company, null, '{}'::jsonb);
end;
$$;
