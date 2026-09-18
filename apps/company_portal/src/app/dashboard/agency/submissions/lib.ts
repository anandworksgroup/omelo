/**
 * Helpers shared by the agency submissions / interviews / offers /
 * placements / billing / analytics pages. Server-safe (no hooks); every read
 * runs as the signed-in user, so RLS and the agency-scoped RPCs decide what
 * comes back.
 */
import type { createClient } from '@/lib/supabase/server';
import { parseSubmissions, type SubmissionRow } from '@/lib/agency';
import { formatPay } from '@/lib/format';
import { OFFER_STATUS_LABEL, type OfferStatus } from '@/lib/hiring';

type Supabase = Awaited<ReturnType<typeof createClient>>;

export const BASE = '/dashboard/agency';

export async function loadSubmissions(
  supabase: Supabase,
  agencyId: string,
  jobOrderId?: string
): Promise<{ rows: SubmissionRow[]; error: string | null }> {
  const { data, error } = await supabase.rpc('omelo_agency_submissions', {
    p_agency: agencyId,
    ...(jobOrderId ? { p_job_order: jobOrderId } : {}),
  });
  return { rows: error ? [] : parseSubmissions(data), error: error?.message ?? null };
}

/** Statuses after which a submission can no longer move (DB trigger). */
export const CLOSED_SUBMISSION = ['hired', 'rejected', 'withdrawn'];
/** Statuses the agency may still withdraw from (omelo_withdraw_submission). */
export const WITHDRAWABLE = ['submitted', 'reviewing'];

/** Plain words for the outcomes an agency records for an off-platform client. */
export const OUTCOME_LABEL: Record<string, string> = {
  reviewing: 'The client is reviewing them',
  shortlisted: 'The client shortlisted them',
  interview: 'The client is interviewing them',
  offer: 'The client made an offer',
  hired: 'Hired — creates a placement',
  rejected: 'Not selected',
};

/** Plain words for a placement move. */
export const PLACEMENT_MOVE_LABEL: Record<string, string> = {
  active: 'They started work',
  completed: 'Completed (the guarantee period is over)',
  fell_through: 'Fell through',
};

export function offerLabel(status: string | null): string | null {
  if (!status) return null;
  return OFFER_STATUS_LABEL[status as OfferStatus] ?? status;
}

/** Money is never a bare number: amount and currency travel together. */
export function money(amount: number | null, currency: string | null): string {
  if (amount == null) return 'No fee set';
  return formatPay({ min: amount, currency: currency || 'INR' });
}

export function candidateLine(r: SubmissionRow) {
  return r.candidate.label ? `${r.candidate.name} · as ${r.candidate.label}` : r.candidate.name;
}

export function positionLine(r: { position: string | null; jobOrder: string | null; client: string | null }) {
  return [r.position ?? 'Position', r.jobOrder, r.client].filter(Boolean).join(' · ');
}

export function first(v: string | string[] | undefined): string | undefined {
  return Array.isArray(v) ? v[0] : v;
}

export type SearchParams = Promise<Record<string, string | string[] | undefined>>;

/** Percent of b in a, or null when there is nothing to divide by. */
export function rate(part: number, whole: number): number | null {
  return whole > 0 ? Math.round((part / whole) * 100) : null;
}
