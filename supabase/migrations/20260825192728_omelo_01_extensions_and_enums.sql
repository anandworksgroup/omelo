-- =====================================================================
-- OMELO 01 — Extensions and Enums
-- Universal employment platform. Every enum must work for a software
-- engineer, an electrician, a nurse, a driver, and a first-time jobseeker.
-- =====================================================================

create extension if not exists pgcrypto      with schema extensions;
create extension if not exists pg_trgm       with schema extensions;
create extension if not exists unaccent      with schema extensions;
create extension if not exists vector        with schema extensions;
create extension if not exists postgis       with schema extensions;
create extension if not exists moddatetime   with schema extensions;

-- ---------- provenance ----------
create type source_type as enum ('user','import','inference','admin','partner','employer');

create type taxonomy_status as enum ('active','pending_review','deprecated','merged');

-- ---------- work shape ----------
-- Deliberately wide: gig, seasonal, and apprenticeship are first-class,
-- not afterthoughts bolted onto a white-collar model.
create type work_type as enum (
  'full_time','part_time','contract','freelance','temporary',
  'internship','apprenticeship','seasonal','gig','volunteer','daily_wage'
);

create type workplace_type as enum (
  'onsite','hybrid','remote','field_based','client_site','multiple_sites'
);

create type shift_type as enum (
  'day','evening','night','early_morning','rotating','split','flexible',
  'weekend','on_call'
);

-- ---------- money ----------
-- Hourly and daily are as important as annual. Piece-rate matters for
-- agriculture, delivery, and manufacturing.
create type pay_period as enum ('hour','day','week','fortnight','month','year','per_task');
create type pay_basis  as enum ('gross','net');

-- ---------- availability ----------
create type availability_window as enum (
  'immediate','within_7_days','within_15_days','within_30_days',
  'within_60_days','within_90_days','flexible','not_available'
);

-- ---------- education ----------
-- 'none' and 'vocational' exist because a large share of the world's
-- workforce has neither a degree nor formal schooling. Omitting them
-- would force people to misrepresent themselves.
create type education_level as enum (
  'none','primary','secondary','high_school','vocational','certificate',
  'diploma','associate','bachelor','master','doctorate','professional','other'
);

-- ---------- skills ----------
create type skill_type as enum (
  'technical','tool','equipment','trade','physical','domain','method',
  'soft','language','safety','administrative'
);

create type proficiency_level as enum ('beginner','basic','intermediate','advanced','expert');

create type evidence_type as enum (
  'self_declared','experience','project','credential','license',
  'assessment','employer_verified','reference'
);

create type requirement_level as enum ('required','preferred','nice_to_have');

create type relation_kind as enum (
  'adjacent_to','prerequisite_of','substitutable_for','specialisation_of'
);

-- ---------- language ----------
-- Plain-language levels, not CEFR. "Conversational Hindi" is meaningful
-- to a warehouse supervisor; "B1" is not.
create type language_proficiency as enum (
  'basic','conversational','professional','fluent','native'
);

-- ---------- work authorisation ----------
create type work_auth_status as enum (
  'citizen','permanent_resident','work_permit','dependent_visa_work_rights',
  'student_visa_limited','requires_sponsorship','no_right_to_work'
);

-- ---------- verification ----------
create type verification_type as enum (
  'identity','phone','email','address','education','employment',
  'license','certificate','right_to_work','background_check','reference'
);

create type verification_status as enum (
  'unverified','pending','verified','failed','expired','revoked'
);

create type verification_method as enum (
  'otp','domain_email','employer_confirmation','document_review',
  'issuer_api','institution_partner','government_api','third_party_provider',
  'manual_admin'
);

-- ---------- documents ----------
create type document_type as enum (
  'resume','cover_letter','government_id','passport','work_permit',
  'driving_license','trade_license','professional_license',
  'education_certificate','professional_certificate','experience_letter',
  'payslip','portfolio','police_clearance','medical_certificate',
  'photo','reference_letter','other'
);

-- ---------- benefits ----------
-- Accommodation, transport, and meals are decisive for migrant and
-- shift work, and absent from every white-collar-shaped schema.
create type benefit_type as enum (
  'accommodation','transport','meals','health_insurance','life_insurance',
  'visa_sponsorship','flight_tickets','relocation_assistance','bonus',
  'overtime_pay','tips','commission','paid_leave','sick_leave',
  'parental_leave','training','equipment_provided','uniform_provided',
  'childcare','retirement','stock_options','gym','other'
);

-- ---------- visibility ----------
create type discoverability as enum ('private','discoverable','public');

-- ---------- company ----------
create type company_role as enum (
  'owner','admin','recruiter','hiring_manager','interviewer','hr','finance','viewer'
);

create type company_size_band as enum (
  '1-10','11-50','51-200','201-500','501-1000','1001-5000','5001-10000','10000+'
);

-- ---------- jobs ----------
create type job_status as enum (
  'draft','pending_review','published','paused','expired','closed','rejected'
);

-- ---------- applications ----------
create type application_state as enum (
  'applied','viewed','shortlisted','screening','assessment','interview',
  'offer','hired','rejected','withdrawn','expired','declined_by_candidate'
);

create type application_event_type as enum (
  'created','viewed','stage_changed','shortlisted','message_sent','note_added',
  'document_requested','document_shared','interview_scheduled','interview_completed',
  'assessment_sent','assessment_completed','offer_extended','offer_responded',
  'decision_made','withdrawn','expired'
);

create type actor_type as enum ('candidate','recruiter','system','admin');

-- ---------- interviews ----------
create type interview_type as enum (
  'phone','video','in_person','group','walk_in','trial_shift',
  'practical_test','assessment_centre','panel'
);

create type interview_status as enum (
  'scheduled','rescheduled','completed','cancelled','no_show_candidate','no_show_employer'
);

create type interview_recommendation as enum ('reject','hold','advance','strong_advance');

-- ---------- offers ----------
create type offer_status as enum (
  'draft','sent','viewed','negotiating','accepted','declined','withdrawn','expired'
);

-- ---------- employment ----------
create type employment_status as enum ('active','on_notice','ended','terminated');

-- ---------- messaging ----------
create type message_kind as enum ('text','action','attachment','system');

-- ---------- adaptive profile ----------
-- Drives the profession-specific profile schema (drivers get vehicle
-- types, nurses get specialisations, engineers get stacks).
create type attribute_data_type as enum (
  'text','long_text','number','boolean','single_select','multi_select',
  'date','years','file','location'
);

-- ---------- notifications ----------
create type notification_type as enum (
  'job_match','job_alert','saved_search','application_update','recruiter_message',
  'interview_scheduled','interview_reminder','offer_received','document_request',
  'verification_update','career_recommendation','company_update','job_closing_soon',
  'profile_reminder','system'
);

-- ---------- trust & safety ----------
create type report_reason as enum (
  'fraud','payment_request','discrimination','harassment','misleading_job',
  'fake_company','spam','inappropriate_content','data_misuse','other'
);

create type report_status as enum ('open','triaging','actioned','dismissed','escalated');

create type moderation_action as enum (
  'none','warning','content_removed','job_unpublished','account_suspended',
  'account_banned','verification_revoked'
);
