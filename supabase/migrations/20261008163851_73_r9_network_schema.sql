-- OMELO 73 — Release 9: the professional network — schema.
--
-- Not a separate social product: the network hangs off what Omelo already has.
--
--   persons / work_identities ──┐
--   companies (organizations) ──┤
--   jobs ───────────────────────┤
--                               ▼
--                             posts ── post_media
--                               ├── post_comments (threaded, one level of reply)
--                               ├── post_reactions / comment_reactions
--                               ├── post_saves
--                               └── shares (a post that quotes another post)
--   follows      (person -> person or organization)   already existed (R1)
--   blocks       (person -> person or company)        already existed (R1)
--   reports      (any subject, moderation)            already existed (R1)
--   connections  (two-way, accepted)                  new
--   feed_preferences / feed_mutes                     new
--
-- The existing privacy rule stands: public content describes people, organizations, careers and
-- opportunities; private employment transactions stay private. A post can carry a job or another
-- post — never an application, offer, assignment, timesheet or payment (R9-003).
--
-- Visibility of a post:
--   public         anyone, signed out included (the public organization feed)
--   followers      people who follow the author
--   connections    accepted connections of the author (person posts only)
--   organization   members of the authoring organization
--
-- Counts (reactions, comments, shares, saves) are kept by triggers so the feed never counts rows.
--
-- Rollback: drop the tables below and the post-media bucket; follows/blocks/reports are untouched.

-- 1. Posts -----------------------------------------------------------------------------------------
create table if not exists public.posts (
  id                 uuid primary key default gen_random_uuid(),
  author_person_id   uuid references persons(id) on delete cascade,
  author_company_id  uuid references companies(id) on delete cascade,
  work_identity_id   uuid references work_identities(id) on delete set null,
  kind               text not null default 'update'
                     check (kind in ('update','job_share','organization_update','hiring','achievement','share')),
  body               text check (body is null or length(body) <= 3000),
  job_id             uuid references jobs(id) on delete set null,
  shared_post_id     uuid references posts(id) on delete set null,
  visibility         text not null default 'public'
                     check (visibility in ('public','followers','connections','organization')),
  status             text not null default 'published'
                     check (status in ('published','hidden','removed')),
  language_code      text,
  reaction_count     integer not null default 0,
  comment_count      integer not null default 0,
  share_count        integer not null default 0,
  save_count         integer not null default 0,
  created_at         timestamptz not null default now(),
  edited_at          timestamptz,
  deleted_at         timestamptz,
  -- exactly one author, and a post says something: text, media, a job, or a quoted post
  check ((author_person_id is null) <> (author_company_id is null)),
  check (author_company_id is null or visibility in ('public','followers','organization')),
  check (shared_post_id is null or shared_post_id <> id)
);
create index if not exists posts_author_person on posts (author_person_id, created_at desc) where deleted_at is null;
create index if not exists posts_author_company on posts (author_company_id, created_at desc) where deleted_at is null;
create index if not exists posts_public_recent on posts (created_at desc) where deleted_at is null and status = 'published';
create index if not exists posts_job on posts (job_id) where job_id is not null;
create index if not exists posts_shared on posts (shared_post_id) where shared_post_id is not null;

create table if not exists public.post_media (
  id          uuid primary key default gen_random_uuid(),
  post_id     uuid not null references posts(id) on delete cascade,
  position    smallint not null default 0 check (position between 0 and 9),
  kind        text not null check (kind in ('image','video')),
  storage_path text not null,
  mime_type   text not null,
  width       integer check (width is null or width > 0),
  height      integer check (height is null or height > 0),
  duration_seconds integer check (duration_seconds is null or duration_seconds between 1 and 600),
  alt_text    text check (alt_text is null or length(alt_text) <= 300),
  created_at  timestamptz not null default now(),
  unique (post_id, position)
);

create table if not exists public.post_comments (
  id                uuid primary key default gen_random_uuid(),
  post_id           uuid not null references posts(id) on delete cascade,
  person_id         uuid not null references persons(id) on delete cascade,
  parent_comment_id uuid references post_comments(id) on delete cascade,
  body              text not null check (length(trim(body)) between 1 and 2000),
  reaction_count    integer not null default 0,
  reply_count       integer not null default 0,
  created_at        timestamptz not null default now(),
  edited_at         timestamptz,
  deleted_at        timestamptz
);
create index if not exists post_comments_post on post_comments (post_id, created_at) where deleted_at is null;
create index if not exists post_comments_parent on post_comments (parent_comment_id, created_at) where parent_comment_id is not null;

create table if not exists public.post_reactions (
  post_id    uuid not null references posts(id) on delete cascade,
  person_id  uuid not null references persons(id) on delete cascade,
  kind       text not null default 'like' check (kind in ('like','celebrate','support','insightful','curious')),
  created_at timestamptz not null default now(),
  primary key (post_id, person_id)
);
create index if not exists post_reactions_person on post_reactions (person_id, created_at desc);

create table if not exists public.comment_reactions (
  comment_id uuid not null references post_comments(id) on delete cascade,
  person_id  uuid not null references persons(id) on delete cascade,
  kind       text not null default 'like' check (kind in ('like','celebrate','support','insightful','curious')),
  created_at timestamptz not null default now(),
  primary key (comment_id, person_id)
);

create table if not exists public.post_saves (
  person_id  uuid not null references persons(id) on delete cascade,
  post_id    uuid not null references posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (person_id, post_id)
);

-- 2. Connections (two-way, by invitation) ------------------------------------------------------------
create table if not exists public.connections (
  id            uuid primary key default gen_random_uuid(),
  requester_id  uuid not null references persons(id) on delete cascade,
  addressee_id  uuid not null references persons(id) on delete cascade,
  status        text not null default 'pending' check (status in ('pending','accepted','declined','withdrawn','removed')),
  message       text check (message is null or length(message) <= 300),
  requested_at  timestamptz not null default now(),
  responded_at  timestamptz,
  check (requester_id <> addressee_id)
);
-- one relationship per pair, whichever way round it was asked
create unique index if not exists connections_pair
  on connections (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index if not exists connections_addressee on connections (addressee_id, status);
create index if not exists connections_requester on connections (requester_id, status);

-- 3. Feed preferences and mutes ------------------------------------------------------------------------
create table if not exists public.feed_preferences (
  person_id            uuid primary key references persons(id) on delete cascade,
  show_jobs            boolean not null default true,
  show_organizations   boolean not null default true,
  show_career_content  boolean not null default true,
  show_network_activity boolean not null default true,
  preferred_languages  text[] not null default '{}',
  updated_at           timestamptz not null default now()
);

create table if not exists public.feed_mutes (
  person_id   uuid not null references persons(id) on delete cascade,
  target_type text not null check (target_type in ('person','company','post')),
  target_id   uuid not null,
  created_at  timestamptz not null default now(),
  primary key (person_id, target_type, target_id)
);

create index if not exists follows_target on follows (target_type, target_id);

-- 4. Who may see a post --------------------------------------------------------------------------------
create or replace function omelo_private.omelo_are_connected(p_a uuid, p_b uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select exists (select 1 from connections c
                  where c.status = 'accepted'
                    and ((c.requester_id = p_a and c.addressee_id = p_b)
                      or (c.requester_id = p_b and c.addressee_id = p_a)));
$$;

create or replace function omelo_private.omelo_blocked_between(p_a uuid, p_b uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select p_a is not null and p_b is not null and exists (
    select 1 from blocks b
     where b.target_type = 'person'
       and ((b.person_id = p_a and b.target_id = p_b) or (b.person_id = p_b and b.target_id = p_a)));
$$;

create or replace function omelo_private.omelo_can_see_post(p_post uuid)
returns boolean
language sql stable security definer
set search_path = public, omelo_private
as $$
  select exists (
    select 1 from posts p
     where p.id = p_post and p.deleted_at is null and p.status = 'published'
       and not omelo_private.omelo_blocked_between(p.author_person_id, (select auth.uid()))
       and not (p.author_company_id is not null
                and exists (select 1 from blocks b where b.person_id = (select auth.uid())
                             and b.target_type = 'company' and b.target_id = p.author_company_id))
       and (
         p.visibility = 'public'
         or p.author_person_id = (select auth.uid())
         or (p.visibility = 'followers'
             and exists (select 1 from follows f
                          where f.person_id = (select auth.uid())
                            and ((p.author_person_id is not null and f.target_type = 'person' and f.target_id = p.author_person_id)
                              or (p.author_company_id is not null and f.target_type = 'company' and f.target_id = p.author_company_id))))
         or (p.visibility = 'connections' and omelo_private.omelo_are_connected(p.author_person_id, (select auth.uid())))
         or (p.visibility = 'organization' and p.author_company_id is not null
             and omelo_private.omelo_is_company_member(p.author_company_id))));
$$;

-- 5. Row level security ---------------------------------------------------------------------------------
alter table posts enable row level security;
alter table post_media enable row level security;
alter table post_comments enable row level security;
alter table post_reactions enable row level security;
alter table comment_reactions enable row level security;
alter table post_saves enable row level security;
alter table connections enable row level security;
alter table feed_preferences enable row level security;
alter table feed_mutes enable row level security;

-- Posts: read by visibility; written by the author (a person for their own posts, an owner, admin,
-- recruiter or HR for an organization's).
drop policy if exists posts_read on posts;
drop policy if exists posts_author_write on posts;
drop policy if exists posts_company_write on posts;
create policy posts_read on posts for select to anon, authenticated
  using (deleted_at is null and status = 'published'
         and (visibility = 'public' or omelo_private.omelo_can_see_post(id)));
create policy posts_author_write on posts for all to authenticated
  using (author_person_id = (select auth.uid()))
  with check (author_person_id = (select auth.uid()));
create policy posts_company_write on posts for all to authenticated
  using (author_company_id is not null
         and omelo_private.omelo_has_company_role(author_company_id,
               array['owner','admin','recruiter','hr']::company_role[]))
  with check (author_company_id is not null
         and omelo_private.omelo_has_company_role(author_company_id,
               array['owner','admin','recruiter','hr']::company_role[]));

drop policy if exists post_media_read on post_media;
drop policy if exists post_media_write on post_media;
create policy post_media_read on post_media for select to anon, authenticated
  using (exists (select 1 from posts p where p.id = post_id
                  and p.deleted_at is null and p.status = 'published'
                  and (p.visibility = 'public' or omelo_private.omelo_can_see_post(p.id))));
create policy post_media_write on post_media for all to authenticated
  using (exists (select 1 from posts p where p.id = post_id
                  and (p.author_person_id = (select auth.uid())
                       or (p.author_company_id is not null
                           and omelo_private.omelo_has_company_role(p.author_company_id,
                                 array['owner','admin','recruiter','hr']::company_role[])))))
  with check (exists (select 1 from posts p where p.id = post_id
                  and (p.author_person_id = (select auth.uid())
                       or (p.author_company_id is not null
                           and omelo_private.omelo_has_company_role(p.author_company_id,
                                 array['owner','admin','recruiter','hr']::company_role[])))));

-- Comments and reactions: anyone who can see the post; each person owns their own rows.
drop policy if exists post_comments_read on post_comments;
drop policy if exists post_comments_self on post_comments;
create policy post_comments_read on post_comments for select to anon, authenticated
  using (deleted_at is null and omelo_private.omelo_can_see_post(post_id));
create policy post_comments_self on post_comments for all to authenticated
  using (person_id = (select auth.uid()))
  with check (person_id = (select auth.uid()) and omelo_private.omelo_can_see_post(post_id));

drop policy if exists post_reactions_read on post_reactions;
drop policy if exists post_reactions_self on post_reactions;
create policy post_reactions_read on post_reactions for select to anon, authenticated
  using (omelo_private.omelo_can_see_post(post_id));
create policy post_reactions_self on post_reactions for all to authenticated
  using (person_id = (select auth.uid()))
  with check (person_id = (select auth.uid()) and omelo_private.omelo_can_see_post(post_id));

drop policy if exists comment_reactions_read on comment_reactions;
drop policy if exists comment_reactions_self on comment_reactions;
create policy comment_reactions_read on comment_reactions for select to anon, authenticated
  using (exists (select 1 from post_comments c where c.id = comment_id and omelo_private.omelo_can_see_post(c.post_id)));
create policy comment_reactions_self on comment_reactions for all to authenticated
  using (person_id = (select auth.uid()))
  with check (person_id = (select auth.uid())
              and exists (select 1 from post_comments c where c.id = comment_id and omelo_private.omelo_can_see_post(c.post_id)));

-- Saves, preferences and mutes are private to the person.
drop policy if exists post_saves_self on post_saves;
create policy post_saves_self on post_saves for all to authenticated
  using (person_id = (select auth.uid()))
  with check (person_id = (select auth.uid()) and omelo_private.omelo_can_see_post(post_id));

drop policy if exists feed_preferences_self on feed_preferences;
create policy feed_preferences_self on feed_preferences for all to authenticated
  using (person_id = (select auth.uid())) with check (person_id = (select auth.uid()));

drop policy if exists feed_mutes_self on feed_mutes;
create policy feed_mutes_self on feed_mutes for all to authenticated
  using (person_id = (select auth.uid())) with check (person_id = (select auth.uid()));

-- Connections: both sides read their own; writes go through the functions in 74.
drop policy if exists connections_read on connections;
create policy connections_read on connections for select to authenticated
  using (requester_id = (select auth.uid()) or addressee_id = (select auth.uid()));
revoke insert, update, delete on connections from anon, authenticated;

-- 6. Integrity -------------------------------------------------------------------------------------------
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
    if new.created_at is distinct from old.created_at then
      raise exception 'A post keeps when it was written' using errcode = '42501';
    end if;
    if (new.body is distinct from old.body) then new.edited_at := now(); end if;
    -- counts are maintained by Omelo, not by the client
    if not omelo_private.omelo_is_privileged()
       and (new.reaction_count, new.comment_count, new.share_count, new.save_count)
           is distinct from (old.reaction_count, old.comment_count, old.share_count, old.save_count) then
      raise exception 'Engagement counts are kept by Omelo' using errcode = '42501';
    end if;
  else
    if new.author_person_id is not null and new.author_person_id <> auth.uid()
       and not omelo_private.omelo_is_privileged() then
      raise exception 'You can only post as yourself' using errcode = '42501';
    end if;
  end if;

  -- a post must say something
  select count(*) into v_media from post_media where post_id = new.id;
  if coalesce(length(trim(coalesce(new.body, ''))), 0) = 0 and new.job_id is null
     and new.shared_post_id is null and v_media = 0 and tg_op = 'UPDATE' then
    raise exception 'A post needs text, media, a job or a shared post' using errcode = '22023';
  end if;

  -- R9-003: a post may carry a public job or another post; never a private transaction
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
drop trigger if exists posts_validate on posts;
create trigger posts_validate before insert or update on posts
  for each row execute function omelo_private.omelo_validate_post();

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
    if not omelo_private.omelo_is_privileged()
       and (new.reaction_count, new.reply_count) is distinct from (old.reaction_count, old.reply_count) then
      raise exception 'Engagement counts are kept by Omelo' using errcode = '42501';
    end if;
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
drop trigger if exists post_comments_validate on post_comments;
create trigger post_comments_validate before insert or update on post_comments
  for each row execute function omelo_private.omelo_validate_comment();

-- Counts, kept by Omelo.
create or replace function omelo_private.omelo_bump_counts()
returns trigger
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_delta int := case when tg_op = 'INSERT' then 1 else -1 end; r record;
begin
  r := case when tg_op = 'DELETE' then old else new end;
  if tg_table_name = 'post_reactions' then
    update posts set reaction_count = greatest(0, reaction_count + v_delta) where id = r.post_id;
  elsif tg_table_name = 'post_saves' then
    update posts set save_count = greatest(0, save_count + v_delta) where id = r.post_id;
  elsif tg_table_name = 'comment_reactions' then
    update post_comments set reaction_count = greatest(0, reaction_count + v_delta) where id = r.comment_id;
  elsif tg_table_name = 'post_comments' then
    -- a soft delete counts as a removal
    if tg_op = 'UPDATE' then
      v_delta := case when new.deleted_at is not null and old.deleted_at is null then -1
                      when new.deleted_at is null and old.deleted_at is not null then 1 else 0 end;
    end if;
    if v_delta <> 0 then
      update posts set comment_count = greatest(0, comment_count + v_delta) where id = r.post_id;
      if r.parent_comment_id is not null then
        update post_comments set reply_count = greatest(0, reply_count + v_delta) where id = r.parent_comment_id;
      end if;
    end if;
  elsif tg_table_name = 'posts' then
    if tg_op = 'INSERT' and new.shared_post_id is not null then
      update posts set share_count = share_count + 1 where id = new.shared_post_id;
    elsif tg_op = 'DELETE' and old.shared_post_id is not null then
      update posts set share_count = greatest(0, share_count - 1) where id = old.shared_post_id;
    end if;
  end if;
  return null;
end;
$$;
drop trigger if exists post_reactions_count on post_reactions;
create trigger post_reactions_count after insert or delete on post_reactions
  for each row execute function omelo_private.omelo_bump_counts();
drop trigger if exists post_saves_count on post_saves;
create trigger post_saves_count after insert or delete on post_saves
  for each row execute function omelo_private.omelo_bump_counts();
drop trigger if exists comment_reactions_count on comment_reactions;
create trigger comment_reactions_count after insert or delete on comment_reactions
  for each row execute function omelo_private.omelo_bump_counts();
drop trigger if exists post_comments_count on post_comments;
create trigger post_comments_count after insert or update or delete on post_comments
  for each row execute function omelo_private.omelo_bump_counts();
drop trigger if exists posts_share_count on posts;
create trigger posts_share_count after insert or delete on posts
  for each row execute function omelo_private.omelo_bump_counts();

-- 7. Media storage ----------------------------------------------------------------------------------------
-- One public bucket for post images and video. Anyone may read (posts can be public); a signed-in
-- person writes only inside their own folder: post-media/<person uuid>/<file>.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('post-media', 'post-media', true, 52428800,
        array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit,
                               allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists post_media_public_read on storage.objects;
drop policy if exists post_media_own_write on storage.objects;
drop policy if exists post_media_own_delete on storage.objects;
create policy post_media_public_read on storage.objects for select to anon, authenticated
  using (bucket_id = 'post-media');
create policy post_media_own_write on storage.objects for insert to authenticated
  with check (bucket_id = 'post-media' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy post_media_own_delete on storage.objects for delete to authenticated
  using (bucket_id = 'post-media' and (storage.foldername(name))[1] = (select auth.uid())::text);

revoke all on function omelo_private.omelo_can_see_post(uuid) from public;
revoke all on function omelo_private.omelo_are_connected(uuid, uuid) from public;
revoke all on function omelo_private.omelo_blocked_between(uuid, uuid) from public;
grant execute on function omelo_private.omelo_can_see_post(uuid) to anon, authenticated;
grant execute on function omelo_private.omelo_are_connected(uuid, uuid) to anon, authenticated;
grant execute on function omelo_private.omelo_blocked_between(uuid, uuid) to anon, authenticated;
