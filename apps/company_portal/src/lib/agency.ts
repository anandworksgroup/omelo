/**
 * Release 4 — Recruiters & Agencies.
 *
 * Principle: a recruiter can represent a worker for a specific opportunity
 * only with the worker's explicit consent, for a defined period and purpose.
 * The recruiter never owns the candidate.
 *
 * Every rule lives in the database (RLS, SECURITY DEFINER functions and
 * validation triggers). This module only parses the jsonb those functions
 * return — defensively, so a missing key renders as empty rather than
 * crashing — and holds the labels and the role table the UI uses to explain
 * *why* an action is unavailable. It never widens what anyone can do.
 */
import type { Json } from '@/lib/supabase/database.types';
import { answerValue, parseCard, type SearchQuota, type TalentCard } from '@/lib/talent';
import type { AttributeDataType, ProfileAnswer } from '@/lib/identity';

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
const strs = (v: unknown): string[] => arr(v).map((x) => (typeof x === 'string' ? x : '')).filter(Boolean);

/* ------------------------------------------------------------------ */
/* Roles                                                               */
/* ------------------------------------------------------------------ */

/**
 * Mirror of omelo_private.omelo_agency_roles(action). Used only to hide or
 * explain actions; the database checks the same table on every call.
 */
export const AGENCY_ACTION_ROLES = {
  manage_agency: ['owner', 'admin'],
  manage_members: ['owner', 'admin'],
  manage_clients: ['owner', 'admin', 'recruiter'],
  create_job_order: ['owner', 'admin', 'recruiter'],
  search_talent: ['owner', 'admin', 'recruiter', 'sourcer'],
  request_consent: ['owner', 'admin', 'recruiter', 'sourcer'],
  submit: ['owner', 'admin', 'recruiter'],
  schedule_interview: ['owner', 'admin', 'recruiter', 'coordinator'],
  view_candidate_details: ['owner', 'admin', 'recruiter'],
  manage_placements: ['owner', 'admin', 'recruiter', 'coordinator'],
  view: ['owner', 'admin', 'recruiter', 'sourcer', 'coordinator'],
} as const;

export type AgencyAction = keyof typeof AGENCY_ACTION_ROLES;

export function agencyCan(ctx: { roles: readonly string[] }, action: AgencyAction): boolean {
  const allowed = AGENCY_ACTION_ROLES[action] as readonly string[];
  return ctx.roles.some((r) => allowed.includes(r));
}

/** "Only owners, admins and recruiters can …" */
export function rolesSentence(action: AgencyAction): string {
  const names = (AGENCY_ACTION_ROLES[action] as readonly string[]).map((r) => ROLE_LABEL[r]?.toLowerCase() ?? r);
  const plural = names.map((n) => (n.endsWith('s') ? n : `${n}s`));
  if (plural.length === 1) return plural[0];
  return `${plural.slice(0, -1).join(', ')} and ${plural.at(-1)}`;
}

export function onlyRoles(action: AgencyAction, what: string): string {
  const s = rolesSentence(action);
  return `Only ${s} can ${what}.`;
}

export const ROLE_LABEL: Record<string, string> = {
  owner: 'Owner',
  admin: 'Admin',
  recruiter: 'Recruiter',
  sourcer: 'Sourcer',
  coordinator: 'Coordinator',
  hiring_manager: 'Hiring manager',
  interviewer: 'Interviewer',
  hr: 'HR',
  finance: 'Finance',
  viewer: 'Viewer',
};

export const roleLabel = (r: string) => ROLE_LABEL[r] ?? r.replace(/_/g, ' ');

/** What each role can do, in plain words, for the team page. */
export const AGENCY_ROLE_HELP: { role: string; does: string }[] = [
  { role: 'owner', does: 'Everything, including inviting other owners and removing the agency’s admins.' },
  { role: 'admin', does: 'Everything except managing owners: team, clients, job orders, submissions, placements.' },
  {
    role: 'recruiter',
    does: 'Clients and job orders, talent search, consent requests, full consented profiles, submitting to clients, placements.',
  },
  {
    role: 'sourcer',
    does: 'Talent search, saving people to pools and asking for consent. Sees skills only; cannot submit.',
  },
  {
    role: 'coordinator',
    does: 'Interviews, offers and placements. Sees skills only; cannot search or submit.',
  },
];

export const EMPLOYER_ROLE_HELP: { role: string; does: string }[] = [
  { role: 'owner', does: 'Everything, including inviting other owners.' },
  { role: 'admin', does: 'Everything except managing owners: team, company profile, jobs, candidates.' },
  { role: 'recruiter', does: 'Jobs, candidates, talent search and invitations.' },
  { role: 'hiring_manager', does: 'Reviews candidates, runs interviews and makes offers.' },
  { role: 'hr', does: 'Reviews candidates, interviews and offers.' },
  { role: 'interviewer', does: 'Only the interviews they are on, and their own feedback.' },
  { role: 'finance', does: 'Billing and plan information.' },
  { role: 'viewer', does: 'Read-only access to jobs and the pipeline.' },
];

/* ------------------------------------------------------------------ */
/* Labels                                                              */
/* ------------------------------------------------------------------ */

type Tone = { label: string; color: string };
const C = {
  brand: 'var(--color-brand-600)',
  good: 'var(--color-verified)',
  warn: 'var(--color-warn)',
  bad: 'var(--color-danger)',
  muted: 'var(--muted)',
  fg: 'var(--fg)',
};

export type ConsentStatus =
  | 'requested'
  | 'accepted'
  | 'active'
  | 'declined'
  | 'expired'
  | 'revoked'
  | 'withdrawn';

export const CONSENT_STATUS: Record<ConsentStatus, Tone> = {
  requested: { label: 'Waiting for reply', color: C.brand },
  accepted: { label: 'Consent given', color: C.good },
  active: { label: 'Submitted with consent', color: C.good },
  declined: { label: 'Declined', color: C.bad },
  expired: { label: 'Expired', color: C.muted },
  revoked: { label: 'Consent withdrawn', color: C.bad },
  withdrawn: { label: 'Request withdrawn', color: C.muted },
};
export const consentTone = (s: string): Tone => CONSENT_STATUS[s as ConsentStatus] ?? { label: s, color: C.muted };

export const SUBMISSION_STATUSES = [
  'submitted',
  'reviewing',
  'shortlisted',
  'interview',
  'offer',
  'hired',
  'rejected',
  'withdrawn',
] as const;
export type SubmissionStatus = (typeof SUBMISSION_STATUSES)[number];

export const SUBMISSION_STATUS: Record<SubmissionStatus, Tone> = {
  submitted: { label: 'Submitted', color: C.brand },
  reviewing: { label: 'Client reviewing', color: C.brand },
  shortlisted: { label: 'Shortlisted', color: C.good },
  interview: { label: 'Interviewing', color: C.good },
  offer: { label: 'Offer', color: C.good },
  hired: { label: 'Hired', color: C.good },
  rejected: { label: 'Not selected', color: C.bad },
  withdrawn: { label: 'Withdrawn', color: C.muted },
};
export const submissionTone = (s: string): Tone =>
  SUBMISSION_STATUS[s as SubmissionStatus] ?? { label: s, color: C.muted };

/** Outcomes an agency may record for an off-platform client. */
export const OUTCOMES: SubmissionStatus[] = ['reviewing', 'shortlisted', 'interview', 'offer', 'hired', 'rejected'];

export const PLACEMENT_STATUS: Record<string, Tone> = {
  pending_start: { label: 'Starting soon', color: C.brand },
  active: { label: 'Working', color: C.good },
  completed: { label: 'Completed', color: C.good },
  fell_through: { label: 'Fell through', color: C.bad },
};
export const placementTone = (s: string): Tone => PLACEMENT_STATUS[s] ?? { label: s, color: C.muted };
/** omelo_update_placement's allowed moves. */
export const PLACEMENT_NEXT: Record<string, string[]> = {
  pending_start: ['active', 'fell_through'],
  active: ['completed', 'fell_through'],
  completed: [],
  fell_through: [],
};

export const JOB_ORDER_STATUSES = ['draft', 'open', 'on_hold', 'filled', 'closed', 'cancelled'] as const;
export const JOB_ORDER_STATUS: Record<string, Tone> = {
  draft: { label: 'Draft', color: C.muted },
  open: { label: 'Open', color: C.good },
  on_hold: { label: 'On hold', color: C.warn },
  filled: { label: 'Filled', color: C.brand },
  closed: { label: 'Closed', color: C.muted },
  cancelled: { label: 'Cancelled', color: C.bad },
};
export const orderTone = (s: string): Tone => JOB_ORDER_STATUS[s] ?? { label: s, color: C.muted };

export const PRIORITIES = ['low', 'normal', 'high', 'urgent'] as const;
export const PRIORITY: Record<string, Tone> = {
  low: { label: 'Low', color: C.muted },
  normal: { label: 'Normal', color: C.fg },
  high: { label: 'High', color: C.warn },
  urgent: { label: 'Urgent', color: C.bad },
};

export const RELATIONSHIP_STATUSES = ['prospect', 'active', 'on_hold', 'ended'] as const;
export const RELATIONSHIP: Record<string, Tone> = {
  prospect: { label: 'Prospect', color: C.brand },
  active: { label: 'Active', color: C.good },
  on_hold: { label: 'On hold', color: C.warn },
  ended: { label: 'Ended', color: C.muted },
};

export const LINK_STATUS: Record<string, Tone> = {
  unlinked: { label: 'Not on Omelo', color: C.muted },
  pending: { label: 'Waiting for the company to confirm', color: C.warn },
  confirmed: { label: 'Linked on Omelo', color: C.good },
  declined: { label: 'The company declined the link', color: C.bad },
};

/** What a worker shares when they consent — plain words, identity first. */
export const SCOPES = ['identity', 'skills', 'experience', 'evidence', 'answers', 'contact'] as const;
export type Scope = (typeof SCOPES)[number];
export const SCOPE_LABEL: Record<Scope, string> = {
  identity: 'Professional identity',
  skills: 'Skills',
  experience: 'Work history',
  evidence: 'Verified evidence',
  answers: 'Profile answers',
  contact: 'Contact details',
};
export const SCOPE_HELP: Record<Scope, string> = {
  identity: 'Name, the work profile you found, headline, experience, location. Always included.',
  skills: 'Their skills and which ones employers confirmed.',
  experience: 'Jobs they list, with verified ones marked.',
  evidence: 'Verified employment, verified skills, licences.',
  answers: 'Answers to their profession’s profile questions.',
  contact: 'Email and phone, for arranging interviews.',
};
export const scopeLabel = (s: string) => SCOPE_LABEL[s as Scope] ?? s;
export const scopeList = (scope: string[]) => scope.map(scopeLabel).join(', ');

export const AVAILABILITY = [
  'immediate',
  'within_7_days',
  'within_15_days',
  'within_30_days',
  'within_60_days',
  'within_90_days',
  'flexible',
  'not_available',
] as const;
export const AVAILABILITY_LABEL: Record<string, string> = {
  immediate: 'Available now',
  within_7_days: 'Within a week',
  within_15_days: 'Within 15 days',
  within_30_days: 'Within a month',
  within_60_days: 'Within 2 months',
  within_90_days: 'Within 3 months',
  flexible: 'Flexible',
  not_available: 'Not available',
};

export const CONSENT_FILTERS = ['any', 'none', 'requested', 'accepted', 'active', 'declined', 'expired', 'revoked'] as const;
export const CONSENT_FILTER_LABEL: Record<string, string> = {
  any: 'Anyone',
  none: 'Not asked yet',
  requested: 'Waiting for reply',
  accepted: 'Consent given',
  active: 'Already submitted',
  declined: 'Declined',
  expired: 'Expired',
  revoked: 'Consent withdrawn',
};

export const CONSENT_MESSAGE_MAX = 1000;
export const SUBMIT_NOTE_MAX = 2000;

/* ------------------------------------------------------------------ */
/* Dashboard                                                           */
/* ------------------------------------------------------------------ */

export type AgencyDashboard = {
  activeJobOrders: number;
  openings: number;
  candidatesSourced: number;
  consentRequests: number;
  consentsAccepted: number;
  submissions: number;
  interviews: number;
  offers: number;
  placements: number;
  days: number;
};

export function parseDashboard(raw: Json | null): AgencyDashboard {
  const r = isObj(raw) ? raw : {};
  return {
    activeJobOrders: num(r.active_job_orders),
    openings: num(r.openings),
    candidatesSourced: num(r.candidates_sourced),
    consentRequests: num(r.consent_requests),
    consentsAccepted: num(r.consents_accepted),
    submissions: num(r.submissions),
    interviews: num(r.interviews),
    offers: num(r.offers),
    placements: num(r.placements),
    days: num(r.days) || 30,
  };
}

/* ------------------------------------------------------------------ */
/* Recruiter talent search                                             */
/* ------------------------------------------------------------------ */

export type Money = { amount: number; period: string | null; currency: string | null };

export type AgencyCard = TalentCard & {
  availability: string | null;
  expectedPay: Money | null;
  verifiedEmployers: number;
  employerConfirmedSkills: number;
  acceptsRecruiterRequests: boolean;
  previousRelationship: boolean;
  consent: { id: string; status: string } | null;
};

export function parseAgencyCard(raw: unknown): AgencyCard | null {
  const base = parseCard(raw);
  if (!base || !isObj(raw)) return null;
  const pay = isObj(raw.expected_pay) ? raw.expected_pay : null;
  const consent = isObj(raw.consent) ? raw.consent : null;
  return {
    ...base,
    availability: str(raw.availability),
    expectedPay:
      pay && numOrNull(pay.amount) != null
        ? { amount: num(pay.amount), period: str(pay.period), currency: str(pay.currency) }
        : null,
    verifiedEmployers: num(raw.verified_employers),
    employerConfirmedSkills: num(raw.employer_confirmed_skills),
    acceptsRecruiterRequests: raw.accepts_recruiter_requests !== false,
    previousRelationship: raw.previous_relationship === true,
    consent: consent && str(consent.id) ? { id: String(consent.id), status: str(consent.status) ?? 'requested' } : null,
  };
}

export type AgencySearchResult = { results: AgencyCard[]; total: number; quota: SearchQuota | null };

export function parseAgencySearch(raw: Json | null): AgencySearchResult {
  const r = isObj(raw) ? raw : {};
  const q = isObj(r.quota) ? r.quota : null;
  return {
    results: arr(r.results)
      .map(parseAgencyCard)
      .filter((c): c is AgencyCard => !!c && !!c.workIdentityId),
    total: num(r.total),
    quota: q ? { used: num(q.used), limit: numOrNull(q.limit) } : null,
  };
}

export type SearchFilters = {
  query?: string;
  radius_km?: number;
  profession_id?: string;
  skill_ids?: string[];
  min_experience_months?: number;
  max_experience_months?: number;
  availability?: string[];
  work_types?: string[];
  max_expected_pay_monthly?: number;
  verified_only?: boolean;
  work_auth_country?: string;
  consent_status?: string;
  previous_relationship?: boolean;
  pool_id?: string;
};

/* ------------------------------------------------------------------ */
/* Candidates (consents)                                               */
/* ------------------------------------------------------------------ */

export type ConsentRow = {
  consentId: string;
  jobOrderId: string;
  jobOrder: string | null;
  position: string | null;
  client: string | null;
  status: string;
  scope: string[];
  requestedAt: string | null;
  respondedAt: string | null;
  expiresAt: string | null;
  declineReason: string | null;
  recruiter: string | null;
  submission: { id: string; status: string; submittedAt: string | null } | null;
  card: TalentCard | null;
  name: string;
};

export function parseConsents(raw: Json | null): ConsentRow[] {
  return arr(raw)
    .filter(isObj)
    .map((x) => {
      const c = isObj(x.candidate) ? x.candidate : {};
      const card = c.work_identity_id ? parseCard(c) : null;
      const s = isObj(x.submission) ? x.submission : null;
      return {
        consentId: String(x.consent_id ?? ''),
        jobOrderId: String(x.job_order_id ?? ''),
        jobOrder: str(x.job_order),
        position: str(x.position),
        client: str(x.client),
        status: str(x.status) ?? 'requested',
        scope: strs(x.scope),
        requestedAt: str(x.requested_at),
        respondedAt: str(x.responded_at),
        expiresAt: str(x.expires_at),
        declineReason: str(x.decline_reason),
        recruiter: str(x.recruiter),
        submission: s
          ? { id: String(s.id ?? ''), status: str(s.status) ?? 'submitted', submittedAt: str(s.submitted_at) }
          : null,
        card,
        name: card?.name ?? str(c.name) ?? 'Candidate',
      };
    });
}

/**
 * Why a consent cannot be used to submit (or null if it can). Mirrors the
 * checks in omelo_submit_candidate so the button never pretends; the database
 * still decides.
 */
export function submitBlocker(
  row: { status: string; expiresAt: string | null; submission: unknown },
  nowMs: number
): string | null {
  if (row.submission) return 'Already submitted with this consent.';
  switch (row.status) {
    case 'requested':
      return 'The candidate has not answered yet. You can submit once they give consent.';
    case 'accepted':
      if (row.expiresAt && new Date(row.expiresAt).getTime() <= nowMs)
        return 'This consent has expired. Ask the candidate again.';
      return null;
    case 'active':
      return 'Already submitted with this consent.';
    case 'declined':
      return 'The candidate declined. You cannot submit them for this job order.';
    case 'expired':
      return 'This consent has expired. Ask the candidate again.';
    case 'revoked':
      return 'The candidate withdrew their consent.';
    case 'withdrawn':
      return 'You withdrew this request.';
    default:
      return 'Consent is not in force.';
  }
}

/* ------------------------------------------------------------------ */
/* Scoped profile (consented view + submission snapshot)                */
/* ------------------------------------------------------------------ */

export type ScopedProfile = {
  identity: {
    workIdentityId: string | null;
    name: string;
    label: string | null;
    profession: string | null;
    headline: string | null;
    about: string | null;
    experienceMonths: number | null;
    location: string | null;
    avatarUrl: string | null;
  };
  skills: { name: string; proficiency: string | null; monthsUsed: number | null; verified: boolean }[] | null;
  experience:
    | {
        title: string;
        employer: string | null;
        startedOn: string | null;
        endedOn: string | null;
        isCurrent: boolean;
        verified: boolean;
        description: string | null;
      }[]
    | null;
  evidence: {
    verifiedEmployment: { employer: string | null; title: string | null; startedOn: string | null; endedOn: string | null }[];
    verifiedSkills: string[];
    licences: { name: string; verified: boolean; expiresOn: string | null }[];
    emailVerified: boolean;
  } | null;
  answers: ProfileAnswer[] | null;
  contact: { email: string | null; phone: string | null } | null;
  scope: string[];
  submittedVia: {
    agency: string | null;
    agencyId: string | null;
    recruiter: string | null;
    note: string | null;
    submittedAt: string | null;
    jobOrder: string | null;
    consentExpiresAt: string | null;
  } | null;
};

export function parseScopedProfile(raw: unknown): ScopedProfile | null {
  if (!isObj(raw) || !isObj(raw.identity)) return null;
  const i = raw.identity;
  const ev = isObj(raw.evidence) ? raw.evidence : null;
  const via = isObj(raw.submitted_via) ? raw.submitted_via : null;
  const contact = isObj(raw.contact) ? raw.contact : null;
  let answers: ProfileAnswer[] | null = null;
  if (Array.isArray(raw.answers)) {
    answers = [];
    raw.answers.forEach((a, idx) => {
      if (!isObj(a)) return;
      const dataType = (str(a.data_type) ?? 'text') as AttributeDataType;
      const value = answerValue(dataType, str(a.unit), a.value);
      if (value == null || value === '') return;
      answers!.push({ id: `${idx}`, label: str(a.label) ?? 'Answer', dataType, position: idx, value });
    });
  }
  return {
    identity: {
      workIdentityId: str(i.work_identity_id),
      name: str(i.name) ?? 'Candidate',
      label: str(i.label),
      profession: str(i.profession),
      headline: str(i.headline),
      about: str(i.about),
      experienceMonths: numOrNull(i.experience_months),
      location: str(i.location_text),
      avatarUrl: str(i.avatar_url),
    },
    skills: Array.isArray(raw.skills)
      ? raw.skills.filter(isObj).map((s) => ({
          name: str(s.name) ?? 'Skill',
          proficiency: str(s.proficiency),
          monthsUsed: numOrNull(s.months_used),
          verified: s.verified === true,
        }))
      : null,
    experience: Array.isArray(raw.experience)
      ? raw.experience.filter(isObj).map((x) => ({
          title: str(x.title) ?? 'Role',
          employer: str(x.employer),
          startedOn: str(x.started_on),
          endedOn: str(x.ended_on),
          isCurrent: x.is_current === true,
          verified: x.verified === true,
          description: str(x.description),
        }))
      : null,
    evidence: ev
      ? {
          verifiedEmployment: arr(ev.verified_employment)
            .filter(isObj)
            .map((x) => ({
              employer: str(x.employer),
              title: str(x.title),
              startedOn: str(x.started_on),
              endedOn: str(x.ended_on),
            })),
          verifiedSkills: strs(ev.verified_skills),
          licences: arr(ev.licences)
            .filter(isObj)
            .map((x) => ({ name: str(x.name) ?? 'Licence', verified: x.verified === true, expiresOn: str(x.expires_on) })),
          emailVerified: ev.email_verified === true,
        }
      : null,
    answers,
    contact: contact ? { email: str(contact.email), phone: str(contact.phone) } : null,
    scope: strs(raw.scope),
    submittedVia: via
      ? {
          agency: str(via.agency),
          agencyId: str(via.agency_id),
          recruiter: str(via.recruiter),
          note: str(via.note),
          submittedAt: str(via.submitted_at),
          jobOrder: str(via.job_order),
          consentExpiresAt: str(via.consent_expires_at),
        }
      : null,
  };
}

/* ------------------------------------------------------------------ */
/* Submissions                                                         */
/* ------------------------------------------------------------------ */

export type SubmissionRow = {
  id: string;
  status: string;
  submittedAt: string | null;
  updatedAt: string | null;
  jobOrderId: string;
  jobOrder: string | null;
  position: string | null;
  client: string | null;
  onOmelo: boolean;
  candidate: { name: string; label: string | null; profession: string | null };
  recruiter: string | null;
  recruiterNote: string | null;
  clientResponse: string | null;
  rejectionReason: string | null;
  consentStatus: string | null;
  applicationState: string | null;
  nextInterview: string | null;
  offerStatus: string | null;
  placement: {
    id: string;
    status: string;
    startDate: string | null;
    feeAmount: number | null;
    feeCurrency: string | null;
  } | null;
};

export function parseSubmissions(raw: Json | null): SubmissionRow[] {
  return arr(raw)
    .filter(isObj)
    .map((x) => {
      const c = isObj(x.candidate) ? x.candidate : {};
      const p = isObj(x.placement) ? x.placement : null;
      return {
        id: String(x.id ?? ''),
        status: str(x.status) ?? 'submitted',
        submittedAt: str(x.submitted_at),
        updatedAt: str(x.updated_at),
        jobOrderId: String(x.job_order_id ?? ''),
        jobOrder: str(x.job_order),
        position: str(x.position),
        client: str(x.client),
        onOmelo: x.on_omelo === true,
        candidate: { name: str(c.name) ?? 'Candidate', label: str(c.label), profession: str(c.profession) },
        recruiter: str(x.recruiter),
        recruiterNote: str(x.recruiter_note),
        clientResponse: str(x.client_response),
        rejectionReason: str(x.rejection_reason),
        consentStatus: str(x.consent_status),
        applicationState: str(x.application_state),
        nextInterview: str(x.next_interview),
        offerStatus: str(x.offer_status),
        placement: p
          ? {
              id: String(p.id ?? ''),
              status: str(p.status) ?? 'pending_start',
              startDate: str(p.start_date),
              feeAmount: numOrNull(p.fee_amount),
              feeCurrency: str(p.fee_currency),
            }
          : null,
      };
    });
}

/* ------------------------------------------------------------------ */
/* Employer (client) side                                              */
/* ------------------------------------------------------------------ */

export type AgencyRef = { id: string; name: string; verified: boolean; independent: boolean; logoUrl: string | null };

function agencyRef(v: unknown): AgencyRef {
  const a = isObj(v) ? v : {};
  return {
    id: String(a.id ?? ''),
    name: str(a.name) ?? 'Agency',
    verified: a.verified === true,
    independent: a.independent === true,
    logoUrl: str(a.logo_url),
  };
}

export type AgencyRelationship = {
  clientId: string;
  companyId: string | null;
  linkStatus: string;
  relationshipStatus: string;
  agency: AgencyRef;
  jobOrders: number;
  submissions: number;
  canAnswer: boolean;
};

export function parseRelationships(raw: Json | null): AgencyRelationship[] {
  return arr(raw)
    .filter(isObj)
    .map((x) => ({
      clientId: String(x.client_id ?? ''),
      companyId: str(x.company_id),
      linkStatus: str(x.link_status) ?? 'unlinked',
      relationshipStatus: str(x.relationship_status) ?? 'prospect',
      agency: agencyRef(x.agency),
      jobOrders: num(x.job_orders),
      submissions: num(x.submissions),
      canAnswer: x.can_answer === true,
    }));
}

export type ClientJobOrder = {
  id: string;
  reference: string | null;
  title: string;
  openings: number;
  status: string;
  location: string | null;
  workType: string | null;
  startDate: string | null;
  pay: { min: number | null; max: number | null; period: string | null; currency: string | null };
  clientJobId: string | null;
  clientJobTitle: string | null;
  agency: AgencyRef;
  submissions: number;
};

export function parseClientJobOrders(raw: Json | null): ClientJobOrder[] {
  return arr(raw)
    .filter(isObj)
    .map((x) => {
      const pay = isObj(x.pay) ? x.pay : {};
      return {
        id: String(x.id ?? ''),
        reference: str(x.reference),
        title: str(x.title) ?? 'Job order',
        openings: num(x.openings) || 1,
        status: str(x.status) ?? 'open',
        location: str(x.location_text),
        workType: str(x.work_type),
        startDate: str(x.start_date),
        pay: {
          min: numOrNull(pay.min),
          max: numOrNull(pay.max),
          period: str(pay.period),
          currency: str(pay.currency),
        },
        clientJobId: str(x.client_job_id),
        clientJobTitle: str(x.client_job_title),
        agency: agencyRef(x.agency),
        submissions: num(x.submissions),
      };
    });
}

export type ClientSubmission = {
  submissionId: string;
  applicationId: string | null;
  jobId: string | null;
  jobTitle: string | null;
  candidateName: string;
  appliedAs: string | null;
  profession: string | null;
  matchScore: number | null;
  stage: string | null;
  submittedAt: string | null;
  agency: AgencyRef;
  recruiter: string | null;
  recruiterNote: string | null;
  consentStatus: string;
  shared: string[];
};

export function parseClientSubmissions(raw: Json | null): ClientSubmission[] {
  return arr(raw)
    .filter(isObj)
    .map((x) => {
      const c = isObj(x.candidate) ? x.candidate : {};
      return {
        submissionId: String(x.submission_id ?? ''),
        applicationId: str(x.application_id),
        jobId: str(x.job_id),
        jobTitle: str(x.job_title),
        candidateName: str(c.name) ?? 'Candidate',
        appliedAs: str(x.applied_as),
        profession: str(c.profession),
        matchScore: numOrNull(x.match_score),
        stage: str(x.stage),
        submittedAt: str(x.submitted_at),
        agency: agencyRef(x.agency),
        recruiter: str(x.recruiter),
        recruiterNote: str(x.recruiter_note),
        consentStatus: str(x.consent_status) ?? 'active',
        shared: strs(x.shared),
      };
    });
}

export const CLIENT_CONSENT: Record<string, Tone> = {
  active: { label: 'Consent active', color: C.good },
  withdrawn: { label: 'Candidate withdrew consent', color: C.bad },
  ended: { label: 'Consent ended', color: C.muted },
};

/* ------------------------------------------------------------------ */
/* Team invitations                                                    */
/* ------------------------------------------------------------------ */

export type TeamInvitation = {
  id: string;
  role: string;
  expiresAt: string | null;
  invitedAt: string | null;
  invitedBy: string | null;
  company: { id: string; name: string; kind: string; verified: boolean; logoUrl: string | null };
};

export function parseTeamInvitations(raw: Json | null): TeamInvitation[] {
  return arr(raw)
    .filter(isObj)
    .map((x) => {
      const c = isObj(x.company) ? x.company : {};
      return {
        id: String(x.id ?? ''),
        role: str(x.role) ?? 'viewer',
        expiresAt: str(x.expires_at),
        invitedAt: str(x.invited_at),
        invitedBy: str(x.invited_by),
        company: {
          id: String(c.id ?? ''),
          name: str(c.name) ?? 'A company',
          kind: str(c.kind) ?? 'employer',
          verified: c.verified === true,
          logoUrl: str(c.logo_url),
        },
      };
    })
    .filter((i) => i.id);
}

/* ------------------------------------------------------------------ */
/* Small helpers                                                       */
/* ------------------------------------------------------------------ */

/** Days from now until an instant (negative when past). */
export function daysLeft(iso: string | null, nowMs: number): number | null {
  if (!iso) return null;
  return Math.ceil((new Date(iso).getTime() - nowMs) / 86_400_000);
}

export function sumBy<T>(items: T[], f: (t: T) => number | null | undefined): number {
  return items.reduce((s, t) => s + (f(t) ?? 0), 0);
}
