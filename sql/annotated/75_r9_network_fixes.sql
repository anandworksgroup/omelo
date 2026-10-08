-- OMELO 75 — Release 9 fixes found by tests/api/network_e2e.py.
--
-- 1. `follows` was built in R1 for companies, professions, skills and categories. The network lets
--    people follow people, so 'person' joins the list (R9 uses it for feed affinity and reach).
-- 2. `reports` could not describe a post or a comment, so network content could not be reported.
-- 3. The engagement-count guard lived inside a SECURITY DEFINER validator. A definer function runs
--    as the owner, so omelo_is_privileged() was true inside it and the guard never fired: anyone
--    could PATCH reaction_count straight to 999. Guards must be SECURITY INVOKER — the same rule
--    invariant 16 enforces for every other omelo_guard_* function.
--
-- Rollback: restore the two CHECK constraints, drop the guard triggers and re-run 73's validators.

alter table follows drop constraint if exists follows_target_type_check;
alter table follows add constraint follows_target_type_check
  check (target_type = any (array['person','company','profession','skill','category']));

alter table reports drop constraint if exists reports_subject_type_check;
alter table reports add constraint reports_subject_type_check
  check (subject_type = any (array['job','company','person','message','conversation','application','post','comment']));

-- The counts belong to Omelo. This one is INVOKER, so current_user really is the caller.
create or replace function omelo_private.omelo_guard_engagement_counts()
returns trigger
language plpgsql
set search_path = public, omelo_private
as $$
begin
  if omelo_private.omelo_is_privileged() then return new; end if;
  if tg_table_name = 'posts' then
    if (new.reaction_count, new.comment_count, new.share_count, new.save_count)
       is distinct from (old.reaction_count, old.comment_count, old.share_count, old.save_count) then
      raise exception 'Reactions, comments, shares and saves are counted by Omelo' using errcode = '42501';
    end if;
    if new.created_at is distinct from old.created_at or new.status is distinct from old.status then
      raise exception 'A post keeps when it was written' using errcode = '42501';
    end if;
  else
    if (new.reaction_count, new.reply_count) is distinct from (old.reaction_count, old.reply_count) then
      raise exception 'Reactions and replies are counted by Omelo' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists posts_guard_counts on posts;
create trigger posts_guard_counts before update on posts
  for each row execute function omelo_private.omelo_guard_engagement_counts();
drop trigger if exists post_comments_guard_counts on post_comments;
create trigger post_comments_guard_counts before update on post_comments
  for each row execute function omelo_private.omelo_guard_engagement_counts();

-- The validators keep the structural rules; the counts are now the guard's business.
create or replace function omelo_private.omelo_validate_post()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_media int;
begin
  if tg_op = 'UPDATE' then
    if new.author_person_id is distinct from old.author_person_id
       or new.author_company_id is distinct from old.author_company_id then
      raise exception 'A post keeps its author' using errcode = '42501';
    end if;
    if new.body is distinct from old.body then new.edited_at := now(); end if;
  else
    if new.author_person_id is not null and new.author_person_id <> auth.uid()
       and not omelo_private.omelo_is_privileged() then
      raise exception 'You can only post as yourself' using errcode = '42501';
    end if;
  end if;

  select count(*) into v_media from post_media where post_id = new.id;
  if coalesce(length(trim(coalesce(new.body, ''))), 0) = 0 and new.job_id is null
     and new.shared_post_id is null and v_media = 0 and tg_op = 'UPDATE' then
    raise exception 'A post needs text, media, a job or a shared post' using errcode = '22023';
  end if;

  -- R9-003: a post may carry a public job or another public post; never a private transaction
  if new.job_id is not null then
    if not exists (select 1 from jobs j where j.id = new.job_id and j.status = 'published') then
      raise exception 'Only a published job can be shared' using errcode = '22023';
    end if;
    if new.author_company_id is not null
       and not exists (select 1 from jobs j where j.id = new.job_id and j.company_id = new.author_company_id) then
      raise exception 'An organization shares its own jobs' using errcode = '42501';
    end if;
  end if;
  if new.shared_post_id is not null then
    if not exists (select 1 from posts p where p.id = new.shared_post_id and p.deleted_at is null
                     and p.status = 'published' and p.visibility = 'public') then
      raise exception 'Only a public post can be shared on' using errcode = '42501';
    end if;
    if exists (select 1 from posts p where p.id = new.shared_post_id and p.shared_post_id is not null) then
      raise exception 'Share the original post' using errcode = '22023';
    end if;
  end if;
  if new.work_identity_id is not null
     and not exists (select 1 from work_identities wi where wi.id = new.work_identity_id
                      and wi.person_id = coalesce(new.author_person_id, auth.uid())) then
    raise exception 'That work identity is not yours' using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function omelo_private.omelo_validate_comment()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if tg_op = 'UPDATE' then
    if new.person_id is distinct from old.person_id or new.post_id is distinct from old.post_id
       or new.parent_comment_id is distinct from old.parent_comment_id then
      raise exception 'A comment stays where it was written' using errcode = '42501';
    end if;
    if new.body is distinct from old.body then new.edited_at := now(); end if;
    return new;
  end if;
  if new.parent_comment_id is not null then
    if not exists (select 1 from post_comments c where c.id = new.parent_comment_id and c.post_id = new.post_id) then
      raise exception 'That reply belongs to another post' using errcode = '22023';
    end if;
    if exists (select 1 from post_comments c where c.id = new.parent_comment_id and c.parent_comment_id is not null) then
      raise exception 'Replies go one level deep' using errcode = '22023';
    end if;
  end if;
  return new;
end;
$$;
