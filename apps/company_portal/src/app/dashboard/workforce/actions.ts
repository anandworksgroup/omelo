'use server';

import { revalidatePath } from 'next/cache';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import type { Json } from '@/lib/supabase/database.types';
import { reportError } from '@/lib/observability';
import { UUID_RE } from '@/lib/talent';
import {
  CHECK_IN_METHODS,
  COMPONENT_KINDS,
  DATE_RE,
  EMPLOYMENT_TYPES,
  PAY_BASES,
  PAY_FREQUENCIES,
  REQUIREMENT_STATUSES,
  SHIFT_KINDS,
  validTimeZone,
  zonedToUtc,
} from '@/lib/workforce';

/*
 * Workforce actions. Authority (roles, company, client vs agency approval),
 * integrity (schedule conflicts, locked timesheets, payments within approved
 * pay) and every field check live in the database; these functions only
 * shape input and pass the database's message straight through:
 * 42501 = not allowed, 22023 = a rule was broken, 23514 / 23P01 = integrity
 * (for example "Schedule conflict").
 */

export type Fail = { ok: false; error: string; code?: string };
export type Ok<T = object> = { ok: true } & T;
type Res<T = object> = Promise<Ok<T> | Fail>;

const SIGNED_OUT = 'You are signed out or not part of a company.';
const BASE = '/dashboard/workforce';
const EXPECTED = new Set(['42501', '22023', '23514', '23P01', 'P0001']);

async function session() {
  const ctx = await getCompanyContext();
  if (!ctx) return null;
  return { ctx, supabase: await createClient() };
}

function fail(error: { message: string; code?: string }, action: string): Fail {
  if (!EXPECTED.has(error.code ?? '')) reportError(error, { action });
  return { ok: false, error: error.message, code: error.code };
}

const bad = (error: string): Fail => ({ ok: false, error });
const isId = (v: unknown): v is string => typeof v === 'string' && UUID_RE.test(v);
const text = (v: string | null | undefined, max: number) => {
  const t = (v ?? '').trim();
  return t ? t.slice(0, max) : null;
};
const numOrNull = (v: unknown): number | null => {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
};

function refresh(...paths: string[]) {
  revalidatePath(BASE, 'layout');
  for (const p of paths) revalidatePath(p);
}

/* ------------------------------------------------------------------ */
/* Requirements                                                        */
/* ------------------------------------------------------------------ */

export type RequirementInput = {
  job_id: string | null;
  job_order_id: string | null;
  title: string;
  profession_id: string | null;
  openings: number | null;
  location_id: string | null;
  location_text: string;
  site_name: string;
  country_code: string;
  currency: string;
  timezone: string;
  employment_type: string;
  work_type: string;
  pay_rate: string;
  pay_period: string;
  pay_frequency: string;
  hours_per_week: string;
  start_date: string;
  end_date: string;
  check_in_method: string;
  geofence_radius_m: string;
  late_grace_minutes: string;
  overtime_policy_id: string | null;
  supervisor_id: string | null;
  status: string;
  notes: string;
};

/**
 * Builds p_fields / p_changes. On create, empty fields are left out so the
 * database copies them from the job or job order; on edit every field is
 * sent (empty = cleared).
 */
function requirementFields(v: RequirementInput, creating: boolean): { fields: Record<string, Json> } | { error: string } {
  const f: Record<string, Json> = {};
  const put = (k: string, val: Json | undefined) => {
    if (val === undefined) return;
    if (creating && (val === null || val === '')) return;
    f[k] = val;
  };
  const title = text(v.title, 120);
  if (title && title.length < 2) return { error: 'Give the requirement a title (2–120 characters).' };
  const linked = !!(v.job_id || v.job_order_id);
  if (!title && !linked) return { error: 'Give the requirement a title, or start it from a job.' };
  if (!creating && !title) return { error: 'The requirement needs a title.' };
  put('title', title);
  if (v.profession_id && !isId(v.profession_id)) return { error: 'Choose a profession from the list.' };
  put('profession_id', v.profession_id || null);
  if (v.openings != null) {
    if (!Number.isInteger(v.openings) || v.openings < 1 || v.openings > 1_000_000)
      return { error: 'Openings must be a whole number from 1 to 1,000,000.' };
    put('openings', v.openings);
  }
  if (v.location_id && !isId(v.location_id)) return { error: 'Choose an area from the list.' };
  put('location_id', v.location_id || null);
  put('location_text', text(v.location_text, 200));
  put('site_name', text(v.site_name, 120));
  const cc = (v.country_code ?? '').trim().toUpperCase();
  if (cc && !/^[A-Z]{2}$/.test(cc)) return { error: 'The country code is two letters, like IN or AE.' };
  put('country_code', cc || null);
  const cur = (v.currency ?? '').trim().toUpperCase();
  if (cur && !/^[A-Z]{3}$/.test(cur)) return { error: 'The currency is a three-letter code, like INR or AED.' };
  if (!cur && !linked) return { error: 'Choose the currency workers are paid in.' };
  if (!cur && !creating) return { error: 'Choose the currency workers are paid in.' };
  put('currency', cur || null);
  const tz = (v.timezone ?? '').trim();
  if (tz && !validTimeZone(tz)) return { error: 'Choose a time zone from the list.' };
  if (!creating && !tz) return { error: 'Choose the site’s time zone.' };
  put('timezone', tz || null);
  if (!(EMPLOYMENT_TYPES as readonly string[]).includes(v.employment_type)) return { error: 'Choose an employment type.' };
  put('employment_type', v.employment_type);
  put('work_type', v.work_type || null);
  const pay = numOrNull(v.pay_rate);
  if (v.pay_rate?.trim() && (pay == null || pay < 0)) return { error: 'The pay rate is a number of 0 or more.' };
  put('pay_rate', pay);
  put('pay_period', v.pay_period || null);
  if (!(PAY_FREQUENCIES as readonly string[]).includes(v.pay_frequency)) return { error: 'Choose how often workers are paid.' };
  put('pay_frequency', v.pay_frequency);
  const hpw = numOrNull(v.hours_per_week);
  if (v.hours_per_week?.trim() && (hpw == null || hpw < 0 || hpw > 168)) return { error: 'Hours a week is between 0 and 168.' };
  put('hours_per_week', hpw);
  for (const k of ['start_date', 'end_date'] as const) {
    if (v[k] && !DATE_RE.test(v[k])) return { error: 'Dates look like 2026-09-30.' };
  }
  if (v.start_date && v.end_date && v.end_date < v.start_date) return { error: 'The end date is before the start date.' };
  put('start_date', v.start_date || null);
  put('end_date', v.end_date || null);
  if (!(CHECK_IN_METHODS as readonly string[]).includes(v.check_in_method)) return { error: 'Choose a check-in method.' };
  put('check_in_method', v.check_in_method);
  const radius = numOrNull(v.geofence_radius_m);
  if (v.check_in_method === 'geofence' && (radius == null || radius < 25 || radius > 5000))
    return { error: 'Location check-in needs a radius from 25 to 5,000 metres.' };
  put('geofence_radius_m', radius);
  const grace = numOrNull(v.late_grace_minutes);
  if (grace == null || !Number.isInteger(grace) || grace < 0 || grace > 240)
    return { error: 'Late grace is 0 to 240 minutes.' };
  f.late_grace_minutes = grace;
  if (v.overtime_policy_id && !isId(v.overtime_policy_id)) return { error: 'Choose an overtime policy from the list.' };
  put('overtime_policy_id', v.overtime_policy_id || null);
  if (v.supervisor_id && !isId(v.supervisor_id)) return { error: 'Choose a supervisor from your team.' };
  put('supervisor_id', v.supervisor_id || null);
  if (!(REQUIREMENT_STATUSES as readonly string[]).includes(v.status)) return { error: 'Choose a status.' };
  put('status', v.status);
  put('notes', text(v.notes, 4000));
  return { fields: f };
}

export async function createRequirement(input: RequirementInput): Res<{ id: string }> {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (input.job_id && !isId(input.job_id)) return bad('Choose a job from the list.');
  if (input.job_order_id && !isId(input.job_order_id)) return bad('Choose a job order from the list.');
  if (s.ctx.kind === 'agency' && !input.job_order_id) return bad('An agency requirement starts from one of its job orders.');
  const r = requirementFields(input, true);
  if ('error' in r) return bad(r.error);
  const fields = { ...r.fields };
  if (s.ctx.kind === 'agency') fields.job_order_id = input.job_order_id;
  else if (input.job_id) fields.job_id = input.job_id;
  const { data, error } = await s.supabase.rpc('omelo_create_requirement', { p_company: s.ctx.companyId, p_fields: fields });
  if (error) return fail(error, 'createRequirement');
  refresh(`${BASE}/requirements`);
  return { ok: true, id: data };
}

export async function updateRequirement(id: string, input: RequirementInput): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(id)) return bad('Requirement not found.');
  const r = requirementFields(input, false);
  if ('error' in r) return bad(r.error);
  const { error } = await s.supabase.rpc('omelo_update_requirement', { p_requirement: id, p_changes: r.fields });
  if (error) return fail(error, 'updateRequirement');
  refresh(`${BASE}/requirements/${id}`);
  return { ok: true };
}

export async function setRequirementStatus(id: string, status: string): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(id) || !(REQUIREMENT_STATUSES as readonly string[]).includes(status)) return bad('Choose a status.');
  const { error } = await s.supabase.rpc('omelo_update_requirement', { p_requirement: id, p_changes: { status } });
  if (error) return fail(error, 'setRequirementStatus');
  refresh(`${BASE}/requirements/${id}`);
  return { ok: true };
}

/* ------------------------------------------------------------------ */
/* Pay components                                                      */
/* ------------------------------------------------------------------ */

export type PayComponentInput = {
  kind: string;
  name: string;
  amount: string;
  basis: string;
  shiftTypes: string[];
};

export async function savePayComponent(
  target: { requirementId: string | null; assignmentId: string | null },
  v: PayComponentInput
): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!!target.requirementId === !!target.assignmentId) return bad('Add it to a requirement or an assignment.');
  if (target.requirementId && !isId(target.requirementId)) return bad('Requirement not found.');
  if (target.assignmentId && !isId(target.assignmentId)) return bad('Assignment not found.');
  if (!(COMPONENT_KINDS as readonly string[]).includes(v.kind)) return bad('Choose allowance, bonus or deduction.');
  const name = text(v.name, 80);
  if (!name) return bad('Name it (for example “Night allowance”).');
  const amount = numOrNull(v.amount);
  if (amount == null || amount < 0) return bad('The amount is a number of 0 or more.');
  if (!(PAY_BASES as readonly string[]).includes(v.basis)) return bad('Choose how it is counted.');
  const { error } = await s.supabase.rpc('omelo_save_pay_component', {
    p_requirement: (target.requirementId ?? null) as unknown as string,
    p_assignment: (target.assignmentId ?? null) as unknown as string,
    p_kind: v.kind,
    p_name: name,
    p_amount: amount,
    p_basis: v.basis,
    p_shift_types: v.shiftTypes.slice(0, 10),
  });
  if (error) return fail(error, 'savePayComponent');
  refresh();
  return { ok: true };
}

export async function removePayComponent(id: string): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(id)) return bad('Not found.');
  const { error } = await s.supabase.rpc('omelo_remove_pay_component', { p_component: id });
  if (error) return fail(error, 'removePayComponent');
  refresh();
  return { ok: true };
}

/* ------------------------------------------------------------------ */
/* Overtime policies (direct CRUD, manage_pay via RLS)                 */
/* ------------------------------------------------------------------ */

export type OvertimeInput = {
  name: string;
  country_code: string;
  daily_threshold_minutes: string;
  weekly_threshold_minutes: string;
  multiplier: string;
  max_overtime_minutes_week: string;
  standard_minutes_per_day: string;
  standard_minutes_per_week: string;
  notes: string;
};

function overtimeRow(v: OvertimeInput) {
  const name = text(v.name, 80);
  if (!name) return { error: 'Name the policy.' } as const;
  const cc = v.country_code.trim().toUpperCase();
  if (cc && !/^[A-Z]{2}$/.test(cc)) return { error: 'The country code is two letters.' } as const;
  const daily = numOrNull(v.daily_threshold_minutes);
  const weekly = numOrNull(v.weekly_threshold_minutes);
  if (daily == null && weekly == null) return { error: 'Set a daily or a weekly threshold (or both).' } as const;
  if (daily != null && (daily < 0 || daily > 1440)) return { error: 'The daily threshold is 0 to 1,440 minutes.' } as const;
  if (weekly != null && (weekly < 0 || weekly > 10080)) return { error: 'The weekly threshold is 0 to 10,080 minutes.' } as const;
  const mult = numOrNull(v.multiplier);
  if (mult == null || mult < 1 || mult > 5) return { error: 'The multiplier is between 1 and 5.' } as const;
  const max = numOrNull(v.max_overtime_minutes_week);
  if (max != null && max < 0) return { error: 'The weekly overtime cap cannot be negative.' } as const;
  const sd = numOrNull(v.standard_minutes_per_day) ?? 480;
  const sw = numOrNull(v.standard_minutes_per_week) ?? 2880;
  if (sd < 60 || sd > 1440 || sw < 60 || sw > 10080) return { error: 'Check the standard day and week lengths.' } as const;
  return {
    row: {
      name,
      country_code: cc || null,
      daily_threshold_minutes: daily == null ? null : Math.round(daily),
      weekly_threshold_minutes: weekly == null ? null : Math.round(weekly),
      multiplier: mult,
      max_overtime_minutes_week: max == null ? null : Math.round(max),
      standard_minutes_per_day: Math.round(sd),
      standard_minutes_per_week: Math.round(sw),
      notes: text(v.notes, 1000),
    },
  } as const;
}

export async function saveOvertimePolicy(id: string | null, v: OvertimeInput): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  const r = overtimeRow(v);
  if ('error' in r) return bad(r.error!);
  if (id) {
    if (!isId(id)) return bad('Policy not found.');
    const { data, error } = await s.supabase.from('overtime_policies').update(r.row).eq('id', id).select('id');
    if (error) return fail(error, 'saveOvertimePolicy');
    if (!data?.length) return { ok: false, error: 'You are not allowed to change pay settings for this company.', code: '42501' };
  } else {
    const { error } = await s.supabase.from('overtime_policies').insert({ ...r.row, company_id: s.ctx.companyId });
    if (error) {
      if (error.code === '42501')
        return { ok: false, error: 'You are not allowed to change pay settings for this company.', code: error.code };
      return fail(error, 'saveOvertimePolicy');
    }
  }
  refresh(`${BASE}/pay`);
  return { ok: true };
}

export async function deleteOvertimePolicy(id: string): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(id)) return bad('Policy not found.');
  const { data, error } = await s.supabase.from('overtime_policies').delete().eq('id', id).select('id');
  if (error) return fail(error, 'deleteOvertimePolicy');
  if (!data?.length) return { ok: false, error: 'You are not allowed to change pay settings for this company.', code: '42501' };
  refresh(`${BASE}/pay`);
  return { ok: true };
}

/* ------------------------------------------------------------------ */
/* Assignments                                                         */
/* ------------------------------------------------------------------ */

export type OfferInput = {
  start_date: string;
  end_date: string;
  pay_rate: string;
  pay_period: string;
  pay_frequency: string;
  employment_type: string;
  title: string;
  supervisor_id: string | null;
  bill_rate: string;
  bill_period: string;
};

function offerFields(v: OfferInput): { fields: Record<string, Json> } | { error: string } {
  const f: Record<string, Json> = {};
  for (const k of ['start_date', 'end_date'] as const) {
    if (v[k] && !DATE_RE.test(v[k])) return { error: 'Dates look like 2026-09-30.' };
    if (v[k]) f[k] = v[k];
  }
  if (v.start_date && v.end_date && v.end_date < v.start_date) return { error: 'The end date is before the start date.' };
  const pay = numOrNull(v.pay_rate);
  if (v.pay_rate.trim()) {
    if (pay == null || pay < 0) return { error: 'The pay rate is a number of 0 or more.' };
    f.pay_rate = pay;
  }
  if (v.pay_period) f.pay_period = v.pay_period;
  if (v.pay_frequency) f.pay_frequency = v.pay_frequency;
  if (v.employment_type) f.employment_type = v.employment_type;
  const title = text(v.title, 120);
  if (title) f.title = title;
  if (v.supervisor_id) {
    if (!isId(v.supervisor_id)) return { error: 'Choose a supervisor from your team.' };
    f.supervisor_id = v.supervisor_id;
  }
  const bill = numOrNull(v.bill_rate);
  if (v.bill_rate.trim()) {
    if (bill == null || bill < 0) return { error: 'The bill rate is a number of 0 or more.' };
    f.bill_rate = bill;
    if (v.bill_period) f.bill_period = v.bill_period;
  }
  return { fields: f };
}

export async function offerAssignment(requirementId: string, identityId: string, v: OfferInput): Res<{ id: string }> {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(requirementId) || !isId(identityId)) return bad('Choose a worker.');
  const r = offerFields(v);
  if ('error' in r) return bad(r.error);
  const { data, error } = await s.supabase.rpc('omelo_offer_assignment', {
    p_requirement: requirementId,
    p_identity: identityId,
    p_fields: r.fields,
  });
  if (error) return fail(error, 'offerAssignment');
  refresh(`${BASE}/requirements/${requirementId}`, `${BASE}/assignments`);
  return { ok: true, id: data };
}

export async function startBulkOffer(requirementId: string, identityIds: string[], v: OfferInput): Res<{ jobId: string }> {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(requirementId)) return bad('Requirement not found.');
  const ids = [...new Set(identityIds.filter(isId))];
  if (ids.length === 0) return bad('Choose at least one worker.');
  if (ids.length > 20000) return bad('A bulk operation handles at most 20,000 workers.');
  const r = offerFields(v);
  if ('error' in r) return bad(r.error);
  const { data, error } = await s.supabase.rpc('omelo_start_workforce_job', {
    p_company: s.ctx.companyId,
    p_kind: 'offer_assignments',
    p_payload: { requirement_id: requirementId, identity_ids: ids, fields: r.fields },
  });
  if (error) return fail(error, 'startBulkOffer');
  refresh(`${BASE}/bulk`);
  return { ok: true, jobId: data };
}

export async function setAssignmentStatus(id: string, status: string, reason: string, endDate: string): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(id)) return bad('Assignment not found.');
  if (!['active', 'paused', 'completed', 'terminated', 'cancelled'].includes(status)) return bad('Choose a status.');
  if (endDate && !DATE_RE.test(endDate)) return bad('Dates look like 2026-09-30.');
  const why = text(reason, 500);
  if (status === 'terminated' && (!why || why.length < 3)) return bad('Say why the assignment is terminated.');
  const { error } = await s.supabase.rpc('omelo_set_assignment_status', {
    p_assignment: id,
    p_status: status,
    ...(why ? { p_reason: why } : {}),
    ...(endDate && (status === 'completed' || status === 'terminated') ? { p_end_date: endDate } : {}),
  });
  if (error) return fail(error, 'setAssignmentStatus');
  refresh(`${BASE}/assignments/${id}`);
  return { ok: true };
}

export async function setAssignmentBilling(id: string, billRate: string, billPeriod: string, note: string): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(id)) return bad('Assignment not found.');
  const r = numOrNull(billRate);
  if (r == null || r < 0) return bad('The bill rate is a number of 0 or more.');
  if (!billPeriod) return bad('Choose the billing period.');
  const n = text(note, 500);
  const { error } = await s.supabase.rpc('omelo_set_assignment_billing', {
    p_assignment: id,
    p_bill_rate: r,
    p_bill_period: billPeriod,
    ...(n ? { p_note: n } : {}),
  });
  if (error) return fail(error, 'setAssignmentBilling');
  refresh(`${BASE}/assignments/${id}`);
  return { ok: true };
}

/* ------------------------------------------------------------------ */
/* Shift templates and shifts                                          */
/* ------------------------------------------------------------------ */

export type TemplateInput = {
  name: string;
  days_of_week: number[];
  start_time: string;
  end_time: string;
  break_minutes: string;
  required_workers: string;
  shift_type: string;
  valid_from: string;
  valid_until: string;
  status: string;
};

export async function saveShiftTemplate(requirementId: string, templateId: string | null, v: TemplateInput): Res<{ id: string }> {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(requirementId) || (templateId && !isId(templateId))) return bad('Not found.');
  const name = text(v.name, 80);
  if (!name) return bad('Name the shift (for example “Night shift”).');
  const days = [...new Set(v.days_of_week.filter((d) => Number.isInteger(d) && d >= 1 && d <= 7))].sort();
  if (days.length === 0) return bad('Pick at least one day.');
  if (!/^\d{2}:\d{2}$/.test(v.start_time) || !/^\d{2}:\d{2}$/.test(v.end_time)) return bad('Give a start and end time.');
  if (v.start_time === v.end_time) return bad('The shift must have a length.');
  const brk = numOrNull(v.break_minutes) ?? 0;
  const req = numOrNull(v.required_workers) ?? 1;
  if (brk < 0 || brk > 480) return bad('A break is 0 to 480 minutes.');
  if (!Number.isInteger(req) || req < 1 || req > 100000) return bad('Workers needed is 1 to 100,000.');
  for (const d of [v.valid_from, v.valid_until]) if (d && !DATE_RE.test(d)) return bad('Dates look like 2026-09-30.');
  const tpl: Record<string, Json> = {
    name,
    days_of_week: days,
    start_time: v.start_time,
    end_time: v.end_time,
    break_minutes: Math.round(brk),
    required_workers: req,
    shift_type: v.shift_type || '',
    valid_from: v.valid_from || '',
    valid_until: v.valid_until || '',
    status: v.status === 'archived' ? 'archived' : 'active',
  };
  const { data, error } = await s.supabase.rpc('omelo_save_shift_template', {
    p_requirement: requirementId,
    p_template: tpl,
    ...(templateId ? { p_template_id: templateId } : {}),
  });
  if (error) return fail(error, 'saveShiftTemplate');
  refresh(`${BASE}/requirements/${requirementId}`);
  return { ok: true, id: data };
}

export async function generateShifts(templateId: string, from: string, to: string): Res<{ count: number }> {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(templateId)) return bad('Template not found.');
  if (!DATE_RE.test(from) || !DATE_RE.test(to)) return bad('Choose a date range.');
  if (to < from) return bad('The range ends before it starts.');
  const { data, error } = await s.supabase.rpc('omelo_generate_shifts', { p_template: templateId, p_from: from, p_to: to });
  if (error) return fail(error, 'generateShifts');
  refresh(`${BASE}/shifts`);
  return { ok: true, count: Number(data) || 0 };
}

export type ShiftInput = {
  starts_at: string; // wall-clock in the site's time zone
  ends_at: string;
  break_minutes: string;
  required_workers: string;
  shift_type: string;
  kind: string;
  instructions: string;
  location_text: string;
};

function shiftTimes(v: { starts_at: string; ends_at: string }, tz: string) {
  const start = zonedToUtc(v.starts_at, tz);
  const end = zonedToUtc(v.ends_at, tz);
  if (!start || !end) return { error: 'Give a start and end date and time.' } as const;
  const len = new Date(end).getTime() - new Date(start).getTime();
  if (len <= 0) return { error: 'The shift ends before it starts.' } as const;
  if (len > 24 * 3_600_000) return { error: 'A shift lasts at most 24 hours.' } as const;
  return { start, end } as const;
}

export async function createShift(requirementId: string, tz: string, v: ShiftInput): Res<{ id: string }> {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(requirementId)) return bad('Requirement not found.');
  const t = shiftTimes(v, tz);
  if ('error' in t) return bad(t.error!);
  if (!(SHIFT_KINDS as readonly string[]).includes(v.kind)) return bad('Choose the kind of shift.');
  const payload: Record<string, Json> = {
    starts_at: t.start,
    ends_at: t.end,
    break_minutes: Math.round(numOrNull(v.break_minutes) ?? 0),
    required_workers: Math.round(numOrNull(v.required_workers) ?? 1),
    shift_type: v.shift_type || '',
    kind: v.kind,
    instructions: text(v.instructions, 2000) ?? '',
    location_text: text(v.location_text, 200) ?? '',
  };
  const { data, error } = await s.supabase.rpc('omelo_create_shift', { p_requirement: requirementId, p_shift: payload });
  if (error) return fail(error, 'createShift');
  refresh(`${BASE}/shifts`, `${BASE}/requirements/${requirementId}`);
  return { ok: true, id: data };
}

export async function updateShift(
  shiftId: string,
  tz: string,
  v: { starts_at: string; ends_at: string; break_minutes: string; required_workers: string; instructions: string }
): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(shiftId)) return bad('Shift not found.');
  const t = shiftTimes(v, tz);
  if ('error' in t) return bad(t.error!);
  const { error } = await s.supabase.rpc('omelo_update_shift', {
    p_shift: shiftId,
    p_changes: {
      starts_at: t.start,
      ends_at: t.end,
      break_minutes: Math.round(numOrNull(v.break_minutes) ?? 0),
      required_workers: Math.round(numOrNull(v.required_workers) ?? 1),
      instructions: text(v.instructions, 2000) ?? '',
    },
  });
  if (error) return fail(error, 'updateShift');
  refresh(`${BASE}/shifts/${shiftId}`);
  return { ok: true };
}

export async function cancelShift(shiftId: string, reason: string): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(shiftId)) return bad('Shift not found.');
  const why = text(reason, 300);
  if (!why || why.length < 3) return bad('Say why the shift is cancelled — workers are told.');
  const { error } = await s.supabase.rpc('omelo_cancel_shift', { p_shift: shiftId, p_reason: why });
  if (error) return fail(error, 'cancelShift');
  refresh(`${BASE}/shifts/${shiftId}`, `${BASE}/shifts`);
  return { ok: true };
}

export type BatchResult = { done: number; errors: { assignmentId: string; error: string }[] };

function parseBatch(raw: Json, key: 'assigned' | 'offered'): BatchResult {
  const d = raw && typeof raw === 'object' && !Array.isArray(raw) ? (raw as Record<string, Json>) : {};
  const errs = Array.isArray(d.errors) ? d.errors : [];
  return {
    done: Number(d[key]) || 0,
    errors: errs.map((e) => {
      const o = e && typeof e === 'object' && !Array.isArray(e) ? (e as Record<string, Json>) : {};
      return { assignmentId: String(o.assignment_id ?? ''), error: String(o.error ?? 'Failed') };
    }),
  };
}

export async function assignShift(shiftId: string, assignmentIds: string[], offer: boolean): Res<BatchResult> {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(shiftId)) return bad('Shift not found.');
  const ids = [...new Set(assignmentIds.filter(isId))];
  if (ids.length === 0) return bad('Choose at least one worker.');
  if (ids.length > 200) return bad('Choose at most 200 workers at once; use a bulk operation for more.');
  const { data, error } = offer
    ? await s.supabase.rpc('omelo_offer_shift', { p_shift: shiftId, p_assignments: ids })
    : await s.supabase.rpc('omelo_assign_shift', { p_shift: shiftId, p_assignments: ids });
  if (error) return fail(error, 'assignShift');
  refresh(`${BASE}/shifts/${shiftId}`);
  return { ok: true, ...parseBatch(data, offer ? 'offered' : 'assigned') };
}

export async function startBulkAssignShifts(shiftIds: string[], assignmentIds: string[]): Res<{ jobId: string }> {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  const sh = [...new Set(shiftIds.filter(isId))];
  const as = [...new Set(assignmentIds.filter(isId))];
  if (!sh.length || !as.length) return bad('Choose shifts and workers.');
  const { data, error } = await s.supabase.rpc('omelo_start_workforce_job', {
    p_company: s.ctx.companyId,
    p_kind: 'assign_shifts',
    p_payload: { shift_ids: sh, assignment_ids: as },
  });
  if (error) return fail(error, 'startBulkAssignShifts');
  refresh(`${BASE}/bulk`);
  return { ok: true, jobId: data };
}

export async function unassignShift(shiftWorkerId: string, reason: string): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(shiftWorkerId)) return bad('Not found.');
  const why = text(reason, 300);
  const { error } = await s.supabase.rpc('omelo_unassign_shift', {
    p_shift_worker: shiftWorkerId,
    ...(why ? { p_reason: why } : {}),
  });
  if (error) return fail(error, 'unassignShift');
  refresh();
  return { ok: true };
}

/* ------------------------------------------------------------------ */
/* Attendance                                                          */
/* ------------------------------------------------------------------ */

export async function recordAttendance(shiftWorkerId: string, tz: string, checkIn: string, checkOut: string, note: string): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(shiftWorkerId)) return bad('Not found.');
  const inUtc = zonedToUtc(checkIn, tz);
  if (!inUtc) return bad('Give the arrival time.');
  const outUtc = checkOut ? zonedToUtc(checkOut, tz) : null;
  if (checkOut && !outUtc) return bad('The departure time is not valid.');
  const n = text(note, 500);
  const { error } = await s.supabase.rpc('omelo_record_attendance', {
    p_shift_worker: shiftWorkerId,
    p_check_in: inUtc,
    ...(outUtc ? { p_check_out: outUtc } : {}),
    ...(n ? { p_note: n } : {}),
  });
  if (error) return fail(error, 'recordAttendance');
  refresh();
  return { ok: true };
}

export async function reviewAttendance(
  attendanceId: string,
  decision: 'approve' | 'adjust' | 'reject',
  tz: string,
  v: { checkIn: string; checkOut: string; breakMinutes: string; note: string }
): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(attendanceId)) return bad('Not found.');
  if (!['approve', 'adjust', 'reject'].includes(decision)) return bad('Choose approve, adjust or reject.');
  const note = text(v.note, 500);
  const args: {
    p_attendance: string;
    p_decision: string;
    p_check_in?: string;
    p_check_out?: string;
    p_break_minutes?: number;
    p_note?: string;
  } = { p_attendance: attendanceId, p_decision: decision };
  if (decision === 'adjust') {
    const i = v.checkIn ? zonedToUtc(v.checkIn, tz) : null;
    const o = v.checkOut ? zonedToUtc(v.checkOut, tz) : null;
    if (!i || !o) return bad('Give both corrected times.');
    args.p_check_in = i;
    args.p_check_out = o;
    const b = numOrNull(v.breakMinutes);
    if (b != null) args.p_break_minutes = Math.max(0, Math.round(b));
  }
  if (decision === 'reject' && (!note || note.length < 3)) return bad('Say why — the worker is told.');
  if (note) args.p_note = note;
  const { error } = await s.supabase.rpc('omelo_review_attendance', args);
  if (error) return fail(error, 'reviewAttendance');
  refresh();
  return { ok: true };
}

export async function correctAttendance(attendanceId: string, tz: string, checkIn: string, checkOut: string, reason: string): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(attendanceId)) return bad('Not found.');
  const i = zonedToUtc(checkIn, tz);
  const o = zonedToUtc(checkOut, tz);
  if (!i || !o) return bad('Give both corrected times.');
  const why = text(reason, 500);
  if (!why || why.length < 5) return bad('A correction needs a reason (at least 5 characters).');
  const { error } = await s.supabase.rpc('omelo_correct_attendance', {
    p_attendance: attendanceId,
    p_check_in: i,
    p_check_out: o,
    p_reason: why,
  });
  if (error) return fail(error, 'correctAttendance');
  refresh(`${BASE}/attendance/${attendanceId}`);
  return { ok: true };
}

export async function reviewLeave(leaveId: string, approve: boolean, note: string): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(leaveId)) return bad('Not found.');
  const n = text(note, 500);
  const { error } = await s.supabase.rpc('omelo_review_leave', {
    p_leave: leaveId,
    p_approve: approve,
    ...(n ? { p_note: n } : {}),
  });
  if (error) return fail(error, 'reviewLeave');
  refresh(`${BASE}/approvals`);
  return { ok: true };
}

/* ------------------------------------------------------------------ */
/* Timesheets                                                          */
/* ------------------------------------------------------------------ */

export async function buildTimesheet(assignmentId: string, from: string, to: string): Res<{ id: string }> {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(assignmentId)) return bad('Assignment not found.');
  if (!DATE_RE.test(from) || !DATE_RE.test(to)) return bad('Choose the period.');
  if (to < from) return bad('The period ends before it starts.');
  const { data, error } = await s.supabase.rpc('omelo_build_timesheet', {
    p_assignment: assignmentId,
    p_period_start: from,
    p_period_end: to,
  });
  if (error) return fail(error, 'buildTimesheet');
  refresh(`${BASE}/assignments/${assignmentId}`);
  return { ok: true, id: data };
}

export async function startTimesheetReview(id: string): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(id)) return bad('Timesheet not found.');
  const { error } = await s.supabase.rpc('omelo_start_timesheet_review', { p_timesheet: id });
  if (error) return fail(error, 'startTimesheetReview');
  refresh(`${BASE}/timesheets/${id}`);
  return { ok: true };
}

export async function reviewTimesheet(id: string, approve: boolean, reason: string): Res<{ earningId: string | null }> {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(id)) return bad('Timesheet not found.');
  const why = text(reason, 500);
  if (!approve && (!why || why.length < 3)) return bad('Say why the timesheet is returned — the worker is told.');
  const { data, error } = await s.supabase.rpc('omelo_review_timesheet', {
    p_timesheet: id,
    p_approve: approve,
    ...(why ? { p_reason: why } : {}),
  });
  if (error) return fail(error, 'reviewTimesheet');
  refresh(`${BASE}/timesheets/${id}`, `${BASE}/approvals`, `${BASE}/pay`);
  const d = data && typeof data === 'object' && !Array.isArray(data) ? (data as Record<string, Json>) : {};
  return { ok: true, earningId: typeof d.earning_id === 'string' ? d.earning_id : null };
}

export async function reopenTimesheet(id: string, reason: string): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(id)) return bad('Timesheet not found.');
  const why = text(reason, 500);
  if (!why || why.length < 5) return bad('A reopening needs a reason (at least 5 characters).');
  const { error } = await s.supabase.rpc('omelo_reopen_timesheet', { p_timesheet: id, p_reason: why });
  if (error) return fail(error, 'reopenTimesheet');
  refresh(`${BASE}/timesheets/${id}`, `${BASE}/pay`);
  return { ok: true };
}

/* ------------------------------------------------------------------ */
/* Earnings, payments, billing                                         */
/* ------------------------------------------------------------------ */

export async function approveEarnings(id: string): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(id)) return bad('Not found.');
  const { error } = await s.supabase.rpc('omelo_approve_earnings', { p_earning: id });
  if (error) return fail(error, 'approveEarnings');
  refresh(`${BASE}/pay`);
  return { ok: true };
}

export async function addEarningAdjustment(id: string, amount: string, reason: string): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(id)) return bad('Not found.');
  const a = numOrNull(amount);
  if (a == null || a === 0) return bad('Give an amount (use a minus sign to reduce).');
  const why = text(reason, 300);
  if (!why || why.length < 3) return bad('An adjustment needs a reason.');
  const { error } = await s.supabase.rpc('omelo_add_earning_adjustment', { p_earning: id, p_amount: a, p_reason: why });
  if (error) return fail(error, 'addEarningAdjustment');
  refresh(`${BASE}/pay`);
  return { ok: true };
}

export async function recordPayment(
  earningId: string,
  v: { amount: string; status: string; provider: string; reference: string; scheduledFor: string }
): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(earningId)) return bad('Not found.');
  const a = numOrNull(v.amount);
  if (a == null || a <= 0) return bad('The amount must be more than 0.');
  if (!['scheduled', 'processing', 'paid'].includes(v.status)) return bad('Choose scheduled, processing or paid.');
  if (v.scheduledFor && !DATE_RE.test(v.scheduledFor)) return bad('Dates look like 2026-09-30.');
  const provider = text(v.provider, 60);
  const ref = text(v.reference, 120);
  const { error } = await s.supabase.rpc('omelo_record_payment', {
    p_earning: earningId,
    p_amount: a,
    p_status: v.status,
    ...(provider ? { p_provider: provider } : {}),
    ...(ref ? { p_reference: ref } : {}),
    ...(v.scheduledFor ? { p_scheduled_for: v.scheduledFor } : {}),
  });
  if (error) return fail(error, 'recordPayment');
  refresh(`${BASE}/pay`);
  return { ok: true };
}

export async function updatePayment(paymentId: string, status: string, reference: string, failureReason: string): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(paymentId)) return bad('Not found.');
  if (!['processing', 'paid', 'failed', 'reversed'].includes(status)) return bad('Choose a status.');
  const ref = text(reference, 120);
  const why = text(failureReason, 300);
  if (status === 'failed' && !why) return bad('Say why the payment failed.');
  const { error } = await s.supabase.rpc('omelo_update_payment', {
    p_payment: paymentId,
    p_status: status,
    ...(ref ? { p_reference: ref } : {}),
    ...(why ? { p_failure_reason: why } : {}),
  });
  if (error) return fail(error, 'updatePayment');
  refresh(`${BASE}/pay`);
  return { ok: true };
}

export async function updateBillingStatus(id: string, status: string): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(id)) return bad('Not found.');
  if (!['invoiced', 'paid', 'void'].includes(status)) return bad('Choose a status.');
  const { error } = await s.supabase.rpc('omelo_update_billing_status', { p_billing: id, p_status: status });
  if (error) return fail(error, 'updateBillingStatus');
  refresh(`${BASE}/pay`);
  return { ok: true };
}

/* ------------------------------------------------------------------ */
/* Bulk jobs                                                           */
/* ------------------------------------------------------------------ */

export async function startBulkGenerate(templateId: string, from: string, to: string): Res<{ jobId: string }> {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(templateId)) return bad('Template not found.');
  if (!DATE_RE.test(from) || !DATE_RE.test(to) || to < from) return bad('Choose a date range.');
  const { data, error } = await s.supabase.rpc('omelo_start_workforce_job', {
    p_company: s.ctx.companyId,
    p_kind: 'generate_shifts',
    p_payload: { template_id: templateId, from, to },
  });
  if (error) return fail(error, 'startBulkGenerate');
  refresh(`${BASE}/bulk`);
  return { ok: true, jobId: data };
}

export async function cancelWorkforceJob(id: string): Res {
  const s = await session();
  if (!s) return bad(SIGNED_OUT);
  if (!isId(id)) return bad('Not found.');
  const { error } = await s.supabase.rpc('omelo_cancel_workforce_job', { p_job: id });
  if (error) return fail(error, 'cancelWorkforceJob');
  refresh(`${BASE}/bulk`);
  return { ok: true };
}
