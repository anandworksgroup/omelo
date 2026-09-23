-- OMELO 69 — Release 8: notification types for approvals and RPO (enum values on their own,
-- because a new enum value cannot be used in the same transaction that adds it).
-- Rollback: enum values cannot be dropped in place; unused values are inert.

alter type notification_type add value if not exists 'approval_request';
alter type notification_type add value if not exists 'approval_update';
alter type notification_type add value if not exists 'rpo_update';
