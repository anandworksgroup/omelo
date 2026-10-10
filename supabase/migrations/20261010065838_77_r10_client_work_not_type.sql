-- OMELO 77 — One organization model, part 2: the rules follow client work.
--
-- R4 and R5 wrote their strongest rules against `company_kind = 'agency'`:
-- an agency may only assign a worker it represents, only an agency bills a
-- client, an agency requirement must start from a job order. Those rules were
-- never really about agencies. They are about *working for someone else*:
-- the moment an organization puts a worker in front of a client, the worker's
-- consent and the client's confidentiality start to matter, whoever that
-- organization is and whatever it calls itself.
--
-- So each one moves onto the question it was always asking — does this
-- assignment / requirement / bill belong to a client? — and in moving, it
-- starts protecting workers from a private company that recruits for clients,
-- which it never did before. This is a tightening, not a loosening.
--
-- The entry points to client work and RPO now ask whether the organization has
-- turned the module on. A capability is not an authorization: turning client
-- recruitment on lets a workspace *start* creating client relationships; it
-- grants no access to any client, job order or candidate, all of which still
-- require the client to confirm and the worker to consent.
--
-- Each change below is applied by reading the live function, asserting the
-- exact line it is replacing, and writing it back. If a function has drifted
-- from what this migration expects, it fails loudly instead of rewriting
-- something it does not recognise.
--
-- Rollback: restore the previous bodies of the eight functions.

-- ---------------------------------------------------------------
-- A capability, with the business type as its default
-- ---------------------------------------------------------------
--
-- A row in company_capabilities is an explicit choice the organization has
-- made. No row means it has not chosen, and the type says what is sensible:
-- a staffing firm recruits for clients on day one, a private company does not
-- until it says so. This is the one job organization_type keeps — supplying a
-- default — and it is never the thing that refuses an action.

create or replace function omelo_private.omelo_has_capability(p_company uuid, p_capability text)
returns boolean
language sql
stable
security definer
set search_path = public, omelo_private
as $$
  select coalesce(
    (select is_enabled from company_capabilities
      where company_id = p_company and capability = p_capability),
    (select case p_capability
              when 'client_recruitment' then
                c.organization_type in ('recruitment_agency','staffing_agency','rpo_provider','workforce_provider')
              when 'workforce' then
                c.organization_type in ('staffing_agency','workforce_provider')
              when 'rpo' then
                c.organization_type = 'rpo_provider'
              when 'billing' then
                c.organization_type <> 'employer'
              else false
            end
       from companies c where c.id = p_company and c.deleted_at is null),
    false);
$$;

-- ---------------------------------------------------------------
-- R5-002: consent follows client work
-- ---------------------------------------------------------------

do $m$
declare src text; out text;
begin
  src := pg_get_functiondef('omelo_private.omelo_validate_assignment()'::regprocedure);

  assert position('    select company_kind into v_kind from companies where id = new.company_id;' in src) > 0,
    '77: omelo_validate_assignment no longer reads company_kind where expected';
  assert position('    if v_kind = ''agency'' then' in src) > 0,
    '77: omelo_validate_assignment agency branch not found';

  out := replace(src,
    '    select company_kind into v_kind from companies where id = new.company_id;',
    '    -- R10: the rule is about working for a client, not about being an agency.'
    || chr(10) ||
    '    v_kind := case when coalesce(new.client_id, new.job_order_id, r.client_id, r.job_order_id) is not null'
    || chr(10) ||
    '                   then ''client'' else ''own'' end;');

  out := replace(out,
    '    if v_kind = ''agency'' then',
    '    if v_kind = ''client'' then');

  assert out <> src, '77: omelo_validate_assignment unchanged';
  execute out;
end
$m$;

-- ---------------------------------------------------------------
-- A free-standing requirement is own work
-- ---------------------------------------------------------------
--
-- An agency was refused a requirement that did not start from a job order,
-- because an agency staffs clients rather than itself. An organization that
-- does both has internal requirements too, and one with neither a job nor a
-- job order is by definition not for a client, so there is nothing left to
-- refuse. The requirement still has to name a title, and a requirement that
-- *does* carry a job order still has to match it.

do $m$
declare src text; out text; needle text;
begin
  src := pg_get_functiondef('public.omelo_create_requirement(uuid, jsonb)'::regprocedure);
  needle :=
    '  elsif (select company_kind from companies where id = p_company) = ''agency'' then' || chr(10) ||
    '    raise exception ''An agency requirement starts from one of its job orders'' using errcode = ''22023'';' || chr(10) ||
    '  end if;';
  assert position(needle in src) > 0, '77: omelo_create_requirement agency branch not found';
  out := replace(src, needle, '  end if;');
  assert out <> src, '77: omelo_create_requirement unchanged';
  execute out;
end
$m$;

-- ---------------------------------------------------------------
-- Client billing belongs to an assignment that has a client
-- ---------------------------------------------------------------

do $m$
declare src text; out text; needle text;
begin
  src := pg_get_functiondef(
    'public.omelo_set_assignment_billing(uuid, numeric, text, text)'::regprocedure);
  needle :=
    '  if a.id is null or (select company_kind from companies where id = a.company_id) <> ''agency'' then' || chr(10) ||
    '    raise exception ''Billing applies to agency assignments'' using errcode = ''42501'';';
  assert position(needle in src) > 0, '77: omelo_set_assignment_billing agency test not found';
  out := replace(src, needle,
    '  if a.id is null or a.client_id is null then' || chr(10) ||
    '    raise exception ''Billing applies to an assignment worked for a client'' using errcode = ''42501'';');
  assert out <> src, '77: omelo_set_assignment_billing unchanged';
  execute out;
end
$m$;

-- ---------------------------------------------------------------
-- A client is any organization on Omelo, except your own
-- ---------------------------------------------------------------
--
-- The client had to be an employer, so a recruitment firm could not be the
-- client of an RPO provider and a staffing firm could not hand overflow work
-- to another. The self-link test stays exactly where it was.

do $m$
declare src text; out text;
begin
  src := pg_get_functiondef('public.omelo_request_client_link(uuid, uuid)'::regprocedure);

  assert position('  if cl.id is null or not omelo_private.omelo_agency_can(cl.agency_id, ''manage_clients'') then' in src) > 0,
    '77: omelo_request_client_link authority test not found';
  assert position('  if not exists (select 1 from companies where id = p_company and company_kind = ''employer'' and deleted_at is null)' in src) > 0,
    '77: omelo_request_client_link employer test not found';

  out := replace(src,
    '  if cl.id is null or not omelo_private.omelo_agency_can(cl.agency_id, ''manage_clients'') then',
    '  if cl.id is null or not omelo_private.omelo_agency_can(cl.agency_id, ''manage_clients'')' || chr(10) ||
    '     or not omelo_private.omelo_has_capability(cl.agency_id, ''client_recruitment'') then');

  out := replace(out,
    '  if not exists (select 1 from companies where id = p_company and company_kind = ''employer'' and deleted_at is null)',
    '  if not exists (select 1 from companies where id = p_company and deleted_at is null)');

  out := replace(out,
    '    raise exception ''Choose an employer company on Omelo'' using errcode = ''22023'';',
    '    raise exception ''Choose an organization on Omelo other than your own'' using errcode = ''22023'';');

  assert out <> src, '77: omelo_request_client_link unchanged';
  execute out;
end
$m$;

-- ---------------------------------------------------------------
-- Client recruitment and RPO are modules you turn on
-- ---------------------------------------------------------------

do $m$
declare src text; out text;
begin
  src := pg_get_functiondef('public.omelo_create_job_order(uuid, jsonb)'::regprocedure);
  assert position('  if cl.id is null or not omelo_private.omelo_agency_can(cl.agency_id, ''create_job_order'') then' in src) > 0,
    '77: omelo_create_job_order authority test not found';
  out := replace(src,
    '  if cl.id is null or not omelo_private.omelo_agency_can(cl.agency_id, ''create_job_order'') then',
    '  if cl.id is null or not omelo_private.omelo_agency_can(cl.agency_id, ''create_job_order'')' || chr(10) ||
    '     or not omelo_private.omelo_has_capability(cl.agency_id, ''client_recruitment'') then');
  assert out <> src, '77: omelo_create_job_order unchanged';
  execute out;
end
$m$;

do $m$
declare src text; out text; needle text;
begin
  src := pg_get_functiondef('public.omelo_create_rpo_engagement(jsonb)'::regprocedure);
  needle := '  if not exists (select 1 from companies c where c.id = v_provider and c.organization_type in (''rpo_provider'',''recruitment_agency'',''staffing_agency'')) then';
  assert position(needle in src) > 0, '77: omelo_create_rpo_engagement type test not found';
  out := replace(src, needle,
    '  if not exists (select 1 from companies c where c.id = v_provider and c.deleted_at is null)' || chr(10) ||
    '     or not omelo_private.omelo_has_capability(v_provider, ''rpo'') then');
  assert out <> src, '77: omelo_create_rpo_engagement unchanged';
  execute out;
end
$m$;

-- ---------------------------------------------------------------
-- Two read paths that were describing the organization, not the work
-- ---------------------------------------------------------------

do $m$
declare src text; out text;
begin
  src := pg_get_functiondef('public.omelo_workforce_dashboard(uuid)'::regprocedure);
  assert position('  select company_kind = ''agency'' into v_agency from companies where id = p_company;' in src) > 0,
    '77: omelo_workforce_dashboard kind test not found';
  out := replace(src,
    '  select company_kind = ''agency'' into v_agency from companies where id = p_company;',
    '  -- "Are we staffing someone else?" is answered by the work, not the type.' || chr(10) ||
    '  select exists (select 1 from assignments a' || chr(10) ||
    '                  where a.company_id = p_company and a.client_id is not null) into v_agency;');
  assert out <> src, '77: omelo_workforce_dashboard unchanged';
  execute out;
end
$m$;

do $m$
declare src text; out text;
begin
  src := pg_get_functiondef('public.omelo_my_assignments()'::regprocedure);
  assert position('      ''employer_is_agency'', (select company_kind = ''agency'' from companies where id = a.company_id),' in src) > 0,
    '77: omelo_my_assignments kind test not found';
  out := replace(src,
    '      ''employer_is_agency'', (select company_kind = ''agency'' from companies where id = a.company_id),',
    '      ''employer_is_agency'', (a.client_id is not null),');
  assert out <> src, '77: omelo_my_assignments unchanged';
  execute out;
end
$m$;