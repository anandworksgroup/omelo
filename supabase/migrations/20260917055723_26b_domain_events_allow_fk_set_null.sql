create or replace function omelo_private.omelo_domain_events_append_only()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'domain_events is append-only';
  end if;
  if (to_jsonb(new) - 'processed_at' - 'company_id' - 'person_id')
       is distinct from (to_jsonb(old) - 'processed_at' - 'company_id' - 'person_id')
     or (new.company_id is distinct from old.company_id and new.company_id is not null)
     or (new.person_id  is distinct from old.person_id  and new.person_id  is not null) then
    raise exception 'domain_events is append-only (only processed_at may be set)';
  end if;
  return new;
end;
$$;