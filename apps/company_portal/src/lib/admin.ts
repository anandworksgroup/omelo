import { cache } from 'react';
import { createClient } from '@/lib/supabase/server';
import { reportError } from '@/lib/observability';

/**
 * Platform-admin detection.
 *
 * The signed-in user cannot read platform_admins, so this asks the database
 * with the cheap omelo_am_i_platform_admin() check (migration 37). It only
 * decides what to SHOW — every admin RPC authorises for itself.
 *
 * cache() dedupes the call within one request (layout + nav).
 */
export const isPlatformAdmin = cache(async (): Promise<boolean> => {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('omelo_am_i_platform_admin');
  if (error) {
    reportError(error, { action: 'isPlatformAdmin' });
    return false;
  }
  return data === true;
});

export type SystemHealth = {
  window_hours: number;
  generated_at: string;
  edge_function_calls: { total: number; failed: number; last_error: string | null };
  email: { by_status: Record<string, number>; overdue_queued: number; failed_recent: number };
  meet: { rooms_live: number; sessions: number; joins: number; expired_unended: number; abuse_reports_open: number };
  trust_and_safety: { reports_open: number; fraud_signals: number };
  events: Record<string, number>;
  cron: {
    job: string;
    schedule: string;
    active: boolean;
    last_status: string | null;
    last_run: string | null;
    last_message: string | null;
  }[];
  accounts: { signups: number; deletions_pending: number };
};

export type Kpis = {
  window_days: number;
  definition: string;
  marketplace: {
    active_workers: number;
    active_employers: number;
    published_jobs: number;
    job_fill_rate: number | null;
  };
  funnel: { applied: number; shortlisted: number; interviewed: number; offered: number; hired: number };
  conversion: {
    apply_to_shortlist: number | null;
    shortlist_to_interview: number | null;
    interview_to_offer: number | null;
    offer_to_hire: number | null;
    apply_to_hire: number | null;
    offer_acceptance: number | null;
  };
  median_hours: {
    to_shortlist: number | null;
    to_interview: number | null;
    to_offer: number | null;
    to_hire: number | null;
  };
  workers: { email_verified: number; with_verified_employment: number };
};

/** 0.423 -> "42.3%"; null -> "—". */
export function pct(v: number | null | undefined): string {
  if (v === null || v === undefined || Number.isNaN(Number(v))) return '—';
  const n = Number(v) * 100;
  return `${n >= 10 || n === 0 ? Math.round(n) : n.toFixed(1)}%`;
}

/** 5.5 -> "5.5 h"; 50 -> "2.1 d"; null -> "—". */
export function hours(v: number | null | undefined): string {
  if (v === null || v === undefined) return '—';
  const n = Number(v);
  if (n < 48) return `${n.toFixed(n < 10 ? 1 : 0)} h`;
  return `${(n / 24).toFixed(1)} d`;
}

export function num(v: number | null | undefined): string {
  if (v === null || v === undefined) return '—';
  return Number(v).toLocaleString('en-IN');
}
