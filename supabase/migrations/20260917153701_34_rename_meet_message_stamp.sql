-- OMELO 34: rename a trigger function so invariant 16 stays meaningful.
-- omelo_guard_* functions must be SECURITY INVOKER (they trust current_user).
-- The meet-message trigger is deliberately SECURITY DEFINER: it does not
-- authorise anything (RLS on meet_messages does), it stamps the sender's
-- display name and counts recent messages for the flood limit, both of
-- which must read past the caller's RLS. It is renamed to say what it does.

create or replace function omelo_private.omelo_stamp_meet_message()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if (select count(*) from meet_messages
       where sender_id = new.sender_id and interview_id = new.interview_id
         and sent_at > now() - interval '1 minute') >= 30 then
    raise exception 'You are sending messages too quickly' using errcode = '54000';
  end if;
  new.sender_name := (select display_name from persons where id = new.sender_id);
  new.sent_at := now();
  return new;
end;
$$;
revoke execute on function omelo_private.omelo_stamp_meet_message() from public, anon, authenticated;

drop trigger if exists meet_messages_guard on meet_messages;
create trigger meet_messages_stamp before insert on meet_messages
  for each row execute function omelo_private.omelo_stamp_meet_message();

drop function if exists omelo_private.omelo_guard_meet_message();
