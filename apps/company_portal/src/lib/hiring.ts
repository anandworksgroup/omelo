/**
 * Shared vocabulary for the employer hiring loop.
 *
 * The database owns every transition (omelo_move_application & co). This file
 * only decides what the portal OFFERS and how it words things, so a button
 * that would be refused by the RPC is never shown in the first place.
 */

import type { Database } from '@/lib/supabase/database.types';

export type ApplicationState = Database['public']['Enums']['application_state'];
export type InterviewType = Database['public']['Enums']['interview_type'];
export type InterviewStatus = Database['public']['Enums']['interview_status'];
export type OfferStatus = Database['public']['Enums']['offer_status'];
export type PayPeriod = Database['public']['Enums']['pay_period'];

/* ------------------------------------------------------------------ */
/* State groups                                                        */
/* ------------------------------------------------------------------ */

export const PRE_OFFER_STATES: ApplicationState[] = [
  'applied',
  'viewed',
  'shortlisted',
  'screening',
  'assessment',
  'interview',
];

export const OPEN_STATES: ApplicationState[] = [...PRE_OFFER_STATES, 'offer'];

export const CLOSED_STATES: ApplicationState[] = [
  'hired',
  'rejected',
  'withdrawn',
  'expired',
  'declined_by_candidate',
];

export const PIPELINE_TABS = [
  { key: 'all', label: 'All', states: null },
  { key: 'new', label: 'New', states: ['applied'] },
  { key: 'reviewing', label: 'Reviewing', states: ['viewed', 'screening', 'assessment'] },
  { key: 'shortlisted', label: 'Shortlisted', states: ['shortlisted'] },
  { key: 'interview', label: 'Interview', states: ['interview'] },
  { key: 'offer', label: 'Offer', states: ['offer'] },
  { key: 'hired', label: 'Hired', states: ['hired'] },
  { key: 'closed', label: 'Closed', states: ['rejected', 'withdrawn', 'declined_by_candidate', 'expired'] },
] as const satisfies readonly {
  key: string;
  label: string;
  states: readonly ApplicationState[] | null;
}[];

export type PipelineTabKey = (typeof PIPELINE_TABS)[number]['key'];

/** Badge colour for a state: green = good outcome, amber = needs action, grey otherwise. */
export function stateTone(state: string): 'good' | 'warn' | 'bad' | 'neutral' {
  if (state === 'hired' || state === 'offer') return 'good';
  if (state === 'applied') return 'warn';
  if (state === 'rejected' || state === 'withdrawn' || state === 'expired' || state === 'declined_by_candidate')
    return 'bad';
  return 'neutral';
}

export const TONE_COLOR = {
  good: 'var(--color-verified)',
  warn: 'var(--color-warn)',
  bad: 'var(--color-danger)',
  neutral: 'var(--muted)',
} as const;

/* ------------------------------------------------------------------ */
/* Labels                                                              */
/* ------------------------------------------------------------------ */

export const INTERVIEW_TYPE_LABEL: Record<InterviewType, string> = {
  phone: 'Phone call',
  video: 'Video call',
  in_person: 'In person',
  group: 'Group interview',
  walk_in: 'Walk-in',
  trial_shift: 'Trial shift',
  practical_test: 'Practical test',
  assessment_centre: 'Assessment centre',
  panel: 'Panel interview',
};

export const INTERVIEW_STATUS_LABEL: Record<InterviewStatus, string> = {
  scheduled: 'Scheduled',
  rescheduled: 'Rescheduled',
  completed: 'Completed',
  cancelled: 'Cancelled',
  no_show_candidate: 'Candidate did not attend',
  no_show_employer: 'Missed by your team',
};

export const OFFER_STATUS_LABEL: Record<OfferStatus, string> = {
  draft: 'Draft',
  sent: 'Sent — awaiting reply',
  viewed: 'Seen by candidate',
  negotiating: 'Negotiating',
  accepted: 'Accepted',
  declined: 'Declined',
  withdrawn: 'Withdrawn',
  expired: 'Expired',
};

export const OPEN_OFFER_STATUSES: OfferStatus[] = ['sent', 'viewed', 'negotiating'];

export const PAY_PERIODS: { value: PayPeriod; label: string }[] = [
  { value: 'hour', label: 'per hour' },
  { value: 'day', label: 'per day' },
  { value: 'week', label: 'per week' },
  { value: 'fortnight', label: 'per fortnight' },
  { value: 'month', label: 'per month' },
  { value: 'year', label: 'per year' },
  { value: 'per_task', label: 'per task' },
];

export const PROFICIENCY_LABEL: Record<string, string> = {
  beginner: 'Beginner',
  basic: 'Basic',
  intermediate: 'Intermediate',
  advanced: 'Advanced',
  expert: 'Expert',
  conversational: 'Conversational',
  professional: 'Professional',
  fluent: 'Fluent',
  native: 'Native',
};

/**
 * Rejection reasons are shown to the worker, word for word. Keep them kind,
 * specific enough to be useful, and never about the person.
 */
export const REJECTION_REASONS = [
  'Position has been filled',
  'Looking for more experience in this role',
  'Location is too far for this role',
  "Schedule or shift doesn't match",
  "Skills don't match this role right now",
];

export const RECOMMENDATIONS = [
  { value: 'strong_yes', label: 'Strong yes' },
  { value: 'yes', label: 'Yes' },
  { value: 'no', label: 'No' },
  { value: 'strong_no', label: 'Strong no' },
] as const;

/* ------------------------------------------------------------------ */
/* Match explanation (matches.feature_vector, engine v1.0)            */
/* ------------------------------------------------------------------ */

export type MatchReason = { factor: string; weight: number; text: string };

export type FeatureVector = {
  score?: number;
  eligible?: boolean;
  gate_failures?: string[];
  gates?: Record<string, string>;
  weight_profile?: string;
  missing_skills?: (string | { name?: string; skill?: string })[];
  strengths?: MatchReason[];
  gaps?: MatchReason[];
  unknowns?: MatchReason[];
};

export const GATE_LABEL: Record<string, string> = {
  job_open: 'Job is not open',
  required_licence: 'Missing a required licence',
  work_authorization: 'Not authorised to work in this location',
};

export function gateLabel(g: string) {
  return GATE_LABEL[g] ?? g.replace(/_/g, ' ');
}

export function skillName(s: string | { name?: string; skill?: string }) {
  return typeof s === 'string' ? s : (s.name ?? s.skill ?? '');
}

/* ------------------------------------------------------------------ */
/* Timeline                                                            */
/* ------------------------------------------------------------------ */

export type TimelineEvent = {
  id: number;
  event_type: string;
  actor_type: string;
  actor_id: string | null;
  from_state: string | null;
  to_state: string | null;
  reason: string | null;
  metadata: unknown;
  occurred_at: string;
};

export type TimelineItem = {
  id: number;
  at: string;
  title: string;
  detail?: string | null;
  tone: 'good' | 'warn' | 'bad' | 'neutral';
};

const STAGE_MOVE_LABEL: Record<string, string> = {
  viewed: 'Moved back to reviewing',
  shortlisted: 'Shortlisted',
  screening: 'Moved to phone screen',
  assessment: 'Moved to assessment',
  interview: 'Moved to interview',
};

/**
 * Turns raw application_events into sentences an employer can read.
 *
 * Several RPCs write two events for one action (the state trigger plus the
 * RPC's own richer row), so near-duplicates within a few seconds are folded.
 */
export function describeTimeline(
  events: TimelineEvent[],
  currentUserId: string | null
): TimelineItem[] {
  const sorted = [...events].sort(
    (a, b) => new Date(a.occurred_at).getTime() - new Date(b.occurred_at).getTime() || a.id - b.id
  );
  const near = (a: TimelineEvent, b: TimelineEvent) =>
    Math.abs(new Date(a.occurred_at).getTime() - new Date(b.occurred_at).getTime()) < 5_000;

  const out: TimelineItem[] = [];
  let viewedShown = false;
  const who = (e: TimelineEvent) =>
    e.actor_type === 'candidate'
      ? 'the candidate'
      : e.actor_id && e.actor_id === currentUserId
        ? 'you'
        : 'your team';

  for (const e of sorted) {
    const m = (e.metadata ?? {}) as Record<string, unknown>;
    const base = { id: e.id, at: e.occurred_at };

    switch (e.event_type) {
      case 'created':
        out.push({ ...base, title: 'Applied', tone: 'neutral' });
        break;

      case 'viewed':
        if (viewedShown) break;
        viewedShown = true;
        out.push({
          ...base,
          title: who(e) === 'you' ? 'You viewed the application' : 'Your team viewed the application',
          tone: 'neutral',
        });
        break;

      case 'shortlisted':
        out.push({ ...base, title: 'Shortlisted', tone: 'good' });
        break;

      case 'stage_changed': {
        const to = e.to_state ?? '';
        if (to === 'viewed') {
          // applied → viewed is the "viewed" signal, not a pipeline move.
          if (e.from_state === 'applied') {
            if (viewedShown) break;
            viewedShown = true;
            out.push({ ...base, title: 'Application viewed', tone: 'neutral' });
            break;
          }
        }
        if (
          to === 'interview' &&
          sorted.some((o) => o.event_type === 'interview_scheduled' && o.to_state === 'interview' && near(o, e))
        )
          break;
        // A move out of `offer` follows a withdrawn offer, which has its own line.
        if (e.from_state === 'offer') {
          out.push({ ...base, title: `Back to ${to.replace(/_/g, ' ')}`, tone: 'neutral' });
          break;
        }
        out.push({ ...base, title: STAGE_MOVE_LABEL[to] ?? `Moved to ${to.replace(/_/g, ' ')}`, tone: 'neutral' });
        break;
      }

      case 'interview_scheduled': {
        if (m.confirmed) {
          out.push({ ...base, title: 'Candidate confirmed the interview', tone: 'good' });
        } else if (m.rescheduled_from) {
          out.push({ ...base, title: 'Interview rescheduled', detail: e.reason, tone: 'warn' });
        } else {
          const type = INTERVIEW_TYPE_LABEL[m.type as InterviewType];
          out.push({
            ...base,
            title: 'Interview scheduled',
            detail: [type, m.round ? `round ${m.round}` : null].filter(Boolean).join(' · ') || null,
            tone: 'neutral',
          });
        }
        break;
      }

      case 'interview_completed': {
        const outcome = String(m.outcome ?? 'completed');
        if (outcome === 'cancelled') {
          out.push({
            ...base,
            title: e.actor_type === 'candidate' ? 'Candidate cancelled the interview' : 'Interview cancelled',
            detail: e.reason,
            tone: 'bad',
          });
        } else if (outcome === 'no_show_candidate') {
          out.push({ ...base, title: 'Candidate did not attend the interview', tone: 'bad' });
        } else if (outcome === 'no_show_employer') {
          out.push({ ...base, title: 'Interview missed by your team', tone: 'bad' });
        } else {
          out.push({ ...base, title: 'Interview completed', tone: 'good' });
        }
        break;
      }

      case 'offer_extended':
        out.push({ ...base, title: 'Offer sent', tone: 'good' });
        break;

      case 'offer_responded': {
        const status = String(m.status ?? '');
        if (status === 'accepted')
          out.push({ ...base, title: 'Candidate accepted the offer', tone: 'good' });
        else if (status === 'declined')
          out.push({ ...base, title: 'Candidate declined the offer', detail: e.reason, tone: 'bad' });
        else if (status === 'withdrawn')
          out.push({ ...base, title: 'Offer withdrawn', detail: e.reason, tone: 'bad' });
        else out.push({ ...base, title: 'Offer updated', tone: 'neutral' });
        break;
      }

      case 'decision_made':
        if (e.to_state === 'hired') out.push({ ...base, title: 'Hired', tone: 'good' });
        else if (e.to_state === 'rejected')
          out.push({ ...base, title: 'Not moving forward', detail: e.reason, tone: 'bad' });
        else if (e.to_state === 'declined_by_candidate') {
          if (sorted.some((o) => o.event_type === 'offer_responded' && near(o, e))) break;
          out.push({ ...base, title: 'Candidate declined', detail: e.reason, tone: 'bad' });
        } else out.push({ ...base, title: 'Decision recorded', tone: 'neutral' });
        break;

      case 'withdrawn':
        out.push({ ...base, title: 'Candidate withdrew their application', detail: e.reason, tone: 'bad' });
        break;

      case 'expired':
        out.push({ ...base, title: 'Application expired', tone: 'neutral' });
        break;

      case 'note_added':
        out.push({ ...base, title: 'Note added', tone: 'neutral' });
        break;

      case 'message_sent':
        out.push({ ...base, title: 'Message sent', tone: 'neutral' });
        break;

      default:
        out.push({ ...base, title: e.event_type.replace(/_/g, ' '), detail: e.reason, tone: 'neutral' });
    }
  }
  return out;
}

/* ------------------------------------------------------------------ */
/* Small formatting helpers                                            */
/* ------------------------------------------------------------------ */

export function monthsLabel(months: number | null | undefined) {
  if (!months) return null;
  if (months < 12) return `${months} month${months === 1 ? '' : 's'}`;
  const y = Math.floor(months / 12);
  const r = months % 12;
  return `${y} yr${y === 1 ? '' : 's'}${r ? ` ${r} mo` : ''}`;
}

export function monthYear(date: string | null) {
  if (!date) return '';
  return new Date(date + 'T00:00:00Z').toLocaleDateString('en-GB', {
    month: 'short',
    year: 'numeric',
    timeZone: 'UTC',
  });
}

/** A plain calendar date (e.g. start_date) — no timezone shift. */
export function calendarDate(date: string | null) {
  if (!date) return '—';
  return new Date(date.slice(0, 10) + 'T00:00:00Z').toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    timeZone: 'UTC',
  });
}

/**
 * "Now" for dynamic server components. They render once per request, so
 * reading the clock is intended; this keeps that decision in one place
 * rather than sprinkling Date.now() through render bodies.
 */
export function requestNow() {
  return Date.now();
}
