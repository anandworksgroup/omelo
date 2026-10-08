-- OMELO 72 — Release 9: notification types for the professional network (enum values on their own,
-- because a new enum value cannot be used in the same transaction that adds it).
-- Rollback: enum values cannot be dropped in place; unused values are inert.

alter type notification_type add value if not exists 'post_reaction';
alter type notification_type add value if not exists 'post_comment';
alter type notification_type add value if not exists 'post_share';
alter type notification_type add value if not exists 'post_mention';
alter type notification_type add value if not exists 'connection_request';
alter type notification_type add value if not exists 'connection_update';
alter type notification_type add value if not exists 'new_follower';
