-- OMELO 44 — Release 4 prerequisites: new enum values.
--
-- Postgres cannot use an enum value in the transaction that adds it, so the
-- values Release 4 needs are added on their own, before migration 45.
--
-- company_role: agencies reuse companies + company_members (an agency is a
-- company with company_kind = 'agency'); they need two roles employers do
-- not: sourcer (finds candidates, asks for consent, cannot submit) and
-- coordinator (schedules and tracks placements, limited candidate view).
--
-- notification_type: a worker is asked to be represented; recruiters and
-- clients are told what happened.
--
-- Rollback: enum values cannot be dropped in place; unused values are inert.

alter type company_role add value if not exists 'sourcer';
alter type company_role add value if not exists 'coordinator';
alter type notification_type add value if not exists 'representation_request';
alter type notification_type add value if not exists 'representation_update';
