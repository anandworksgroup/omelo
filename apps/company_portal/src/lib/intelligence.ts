/**
 * Release 7 — Hiring intelligence, employer side.
 *
 * omelo_job_intelligence, omelo_company_intelligence and omelo_market_insights
 * return jsonb. These helpers parse them defensively: a missing number stays
 * null (shown as "—" or "Not enough data"), never a made-up zero, and a
 * missing object never crashes a page. The database computes every figure;
 * nothing here estimates or fills in data.
 */
import type { Json } from '@/lib/supabase/database.types';

type Obj = Record<string, unknown>;
const isObj = (v: unknown): v is Obj => !!v && typeof v === 'object' && !Array.isArray(v);
const arr = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);
const str = (v: unknown): string | null => (typeof v === 'string' && v.trim() ? v : null);
const numOrNull = (v: unknown): number | null => {
  if (v === null || v === undefined || v === '' || typeof v === 'boolean') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
};
/** Counts: absent means zero only where the RPC always sends a count. */
const count = (v: unknown): number => numOrNull(v) ?? 0;

/* ------------------------------------------------------------------ */
/* Labels and tones                                                    */
/* ------------------------------------------------------------------ */

export const DIFFICULTY = ['easy', 'moderate', 'hard', 'very_hard'] as const;
export type Difficulty = (typeof DIFFICULTY)[number];

export const DIFFICULTY_LABEL: Record<Difficulty, string> = {
  easy: 'Easy',
  moderate: 'Moderate',
  hard: 'Hard',
  very_hard: 'Very hard',
};

export const DIFFICULTY_COLOR: Record<Difficulty, string> = {
  easy: 'var(--color-verified)',
  moderate: 'var(--color-brand-600)',
  hard: 'var(--color-warn)',
  very_hard: 'var(--color-danger)',
};

export const BOTTLENECKS = [
  'supply',
  'compensation',
  'attraction',
  'reach',
  'screening',
  'requirements',
  'interview_scheduling',
  'selection',
  'offer_acceptance',
  'filled',
  'none',
] as const;
export type Bottleneck = (typeof BOTTLENECKS)[number];

export const BOTTLENECK_LABEL: Record<Bottleneck, string> = {
  supply: 'Worker supply',
  compensation: 'Pay',
  attraction: 'Attraction',
  reach: 'Reach',
  screening: 'Screening',
  requirements: 'Requirements',
  interview_scheduling: 'Interview scheduling',
  selection: 'Selection',
  offer_acceptance: 'Offer acceptance',
  filled: 'Filled',
  none: 'No clear bottleneck',
};

/** Which card on the insights page each bottleneck points at. */
export const BOTTLENECK_CARD: Record<Bottleneck, ChainCard | null> = {
  supply: 'supply',
  compensation: 'compensation',
  attraction: 'applications',
  reach: 'applications',
  screening: 'applications',
  requirements: 'match',
  interview_scheduling: 'interviews',
  selection: 'interviews',
  offer_acceptance: 'offers',
  filled: null,
  none: null,
};

export type ChainCard = 'job' | 'supply' | 'compensation' | 'match' | 'applications' | 'interviews' | 'offers';

export const PAY_POSITIONS = ['below_market', 'at_market', 'above_market', 'unknown', 'not_disclosed'] as const;
export type PayPosition = (typeof PAY_POSITIONS)[number];

export const PAY_POSITION_LABEL: Record<PayPosition, string> = {
  below_market: 'Below market',
  at_market: 'At market',
  above_market: 'Above market',
  unknown: 'Not enough data to compare',
  not_disclosed: 'Pay not shown',
};

export const PAY_POSITION_COLOR: Record<PayPosition, string> = {
  below_market: 'var(--color-warn)',
  at_market: 'var(--color-brand-600)',
  above_market: 'var(--color-verified)',
  unknown: 'var(--muted)',
  not_disclosed: 'var(--muted)',
};

const oneOf = <T extends string>(list: readonly T[], v: unknown): T | null =>
  list.find((x) => x === v) ?? null;

export const humanize = (s: string) => s.replace(/_/g, ' ').replace(/^\w/, (c) => c.toUpperCase());

/* ------------------------------------------------------------------ */
/* Job intelligence                                                    */
/* ------------------------------------------------------------------ */

export type Percentiles = { n: number; p25: number | null; median: number | null; p75: number | null };

function parsePercentiles(v: unknown): Percentiles | null {
  if (!isObj(v)) return null;
  const p = { n: count(v.n), p25: numOrNull(v.p25), median: numOrNull(v.median), p75: numOrNull(v.p75) };
  return p.median == null && p.p25 == null && p.p75 == null ? null : p;
}

export type JobIntelligence = {
  jobId: string;
  title: string;
  status: string | null;
  openings: number | null;
  openOpenings: number | null;
  supply: {
    workersInProfession: number | null;
    availableSoon: number | null;
    /** Null for remote jobs (distance does not apply). */
    within25Km: number | null;
    openToRelocating: number | null;
    competingJobs: number | null;
    workersPerOpening: number | null;
    workersPerCompetingJob: number | null;
  };
  compensation: {
    currency: string | null;
    jobMonthly: number | null;
    market: Percentiles | null;
    expectations: Percentiles | null;
    meetsMinimumPct: number | null;
    position: PayPosition;
    rateSource: string | null;
  };
  match: {
    scored: number;
    eligible: number;
    strong: number;
    buckets: { top: number; mid: number; low: number };
    missingSkills: { skill: string; candidates: number }[];
    gateFailures: { name: string; count: number }[];
  };
  applications: {
    impressions: number;
    applied: number;
    viewed: number;
    shortlisted: number;
    interviewed: number;
    offered: number;
    hired: number;
  };
  interviews: {
    scheduled: number;
    completed: number;
    cancelled: number;
    noShowCandidate: number;
    noShowEmployer: number;
    upcoming: number;
  };
  offers: {
    sent: number;
    accepted: number;
    declined: number;
    expired: number;
    withdrawn: number;
    declineReasons: string[];
  };
  timing: {
    daysOpen: number | null;
    hoursToFirstApplication: number | null;
    medianHoursToFirstView: number | null;
    unreviewed: number;
  };
  difficulty: { score: number | null; label: Difficulty | null };
  bottleneck: { stage: Bottleneck | null; explanation: string | null };
  recommendations: string[];
  computedAt: string | null;
  note: string | null;
};

export function parseJobIntelligence(raw: Json | null): JobIntelligence | null {
  if (!isObj(raw)) return null;
  const jobId = str(raw.job_id);
  if (!jobId) return null;
  const s = isObj(raw.supply) ? raw.supply : {};
  const c = isObj(raw.compensation) ? raw.compensation : {};
  const m = isObj(raw.match_quality) ? raw.match_quality : {};
  const b = isObj(m.buckets) ? m.buckets : {};
  const f = isObj(raw.application_funnel) ? raw.application_funnel : {};
  const i = isObj(raw.interview_funnel) ? raw.interview_funnel : {};
  const o = isObj(raw.offer_funnel) ? raw.offer_funnel : {};
  const t = isObj(raw.timing) ? raw.timing : {};
  const d = isObj(raw.difficulty) ? raw.difficulty : {};
  const bn = isObj(raw.bottleneck) ? raw.bottleneck : {};
  const score = numOrNull(d.score);
  return {
    jobId,
    title: str(raw.title) ?? 'Job',
    status: str(raw.status),
    openings: numOrNull(raw.openings),
    openOpenings: numOrNull(raw.open_openings),
    supply: {
      workersInProfession: numOrNull(s.workers_in_profession),
      availableSoon: numOrNull(s.available_soon),
      within25Km: numOrNull(s.within_25_km),
      openToRelocating: numOrNull(s.open_to_relocating_here),
      competingJobs: numOrNull(s.competing_jobs),
      workersPerOpening: numOrNull(s.workers_per_opening),
      workersPerCompetingJob: numOrNull(s.workers_per_competing_job),
    },
    compensation: {
      currency: str(c.currency)?.trim() ?? null,
      jobMonthly: numOrNull(c.job_monthly),
      market: parsePercentiles(c.market_jobs_monthly),
      expectations: parsePercentiles(c.worker_expectations_monthly),
      meetsMinimumPct: numOrNull(c.workers_whose_minimum_it_meets_pct),
      position: oneOf(PAY_POSITIONS, c.position) ?? 'unknown',
      rateSource: str(c.rate_source),
    },
    match: {
      scored: count(m.scored),
      eligible: count(m.eligible),
      strong: count(m.strong_matches),
      buckets: { top: count(b['80_plus']), mid: count(b['60_79']), low: count(b.under_60) },
      missingSkills: arr(m.top_missing_skills)
        .filter(isObj)
        .map((x) => ({ skill: str(x.skill) ?? '', candidates: count(x.candidates) }))
        .filter((x) => x.skill),
      gateFailures: isObj(m.gate_failures)
        ? Object.entries(m.gate_failures)
            .map(([name, n]) => ({ name, count: count(n) }))
            .filter((g) => g.count > 0)
            .sort((a, z) => z.count - a.count)
        : [],
    },
    applications: {
      impressions: count(f.impressions),
      applied: count(f.applied),
      viewed: count(f.viewed),
      shortlisted: count(f.shortlisted),
      interviewed: count(f.interviewed),
      offered: count(f.offered),
      hired: count(f.hired),
    },
    interviews: {
      scheduled: count(i.scheduled),
      completed: count(i.completed),
      cancelled: count(i.cancelled),
      noShowCandidate: count(i.no_show_candidate),
      noShowEmployer: count(i.no_show_employer),
      upcoming: count(i.upcoming),
    },
    offers: {
      sent: count(o.sent),
      accepted: count(o.accepted),
      declined: count(o.declined),
      expired: count(o.expired),
      withdrawn: count(o.withdrawn),
      declineReasons: arr(o.decline_reasons)
        .map((r) => str(r))
        .filter((r): r is string => !!r),
    },
    timing: {
      daysOpen: numOrNull(t.days_open),
      hoursToFirstApplication: numOrNull(t.hours_to_first_application),
      medianHoursToFirstView: numOrNull(t.median_hours_to_first_view),
      unreviewed: count(t.unreviewed_applications),
    },
    difficulty: {
      score: score == null ? null : Math.max(0, Math.min(100, Math.round(score))),
      label: oneOf(DIFFICULTY, d.label),
    },
    bottleneck: { stage: oneOf(BOTTLENECKS, bn.stage), explanation: str(bn.explanation) },
    recommendations: arr(raw.recommendations)
      .map((r) => str(r))
      .filter((r): r is string => !!r),
    computedAt: str(raw.computed_at),
    note: str(raw.note),
  };
}

/** Where a recommendation's text points; the RPC words them in fixed phrases. */
export type RecommendationLink = { href: string; label: string } | null;

export function recommendationLink(
  text: string,
  links: { talent: string | null; unreviewed: string | null; shortlisted: string | null }
): RecommendationLink {
  if (/invite strong matches/i.test(text) && links.talent) return { href: links.talent, label: 'Open talent search' };
  if (/not been opened/i.test(text) && links.unreviewed) return { href: links.unreviewed, label: 'Review applicants' };
  if (/schedule interviews/i.test(text) && links.shortlisted) return { href: links.shortlisted, label: 'See shortlist' };
  return null;
}

/* ------------------------------------------------------------------ */
/* Company intelligence                                                */
/* ------------------------------------------------------------------ */

export type CompanyJobInsight = {
  jobId: string;
  title: string;
  score: number | null;
  difficulty: Difficulty | null;
  bottleneck: Bottleneck | null;
  bottleneckWhy: string | null;
  applied: number;
  hired: number;
  daysOpen: number | null;
  payPosition: PayPosition | null;
  topRecommendation: string | null;
};

export type CompanyIntelligence = {
  jobs: CompanyJobInsight[];
  openJobs: number;
  hardOrVeryHard: number;
  bottlenecks: { stage: string; count: number }[];
};

export function parseCompanyIntelligence(raw: Json | null): CompanyIntelligence | null {
  if (!isObj(raw)) return null;
  const sum = isObj(raw.summary) ? raw.summary : {};
  const jobs = arr(raw.jobs)
    .filter(isObj)
    .map((j): CompanyJobInsight | null => {
      const id = str(j.job_id);
      if (!id) return null;
      const d = isObj(j.difficulty) ? j.difficulty : {};
      const b = isObj(j.bottleneck) ? j.bottleneck : {};
      return {
        jobId: id,
        title: str(j.title) ?? 'Job',
        score: numOrNull(d.score),
        difficulty: oneOf(DIFFICULTY, d.label),
        bottleneck: oneOf(BOTTLENECKS, b.stage),
        bottleneckWhy: str(b.explanation),
        applied: count(j.applied),
        hired: count(j.hired),
        daysOpen: numOrNull(j.days_open),
        payPosition: oneOf(PAY_POSITIONS, j.pay_position),
        topRecommendation: str(j.top_recommendation),
      };
    })
    .filter((j): j is CompanyJobInsight => !!j)
    // Already hardest first from the RPC; keep that order stable if scores tie.
    .sort((a, z) => (z.score ?? -1) - (a.score ?? -1));
  return {
    jobs,
    openJobs: numOrNull(sum.open_jobs) ?? jobs.length,
    hardOrVeryHard: count(sum.hard_or_very_hard),
    bottlenecks: isObj(sum.bottlenecks)
      ? Object.entries(sum.bottlenecks)
          .map(([stage, n]) => ({ stage, count: count(n) }))
          .filter((x) => x.count > 0)
          .sort((a, z) => z.count - a.count)
      : [],
  };
}

export const bottleneckLabel = (s: string | null) =>
  s ? (BOTTLENECK_LABEL[s as Bottleneck] ?? humanize(s)) : '—';

/* ------------------------------------------------------------------ */
/* Market insights (job form)                                          */
/* ------------------------------------------------------------------ */

export type MarketInsights = {
  profession: string | null;
  country: string | null;
  openJobs: number;
  openings: number;
  remoteJobs: number;
  sponsoredJobs: number;
  pay: { currency: string; jobs: number; p25: number | null; median: number | null; p75: number | null } | null;
  skills: { id: string; name: string; jobs: number }[];
  workers: number | null;
  note: string | null;
};

export function parseMarketInsights(raw: Json | null): MarketInsights | null {
  if (!isObj(raw)) return null;
  const p = isObj(raw.pay_monthly) ? raw.pay_monthly : null;
  const cur = p ? str(p.currency)?.trim() : null;
  return {
    profession: str(raw.profession),
    country: str(raw.country)?.trim() ?? null,
    openJobs: count(raw.open_jobs),
    openings: count(raw.openings),
    remoteJobs: count(raw.remote_jobs),
    sponsoredJobs: count(raw.sponsored_jobs),
    pay:
      p && cur
        ? { currency: cur, jobs: count(p.jobs), p25: numOrNull(p.p25), median: numOrNull(p.median), p75: numOrNull(p.p75) }
        : null,
    skills: arr(raw.skills_in_demand)
      .filter(isObj)
      .map((s) => ({ id: str(s.skill_id) ?? str(s.name) ?? '', name: str(s.name) ?? '', jobs: count(s.jobs) }))
      .filter((s) => s.name),
    workers: numOrNull(raw.workers),
    note: str(raw.note),
  };
}

/** A friendly sentence for the errors these RPCs raise. */
export function intelligenceError(e: { code?: string; message: string }): { forbidden: boolean; text: string } {
  if (e.code === '42501') return { forbidden: true, text: 'Only the hiring team can see hiring insights for this job.' };
  if (e.code === '22023') return { forbidden: false, text: 'This job could not be found.' };
  return { forbidden: false, text: e.message };
}
