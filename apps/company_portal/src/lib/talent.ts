/**
 * Release 3 — Marketplace, employer side.
 *
 * Talent search, talent profiles, invitations, pools and the job funnel all
 * come back from SECURITY DEFINER RPCs as jsonb. These helpers parse that
 * jsonb defensively (missing keys become empty values, never crashes) and
 * hold the labels the UI shows. Consent is enforced in the database: nothing
 * here widens what the employer can see.
 */
import type { Json } from '@/lib/supabase/database.types';
import { parseEvidence, type AttributeDataType, type IdentityEvidence, type ProfileAnswer } from '@/lib/identity';
import { factorLabel, skillName } from '@/lib/hiring';
import { parseCardEligibility, type CardEligibility } from '@/lib/global';

/* ------------------------------------------------------------------ */
/* Small parsing helpers                                               */
/* ------------------------------------------------------------------ */

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

/**
 * Match strengths / gaps arrive as `{factor, weight, text}` objects from the
 * match engine, but older rows (and some surfaces) hold plain strings. Either
 * way the employer sees one readable sentence.
 */
const R6_FACTORS = new Set(['mobility_fit', 'eligibility_fit']);

export function reasonText(r: unknown): string {
  if (typeof r === 'string') return r;
  if (isObj(r)) {
    const t = r.text ?? r.label ?? r.reason ?? r.message ?? r.name;
    // R6 factors say what they are about ("Mobility: Open to relocating…").
    const label = typeof r.factor === 'string' && R6_FACTORS.has(r.factor) ? factorLabel(r.factor) : null;
    if (typeof t === 'string' && t.trim()) return label ? `${label}: ${t}` : t;
    if (typeof r.factor === 'string') return factorLabel(r.factor);
  }
  return '';
}
const reasons = (v: unknown) => arr(v).map(reasonText).filter(Boolean);

/* ------------------------------------------------------------------ */
/* Talent card                                                         */
/* ------------------------------------------------------------------ */

export type Activity = 'this_week' | 'this_month' | 'earlier';
export type InvitationStatus = 'pending' | 'applied' | 'declined' | 'withdrawn' | 'expired' | 'ignored';

export type TalentCard = {
  workIdentityId: string;
  name: string;
  avatarUrl: string | null;
  label: string | null;
  profession: string | null;
  headline: string | null;
  location: string | null;
  distanceKm: number | null;
  experienceMonths: number | null;
  completeness: number | null;
  active: Activity | null;
  topSkills: string[];
  verifiedSkills: number;
  score: number | null;
  eligible: boolean | null;
  strengths: string[];
  gaps: string[];
  invitation: { id: string; sentAt: string | null; status: InvitationStatus } | null;
  pools: string[];
  allowInvitations: boolean;
  /** R6: eligibility for the searched job (never authorization details). */
  eligibility: CardEligibility | null;
  openToRelocation: boolean;
  currentCountry: string | null;
};

export function parseCard(raw: unknown): TalentCard | null {
  if (!isObj(raw)) return null;
  const inv = isObj(raw.invitation) ? raw.invitation : null;
  return {
    workIdentityId: String(raw.work_identity_id ?? ''),
    name: str(raw.name) ?? 'Candidate',
    avatarUrl: str(raw.avatar_url),
    label: str(raw.label),
    profession: str(raw.profession),
    headline: str(raw.headline),
    location: str(raw.location_text),
    distanceKm: numOrNull(raw.distance_km),
    experienceMonths: numOrNull(raw.experience_months),
    completeness: numOrNull(raw.completeness),
    active: (['this_week', 'this_month', 'earlier'] as const).find((a) => a === raw.active) ?? null,
    topSkills: arr(raw.top_skills).map((s) => (typeof s === 'string' ? s : skillName(s as { name?: string }))).filter(Boolean),
    verifiedSkills: num(raw.verified_skills),
    score: numOrNull(raw.score),
    eligible: typeof raw.eligible === 'boolean' ? raw.eligible : null,
    strengths: reasons(raw.strengths),
    gaps: reasons(raw.gaps),
    invitation: inv
      ? {
          id: String(inv.id ?? ''),
          sentAt: str(inv.sent_at),
          status: (str(inv.status) ?? 'pending') as InvitationStatus,
        }
      : null,
    pools: arr(raw.pools).map(String),
    // Absent means the worker did not turn invitations off.
    allowInvitations: raw.allow_invitations !== false,
    eligibility: parseCardEligibility(raw.eligibility),
    openToRelocation: raw.open_to_relocation === true,
    currentCountry: str(raw.current_country)?.trim() ?? null,
  };
}

/* ------------------------------------------------------------------ */
/* Search                                                              */
/* ------------------------------------------------------------------ */

export type SearchQuota = { used: number; limit: number | null };
export type SearchResult = { results: TalentCard[]; total: number; quota: SearchQuota | null };

export function parseSearch(raw: Json | null): SearchResult {
  const r = isObj(raw) ? raw : {};
  const q = isObj(r.quota) ? r.quota : null;
  return {
    results: arr(r.results).map(parseCard).filter((c): c is TalentCard => !!c && !!c.workIdentityId),
    total: num(r.total),
    quota: q ? { used: num(q.used), limit: numOrNull(q.limit) } : null,
  };
}

export const RADII = [10, 25, 50, 100, 250] as const;
export const PAGE_SIZE = 20;
export const INVITE_MAX = 1000;
export const NOTE_MAX = 500;

/* ------------------------------------------------------------------ */
/* Profile                                                             */
/* ------------------------------------------------------------------ */

export type TalentExperience = {
  title: string;
  employer: string | null;
  startedOn: string | null;
  endedOn: string | null;
  isCurrent: boolean;
  verified: boolean;
  description: string | null;
};

export type TalentMatch = {
  score: number | null;
  eligible: boolean | null;
  strengths: string[];
  gaps: string[];
  missingSkills: string[];
};

export type TalentProfile = {
  card: TalentCard | null;
  about: string | null;
  evidence: IdentityEvidence | null;
  answers: ProfileAnswer[];
  experiences: TalentExperience[];
  match: TalentMatch | null;
};

export function answerValue(dataType: string, unit: string | null, v: unknown): string | string[] | null {
  if (v === null || v === undefined || v === '') return null;
  const u = unit ? ` ${unit}` : '';
  const text = (x: unknown): string => {
    if (typeof x === 'string') return x;
    if (typeof x === 'number') return x.toLocaleString('en-IN');
    if (typeof x === 'boolean') return x ? 'Yes' : 'No';
    if (isObj(x)) {
      const t = x.label ?? x.name ?? x.text ?? x.city;
      if (typeof t === 'string') return t;
    }
    return JSON.stringify(x);
  };
  switch (dataType) {
    case 'multi_select': {
      const list = arr(v).map(text).filter(Boolean);
      return list.length ? list : null;
    }
    case 'boolean':
      return typeof v === 'boolean' ? (v ? 'Yes' : 'No') : text(v);
    case 'years': {
      const n = numOrNull(v);
      return n == null ? text(v) : `${n} year${n === 1 ? '' : 's'}`;
    }
    case 'number': {
      const n = numOrNull(v);
      return n == null ? text(v) : `${n.toLocaleString('en-IN')}${u}`;
    }
    case 'date':
      return typeof v === 'string'
        ? new Date(v.slice(0, 10) + 'T00:00:00Z').toLocaleDateString('en-GB', {
            day: 'numeric',
            month: 'short',
            year: 'numeric',
            timeZone: 'UTC',
          })
        : text(v);
    case 'file':
      return 'File provided';
    default:
      return `${text(v)}${dataType === 'text' ? u : ''}`;
  }
}

export function parseProfile(raw: Json | null): TalentProfile | null {
  if (!isObj(raw)) return null;
  const m = isObj(raw.match) ? raw.match : null;
  const answers: ProfileAnswer[] = [];
  arr(raw.answers).forEach((a, i) => {
    if (!isObj(a)) return;
    const dataType = (str(a.data_type) ?? 'text') as AttributeDataType;
    const value = answerValue(dataType, str(a.unit), a.value);
    if (value == null || value === '') return;
    answers.push({ id: `${i}`, label: str(a.label) ?? 'Answer', dataType, position: i, value });
  });
  return {
    card: parseCard(raw.card),
    about: str(raw.about),
    evidence: parseEvidence((raw.evidence ?? null) as Json | null),
    answers,
    experiences: arr(raw.experiences)
      .filter(isObj)
      .map((x) => ({
        title: str(x.title) ?? 'Role',
        employer: str(x.employer),
        startedOn: str(x.started_on),
        endedOn: str(x.ended_on),
        isCurrent: x.is_current === true,
        verified: x.verified === true,
        description: str(x.description),
      })),
    match: m
      ? {
          score: numOrNull(m.score),
          eligible: typeof m.eligible === 'boolean' ? m.eligible : null,
          strengths: reasons(m.strengths),
          gaps: reasons(m.gaps),
          missingSkills: arr(m.missing_skills)
            .map((s) => (typeof s === 'string' ? s : isObj(s) ? skillName(s as { name?: string }) : ''))
            .filter(Boolean),
        }
      : null,
  };
}

/* ------------------------------------------------------------------ */
/* Invitations                                                         */
/* ------------------------------------------------------------------ */

export type JobInvitation = {
  id: string;
  sentAt: string | null;
  respondedAt: string | null;
  viewed: boolean;
  status: InvitationStatus;
  declineReason: string | null;
  sentBy: string | null;
  applicationId: string | null;
  candidate: TalentCard | null;
  candidateName: string;
};

export function parseInvitations(raw: Json | null): JobInvitation[] {
  return arr(raw)
    .filter(isObj)
    .map((x) => {
      const c = isObj(x.candidate) ? x.candidate : {};
      const card = c.work_identity_id ? parseCard(c) : null;
      return {
        id: String(x.id ?? ''),
        sentAt: str(x.sent_at),
        respondedAt: str(x.responded_at),
        viewed: x.viewed === true,
        status: (str(x.status) ?? 'pending') as InvitationStatus,
        declineReason: str(x.decline_reason),
        sentBy: str(x.sent_by),
        applicationId: str(x.application_id),
        candidate: card,
        candidateName: card?.name ?? str(c.name) ?? 'Candidate (no longer visible)',
      };
    });
}

export const INVITATION_LABEL: Record<InvitationStatus, string> = {
  pending: 'Invited · waiting',
  applied: 'Applied',
  declined: 'Declined',
  withdrawn: 'Withdrawn',
  expired: 'Expired',
  ignored: 'No reply',
};

export const INVITATION_COLOR: Record<InvitationStatus, string> = {
  pending: 'var(--color-brand-600)',
  applied: 'var(--color-verified)',
  declined: 'var(--color-danger)',
  withdrawn: 'var(--muted)',
  expired: 'var(--muted)',
  ignored: 'var(--muted)',
};

/* ------------------------------------------------------------------ */
/* Pools                                                               */
/* ------------------------------------------------------------------ */

export type PoolMember = {
  personId: string;
  workIdentityId: string | null;
  note: string | null;
  addedAt: string | null;
  visible: boolean;
  candidate: TalentCard | null;
  candidateName: string;
};

export function parsePoolMembers(raw: Json | null): PoolMember[] {
  return arr(raw)
    .filter(isObj)
    .map((x) => {
      const c = isObj(x.candidate) ? x.candidate : {};
      const visible = x.visible === true;
      const card = visible && c.work_identity_id ? parseCard(c) : null;
      return {
        personId: String(x.person_id ?? ''),
        workIdentityId: str(x.work_identity_id),
        note: str(x.note),
        addedAt: str(x.added_at),
        visible,
        candidate: card,
        candidateName: card?.name ?? str(c.name) ?? 'Candidate (no longer visible)',
      };
    });
}

export type Pool = { id: string; name: string };

/* ------------------------------------------------------------------ */
/* Labels                                                              */
/* ------------------------------------------------------------------ */

export const ACTIVE_LABEL: Record<Activity, string> = {
  this_week: 'Active this week',
  this_month: 'Active this month',
  earlier: 'Active over a month ago',
};

export const SURFACE_LABEL: Record<string, string> = {
  recommended: 'Recommended for them',
  nearby: 'Jobs nearby',
  search: 'Job search',
  job_page: 'Job page / shared link',
  invitation: 'Your invitations',
  talent_search: 'Talent search',
  notification: 'Notification',
  email: 'Email',
  saved: 'Their saved jobs',
  other: 'Other',
};

export const surfaceLabel = (s: string) => SURFACE_LABEL[s] ?? s.replace(/_/g, ' ');

export function distanceText(km: number | null) {
  if (km == null) return null;
  if (km < 1) return 'Under 1 km away';
  return `${km < 10 ? km.toFixed(1) : Math.round(km)} km away`;
}

export function quotaText(q: SearchQuota | null) {
  if (!q || q.limit == null) return null;
  return `${q.used} of ${q.limit} searches used this month`;
}

/** The friendly default the invite dialog starts with. Editable. */
export function defaultInviteMessage(opts: { firstName: string; jobTitle: string; companyName: string }) {
  const hi = opts.firstName && opts.firstName !== 'Candidate' ? `Hi ${opts.firstName},` : 'Hi,';
  return `${hi}

We think your experience is a great fit for our ${opts.jobTitle} role at ${opts.companyName}. Take a look at the job and apply if it interests you — we would love to hear from you.`;
}

/* ------------------------------------------------------------------ */
/* Funnel                                                              */
/* ------------------------------------------------------------------ */

export type JobFunnel = {
  impressions: number;
  views: number;
  viewCount: number;
  applied: number;
  viewed: number;
  shortlisted: number;
  interviewed: number;
  offered: number;
  hired: number;
  bySurface: { surface: string; impressions: number; views: number; applications: number }[];
  invitations: { sent: number; viewed: number; applied: number; declined: number; pending: number };
  talentSearches: number;
};

export function parseFunnel(raw: Json | null): JobFunnel {
  const r = isObj(raw) ? raw : {};
  const inv = isObj(r.invitations) ? r.invitations : {};
  return {
    impressions: num(r.impressions),
    views: num(r.views),
    viewCount: num(r.view_count),
    applied: num(r.applied),
    viewed: num(r.viewed),
    shortlisted: num(r.shortlisted),
    interviewed: num(r.interviewed),
    offered: num(r.offered),
    hired: num(r.hired),
    bySurface: arr(r.by_surface)
      .filter(isObj)
      .map((s) => ({
        surface: String(s.surface ?? 'other'),
        impressions: num(s.impressions),
        views: num(s.views),
        applications: num(s.applications),
      })),
    invitations: {
      sent: num(inv.sent),
      viewed: num(inv.viewed),
      applied: num(inv.applied),
      declined: num(inv.declined),
      pending: num(inv.pending),
    },
    talentSearches: num(r.talent_searches),
  };
}

/* ------------------------------------------------------------------ */
/* Admin: matching metrics                                             */
/* ------------------------------------------------------------------ */

export type MatchingMetrics = {
  days: number;
  bySurface: {
    surface: string;
    impressions: number;
    views: number;
    applications: number;
    viewRate: number | null;
    applyRate: number | null;
  }[];
  byScoreBand: { band: string; applications: number; progressedRate: number | null; hireRate: number | null }[];
  talent: {
    searches: number;
    companiesSearching: number;
    invitationsSent: number;
    invitationsApplied: number;
    invitationsDeclined: number;
    invitationApplyRate: number | null;
  };
  engines: { engineVersion: string; matches: number }[];
};

export const SCORE_BANDS = ['85-100', '70-84', '50-69', '0-49', 'unscored'] as const;

export function parseMatchingMetrics(raw: Json | null): MatchingMetrics {
  const r = isObj(raw) ? raw : {};
  const t = isObj(r.talent) ? r.talent : {};
  const bands = arr(r.by_score_band)
    .filter(isObj)
    .map((b) => ({
      band: String(b.band ?? 'unscored'),
      applications: num(b.applications),
      progressedRate: numOrNull(b.progressed_rate),
      hireRate: numOrNull(b.hire_rate),
    }));
  bands.sort(
    (a, b) =>
      (SCORE_BANDS.indexOf(a.band as never) + 1 || 99) - (SCORE_BANDS.indexOf(b.band as never) + 1 || 99)
  );
  return {
    days: num(r.days) || 30,
    bySurface: arr(r.by_surface)
      .filter(isObj)
      .map((s) => ({
        surface: String(s.surface ?? 'other'),
        impressions: num(s.impressions),
        views: num(s.views),
        applications: num(s.applications),
        viewRate: numOrNull(s.view_rate),
        applyRate: numOrNull(s.apply_rate),
      })),
    byScoreBand: bands,
    talent: {
      searches: num(t.searches),
      companiesSearching: num(t.companies_searching),
      invitationsSent: num(t.invitations_sent),
      invitationsApplied: num(t.invitations_applied),
      invitationsDeclined: num(t.invitations_declined),
      invitationApplyRate: numOrNull(t.invitation_apply_rate),
    },
    engines: arr(r.engines)
      .filter(isObj)
      .map((e) => ({ engineVersion: String(e.engine_version ?? 'unknown'), matches: num(e.matches) })),
  };
}

export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Roles that may search, invite and edit pools (the DB enforces the same). */
export const TALENT_ROLES = ['owner', 'admin', 'recruiter'];
