-- OMELO 50 — Release 5 prerequisites: notification types for the workforce
-- engine (added on their own; an enum value cannot be used in the
-- transaction that adds it).
--   shift_update  ShiftAssigned / Changed / Cancelled / StartingSoon / offers
--   work_update   assignments, attendance, timesheets, earnings, leave
-- Rollback: enum values cannot be dropped in place; unused values are inert.

alter type notification_type add value if not exists 'shift_update';
alter type notification_type add value if not exists 'work_update';
