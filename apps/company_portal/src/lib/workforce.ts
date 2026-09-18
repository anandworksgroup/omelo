/**
 * Release 5 — Staffing & Workforce.
 *
 * Lifecycle: requirement -> assignment -> shift -> check-in/out -> attendance
 * -> timesheet -> approval -> earnings -> payment.
 *
 * Every rule lives in the database (RLS, SECURITY DEFINER functions and
 * integrity triggers). This module parses the jsonb those functions return —
 * defensively, so a missing key renders as empty rather than crashing — and
 * holds labels, the role table (only to hide or explain actions; the database
 * checks the same table on every call) and time-zone helpers.
 */
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database, Json } from '@/lib/supabase/database.types';

type Obj = Record<string, unknown>;
const isObj = (v: unknown): v is Obj => !!v && typeof v === 'object' && !Array.isArray(v);
const arr = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);
const str = (v: unknown): string | null => (typeof v === 'string' && v.trim() ? v : null);
const numOrNull = (v: unknown): number | null => {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
};
const num = (v: unknown): number => numOrNull(v) ?? 0;

/* ------------------------------------------------------------------ */
/* Roles                                                               */
/* ------------------------------------------------------------------ */

/** Mirror of omelo_private.omelo_workforce_roles(kind, action). */
export const WORKFORCE_ROLES = {
  employer: {
    manage_workforce: ['owner', 'admin', 'recruiter', 'hiring_manager', 'hr'],
    approve_time: ['owner', 'admin', 'hiring_manager', 'hr'],
    manage_pay: ['owner', 'admin', 'finance', 'hr'],
    view: ['owner', 'admin', 'recruiter', 'hiring_manager', 'interviewer', 'hr', 'finance', 'viewer'],
  },
  agency: {
    manage_workforce: ['owner', 'admin', 'recruiter', 'coordinator'],
    approve_time: ['owner', 'admin', 'coordinator'],
    manage_pay: ['owner', 'admin', 'finance', 'coordinator'],
    view: ['owner', 'admin', 'recruiter', 'sourcer', 'coordinator', 'finance', 'viewer'],
  },
} as const;

export type WorkforceAction = keyof (typeof WORKFORCE_ROLES)['employer'];

export function wfCan(ctx: { kind: 'employer' | 'agency'; roles: readonly string[] }, action: WorkforceAction): boolean {
  const allowed = WORKFORCE_ROLES[ctx.kind][action] as readonly string[];
  return ctx.roles.some((r) => allowed.includes(r));
}

const ROLE_WORD: Record<string, string> = {
  owner: 'owners',
  admin: 'admins',
  recruiter: 'recruiters',
  hiring_manager: 'hiring managers',
  hr: 'HR',
  coordinator: 'coordinators',
  finance: 'finance',
  sourcer: 'sourcers',
  interviewer: 'interviewers',
  viewer: 'viewers',
};

/** "Only owners, admins and coordinators can approve time." */
export function onlyWf(kind: 'employer' | 'agency', action: WorkforceAction, what: string): string {
  const names = (WORKFORCE_ROLES[kind][action] as readonly string[]).map((r) => ROLE_WORD[r] ?? r);
  const list = names.length === 1 ? names[0] : `${names.slice(0, -1).join(', ')} and ${names.at(-1)}`;
  return `Only ${list} can ${what}.`;
}

/* ------------------------------------------------------------------ */
/* Labels                                                              */
/* ------------------------------------------------------------------ */

export type Tone = { label: string; color: string };
const C = {
  brand: 'var(--color-brand-600)',
  good: 'var(--color-verified)',
  warn: 'var(--color-warn)',
  bad: 'var(--color-danger)',
  muted: 'var(--muted)',
};
const tone = (map: Record<string, Tone>) => (s: string | null | undefined): Tone =>
  map[s ?? ''] ?? { label: (s ?? '—').replace(/_/g, ' '), color: C.muted };

export const REQUIREMENT_STATUSES = ['draft', 'open', 'filled', 'active', 'completed', 'cancelled'] as const;
export const requirementTone = tone({
  draft: { label: 'Draft', color: C.muted },
  open: { label: 'Open', color: C.good },
  filled: { label: 'Filled', color: C.brand },
  active: { label: 'Active', color: C.good },
  completed: { label: 'Completed', color: C.muted },
  cancelled: { label: 'Cancelled', color: C.bad },
});

export const ASSIGNMENT_STATUSES = [
  'offered',
  'accepted',
  'active',
  'paused',
  'completed',
  'declined',
  'cancelled',
  'terminated',
] as const;
export const assignmentTone = tone({
  draft: { label: 'Draft', color: C.muted },
  offered: { label: 'Offered', color: C.brand },
  accepted: { label: 'Accepted', color: C.good },
  active: { label: 'Working', color: C.good },
  paused: { label: 'Paused', color: C.warn },
  completed: { label: 'Completed', color: C.muted },
  declined: { label: 'Declined', color: C.bad },
  cancelled: { label: 'Cancelled', color: C.muted },
  terminated: { label: 'Terminated', color: C.bad },
});
/** The moves omelo_set_assignment_status (and the trigger) allow a manager. */
export const ASSIGNMENT_NEXT: Record<string, string[]> = {
  offered: ['cancelled'],
  accepted: ['active', 'cancelled'],
  active: ['paused', 'completed', 'terminated'],
  paused: ['active', 'completed', 'terminated'],
};
export const ASSIGNMENT_ACTION_LABEL: Record<string, string> = {
  active: 'Start / resume',
  paused: 'Pause',
  completed: 'Complete',
  terminated: 'Terminate',
  cancelled: 'Cancel',
};

export const shiftTone = tone({
  scheduled: { label: 'Scheduled', color: C.brand },
  in_progress: { label: 'In progress', color: C.good },
  completed: { label: 'Completed', color: C.muted },
  cancelled: { label: 'Cancelled', color: C.bad },
});
export const shiftWorkerTone = tone({
  offered: { label: 'Offered', color: C.brand },
  assigned: { label: 'Assigned', color: C.good },
  declined: { label: 'Declined', color: C.muted },
  cancelled: { label: 'Removed', color: C.muted },
  on_leave: { label: 'On leave', color: C.warn },
  completed: { label: 'Completed', color: C.good },
  absent: { label: 'Absent', color: C.bad },
});
export const attendanceTone = tone({
  checked_in: { label: 'Checked in', color: C.brand },
  present: { label: 'Present', color: C.good },
  late: { label: 'Late', color: C.warn },
  absent: { label: 'Absent', color: C.bad },
  partial: { label: 'Partial', color: C.warn },
  early_departure: { label: 'Left early', color: C.warn },
  approved_leave: { label: 'On leave', color: C.muted },
  unapproved_absence: { label: 'Unapproved absence', color: C.bad },
});
export const reviewTone = tone({
  none: { label: 'Not reviewed', color: C.muted },
  pending: { label: 'Needs review', color: C.warn },
  approved: { label: 'Approved', color: C.good },
  adjusted: { label: 'Adjusted', color: C.brand },
  rejected: { label: 'Rejected', color: C.bad },
});
export const EXCEPTION_LABEL: Record<string, string> = {
  late: 'Late arrival',
  early_departure: 'Left early',
  absent: 'No check-in',
  missing_check_out: 'No check-out',
  location_mismatch: 'Location mismatch',
  manual_correction: 'Manual correction',
};
export const timesheetTone = tone({
  draft: { label: 'Draft', color: C.muted },
  submitted: { label: 'Submitted', color: C.brand },
  under_review: { label: 'Under review', color: C.warn },
  approved: { label: 'Approved', color: C.good },
  rejected: { label: 'Returned', color: C.bad },
  locked: { label: 'Locked', color: C.muted },
});
export const earningTone = tone({
  calculated: { label: 'To approve', color: C.warn },
  approved: { label: 'Approved', color: C.good },
  scheduled: { label: 'Payment scheduled', color: C.brand },
  processing: { label: 'Processing', color: C.brand },
  paid: { label: 'Paid', color: C.good },
  failed: { label: 'Payment failed', color: C.bad },
  reversed: { label: 'Reversed', color: C.muted },
});
export const paymentTone = tone({
  scheduled: { label: 'Scheduled', color: C.brand },
  processing: { label: 'Processing', color: C.brand },
  paid: { label: 'Paid', color: C.good },
  failed: { label: 'Failed', color: C.bad },
  reversed: { label: 'Reversed', color: C.muted },
});
/** omelo_validate_payment's allowed moves. */
export const PAYMENT_NEXT: Record<string, string[]> = {
  scheduled: ['processing', 'paid', 'failed'],
  processing: ['paid', 'failed'],
  paid: ['reversed'],
};
export const billingTone = tone({
  draft: { label: 'Draft', color: C.muted },
  invoiced: { label: 'Invoiced', color: C.brand },
  paid: { label: 'Paid', color: C.good },
  void: { label: 'Void', color: C.bad },
});
export const BILLING_NEXT: Record<string, string[]> = { draft: ['invoiced', 'void'], invoiced: ['paid', 'void'] };
export const leaveTone = tone({
  requested: { label: 'Requested', color: C.warn },
  approved: { label: 'Approved', color: C.good },
  rejected: { label: 'Not approved', color: C.bad },
  cancelled: { label: 'Cancelled', color: C.muted },
});
export const jobTone = tone({
  queued: { label: 'Queued', color: C.muted },
  running: { label: 'Running', color: C.brand },
  succeeded: { label: 'Done', color: C.good },
  partial: { label: 'Done with errors', color: C.warn },
  failed: { label: 'Failed', color: C.bad },
  cancelled: { label: 'Cancelled', color: C.muted },
});
export const JOB_KIND_LABEL: Record<string, string> = {
  offer_assignments: 'Offer assignments',
  assign_shifts: 'Assign shifts',
  generate_shifts: 'Generate shifts',
};

export const EMPLOYMENT_TYPES = [
  'temporary',
  'permanent',
  'contract',
  'seasonal',
  'project',
  'gig',
  'freelance',
  'internship',
  'apprenticeship',
  'on_call',
] as const;
export const PAY_FREQUENCIES = ['daily', 'weekly', 'biweekly', 'semimonthly', 'monthly', 'per_shift', 'on_completion'] as const;
export const PAY_FREQUENCY_LABEL: Record<string, string> = {
  daily: 'Daily',
  weekly: 'Weekly',
  biweekly: 'Every two weeks',
  semimonthly: 'Twice a month',
  monthly: 'Monthly',
  per_shift: 'After each shift',
  on_completion: 'On completion',
};
export const CHECK_IN_METHODS = ['app', 'qr', 'geofence', 'employer'] as const;
export const CHECK_IN_LABEL: Record<string, string> = {
  app: 'In the app',
  qr: 'Supervisor’s code / QR',
  geofence: 'In the app, at the site (location)',
  employer: 'Supervisor records it',
};
export const SHIFT_KINDS = ['regular', 'overtime', 'emergency', 'split', 'on_call'] as const;
export const PAY_BASES = ['per_hour', 'per_shift', 'per_day', 'per_period'] as const;
export const PAY_BASIS_LABEL: Record<string, string> = {
  per_hour: 'per hour',
  per_shift: 'per shift',
  per_day: 'per day worked',
  per_period: 'per pay period',
};
export const COMPONENT_KINDS = ['allowance', 'bonus', 'deduction'] as const;
export const LEAVE_LABEL: Record<string, string> = {
  paid: 'Paid leave',
  unpaid: 'Unpaid leave',
  sick: 'Sick leave',
  personal: 'Personal leave',
  other: 'Other leave',
};
export const DAY_LABEL = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

export const CURRENCIES = [
  'INR', 'USD', 'EUR', 'GBP', 'AED', 'SAR', 'QAR', 'KWD', 'OMR', 'BHD', 'SGD', 'MYR', 'AUD', 'NZD', 'CAD',
  'JPY', 'CNY', 'HKD', 'PHP', 'IDR', 'THB', 'VND', 'BDT', 'LKR', 'NPR', 'PKR', 'ZAR', 'NGN', 'KES', 'EGP',
  'BRL', 'MXN', 'CHF', 'SEK', 'NOK', 'DKK', 'PLN', 'TRY',
];

export const nice = (s: string | null | undefined) => (s ? s.charAt(0).toUpperCase() + s.slice(1).replace(/_/g, ' ') : '—');

/* ------------------------------------------------------------------ */
/* Money, minutes                                                      */
/* ------------------------------------------------------------------ */

export function money(amount: number | string | null | undefined, currency: string | null | undefined): string {
  const n = numOrNull(amount);
  if (n == null) return '—';
  const cur = (currency ?? '').trim().toUpperCase() || 'INR';
  try {
    return new Intl.NumberFormat(cur === 'INR' ? 'en-IN' : 'en-US', {
      style: 'currency',
      currency: cur,
      maximumFractionDigits: 2,
    }).format(n);
  } catch {
    return `${cur} ${n.toFixed(2)}`;
  }
}

const PERIOD_WORD: Record<string, string> = {
  hour: 'hour',
  day: 'day',
  week: 'week',
  fortnight: 'fortnight',
  month: 'month',
  year: 'year',
  per_task: 'task',
};
export function rate(amount: number | string | null | undefined, currency: string | null | undefined, period: string | null | undefined) {
  if (numOrNull(amount) == null) return 'Not set';
  return `${money(amount, currency)}${period ? ` / ${PERIOD_WORD[period] ?? period}` : ''}`;
}

export function hours(minutes: number | null | undefined): string {
  if (minutes == null) return '—';
  const h = Math.floor(minutes / 60);
  const m = Math.round(minutes % 60);
  return m ? `${h} h ${m} min` : `${h} h`;
}

/* ------------------------------------------------------------------ */
/* Time zones                                                          */
/* ------------------------------------------------------------------ */

/** Offset (ms) of `tz` from UTC at instant `t`. */
function tzOffset(t: number, tz: string): number {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    hourCycle: 'h23',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  }).formatToParts(new Date(t));
  const get = (k: string) => Number(parts.find((p) => p.type === k)?.value ?? 0);
  const asUtc = Date.UTC(get('year'), get('month') - 1, get('day'), get('hour') % 24, get('minute'), get('second'));
  return asUtc - Math.floor(t / 1000) * 1000;
}

export function validTimeZone(tz: string | null | undefined): tz is string {
  if (!tz) return false;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

/** "2026-09-20T22:00" read as wall-clock time in `tz` -> UTC ISO string. */
export function zonedToUtc(local: string, tz: string): string | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})/.exec(local.trim());
  if (!m || !validTimeZone(tz)) return null;
  const guess = Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]);
  let t = guess - tzOffset(guess, tz);
  t = guess - tzOffset(t, tz);
  return new Date(t).toISOString();
}

/** UTC ISO -> "YYYY-MM-DDTHH:mm" wall-clock in `tz` (for datetime-local inputs). */
export function utcToZonedInput(iso: string | null | undefined, tz: string): string {
  if (!iso) return '';
  const t = new Date(iso).getTime();
  if (!Number.isFinite(t) || !validTimeZone(tz)) return '';
  return new Date(t + tzOffset(t, tz)).toISOString().slice(0, 16);
}

/** The calendar date (YYYY-MM-DD) of an instant in `tz`. */
export function zonedDate(iso: string | number | Date, tz: string): string {
  const t = new Date(iso).getTime();
  return new Date(t + tzOffset(t, validTimeZone(tz) ? tz : 'UTC')).toISOString().slice(0, 10);
}

/** Server-safe formatting in a fixed zone (the site's), so it never mismatches on hydration. */
export function fmtIn(iso: string | null | undefined, tz: string, what: 'time' | 'date' | 'datetime' | 'day' = 'datetime') {
  if (!iso) return '—';
  const zone = validTimeZone(tz) ? tz : 'UTC';
  const opts: Intl.DateTimeFormatOptions =
    what === 'time'
      ? { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }
      : what === 'date'
        ? { day: 'numeric', month: 'short', year: 'numeric' }
        : what === 'day'
          ? { weekday: 'short', day: 'numeric', month: 'short' }
          : { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' };
  return new Date(iso).toLocaleString('en-GB', { ...opts, timeZone: zone });
}

export function tzShort(tz: string): string {
  return tz.replace(/_/g, ' ');
}

/** YYYY-MM-DD plus n days. */
export function addDays(date: string, n: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

/** The Monday of the ISO week containing `date`. */
export function mondayOf(date: string): string {
  const d = new Date(`${date}T00:00:00Z`);
  const dow = d.getUTCDay() || 7;
  return addDays(date, 1 - dow);
}

export const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

/* ------------------------------------------------------------------ */
/* RPC read models                                                     */
/* ------------------------------------------------------------------ */

export type WorkforceDashboard = {
  activeWorkers: number;
  todaysShifts: number;
  present: number;
  absent: number;
  openPositions: number;
  pendingApprovals: number;
  timesheets: number;
  offersPending: number;
  earningsToApprove: number;
  agency: {
    clients: number;
    activeJobOrders: number;
    pendingConsents: number;
    submissions: number;
    interviews: number;
    offers: number;
    placements: number;
  } | null;
};

export function parseWorkforceDashboard(raw: Json | null): WorkforceDashboard {
  const d = isObj(raw) ? raw : {};
  return {
    activeWorkers: num(d.active_workers),
    todaysShifts: num(d.todays_shifts),
    present: num(d.present),
    absent: num(d.absent),
    openPositions: num(d.open_positions),
    pendingApprovals: num(d.pending_approvals),
    timesheets: num(d.timesheets),
    offersPending: num(d.offers_pending),
    earningsToApprove: num(d.earnings_to_approve),
    agency:
      'placements' in d || 'clients' in d
        ? {
            clients: num(d.clients),
            activeJobOrders: num(d.active_job_orders),
            pendingConsents: num(d.pending_consents),
            submissions: num(d.submissions),
            interviews: num(d.interviews),
            offers: num(d.offers),
            placements: num(d.placements),
          }
        : null,
  };
}

export type RosterException = { id: string; kind: string; minutes: number | null; status: string };
export type RosterWorker = {
  shiftWorkerId: string;
  assignmentId: string;
  personId: string;
  name: string;
  status: string;
  attendance: {
    id: string;
    checkInAt: string | null;
    checkOutAt: string | null;
    status: string;
    reviewStatus: string;
    workedMinutes: number | null;
    exceptions: RosterException[];
  } | null;
};
export type ShiftRow = {
  id: string;
  requirementId: string;
  companyId: string;
  templateId: string | null;
  startsAt: string;
  endsAt: string;
  timezone: string;
  breakMinutes: number;
  requiredWorkers: number;
  shiftType: string | null;
  kind: string;
  status: string;
  cancelReason: string | null;
  instructions: string | null;
  supervisorId: string | null;
  locationText: string | null;
};
export type Roster = { shift: ShiftRow | null; code: string | null; workers: RosterWorker[] };

export function parseShift(s: unknown): ShiftRow | null {
  if (!isObj(s) || !s.id) return null;
  return {
    id: String(s.id),
    requirementId: String(s.requirement_id ?? ''),
    companyId: String(s.company_id ?? ''),
    templateId: str(s.template_id),
    startsAt: String(s.starts_at ?? ''),
    endsAt: String(s.ends_at ?? ''),
    timezone: str(s.timezone) ?? 'UTC',
    breakMinutes: num(s.break_minutes),
    requiredWorkers: num(s.required_workers) || 1,
    shiftType: str(s.shift_type),
    kind: str(s.kind) ?? 'regular',
    status: str(s.status) ?? 'scheduled',
    cancelReason: str(s.cancel_reason),
    instructions: str(s.instructions),
    supervisorId: str(s.supervisor_id),
    locationText: str(s.location_text),
  };
}

export function parseRoster(raw: Json | null): Roster {
  const d = isObj(raw) ? raw : {};
  return {
    shift: parseShift(d.shift),
    code: str(d.code),
    workers: arr(d.workers)
      .filter(isObj)
      .map((w) => {
        const a = isObj(w.attendance) ? w.attendance : null;
        return {
          shiftWorkerId: String(w.shift_worker_id ?? ''),
          assignmentId: String(w.assignment_id ?? ''),
          personId: String(w.person_id ?? ''),
          name: str(w.name) ?? 'Worker',
          status: str(w.status) ?? 'assigned',
          attendance: a
            ? {
                id: String(a.id ?? ''),
                checkInAt: str(a.check_in_at),
                checkOutAt: str(a.check_out_at),
                status: str(a.status) ?? 'checked_in',
                reviewStatus: str(a.review_status) ?? 'none',
                workedMinutes: numOrNull(a.worked_minutes),
                exceptions: arr(a.exceptions)
                  .filter(isObj)
                  .map((x) => ({
                    id: String(x.id ?? ''),
                    kind: str(x.kind) ?? '',
                    minutes: numOrNull(x.minutes),
                    status: str(x.status) ?? 'pending',
                  })),
              }
            : null,
        };
      }),
  };
}

export type ReplacementCandidate = {
  assignmentId: string;
  name: string;
  title: string | null;
  status: string;
  minutesThisWeek: number;
  offered: boolean;
};
export type Replacements = {
  open: number;
  candidates: ReplacementCandidate[];
  external: { jobOrderId: string | null; jobId: string | null } | null;
};

export function parseReplacements(raw: Json | null): Replacements {
  const d = isObj(raw) ? raw : {};
  const ext = isObj(d.external_search) ? d.external_search : null;
  return {
    open: num(d.open),
    candidates: arr(d.candidates)
      .filter(isObj)
      .map((c) => ({
        assignmentId: String(c.assignment_id ?? ''),
        name: str(c.name) ?? 'Worker',
        title: str(c.title),
        status: str(c.status) ?? 'active',
        minutesThisWeek: num(c.minutes_this_week),
        offered: c.offered === true,
      })),
    external: ext ? { jobOrderId: str(ext.job_order_id), jobId: str(ext.job_id) } : null,
  };
}

export type ApprovalException = {
  attendanceId: string;
  exceptionId: string;
  kind: string;
  minutes: number | null;
  detail: string | null;
  worker: string;
  title: string | null;
  scheduledStart: string | null;
  checkInAt: string | null;
  checkOutAt: string | null;
};
export type ApprovalTimesheet = {
  timesheetId: string;
  worker: string;
  title: string | null;
  periodStart: string;
  periodEnd: string;
  totalMinutes: number;
  overtimeMinutes: number;
  status: string;
  submittedAt: string | null;
};
export type ApprovalLeave = {
  leaveId: string;
  worker: string;
  title: string | null;
  leaveType: string;
  label: string | null;
  startDate: string;
  endDate: string;
  reason: string | null;
};
export type Approvals = { exceptions: ApprovalException[]; timesheets: ApprovalTimesheet[]; leave: ApprovalLeave[] };

export function parseApprovals(raw: Json | null): Approvals {
  const d = isObj(raw) ? raw : {};
  return {
    exceptions: arr(d.exceptions)
      .filter(isObj)
      .map((x) => ({
        attendanceId: String(x.attendance_id ?? ''),
        exceptionId: String(x.exception_id ?? ''),
        kind: str(x.kind) ?? '',
        minutes: numOrNull(x.minutes),
        detail: str(x.detail),
        worker: str(x.worker) ?? 'Worker',
        title: str(x.title),
        scheduledStart: str(x.scheduled_start),
        checkInAt: str(x.check_in_at),
        checkOutAt: str(x.check_out_at),
      })),
    timesheets: arr(d.timesheets)
      .filter(isObj)
      .map((x) => ({
        timesheetId: String(x.timesheet_id ?? ''),
        worker: str(x.worker) ?? 'Worker',
        title: str(x.title),
        periodStart: String(x.period_start ?? ''),
        periodEnd: String(x.period_end ?? ''),
        totalMinutes: num(x.total_minutes),
        overtimeMinutes: num(x.overtime_minutes),
        status: str(x.status) ?? 'submitted',
        submittedAt: str(x.submitted_at),
      })),
    leave: arr(d.leave)
      .filter(isObj)
      .map((x) => ({
        leaveId: String(x.leave_id ?? ''),
        worker: str(x.worker) ?? 'Worker',
        title: str(x.title),
        leaveType: str(x.leave_type) ?? 'other',
        label: str(x.label),
        startDate: String(x.start_date ?? ''),
        endDate: String(x.end_date ?? ''),
        reason: str(x.reason),
      })),
  };
}

export type ClientWorker = {
  assignmentId: string;
  worker: string;
  identityLabel: string | null;
  title: string | null;
  status: string;
  startDate: string | null;
  endDate: string | null;
  agency: string | null;
  nextShift: string | null;
};

export function parseClientWorkforce(raw: Json | null): ClientWorker[] {
  return arr(raw)
    .filter(isObj)
    .map((x) => ({
      assignmentId: String(x.assignment_id ?? ''),
      worker: str(x.worker) ?? 'Worker',
      identityLabel: str(x.identity_label),
      title: str(x.title),
      status: str(x.status) ?? 'active',
      startDate: str(x.start_date),
      endDate: str(x.end_date),
      agency: str(x.agency),
      nextShift: str(x.next_shift),
    }));
}

export type JobError = { item: number | null; error: string };
export function parseJobErrors(raw: Json | null): JobError[] {
  return arr(raw)
    .filter(isObj)
    .map((x) => ({ item: numOrNull(x.item), error: str(x.error) ?? 'Failed' }));
}

/** Agreement snapshot shown to the worker when offered. */
export type Agreement = {
  employer: string | null;
  client: string | null;
  location: string | null;
  hoursPerWeek: number | null;
  checkIn: string | null;
  supervisor: string | null;
  shifts: { name: string; days: number[]; start: string; end: string; breakMinutes: number }[];
  allowances: { kind: string; name: string; amount: number; basis: string }[];
  overtime: { name: string; multiplier: number; daily: number | null; weekly: number | null } | null;
};
export function parseAgreement(raw: Json | null): Agreement {
  const d = isObj(raw) ? raw : {};
  const ot = isObj(d.overtime) ? d.overtime : null;
  return {
    employer: str(d.employer),
    client: str(d.client),
    location: str(d.location),
    hoursPerWeek: numOrNull(d.hours_per_week),
    checkIn: str(d.check_in),
    supervisor: str(d.supervisor),
    shifts: arr(d.shifts)
      .filter(isObj)
      .map((s) => ({
        name: str(s.name) ?? 'Shift',
        days: arr(s.days).map(Number).filter((n) => n >= 1 && n <= 7),
        start: String(s.start ?? '').slice(0, 5),
        end: String(s.end ?? '').slice(0, 5),
        breakMinutes: num(s.break_minutes),
      })),
    allowances: arr(d.allowances)
      .filter(isObj)
      .map((a) => ({ kind: str(a.kind) ?? 'allowance', name: str(a.name) ?? '', amount: num(a.amount), basis: str(a.basis) ?? '' })),
    overtime: ot
      ? {
          name: str(ot.name) ?? 'Overtime',
          multiplier: num(ot.multiplier),
          daily: numOrNull(ot.daily_threshold_minutes),
          weekly: numOrNull(ot.weekly_threshold_minutes),
        }
      : null,
  };
}

export const daysText = (days: number[]) => days.map((d) => DAY_LABEL[d] ?? d).join(', ');

/** Split a list into groups of `size` (for `.in()` filters that travel in the URL). */
export function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

/* ------------------------------------------------------------------ */
/* Worker names                                                        */
/* ------------------------------------------------------------------ */

/**
 * Names for workers, with only what RLS already lets this user read:
 * persons rows (applicants, consented or public people), the agency's own
 * consented candidates, then the work identity label. Never widens access.
 */
export async function loadWorkerNames(
  supabase: SupabaseClient<Database>,
  ctx: { companyId: string; kind: 'employer' | 'agency' },
  people: { personId: string; identityId: string | null }[]
): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  const personIds = [...new Set(people.map((p) => p.personId).filter(Boolean))];
  if (personIds.length === 0) return out;
  // Chunked: hundreds of ids in one ?id=in.(...) would overflow the URL.
  const results = await Promise.all(
    chunk(personIds.slice(0, 1000), 150).map((ids) => supabase.from('persons').select('id, display_name').in('id', ids))
  );
  for (const r of results) for (const p of r.data ?? []) if (p.display_name) out.set(p.id, p.display_name);
  const missing = people.filter((p) => !out.has(p.personId));
  if (missing.length && ctx.kind === 'agency') {
    const { data: cand } = await supabase.rpc('omelo_agency_candidates', { p_agency: ctx.companyId });
    const byIdentity = new Map<string, string>();
    for (const c of arr(cand)) {
      if (!isObj(c) || !isObj(c.candidate)) continue;
      const wi = str(c.candidate.work_identity_id);
      const nm = str(c.candidate.name);
      if (wi && nm) byIdentity.set(wi, nm);
    }
    for (const p of missing) if (p.identityId && byIdentity.has(p.identityId)) out.set(p.personId, byIdentity.get(p.identityId)!);
  }
  return out;
}
