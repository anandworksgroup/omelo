'use server';

import { revalidatePath } from 'next/cache';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import type { Json } from '@/lib/supabase/database.types';
import { reportError } from '@/lib/observability';
import { UUID_RE } from '@/lib/talent';
import {
  CONSENT_MESSAGE_MAX,
  OUTCOMES,
  RELATIONSHIP_STATUSES,
  SCOPES,
  SUBMIT_NOTE_MAX,
  parseAgencySearch,
  type AgencySearchResult,
  type SearchFilters,
} from '@/lib/agency';

/*
 * Agency (recruiter) actions. Every rule — roles, consent, scope, expiry,
 * assignment, verification, quotas — is enforced by the database; these
 * functions only shape input and pass the database's message straight
 * through (42501 = not allowed, 22023 = a rule was broken).
 */

export type Fail = { ok: false; error: string; code?: string };
export type Ok<T = object> = { ok: true } & T;

const SIGNED_OUT = 'You are signed out or not part of a company.';
const BASE = '/dashboard/agency';

async function agency() {
  const ctx = await getCompanyContext();
  if (!ctx) return null;
  return { ctx, supabase: await createClient() };
}

const fail = (e: { message: string; code?: string }): Fail => ({ ok: false, error: e.message, code: e.code });

function report(error: { message: string; code?: string }, action: string) {
  if (error.code !== '42501' && error.code !== '22023') reportError(error, { action });
}

const clean = (v: string | null | undefined, max: number) => {
  const t = (v ?? '').trim();
  return t ? t.slice(0, max) : null;
};

const list = (v: string[] | undefined, maxItems: number, maxLen: number) =>
  [...new Set((v ?? []).map((x) => x.trim()).filter((x) => x.length > 0 && x.length <= maxLen))].slice(0, maxItems);

/* ------------------------------------------------------------------ */
/* Clients                                                             */
/* ------------------------------------------------------------------ */

export type ClientInput = {
  name: string;
  relationshipStatus: string;
  ownerId: string | null;
  industry: string;
  website: string;
  locations: string[];
  departments: string[];
  notes: string;
};

function clientRow(input: ClientInput) {
  const name = input.name.trim().replace(/\s+/g, ' ');
  if (name.length < 2 || name.length > 120) return { error: 'Give the client a name (2–120 characters).' } as const;
  if (!(RELATIONSHIP_STATUSES as readonly string[]).includes(input.relationshipStatus))
    return { error: 'Choose a relationship status.' } as const;
  if (input.ownerId && !UUID_RE.test(input.ownerId)) return { error: 'Choose an owner from your team.' } as const;
  const website = clean(input.website, 300);
  if (website && !/^https?:\/\/\S+$/i.test(website)) return { error: 'Websites start with http:// or https://' } as const;
  const notes = clean(input.notes, 4000);
  return {
    row: {
      name,
      relationship_status: input.relationshipStatus,
      owner_id: input.ownerId || null,
      industry: clean(input.industry, 120),
      website,
      locations: list(input.locations, 50, 120),
      departments: list(input.departments, 50, 120),
      notes,
    },
  } as const;
}

export async function createAgencyClient(input: ClientInput): Promise<Ok<{ id: string }> | Fail> {
  const a = await agency();
  if (!a) return { ok: false, error: SIGNED_OUT };
  const r = clientRow(input);
  if ('error' in r) return { ok: false, error: r.error! };
  const { data, error } = await a.supabase
    .from('agency_clients')
    .insert({ ...r.row, agency_id: a.ctx.companyId })
    .select('id')
    .single();
  if (error) {
    report(error, 'createAgencyClient');
    if (error.code === '42501') return { ok: false, error: 'Only owners, admins and recruiters can add clients.', code: error.code };
    return fail(error);
  }
  revalidatePath(`${BASE}/clients`);
  return { ok: true, id: data.id };
}

export async function updateAgencyClient(clientId: string, input: ClientInput): Promise<Ok | Fail> {
  const a = await agency();
  if (!a) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(clientId)) return { ok: false, error: 'Client not found.' };
  const r = clientRow(input);
  if ('error' in r) return { ok: false, error: r.error! };
  const { data, error } = await a.supabase.from('agency_clients').update(r.row).eq('id', clientId).select('id');
  if (error) {
    report(error, 'updateAgencyClient');
    return fail(error);
  }
  if (!data?.length) return { ok: false, error: 'Only owners, admins and recruiters can edit clients.', code: '42501' };
  revalidatePath(`${BASE}/clients`, 'layout');
  return { ok: true };
}

export async function deleteAgencyClient(clientId: string): Promise<Ok | Fail> {
  const a = await agency();
  if (!a) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(clientId)) return { ok: false, error: 'Client not found.' };
  const { data, error } = await a.supabase.from('agency_clients').delete().eq('id', clientId).select('id');
  if (error) return fail(error);
  if (!data?.length) return { ok: false, error: 'Only owners and admins can delete clients.', code: '42501' };
  revalidatePath(`${BASE}/clients`, 'layout');
  return { ok: true };
}

export type ContactInput = {
  name: string;
  title: string;
  email: string;
  phone: string;
  isPrimary: boolean;
  notes: string;
};

export async function saveClientContact(
  clientId: string,
  contactId: string | null,
  input: ContactInput
): Promise<Ok | Fail> {
  const a = await agency();
  if (!a) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(clientId) || (contactId && !UUID_RE.test(contactId))) return { ok: false, error: 'Contact not found.' };
  const name = input.name.trim();
  if (!name || name.length > 120) return { ok: false, error: 'Give the contact a name.' };
  const email = clean(input.email, 254);
  if (email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return { ok: false, error: 'Enter a valid email address.' };
  const row = {
    name,
    title: clean(input.title, 120),
    email,
    phone: clean(input.phone, 40),
    is_primary: input.isPrimary,
    notes: clean(input.notes, 1000),
  };
  const res = contactId
    ? await a.supabase.from('agency_client_contacts').update(row).eq('id', contactId).eq('client_id', clientId).select('id')
    : await a.supabase.from('agency_client_contacts').insert({ ...row, client_id: clientId }).select('id');
  if (res.error) {
    if (res.error.code === '42501')
      return { ok: false, error: 'Only owners, admins and recruiters can edit contacts.', code: '42501' };
    return fail(res.error);
  }
  if (!res.data?.length) return { ok: false, error: 'Only owners, admins and recruiters can edit contacts.', code: '42501' };
  revalidatePath(`${BASE}/clients/${clientId}`);
  return { ok: true };
}

export async function deleteClientContact(clientId: string, contactId: string): Promise<Ok | Fail> {
  const a = await agency();
  if (!a) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(clientId) || !UUID_RE.test(contactId)) return { ok: false, error: 'Contact not found.' };
  const { data, error } = await a.supabase
    .from('agency_client_contacts')
    .delete()
    .eq('id', contactId)
    .eq('client_id', clientId)
    .select('id');
  if (error) return fail(error);
  if (!data?.length) return { ok: false, error: 'Only owners, admins and recruiters can remove contacts.', code: '42501' };
  revalidatePath(`${BASE}/clients/${clientId}`);
  return { ok: true };
}

/** Employer companies on Omelo whose name matches (companies are public). */
export async function findEmployerCompanies(
  term: string
): Promise<Ok<{ companies: { id: string; name: string; verified: boolean; slug: string }[] }> | Fail> {
  const a = await agency();
  if (!a) return { ok: false, error: SIGNED_OUT };
  const t = term.replace(/[^\p{L}\p{N} &._-]/gu, '').trim().slice(0, 80);
  if (t.length < 2) return { ok: false, error: 'Type at least two letters of the company name.' };
  const { data, error } = await a.supabase
    .from('companies')
    .select('id, display_name, is_verified, slug')
    .eq('company_kind', 'employer')
    .is('deleted_at', null)
    .neq('id', a.ctx.companyId)
    .ilike('display_name', `%${t.replace(/[%_]/g, (m) => `\\${m}`)}%`)
    .order('is_verified', { ascending: false })
    .order('display_name')
    .limit(10);
  if (error) return fail(error);
  return {
    ok: true,
    companies: (data ?? []).map((c) => ({ id: c.id, name: c.display_name, verified: c.is_verified, slug: c.slug })),
  };
}

export async function requestClientLink(clientId: string, companyId: string): Promise<Ok | Fail> {
  const a = await agency();
  if (!a) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(clientId) || !UUID_RE.test(companyId)) return { ok: false, error: 'Choose a company.' };
  const { error } = await a.supabase.rpc('omelo_request_client_link', { p_client: clientId, p_company: companyId });
  if (error) {
    report(error, 'requestClientLink');
    return fail(error);
  }
  revalidatePath(`${BASE}/clients/${clientId}`);
  return { ok: true };
}

export async function endClientLink(clientId: string): Promise<Ok | Fail> {
  const a = await agency();
  if (!a) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(clientId)) return { ok: false, error: 'Client not found.' };
  const { error } = await a.supabase.rpc('omelo_end_client_link', { p_client: clientId });
  if (error) return fail(error);
  revalidatePath(`${BASE}/clients/${clientId}`);
  revalidatePath('/dashboard/agencies');
  return { ok: true };
}

/* ------------------------------------------------------------------ */
/* Job orders                                                          */
/* ------------------------------------------------------------------ */

export type JobOrderInput = {
  title: string;
  reference?: string;
  profession_id: string | null;
  openings: number;
  location_id: string | null;
  location_text: string;
  workplace_type: string;
  work_type: string;
  shift_types: string[];
  pay_min: number | null;
  pay_max: number | null;
  pay_period: string | null;
  pay_currency: string;
  min_experience_months: number | null;
  required_skill_ids: string[];
  hard_requirements: string[];
  description: string;
  start_date: string | null;
  closing_date: string | null;
  priority: string;
  status: string;
  notes: string;
};

function orderPayload(input: JobOrderInput): { error: string } | { payload: Record<string, Json> } {
  const title = input.title.trim();
  if (title.length < 2 || title.length > 120) return { error: 'Give the job order a title (2–120 characters).' };
  const openings = Math.floor(Number(input.openings));
  if (!Number.isFinite(openings) || openings < 1 || openings > 10000) return { error: 'Openings must be 1 or more.' };
  for (const id of [input.profession_id, input.location_id, ...input.required_skill_ids])
    if (id && !UUID_RE.test(id)) return { error: 'Pick options from the lists.' };
  if (input.pay_min != null && input.pay_max != null && input.pay_max < input.pay_min)
    return { error: 'The maximum pay is below the minimum.' };
  const date = /^\d{4}-\d{2}-\d{2}$/;
  if ((input.start_date && !date.test(input.start_date)) || (input.closing_date && !date.test(input.closing_date)))
    return { error: 'Check the dates.' };
  const currency = (input.pay_currency || 'INR').trim().toUpperCase();
  if (!/^[A-Z]{3}$/.test(currency)) return { error: 'Currency is a three-letter code, e.g. INR.' };
  const reference = (input.reference ?? '').trim();
  if (reference.length > 40) return { error: 'Keep the reference under 40 characters.' };
  const payload: Record<string, Json> = {
    title,
    profession_id: input.profession_id ?? '',
    openings,
    location_id: input.location_id ?? '',
    location_text: input.location_text.trim().slice(0, 200),
    workplace_type: input.workplace_type,
    work_type: input.work_type,
    shift_types: input.shift_types,
    pay_min: input.pay_min ?? '',
    pay_max: input.pay_max ?? '',
    pay_period: input.pay_period ?? '',
    pay_currency: currency,
    min_experience_months: input.min_experience_months ?? '',
    required_skill_ids: [...new Set(input.required_skill_ids)].slice(0, 50),
    hard_requirements: list(input.hard_requirements, 30, 200),
    description: input.description.trim().slice(0, 8000),
    start_date: input.start_date ?? '',
    closing_date: input.closing_date ?? '',
    priority: input.priority,
    status: input.status,
    notes: input.notes.trim().slice(0, 4000),
  };
  if (reference) payload.reference = reference;
  return { payload };
}

export async function createJobOrder(clientId: string, input: JobOrderInput): Promise<Ok<{ id: string }> | Fail> {
  const a = await agency();
  if (!a) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(clientId)) return { ok: false, error: 'Choose a client.' };
  const p = orderPayload(input);
  if ('error' in p) return { ok: false, error: p.error };
  const { data, error } = await a.supabase.rpc('omelo_create_job_order', { p_client: clientId, p_order: p.payload });
  if (error) {
    report(error, 'createJobOrder');
    return fail(error);
  }
  revalidatePath(`${BASE}/job-orders`);
  revalidatePath(`${BASE}/clients/${clientId}`);
  return { ok: true, id: String(data) };
}

export async function updateJobOrder(orderId: string, input: JobOrderInput): Promise<Ok | Fail> {
  const a = await agency();
  if (!a) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(orderId)) return { ok: false, error: 'Job order not found.' };
  const p = orderPayload(input);
  if ('error' in p) return { ok: false, error: p.error };
  const { error } = await a.supabase.rpc('omelo_update_job_order', { p_order: orderId, p_changes: p.payload });
  if (error) {
    report(error, 'updateJobOrder');
    return fail(error);
  }
  revalidatePath(`${BASE}/job-orders`, 'layout');
  return { ok: true };
}

/** Status-only change (from the order page). */
export async function setJobOrderStatus(orderId: string, status: string): Promise<Ok | Fail> {
  const a = await agency();
  if (!a) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(orderId)) return { ok: false, error: 'Job order not found.' };
  const { error } = await a.supabase.rpc('omelo_update_job_order', { p_order: orderId, p_changes: { status } });
  if (error) return fail(error);
  revalidatePath(`${BASE}/job-orders`, 'layout');
  return { ok: true };
}

export async function assignRecruiter(input: {
  orderId: string;
  personId: string;
  assign: boolean;
  role: 'lead' | 'support';
}): Promise<Ok | Fail> {
  const a = await agency();
  if (!a) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(input.orderId) || !UUID_RE.test(input.personId)) return { ok: false, error: 'Choose a teammate.' };
  const { error } = await a.supabase.rpc('omelo_assign_job_order_recruiter', {
    p_order: input.orderId,
    p_person: input.personId,
    p_assign: input.assign,
    p_role: input.role,
  });
  if (error) return fail(error);
  revalidatePath(`${BASE}/job-orders/${input.orderId}`);
  return { ok: true };
}

/* ------------------------------------------------------------------ */
/* Talent search                                                       */
/* ------------------------------------------------------------------ */

export async function searchForOrder(input: {
  orderId: string;
  filters: SearchFilters;
  offset: number;
}): Promise<Ok<{ data: AgencySearchResult }> | Fail> {
  const a = await agency();
  if (!a) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(input.orderId)) return { ok: false, error: 'Choose a job order.' };
  const f = input.filters;
  if ((f.query ?? '').length > 80) return { ok: false, error: 'Keep the search under 80 characters.' };
  // Drop empty values so the database applies its defaults.
  const filters: Record<string, Json> = {};
  for (const [k, v] of Object.entries(f)) {
    if (v === undefined || v === null || v === '') continue;
    if (Array.isArray(v) && v.length === 0) continue;
    filters[k] = v as Json;
  }
  const { data, error } = await a.supabase.rpc('omelo_search_talent_for_order', {
    p_job_order: input.orderId,
    p_filters: filters,
    p_limit: 20,
    p_offset: Math.max(0, Math.floor(input.offset) || 0),
  });
  if (error) {
    report(error, 'searchForOrder');
    return fail(error);
  }
  return { ok: true, data: parseAgencySearch(data) };
}

/* ------------------------------------------------------------------ */
/* Consent                                                             */
/* ------------------------------------------------------------------ */

export async function requestConsent(input: {
  orderId: string;
  identityId: string;
  scope: string[];
  validDays: number;
  message: string;
}): Promise<Ok<{ consentId: string }> | Fail> {
  const a = await agency();
  if (!a) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(input.orderId) || !UUID_RE.test(input.identityId))
    return { ok: false, error: 'Choose a job order and a candidate.' };
  const scope = [...new Set(['identity', ...input.scope])].filter((s) => (SCOPES as readonly string[]).includes(s));
  const days = Math.floor(Number(input.validDays));
  if (!Number.isFinite(days) || days < 7 || days > 180) return { ok: false, error: 'Consent can last between 7 and 180 days.' };
  const message = input.message.trim();
  if (message.length > CONSENT_MESSAGE_MAX)
    return { ok: false, error: `Keep the message under ${CONSENT_MESSAGE_MAX} characters.` };
  const { data, error } = await a.supabase.rpc('omelo_request_representation', {
    p_job_order: input.orderId,
    p_identity: input.identityId,
    p_scope: scope,
    p_valid_days: days,
    p_message: message || undefined,
  });
  if (error) {
    report(error, 'requestConsent');
    return fail(error);
  }
  revalidatePath(`${BASE}/candidates`);
  revalidatePath(`${BASE}/job-orders/${input.orderId}`);
  return { ok: true, consentId: String(data) };
}

export async function withdrawConsentRequest(consentId: string): Promise<Ok | Fail> {
  const a = await agency();
  if (!a) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(consentId)) return { ok: false, error: 'Request not found.' };
  const { error } = await a.supabase.rpc('omelo_withdraw_representation_request', { p_consent: consentId });
  if (error) return fail(error);
  revalidatePath(`${BASE}/candidates`, 'layout');
  revalidatePath(`${BASE}/job-orders`, 'layout');
  return { ok: true };
}

/* ------------------------------------------------------------------ */
/* Submissions                                                         */
/* ------------------------------------------------------------------ */

export async function submitCandidate(consentId: string, note: string): Promise<Ok<{ submissionId: string }> | Fail> {
  const a = await agency();
  if (!a) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(consentId)) return { ok: false, error: 'Consent not found.' };
  const n = note.trim();
  if (n.length > SUBMIT_NOTE_MAX) return { ok: false, error: `Keep the note under ${SUBMIT_NOTE_MAX} characters.` };
  const { data, error } = await a.supabase.rpc('omelo_submit_candidate', { p_consent: consentId, p_note: n || undefined });
  if (error) {
    report(error, 'submitCandidate');
    return fail(error);
  }
  revalidatePath(`${BASE}/candidates`, 'layout');
  revalidatePath(`${BASE}/submissions`);
  revalidatePath(`${BASE}/job-orders`, 'layout');
  return { ok: true, submissionId: String(data) };
}

export async function withdrawSubmission(submissionId: string, reason: string): Promise<Ok | Fail> {
  const a = await agency();
  if (!a) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(submissionId)) return { ok: false, error: 'Submission not found.' };
  const { error } = await a.supabase.rpc('omelo_withdraw_submission', {
    p_submission: submissionId,
    p_reason: reason.trim().slice(0, 300) || undefined,
  });
  if (error) return fail(error);
  revalidatePath(`${BASE}/submissions`, 'layout');
  return { ok: true };
}

export async function recordOutcome(input: {
  submissionId: string;
  status: string;
  note: string;
  startDate: string | null;
}): Promise<Ok | Fail> {
  const a = await agency();
  if (!a) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(input.submissionId)) return { ok: false, error: 'Submission not found.' };
  if (!(OUTCOMES as string[]).includes(input.status)) return { ok: false, error: 'Choose an outcome.' };
  if (input.startDate && !/^\d{4}-\d{2}-\d{2}$/.test(input.startDate)) return { ok: false, error: 'Check the start date.' };
  const { error } = await a.supabase.rpc('omelo_record_submission_outcome', {
    p_submission: input.submissionId,
    p_status: input.status,
    p_note: input.note.trim().slice(0, 2000) || undefined,
    p_start_date: input.startDate || undefined,
  });
  if (error) return fail(error);
  revalidatePath(`${BASE}/submissions`, 'layout');
  revalidatePath(`${BASE}/placements`);
  return { ok: true };
}

/* ------------------------------------------------------------------ */
/* Placements                                                          */
/* ------------------------------------------------------------------ */

export async function updatePlacement(input: {
  placementId: string;
  status?: string;
  startDate?: string | null;
  guaranteeEndsOn?: string | null;
  feeAmount?: number | null;
  feeCurrency?: string | null;
  notes?: string | null;
}): Promise<Ok | Fail> {
  const a = await agency();
  if (!a) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(input.placementId)) return { ok: false, error: 'Placement not found.' };
  const changes: Record<string, Json> = {};
  const date = /^\d{4}-\d{2}-\d{2}$/;
  if (input.status) changes.status = input.status;
  if (input.startDate !== undefined) {
    if (input.startDate && !date.test(input.startDate)) return { ok: false, error: 'Check the start date.' };
    changes.start_date = input.startDate ?? '';
  }
  if (input.guaranteeEndsOn !== undefined) {
    if (input.guaranteeEndsOn && !date.test(input.guaranteeEndsOn)) return { ok: false, error: 'Check the guarantee date.' };
    changes.guarantee_ends_on = input.guaranteeEndsOn ?? '';
  }
  if (input.feeAmount !== undefined) {
    if (input.feeAmount != null && (!Number.isFinite(input.feeAmount) || input.feeAmount < 0))
      return { ok: false, error: 'The fee must be 0 or more.' };
    changes.fee_amount = input.feeAmount ?? '';
  }
  if (input.feeCurrency !== undefined) {
    const c = (input.feeCurrency ?? '').trim().toUpperCase();
    if (c && !/^[A-Z]{3}$/.test(c)) return { ok: false, error: 'Currency is a three-letter code, e.g. INR.' };
    changes.fee_currency = c;
  }
  if (input.notes !== undefined) changes.notes = (input.notes ?? '').trim().slice(0, 2000);
  const { error } = await a.supabase.rpc('omelo_update_placement', { p_placement: input.placementId, p_changes: changes });
  if (error) return fail(error);
  revalidatePath(`${BASE}/placements`);
  revalidatePath(`${BASE}/billing`);
  revalidatePath(`${BASE}/submissions`, 'layout');
  return { ok: true };
}
