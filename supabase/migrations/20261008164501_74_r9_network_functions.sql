-- OMELO 74 — Release 9: the professional network — functions.
--
--   omelo_create_post / omelo_update_post / omelo_delete_post   write as yourself or as an organization
--   omelo_react_to_post / omelo_comment_on_post / omelo_delete_comment / omelo_share_post / omelo_save_post
--   omelo_follow / omelo_request_connection / omelo_respond_connection / omelo_remove_connection
--   omelo_my_network / omelo_connection_suggestions
--   omelo_feed            following · organizations · jobs · for you · saved, with pagination
--   omelo_organization_feed / omelo_person_posts / omelo_post_detail / omelo_post_comments
--   omelo_save_feed_preferences / omelo_mute_from_feed
--
-- Ranking for "for you" is explainable, not a black box:
--
--   affinity   connection 3 · person you follow 2 · organization you follow 2 · same profession 1
--   interest   + 0.5 × ln(1 + reactions + 2×comments + 3×shares)
--   freshness  − 0.15 per day since it was written
--
-- Each card carries why it is there ('from a connection', 'you follow this organization', …), so the
-- feed can explain itself the way the matcher does.
--
-- Rollback: drop the functions below; the tables in 73 stay.

-- The card Omelo shows for whoever wrote a post. Posting publicly means your name and photo travel
-- with the post — nothing else about the person is exposed here.
create or replace function omelo_private.omelo_author_card(p_person uuid, p_company uuid)
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select case
    when p_company is not null then
      (select jsonb_build_object('type', 'organization', 'id', c.id, 'name', c.display_name,
                                 'avatar_url', c.logo_url, 'slug', c.slug, 'verified', c.is_verified,
                                 'organization_type', c.organization_type)
         from companies c where c.id = p_company and c.deleted_at is null)
    else
      (select jsonb_build_object('type', 'person', 'id', p.id, 'name', p.display_name,
                                 'avatar_url', p.avatar_url, 'headline', p.headline, 'slug', p.profile_slug)
         from persons p where p.id = p_person and p.deleted_at is null)
  end;
$$;

create or replace function omelo_private.omelo_post_card(p_post posts, p_viewer uuid)
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select jsonb_build_object(
    'id', p_post.id,
    'kind', p_post.kind,
    'body', p_post.body,
    'visibility', p_post.visibility,
    'created_at', p_post.created_at,
    'edited_at', p_post.edited_at,
    'author', omelo_private.omelo_author_card(p_post.author_person_id, p_post.author_company_id),
    'media', coalesce((select jsonb_agg(jsonb_build_object('kind', m.kind, 'url', m.storage_path,
                                                           'alt_text', m.alt_text, 'width', m.width,
                                                           'height', m.height, 'duration_seconds', m.duration_seconds)
                               order by m.position)
                         from post_media m where m.post_id = p_post.id), '[]'::jsonb),
    'job', case when p_post.job_id is not null then
             (select jsonb_build_object('id', j.id, 'title', j.title, 'company', c.display_name,
                                        'location_text', j.location_text, 'country', j.country_code,
                                        'workplace_type', j.workplace_type, 'work_type', j.work_type,
                                        'status', j.status,
                                        'pay', case when j.pay_disclosed is distinct from false
                                                     and coalesce(j.pay_max, j.pay_min) is not null then
                                                 jsonb_build_object('min', j.pay_min, 'max', j.pay_max,
                                                                    'period', j.pay_period, 'currency', j.pay_currency) end)
                from jobs j join companies c on c.id = j.company_id where j.id = p_post.job_id) end,
    'shared_post', case when p_post.shared_post_id is not null then
             (select jsonb_build_object('id', s.id, 'body', s.body, 'created_at', s.created_at,
                                        'author', omelo_private.omelo_author_card(s.author_person_id, s.author_company_id),
                                        'media', coalesce((select jsonb_agg(jsonb_build_object('kind', m.kind, 'url', m.storage_path)
                                                                    order by m.position)
                                                             from post_media m where m.post_id = s.id), '[]'::jsonb))
                from posts s where s.id = p_post.shared_post_id and s.deleted_at is null) end,
    'engagement', jsonb_build_object('reactions', p_post.reaction_count, 'comments', p_post.comment_count,
                                     'shares', p_post.share_count, 'saves', p_post.save_count),
    'my', jsonb_build_object(
            'reaction', (select r.kind from post_reactions r where r.post_id = p_post.id and r.person_id = p_viewer),
            'saved', exists (select 1 from post_saves s where s.post_id = p_post.id and s.person_id = p_viewer),
            'mine', p_post.author_person_id = p_viewer
                    or (p_post.author_company_id is not null
                        and omelo_private.omelo_has_company_role(p_post.author_company_id,
                              array['owner','admin','recruiter','hr']::company_role[]))));
$$;

-- 1. Writing ---------------------------------------------------------------------------------------
create or replace function public.omelo_create_post(p jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_uid uuid := auth.uid(); v_company uuid := nullif(p->>'company_id', '')::uuid; po posts; m jsonb; v_pos int := 0;
begin
  if v_uid is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if v_company is not null
     and not omelo_private.omelo_has_company_role(v_company, array['owner','admin','recruiter','hr']::company_role[]) then
    raise exception 'You cannot post as that organization' using errcode = '42501';
  end if;
  if coalesce(length(trim(coalesce(p->>'body', ''))), 0) = 0
     and nullif(p->>'job_id', '') is null and nullif(p->>'shared_post_id', '') is null
     and coalesce(jsonb_array_length(p->'media'), 0) = 0 then
    raise exception 'Write something, add media, or share a job or post' using errcode = '22023';
  end if;
  begin
    insert into posts (author_person_id, author_company_id, work_identity_id, kind, body, job_id, shared_post_id,
                       visibility, language_code)
    values (case when v_company is null then v_uid end, v_company,
            nullif(p->>'work_identity_id', '')::uuid,
            coalesce(nullif(p->>'kind', ''), case when nullif(p->>'job_id', '') is not null then 'job_share'
                                                  when nullif(p->>'shared_post_id', '') is not null then 'share'
                                                  when v_company is not null then 'organization_update'
                                                  else 'update' end),
            nullif(trim(p->>'body'), ''), nullif(p->>'job_id', '')::uuid, nullif(p->>'shared_post_id', '')::uuid,
            coalesce(nullif(p->>'visibility', ''), 'public'), nullif(p->>'language_code', ''))
    returning * into po;
    for m in select x from jsonb_array_elements(coalesce(p->'media', '[]'::jsonb)) x loop
      insert into post_media (post_id, position, kind, storage_path, mime_type, width, height, duration_seconds, alt_text)
      values (po.id, v_pos, coalesce(nullif(m->>'kind', ''), 'image'), m->>'storage_path', m->>'mime_type',
              nullif(m->>'width', '')::int, nullif(m->>'height', '')::int,
              nullif(m->>'duration_seconds', '')::int, nullif(m->>'alt_text', ''));
      v_pos := v_pos + 1;
    end loop;
  exception
    when check_violation or invalid_text_representation or not_null_violation then
      raise exception 'Check the post: %', sqlerrm using errcode = '22023';
  end;

  -- a share tells the original author
  if po.shared_post_id is not null then
    perform omelo_private.omelo_notify(s.author_person_id, 'post_share'::notification_type, 'Your post was shared',
              coalesce(left(po.body, 120), 'Someone shared your post'), 'post', po.id, '/feed/' || po.id)
       from posts s where s.id = po.shared_post_id and s.author_person_id is not null and s.author_person_id <> v_uid;
  end if;
  perform omelo_private.omelo_emit('PostPublished', 'post', po.id, v_company, v_uid,
                                   jsonb_build_object('kind', po.kind, 'visibility', po.visibility));
  return omelo_private.omelo_post_card(po, v_uid);
end;
$$;

create or replace function public.omelo_update_post(p_post uuid, p jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare po posts;
begin
  select * into po from posts where id = p_post and deleted_at is null;
  if po.id is null then raise exception 'Post not found' using errcode = '22023'; end if;
  if not (po.author_person_id = auth.uid()
          or (po.author_company_id is not null
              and omelo_private.omelo_has_company_role(po.author_company_id,
                    array['owner','admin','recruiter','hr']::company_role[]))) then
    raise exception 'Only the author can edit this post' using errcode = '42501';
  end if;
  update posts
     set body = case when p ? 'body' then nullif(trim(p->>'body'), '') else body end,
         visibility = coalesce(nullif(p->>'visibility', ''), visibility)
   where id = p_post returning * into po;
  perform omelo_private.omelo_emit('PostEdited', 'post', po.id, po.author_company_id, auth.uid(), '{}'::jsonb);
  return omelo_private.omelo_post_card(po, auth.uid());
end;
$$;

create or replace function public.omelo_delete_post(p_post uuid)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare po posts;
begin
  select * into po from posts where id = p_post and deleted_at is null;
  if po.id is null then raise exception 'Post not found' using errcode = '22023'; end if;
  if not (po.author_person_id = auth.uid()
          or (po.author_company_id is not null
              and omelo_private.omelo_has_company_role(po.author_company_id, array['owner','admin']::company_role[]))
          or omelo_private.omelo_is_platform_admin(array['superadmin','trust_safety'])) then
    raise exception 'Only the author can delete this post' using errcode = '42501';
  end if;
  update posts set deleted_at = now(), status = 'removed' where id = p_post;
  perform omelo_private.omelo_emit('PostDeleted', 'post', p_post, po.author_company_id, auth.uid(), '{}'::jsonb);
  return jsonb_build_object('id', p_post, 'deleted', true);
end;
$$;

-- 2. Engagement -------------------------------------------------------------------------------------
create or replace function public.omelo_react_to_post(p_post uuid, p_kind text default 'like')
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_uid uuid := auth.uid(); po posts;
begin
  if v_uid is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if not omelo_private.omelo_can_see_post(p_post) then raise exception 'Post not found' using errcode = '22023'; end if;
  select * into po from posts where id = p_post;
  if p_kind is null then
    delete from post_reactions where post_id = p_post and person_id = v_uid;
  else
    insert into post_reactions (post_id, person_id, kind) values (p_post, v_uid, p_kind)
    on conflict (post_id, person_id) do update set kind = excluded.kind;
    if po.author_person_id is not null and po.author_person_id <> v_uid then
      perform omelo_private.omelo_notify(po.author_person_id, 'post_reaction'::notification_type,
                'Someone reacted to your post', coalesce(left(po.body, 120), 'Your post'),
                'post', p_post, '/feed/' || p_post);
    end if;
  end if;
  select * into po from posts where id = p_post;
  return jsonb_build_object('post_id', p_post, 'reactions', po.reaction_count, 'my_reaction', p_kind);
exception when check_violation then
  raise exception 'Unknown reaction' using errcode = '22023';
end;
$$;

create or replace function public.omelo_comment_on_post(p_post uuid, p_body text, p_parent uuid default null)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_uid uuid := auth.uid(); c post_comments; po posts; v_parent_author uuid;
begin
  if v_uid is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if not omelo_private.omelo_can_see_post(p_post) then raise exception 'Post not found' using errcode = '22023'; end if;
  insert into post_comments (post_id, person_id, parent_comment_id, body)
  values (p_post, v_uid, p_parent, trim(p_body))
  returning * into c;
  select * into po from posts where id = p_post;
  if po.author_person_id is not null and po.author_person_id <> v_uid then
    perform omelo_private.omelo_notify(po.author_person_id, 'post_comment'::notification_type,
              'New comment on your post', left(trim(p_body), 140), 'post', p_post, '/feed/' || p_post);
  end if;
  if p_parent is not null then
    select person_id into v_parent_author from post_comments where id = p_parent;
    if v_parent_author is not null and v_parent_author not in (v_uid, coalesce(po.author_person_id, v_uid)) then
      perform omelo_private.omelo_notify(v_parent_author, 'post_comment'::notification_type,
                'Someone replied to you', left(trim(p_body), 140), 'post', p_post, '/feed/' || p_post);
    end if;
  end if;
  return jsonb_build_object('id', c.id, 'post_id', p_post, 'body', c.body, 'created_at', c.created_at,
                            'author', omelo_private.omelo_author_card(v_uid, null));
exception when check_violation then
  raise exception 'A comment is between 1 and 2000 characters' using errcode = '22023';
end;
$$;

create or replace function public.omelo_delete_comment(p_comment uuid)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare c post_comments; po posts;
begin
  select * into c from post_comments where id = p_comment and deleted_at is null;
  if c.id is null then raise exception 'Comment not found' using errcode = '22023'; end if;
  select * into po from posts where id = c.post_id;
  -- the comment's author, the post's author, or trust & safety
  if not (c.person_id = auth.uid() or po.author_person_id = auth.uid()
          or (po.author_company_id is not null
              and omelo_private.omelo_has_company_role(po.author_company_id, array['owner','admin']::company_role[]))
          or omelo_private.omelo_is_platform_admin(array['superadmin','trust_safety'])) then
    raise exception 'You cannot delete that comment' using errcode = '42501';
  end if;
  update post_comments set deleted_at = now() where id = p_comment;
  return jsonb_build_object('id', p_comment, 'deleted', true);
end;
$$;

create or replace function public.omelo_share_post(p_post uuid, p_body text default null, p_visibility text default 'public')
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if not omelo_private.omelo_can_see_post(p_post) then raise exception 'Post not found' using errcode = '22023'; end if;
  return public.omelo_create_post(jsonb_build_object('shared_post_id', p_post, 'body', p_body,
                                                     'visibility', p_visibility, 'kind', 'share'));
end;
$$;

create or replace function public.omelo_save_post(p_post uuid, p_save boolean default true)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if p_save then
    if not omelo_private.omelo_can_see_post(p_post) then raise exception 'Post not found' using errcode = '22023'; end if;
    insert into post_saves (person_id, post_id) values (auth.uid(), p_post) on conflict do nothing;
  else
    delete from post_saves where person_id = auth.uid() and post_id = p_post;
  end if;
  return jsonb_build_object('post_id', p_post, 'saved', p_save);
end;
$$;

-- 3. Following and connections --------------------------------------------------------------------------
create or replace function public.omelo_follow(p_target_type text, p_target_id uuid, p_follow boolean default true)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if p_target_type not in ('person','company') then raise exception 'Follow a person or an organization' using errcode = '22023'; end if;
  if p_target_type = 'person' and p_target_id = v_uid then raise exception 'You already follow yourself' using errcode = '22023'; end if;
  if p_target_type = 'person' and not exists (select 1 from persons where id = p_target_id and deleted_at is null) then
    raise exception 'Person not found' using errcode = '22023';
  end if;
  if p_target_type = 'company' and not exists (select 1 from companies where id = p_target_id and deleted_at is null) then
    raise exception 'Organization not found' using errcode = '22023';
  end if;
  if p_target_type = 'person' and omelo_private.omelo_blocked_between(v_uid, p_target_id) then
    raise exception 'You cannot follow this person' using errcode = '42501';
  end if;
  if p_follow then
    insert into follows (person_id, target_type, target_id) values (v_uid, p_target_type, p_target_id)
    on conflict do nothing;
    if p_target_type = 'person' then
      perform omelo_private.omelo_notify(p_target_id, 'new_follower'::notification_type, 'New follower',
                (select display_name from persons where id = v_uid) || ' follows your updates',
                'person', v_uid, '/network/followers');
    end if;
  else
    delete from follows where person_id = v_uid and target_type = p_target_type and target_id = p_target_id;
  end if;
  return jsonb_build_object('target_type', p_target_type, 'target_id', p_target_id, 'following', p_follow,
                            'followers', (select count(*) from follows where target_type = p_target_type and target_id = p_target_id));
end;
$$;

create or replace function public.omelo_request_connection(p_person uuid, p_message text default null)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare v_uid uuid := auth.uid(); c connections;
begin
  if v_uid is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if p_person = v_uid then raise exception 'You cannot connect with yourself' using errcode = '22023'; end if;
  if not exists (select 1 from persons where id = p_person and deleted_at is null) then
    raise exception 'Person not found' using errcode = '22023';
  end if;
  if omelo_private.omelo_blocked_between(v_uid, p_person) then
    raise exception 'You cannot connect with this person' using errcode = '42501';
  end if;
  select * into c from connections
   where least(requester_id, addressee_id) = least(v_uid, p_person)
     and greatest(requester_id, addressee_id) = greatest(v_uid, p_person);
  if c.id is not null then
    if c.status = 'accepted' then raise exception 'You are already connected' using errcode = '22023'; end if;
    if c.status = 'pending' then
      if c.addressee_id = v_uid then
        return public.omelo_respond_connection(c.id, true);   -- they asked first: accept
      end if;
      raise exception 'You already asked; it is waiting for an answer' using errcode = '22023';
    end if;
    -- declined, withdrawn or removed: ask again, the other way round if needed
    update connections set requester_id = v_uid, addressee_id = p_person, status = 'pending',
           message = nullif(trim(p_message), ''), requested_at = now(), responded_at = null
     where id = c.id returning * into c;
  else
    insert into connections (requester_id, addressee_id, message)
    values (v_uid, p_person, nullif(trim(p_message), '')) returning * into c;
  end if;
  perform omelo_private.omelo_notify(p_person, 'connection_request'::notification_type, 'Connection request',
            (select display_name from persons where id = v_uid) || ' would like to connect',
            'connection', c.id, '/network/invitations');
  perform omelo_private.omelo_emit('ConnectionRequested', 'connection', c.id, null, v_uid, '{}'::jsonb);
  return to_jsonb(c);
end;
$$;

create or replace function public.omelo_respond_connection(p_connection uuid, p_accept boolean)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare c connections;
begin
  select * into c from connections where id = p_connection for update;
  if c.id is null then raise exception 'Request not found' using errcode = '22023'; end if;
  if c.addressee_id <> auth.uid() then
    raise exception 'Only the person who was asked can answer' using errcode = '42501';
  end if;
  if c.status <> 'pending' then raise exception 'This request is already %', c.status using errcode = '22023'; end if;
  update connections set status = case when p_accept then 'accepted' else 'declined' end, responded_at = now()
   where id = c.id returning * into c;
  if p_accept then
    perform omelo_private.omelo_notify(c.requester_id, 'connection_update'::notification_type, 'Connection accepted',
              (select display_name from persons where id = c.addressee_id) || ' accepted your request',
              'connection', c.id, '/network');
  end if;
  perform omelo_private.omelo_emit(case when p_accept then 'ConnectionAccepted' else 'ConnectionDeclined' end,
                                   'connection', c.id, null, auth.uid(), '{}'::jsonb);
  return to_jsonb(c);
end;
$$;

create or replace function public.omelo_remove_connection(p_person uuid)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare c connections;
begin
  select * into c from connections
   where least(requester_id, addressee_id) = least(auth.uid(), p_person)
     and greatest(requester_id, addressee_id) = greatest(auth.uid(), p_person);
  if c.id is null then raise exception 'You are not connected' using errcode = '22023'; end if;
  if auth.uid() not in (c.requester_id, c.addressee_id) then
    raise exception 'Not your connection' using errcode = '42501';
  end if;
  update connections set status = case when c.status = 'pending' and c.requester_id = auth.uid() then 'withdrawn'
                                       else 'removed' end,
         responded_at = now()
   where id = c.id returning * into c;
  return to_jsonb(c);
end;
$$;

create or replace function public.omelo_my_network(p_view text default 'connections')
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if p_view not in ('connections','invitations','sent','followers','following') then
    raise exception 'Unknown view %', p_view using errcode = '22023';
  end if;
  return case p_view
    when 'connections' then
      coalesce((select jsonb_agg(omelo_private.omelo_author_card(
                         case when c.requester_id = v_uid then c.addressee_id else c.requester_id end, null)
                         || jsonb_build_object('connected_at', c.responded_at) order by c.responded_at desc)
                  from connections c
                 where c.status = 'accepted' and v_uid in (c.requester_id, c.addressee_id)), '[]'::jsonb)
    when 'invitations' then
      coalesce((select jsonb_agg(jsonb_build_object('connection_id', c.id, 'message', c.message,
                                                    'requested_at', c.requested_at,
                                                    'person', omelo_private.omelo_author_card(c.requester_id, null))
                                 order by c.requested_at desc)
                  from connections c where c.status = 'pending' and c.addressee_id = v_uid), '[]'::jsonb)
    when 'sent' then
      coalesce((select jsonb_agg(jsonb_build_object('connection_id', c.id, 'requested_at', c.requested_at,
                                                    'person', omelo_private.omelo_author_card(c.addressee_id, null))
                                 order by c.requested_at desc)
                  from connections c where c.status = 'pending' and c.requester_id = v_uid), '[]'::jsonb)
    when 'followers' then
      coalesce((select jsonb_agg(omelo_private.omelo_author_card(f.person_id, null) order by f.created_at desc)
                  from follows f where f.target_type = 'person' and f.target_id = v_uid), '[]'::jsonb)
    else
      coalesce((select jsonb_agg(omelo_private.omelo_author_card(
                         case when f.target_type = 'person' then f.target_id end,
                         case when f.target_type = 'company' then f.target_id end) order by f.created_at desc)
                  from follows f where f.person_id = v_uid), '[]'::jsonb)
  end;
end;
$$;

-- People worth knowing: colleagues at organizations you worked for, and people in your profession.
create or replace function public.omelo_connection_suggestions(p_limit integer default 10)
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  with me as (select id, (select profession_id from work_identities w
                           where w.person_id = persons.id and w.status = 'active'
                           order by is_primary desc limit 1) as profession_id
                from persons where id = auth.uid()),
  mine_companies as (select distinct company_id from employments where person_id = auth.uid() and company_id is not null),
  candidates as (
    select p.id,
           case when exists (select 1 from employments e where e.person_id = p.id
                              and e.company_id in (select company_id from mine_companies)) then 'Worked at the same organization'
                else 'Works in the same profession' end as reason
      from persons p, me
     where p.id <> me.id and p.deleted_at is null
       and p.discoverability in ('public','discoverable','recruiters')
       and not exists (select 1 from connections c
                        where least(c.requester_id, c.addressee_id) = least(me.id, p.id)
                          and greatest(c.requester_id, c.addressee_id) = greatest(me.id, p.id)
                          and c.status in ('pending','accepted'))
       and not omelo_private.omelo_blocked_between(me.id, p.id)
       and (exists (select 1 from employments e where e.person_id = p.id
                     and e.company_id in (select company_id from mine_companies))
            or exists (select 1 from work_identities w where w.person_id = p.id and w.status = 'active'
                        and w.profession_id = me.profession_id))
     limit greatest(1, least(coalesce(p_limit, 10), 25)))
  select coalesce(jsonb_agg(omelo_private.omelo_author_card(c.id, null) || jsonb_build_object('reason', c.reason)), '[]'::jsonb)
    from candidates c
   where auth.uid() is not null;
$$;

-- 4. The feed ------------------------------------------------------------------------------------------
create or replace function public.omelo_feed(p_tab text default 'for_you', p_limit integer default 20,
                                             p_before timestamptz default null, p_offset integer default 0)
returns jsonb
language plpgsql stable security definer
set search_path = public, omelo_private
as $$
declare
  v_uid uuid := auth.uid(); pr feed_preferences; v_limit int := greatest(1, least(coalesce(p_limit, 20), 50));
  v_offset int := greatest(0, least(coalesce(p_offset, 0), 500)); v_profession uuid; v jsonb;
begin
  if v_uid is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if p_tab not in ('for_you','following','organizations','jobs','saved') then
    raise exception 'Unknown feed %', p_tab using errcode = '22023';
  end if;
  select * into pr from feed_preferences where person_id = v_uid;
  select profession_id into v_profession from work_identities
   where person_id = v_uid and status = 'active' order by is_primary desc, created_at limit 1;

  with visible as (
    select p.*,
           case when p.author_person_id is not null and omelo_private.omelo_are_connected(p.author_person_id, v_uid) then 3
                when p.author_person_id is not null and exists (select 1 from follows f where f.person_id = v_uid
                       and f.target_type = 'person' and f.target_id = p.author_person_id) then 2
                when p.author_company_id is not null and exists (select 1 from follows f where f.person_id = v_uid
                       and f.target_type = 'company' and f.target_id = p.author_company_id) then 2
                when p.job_id is not null and v_profession is not null
                     and exists (select 1 from jobs j where j.id = p.job_id and j.profession_id = v_profession) then 1
                else 0 end as affinity,
           case when p.author_person_id is not null and omelo_private.omelo_are_connected(p.author_person_id, v_uid) then 'From a connection'
                when p.author_person_id is not null and exists (select 1 from follows f where f.person_id = v_uid
                       and f.target_type = 'person' and f.target_id = p.author_person_id) then 'From someone you follow'
                when p.author_company_id is not null and exists (select 1 from follows f where f.person_id = v_uid
                       and f.target_type = 'company' and f.target_id = p.author_company_id) then 'From an organization you follow'
                when p.job_id is not null then 'A job in your profession'
                else 'Popular on Omelo' end as why
      from posts p
     where p.deleted_at is null and p.status = 'published'
       and omelo_private.omelo_can_see_post(p.id)
       and (p_before is null or p.created_at < p_before)
       and p.author_person_id is distinct from v_uid
       -- muted and blocked sources never appear
       and not exists (select 1 from feed_mutes mu where mu.person_id = v_uid
                        and ((mu.target_type = 'person' and mu.target_id = p.author_person_id)
                          or (mu.target_type = 'company' and mu.target_id = p.author_company_id)
                          or (mu.target_type = 'post' and mu.target_id = p.id)))
       -- what the person chose to see
       and (coalesce(pr.show_jobs, true) or p.job_id is null)
       and (coalesce(pr.show_organizations, true) or p.author_company_id is null)
  ),
  picked as (
    select v.*,
           round((v.affinity
                  + 0.5 * ln(1 + v.reaction_count + 2 * v.comment_count + 3 * v.share_count)
                  - 0.15 * extract(epoch from now() - v.created_at) / 86400)::numeric, 3) as score
      from visible v
     where case p_tab
             when 'following' then v.affinity >= 2
             when 'organizations' then v.author_company_id is not null
             when 'jobs' then v.job_id is not null
             when 'saved' then exists (select 1 from post_saves s where s.post_id = v.id and s.person_id = v_uid)
             else true end)
  select coalesce(jsonb_agg((select omelo_private.omelo_post_card(pp, v_uid) from posts pp where pp.id = x.id)
                            || jsonb_build_object('why', x.why, 'score', x.score)
                            order by case when p_tab in ('for_you') then x.score end desc nulls last,
                                     x.created_at desc), '[]'::jsonb)
    into v
    from (select * from picked
           order by case when p_tab = 'for_you' then score end desc nulls last, created_at desc
           limit v_limit offset case when p_tab = 'for_you' then v_offset else 0 end) x;

  return jsonb_build_object(
    'tab', p_tab, 'posts', v,
    'next_before', case when p_tab <> 'for_you' then (select min((e->>'created_at')::timestamptz) from jsonb_array_elements(v) e) end,
    'next_offset', case when p_tab = 'for_you' then v_offset + jsonb_array_length(v) end,
    'preferences', coalesce(to_jsonb(pr) - 'person_id',
                            jsonb_build_object('show_jobs', true, 'show_organizations', true,
                                               'show_career_content', true, 'show_network_activity', true)),
    'ranking', 'connection 3 · following 2 · your profession 1, plus engagement, minus 0.15 a day');
end;
$$;

create or replace function public.omelo_organization_feed(p_company uuid, p_limit integer default 20,
                                                          p_before timestamptz default null)
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select jsonb_build_object(
    'organization', omelo_private.omelo_author_card(null, p_company),
    'followers', (select count(*) from follows f where f.target_type = 'company' and f.target_id = p_company),
    'following', exists (select 1 from follows f where f.person_id = auth.uid()
                          and f.target_type = 'company' and f.target_id = p_company),
    'posts', coalesce((select jsonb_agg((select omelo_private.omelo_post_card(pp, auth.uid()) from posts pp where pp.id = p.id)
                                        order by p.created_at desc)
                         from (select * from posts
                                where author_company_id = p_company and deleted_at is null and status = 'published'
                                  and (visibility = 'public' or omelo_private.omelo_can_see_post(id))
                                  and (p_before is null or created_at < p_before)
                                order by created_at desc
                                limit greatest(1, least(coalesce(p_limit, 20), 50))) p), '[]'::jsonb))
  where exists (select 1 from companies c where c.id = p_company and c.deleted_at is null);
$$;

create or replace function public.omelo_person_posts(p_person uuid, p_limit integer default 20,
                                                     p_before timestamptz default null)
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select coalesce(jsonb_agg((select omelo_private.omelo_post_card(pp, auth.uid()) from posts pp where pp.id = p.id)
                            order by p.created_at desc), '[]'::jsonb)
    from (select * from posts
           where author_person_id = p_person and deleted_at is null and status = 'published'
             and omelo_private.omelo_can_see_post(id)
             and (p_before is null or created_at < p_before)
           order by created_at desc
           limit greatest(1, least(coalesce(p_limit, 20), 50))) p;
$$;

create or replace function public.omelo_post_detail(p_post uuid)
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select omelo_private.omelo_post_card(p, auth.uid())
    from posts p where p.id = p_post and omelo_private.omelo_can_see_post(p.id);
$$;

create or replace function public.omelo_post_comments(p_post uuid, p_limit integer default 30, p_after timestamptz default null)
returns jsonb
language sql stable security definer
set search_path = public, omelo_private
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'body', c.body, 'created_at', c.created_at, 'edited_at', c.edited_at,
           'author', omelo_private.omelo_author_card(c.person_id, null),
           'reactions', c.reaction_count, 'replies', c.reply_count,
           'mine', c.person_id = auth.uid(),
           'my_reaction', (select r.kind from comment_reactions r where r.comment_id = c.id and r.person_id = auth.uid()),
           'thread', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'body', r.body, 'created_at', r.created_at,
                                                                   'author', omelo_private.omelo_author_card(r.person_id, null),
                                                                   'reactions', r.reaction_count, 'mine', r.person_id = auth.uid())
                                                order by r.created_at)
                                 from post_comments r where r.parent_comment_id = c.id and r.deleted_at is null), '[]'::jsonb))
           order by c.created_at), '[]'::jsonb)
    from (select * from post_comments
           where post_id = p_post and parent_comment_id is null and deleted_at is null
             and (p_after is null or created_at > p_after)
           order by created_at
           limit greatest(1, least(coalesce(p_limit, 30), 100))) c
   where omelo_private.omelo_can_see_post(p_post);
$$;

-- 5. Preferences and muting --------------------------------------------------------------------------------
create or replace function public.omelo_save_feed_preferences(p jsonb)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
declare f feed_preferences;
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  insert into feed_preferences as t (person_id, show_jobs, show_organizations, show_career_content,
                                     show_network_activity, preferred_languages)
  values (auth.uid(), coalesce((p->>'show_jobs')::boolean, true), coalesce((p->>'show_organizations')::boolean, true),
          coalesce((p->>'show_career_content')::boolean, true), coalesce((p->>'show_network_activity')::boolean, true),
          coalesce(array(select x from jsonb_array_elements_text(p->'preferred_languages') x), '{}'))
  on conflict (person_id) do update set
    show_jobs = excluded.show_jobs, show_organizations = excluded.show_organizations,
    show_career_content = excluded.show_career_content, show_network_activity = excluded.show_network_activity,
    preferred_languages = excluded.preferred_languages, updated_at = now()
  returning * into f;
  return to_jsonb(f) - 'person_id';
end;
$$;

create or replace function public.omelo_mute_from_feed(p_target_type text, p_target_id uuid, p_mute boolean default true)
returns jsonb
language plpgsql security definer
set search_path = public, omelo_private
as $$
begin
  if auth.uid() is null then raise exception 'Sign in first' using errcode = '42501'; end if;
  if p_target_type not in ('person','company','post') then
    raise exception 'Mute a person, an organization or a post' using errcode = '22023';
  end if;
  if p_mute then
    insert into feed_mutes (person_id, target_type, target_id) values (auth.uid(), p_target_type, p_target_id)
    on conflict do nothing;
  else
    delete from feed_mutes where person_id = auth.uid() and target_type = p_target_type and target_id = p_target_id;
  end if;
  return jsonb_build_object('target_type', p_target_type, 'target_id', p_target_id, 'muted', p_mute);
end;
$$;

-- 6. Grants -------------------------------------------------------------------------------------------------
revoke all on function omelo_private.omelo_author_card(uuid, uuid) from public, anon, authenticated;
revoke all on function omelo_private.omelo_post_card(posts, uuid) from public, anon, authenticated;

revoke all on function public.omelo_create_post(jsonb) from public, anon;
revoke all on function public.omelo_update_post(uuid, jsonb) from public, anon;
revoke all on function public.omelo_delete_post(uuid) from public, anon;
revoke all on function public.omelo_react_to_post(uuid, text) from public, anon;
revoke all on function public.omelo_comment_on_post(uuid, text, uuid) from public, anon;
revoke all on function public.omelo_delete_comment(uuid) from public, anon;
revoke all on function public.omelo_share_post(uuid, text, text) from public, anon;
revoke all on function public.omelo_save_post(uuid, boolean) from public, anon;
revoke all on function public.omelo_follow(text, uuid, boolean) from public, anon;
revoke all on function public.omelo_request_connection(uuid, text) from public, anon;
revoke all on function public.omelo_respond_connection(uuid, boolean) from public, anon;
revoke all on function public.omelo_remove_connection(uuid) from public, anon;
revoke all on function public.omelo_my_network(text) from public, anon;
revoke all on function public.omelo_connection_suggestions(integer) from public, anon;
revoke all on function public.omelo_feed(text, integer, timestamptz, integer) from public, anon;
revoke all on function public.omelo_organization_feed(uuid, integer, timestamptz) from public;
revoke all on function public.omelo_person_posts(uuid, integer, timestamptz) from public;
revoke all on function public.omelo_post_detail(uuid) from public;
revoke all on function public.omelo_post_comments(uuid, integer, timestamptz) from public;
revoke all on function public.omelo_save_feed_preferences(jsonb) from public, anon;
revoke all on function public.omelo_mute_from_feed(text, uuid, boolean) from public, anon;

grant execute on function public.omelo_create_post(jsonb) to authenticated;
grant execute on function public.omelo_update_post(uuid, jsonb) to authenticated;
grant execute on function public.omelo_delete_post(uuid) to authenticated;
grant execute on function public.omelo_react_to_post(uuid, text) to authenticated;
grant execute on function public.omelo_comment_on_post(uuid, text, uuid) to authenticated;
grant execute on function public.omelo_delete_comment(uuid) to authenticated;
grant execute on function public.omelo_share_post(uuid, text, text) to authenticated;
grant execute on function public.omelo_save_post(uuid, boolean) to authenticated;
grant execute on function public.omelo_follow(text, uuid, boolean) to authenticated;
grant execute on function public.omelo_request_connection(uuid, text) to authenticated;
grant execute on function public.omelo_respond_connection(uuid, boolean) to authenticated;
grant execute on function public.omelo_remove_connection(uuid) to authenticated;
grant execute on function public.omelo_my_network(text) to authenticated;
grant execute on function public.omelo_connection_suggestions(integer) to authenticated;
grant execute on function public.omelo_feed(text, integer, timestamptz, integer) to authenticated;
-- the public organization feed and a person's public posts are readable signed out
grant execute on function public.omelo_organization_feed(uuid, integer, timestamptz) to anon, authenticated;
grant execute on function public.omelo_person_posts(uuid, integer, timestamptz) to anon, authenticated;
grant execute on function public.omelo_post_detail(uuid) to anon, authenticated;
grant execute on function public.omelo_post_comments(uuid, integer, timestamptz) to anon, authenticated;
grant execute on function public.omelo_save_feed_preferences(jsonb) to authenticated;
grant execute on function public.omelo_mute_from_feed(text, uuid, boolean) to authenticated;
