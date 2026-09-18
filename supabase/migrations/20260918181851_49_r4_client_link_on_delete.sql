-- OMELO 49 (Release 4 fix, found while cleaning up tests/api/recruitment_e2e.py)
--
-- When a linked client company is deleted, agency_clients.client_company_id
-- is set to NULL by its foreign key, but link_status stayed 'confirmed' and
-- the row check (confirmed => company present) rejected the delete. Deleting
-- an account that owns a client company could therefore fail. The guard now
-- normalises the link for every writer: a vanished company means 'unlinked'.

create or replace function omelo_private.omelo_guard_agency_client()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if new.link_status = 'confirmed' and new.client_company_id is null then
    new.link_status := 'unlinked';
  end if;
  if new.link_status = 'pending' and new.requested_company_id is null then
    new.link_status := 'unlinked';
  end if;
  if omelo_private.omelo_is_privileged() then
    new.updated_at := now();
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.client_company_id := null;
    new.requested_company_id := null;
    new.link_status := 'unlinked';
    new.created_by := auth.uid();
  else
    if new.agency_id is distinct from old.agency_id
    or new.client_company_id is distinct from old.client_company_id
    or new.requested_company_id is distinct from old.requested_company_id
    or new.link_status is distinct from old.link_status
    or new.created_by is distinct from old.created_by then
      raise exception 'Linking a client company goes through the client''s confirmation' using errcode = '42501';
    end if;
  end if;
  if new.owner_id is not null
     and not omelo_private.omelo_person_agency_can(new.owner_id, new.agency_id, 'view') then
    raise exception 'The client owner must be a member of the agency' using errcode = '22023';
  end if;
  new.updated_at := now();
  return new;
end;
$$;
