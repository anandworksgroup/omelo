/**
 * Release 8 — Enterprise organizations, approvals and RPO, employer side.
 *
 * The structure tables (business_units, departments, teams, company_role_grants)
 * are read through RLS; the approval and RPO functions return jsonb. These
 * helpers parse that jsonb defensively — a missing field stays null and a
 * missing object never crashes a page — and turn the database's vocabulary
 * into the words a person reads on screen.
 *
 * Nothing here decides access. A scoped member simply sees fewer rows, and an
 * action their scope does not cover comes back as 42501; `enterpriseError`
 * turns that into one sentence instead of a stack trace (R8-002).
 */
import type { Json } from '@/lib/supabase/database.types';
import { roleLabel } from '@/lib/agency';

type Obj = Record<string, unknown>;
const isObj = (v: unknown): v is Obj => !!v && typeof v === 'object' && !Array.isArray(v);
const arr = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);
const str = (v: unknown): string | null => (typeof v === 'string' && v.trim() ? v : null);
const count = (v: unknown): number => {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
};
const strings = (v: unknown): string[] => arr(v).filter((x): x is string => typeof x === 'string');

/* ------------------------------------------------------------------ */
/* Errors                                                              */
/* ------------------------------------------------------------------ */

/** What a person is told when their scope does not reach something. */
export const NO_ACCESS = "You don't have access to this part of the organization.";

/**
 * One sentence for anything the database refuses.
 *
 * The R8 functions raise their own plain-English messages (for example "Only
 * an owner or admin sets approval workflows"), so those are shown as they are.
 * A bare row-level-security refusal has no sentence of its own, and that is
 * the case `NO_ACCESS` covers.
 */
export function enterpriseError(e: { code?: string; message?: string } | null | undefined): {
  forbidden: boolean;
  text: string;
} {
  const m = (e?.message ?? '').trim();
  if (e?.code === '42501')
    return {
      forbidden: true,
      text: !m || /row-level security|permission denied|violates|not allowed/i.test(m) ? NO_ACCESS : m,
    };
  if (e?.code === '22023') return { forbidden: false, text: m || 'Omelo could not do that here.' };
  if (e?.code === '23505') return { forbidden: false, text: m || 'That already exists.' };
  return { forbidden: false, text: m || 'Something went wrong.' };
}

/* ------------------------------------------------------------------ */
/* What kind of organization this is                                   */
/* ------------------------------------------------------------------ */

export const ORGANIZATION_TYPES = [
  'employer',
  'staffing_agency',
  'recruitment_agency',
  'rpo_provider',
  'workforce_provider',
] as const;
export type OrganizationType = (typeof ORGANIZATION_TYPES)[number];

export const ORGANIZATION_TYPE_LABEL: Record<OrganizationType, string> = {
  employer: 'Employer',
  staffing_agency: 'Staffing agency',
  recruitment_agency: 'Recruitment agency',
  rpo_provider: 'RPO provider',
  workforce_provider: 'Workforce provider',
};

export const ORGANIZATION_TYPE_HELP: Record<OrganizationType, string> = {
  employer: 'You hire for yourself. Jobs, candidates and workforce are your own.',
  staffing_agency: 'You supply workers to client organizations and manage their shifts and pay.',
  recruitment_agency: 'You find candidates for client organizations and submit them to client job orders.',
  rpo_provider: 'You run part of a client’s recruiting inside their own pipeline, under an engagement they confirm.',
  workforce_provider: 'You manage a workforce on behalf of others — assignments, attendance and timesheets.',
};

export const isAgencyType = (t: string) => t !== 'employer';

/** Organization types that may create an RPO engagement as the provider. */
export const RPO_PROVIDER_TYPES: string[] = ['rpo_provider', 'recruitment_agency', 'staffing_agency'];

export function asOrganizationType(v: string | null | undefined): OrganizationType {
  return (ORGANIZATION_TYPES as readonly string[]).includes(v ?? '') ? (v as OrganizationType) : 'employer';
}

/* ------------------------------------------------------------------ */
/* Structure                                                           */
/* ------------------------------------------------------------------ */

export type BusinessUnit = {
  id: string;
  parentId: string | null;
  name: string;
  code: string | null;
  isActive: boolean;
};

export type UnitNode = BusinessUnit & { depth: number };

/**
 * Business units flattened into reading order, parents before children.
 * A unit whose parent is missing (or points at itself through a cycle) is
 * shown at the top rather than dropped.
 */
export function unitTree(units: BusinessUnit[]): UnitNode[] {
  const byParent = new Map<string | null, BusinessUnit[]>();
  const ids = new Set(units.map((u) => u.id));
  for (const u of units) {
    const key = u.parentId && ids.has(u.parentId) ? u.parentId : null;
    const list = byParent.get(key);
    if (list) list.push(u);
    else byParent.set(key, [u]);
  }
  const out: UnitNode[] = [];
  const seen = new Set<string>();
  const walk = (parent: string | null, depth: number) => {
    for (const u of byParent.get(parent) ?? []) {
      if (seen.has(u.id)) continue;
      seen.add(u.id);
      out.push({ ...u, depth });
      if (depth < 6) walk(u.id, depth + 1);
    }
  };
  walk(null, 0);
  // Anything left behind a cycle still deserves a row.
  for (const u of units) if (!seen.has(u.id)) out.push({ ...u, depth: 0 });
  return out;
}

export const TEAM_PURPOSES = ['hiring', 'workforce', 'rpo', 'general'] as const;
export type TeamPurpose = (typeof TEAM_PURPOSES)[number];
export const TEAM_PURPOSE_LABEL: Record<TeamPurpose, string> = {
  hiring: 'Hiring',
  workforce: 'Workforce',
  rpo: 'RPO',
  general: 'General',
};

/* ------------------------------------------------------------------ */
/* Scoped roles                                                        */
/* ------------------------------------------------------------------ */

export const GRANT_SCOPES = ['organization', 'business_unit', 'department', 'location', 'legal_entity'] as const;
export type GrantScope = (typeof GRANT_SCOPES)[number];

export const GRANT_SCOPE_LABEL: Record<GrantScope, string> = {
  organization: 'Whole organization',
  business_unit: 'Business unit',
  department: 'Department',
  location: 'Location',
  legal_entity: 'Legal entity',
};

/** The noun used after the thing's own name: "Engineering department only". */
export const GRANT_SCOPE_NOUN: Record<GrantScope, string> = {
  organization: 'organization',
  business_unit: 'business unit',
  department: 'department',
  location: 'location',
  legal_entity: 'legal entity',
};

export const SCOPE_MODES = ['organization', 'scoped'] as const;
export type ScopeMode = (typeof SCOPE_MODES)[number];

export const SCOPE_MODE_LABEL: Record<ScopeMode, string> = {
  organization: 'Whole organization',
  scoped: 'Only what they are granted',
};

export const SCOPE_MODE_HELP: Record<ScopeMode, string> = {
  organization: 'They work across the whole organization, the way Omelo worked before.',
  scoped: 'They reach only the parts granted below — jobs, candidates and everything downstream.',
};

/** "Recruiter — Engineering department only", in the words a person reads. */
export function grantSentence(role: string, scopeType: string, label: string | null): string {
  const r = roleLabel(role);
  if (scopeType === 'organization') return `${r} — everywhere in the organization`;
  const noun = GRANT_SCOPE_NOUN[scopeType as GrantScope] ?? scopeType.replace(/_/g, ' ');
  return `${r} — ${label ?? 'a part of the organization'} ${noun} only`;
}

/* ------------------------------------------------------------------ */
/* Approvals                                                           */
/* ------------------------------------------------------------------ */

export const APPROVAL_ENTITIES = ['job', 'workforce_requirement', 'offer'] as const;
export type ApprovalEntity = (typeof APPROVAL_ENTITIES)[number];

export const APPROVAL_ENTITY_LABEL: Record<ApprovalEntity, string> = {
  job: 'Job',
  workforce_requirement: 'Workforce requirement',
  offer: 'Offer',
};

export const APPROVAL_ENTITY_HELP: Record<ApprovalEntity, string> = {
  job: 'A job cannot go live until this chain has approved it.',
  workforce_requirement: 'A workforce requirement cannot open until this chain has approved it.',
  offer: 'Offers are sent for approval before they reach the candidate.',
};

export const APPROVAL_STATUS_LABEL: Record<string, string> = {
  pending: 'Waiting',
  approved: 'Approved',
  rejected: 'Not approved',
  cancelled: 'Withdrawn',
};

export const APPROVAL_STATUS_COLOR: Record<string, string> = {
  pending: 'var(--color-warn)',
  approved: 'var(--color-verified)',
  rejected: 'var(--color-danger)',
  cancelled: 'var(--muted)',
};

/** Where an entity lives, for the link on an approval task. */
export function approvalHref(entityType: string, entityId: string): string | null {
  if (entityType === 'job') return `/dashboard/jobs/${entityId}`;
  if (entityType === 'workforce_requirement') return `/dashboard/workforce/requirements/${entityId}`;
  if (entityType === 'offer') return '/dashboard/offers';
  return null;
}

export type ApprovalTask = {
  requestId: string;
  companyId: string | null;
  entityType: string;
  entityId: string;
  step: string;
  position: number;
  role: string;
  requestedAt: string | null;
  requestedByMe: boolean;
  note: string | null;
  title: string | null;
};

/** omelo_my_approvals → the list of things waiting for this person. */
export function parseMyApprovals(raw: Json | null): ApprovalTask[] {
  return arr(raw)
    .filter(isObj)
    .map((r) => ({
      requestId: str(r.request_id) ?? '',
      companyId: str(r.company_id),
      entityType: str(r.entity_type) ?? 'job',
      entityId: str(r.entity_id) ?? '',
      step: str(r.step) ?? 'Approval',
      position: count(r.position),
      role: str(r.role) ?? 'owner',
      requestedAt: str(r.requested_at),
      requestedByMe: r.requested_by_me === true,
      note: str(r.note),
      title: str(r.title),
    }))
    .filter((t) => t.requestId && t.entityId);
}

export type ApprovalStepState = {
  position: number;
  name: string;
  role: string;
  required: number;
  approvals: number;
};

export type ApprovalDecision = {
  position: number;
  decision: string;
  note: string | null;
  at: string | null;
};

export type ApprovalRequest = {
  id: string;
  status: string;
  position: number;
  requestedAt: string | null;
  decidedAt: string | null;
  steps: ApprovalStepState[];
  decisions: ApprovalDecision[];
};

export type ApprovalStatus = {
  /** True when an active workflow exists for this kind of thing. */
  required: boolean;
  request: ApprovalRequest | null;
};

/** omelo_approval_status → the panel on a job, requirement or offer. */
export function parseApprovalStatus(raw: Json | null): ApprovalStatus | null {
  if (!isObj(raw)) return null;
  const r = raw.request;
  return {
    required: raw.required === true,
    request: isObj(r)
      ? {
          id: str(r.id) ?? '',
          status: str(r.status) ?? 'pending',
          position: count(r.position),
          requestedAt: str(r.requested_at),
          decidedAt: str(r.decided_at),
          steps: arr(r.steps)
            .filter(isObj)
            .map((s) => ({
              position: count(s.position),
              name: str(s.name) ?? 'Step',
              role: str(s.role) ?? 'owner',
              required: Math.max(1, count(s.required)),
              approvals: count(s.approvals),
            }))
            .sort((a, b) => a.position - b.position),
          decisions: arr(r.decisions)
            .filter(isObj)
            .map((d) => ({
              position: count(d.position),
              decision: str(d.decision) ?? 'approved',
              note: str(d.note),
              at: str(d.at),
            })),
        }
      : null,
  };
}

/** Is a step done, in progress, or still ahead? */
export function stepState(
  step: ApprovalStepState,
  request: ApprovalRequest
): 'approved' | 'current' | 'waiting' | 'stopped' {
  if (step.approvals >= step.required) return 'approved';
  if (request.status === 'rejected' && step.position === request.position) return 'stopped';
  if (request.status === 'pending' && step.position === request.position) return 'current';
  return 'waiting';
}

/**
 * Why publishing is refused, in plain words. The trigger raises 42501 with
 * "This organization approves job before it goes live…"; this is the same
 * thing said before the round trip.
 */
export function publishBlockedReason(status: ApprovalStatus | null): string | null {
  if (!status?.required) return null;
  const r = status.request;
  if (r && r.status === 'approved') return null;
  if (!r || r.status === 'cancelled')
    return 'This organization approves a job before it goes live. Submit it for approval first.';
  if (r.status === 'pending') return 'This job is waiting for approval. It can go live once the chain has approved it.';
  return 'This job was not approved, so it cannot go live. Ask the approver what to change, then submit it again.';
}

/* ------------------------------------------------------------------ */
/* RPO                                                                 */
/* ------------------------------------------------------------------ */

export const RPO_PERMISSIONS = [
  'view_jobs',
  'manage_jobs',
  'view_candidates',
  'move_candidates',
  'schedule_interviews',
  'send_offers',
  'view_reports',
] as const;
export type RpoPermission = (typeof RPO_PERMISSIONS)[number];

export const RPO_PERMISSION_LABEL: Record<RpoPermission, string> = {
  view_jobs: 'See jobs',
  manage_jobs: 'Edit jobs',
  view_candidates: 'See candidates',
  move_candidates: 'Move candidates',
  schedule_interviews: 'Schedule interviews',
  send_offers: 'Send offers',
  view_reports: 'See reports',
};

export const RPO_PERMISSION_HELP: Record<RpoPermission, string> = {
  view_jobs: 'Read the jobs inside the scope below.',
  manage_jobs: 'Create and edit those jobs.',
  view_candidates: 'Read the applicants on those jobs.',
  move_candidates: 'Move applicants through the client’s own pipeline.',
  schedule_interviews: 'Set up interviews on those applications.',
  send_offers: 'Send offers on those applications.',
  view_reports: 'Read the hiring reports for that part of the organization.',
};

export const rpoPermissionLabel = (p: string) =>
  RPO_PERMISSION_LABEL[p as RpoPermission] ?? p.replace(/_/g, ' ');

export const RPO_SCOPES = ['organization', 'business_unit', 'department', 'location', 'job', 'profession'] as const;
export type RpoScopeType = (typeof RPO_SCOPES)[number];

export const RPO_SCOPE_LABEL: Record<RpoScopeType, string> = {
  organization: 'Whole organization',
  business_unit: 'Business unit',
  department: 'Department',
  location: 'Location',
  job: 'One job',
  profession: 'Profession',
};

export const RPO_STATUSES = [
  'draft',
  'pending_approval',
  'active',
  'paused',
  'completed',
  'terminated',
] as const;
export type RpoStatus = (typeof RPO_STATUSES)[number];

export const RPO_STATUS_LABEL: Record<string, string> = {
  draft: 'Draft',
  pending_approval: 'Waiting for the client',
  active: 'Active',
  paused: 'Paused',
  completed: 'Completed',
  terminated: 'Ended',
};

export const RPO_STATUS_COLOR: Record<string, string> = {
  draft: 'var(--muted)',
  pending_approval: 'var(--color-warn)',
  active: 'var(--color-verified)',
  paused: 'var(--color-warn)',
  completed: 'var(--muted)',
  terminated: 'var(--color-danger)',
};

export const RPO_RECRUITER_ROLES = ['lead', 'recruiter', 'coordinator', 'sourcer'] as const;
export const RPO_RECRUITER_ROLE_LABEL: Record<string, string> = {
  lead: 'Lead',
  recruiter: 'Recruiter',
  coordinator: 'Coordinator',
  sourcer: 'Sourcer',
};

export type RpoScope = { scopeType: string; scopeId: string | null; label: string | null };
export type RpoRecruiter = { personId: string; role: string; active: boolean; name: string | null };

export type Engagement = {
  id: string;
  title: string;
  reference: string | null;
  status: string;
  /** Which side of the engagement the current workspace is on. */
  side: 'provider' | 'client';
  provider: string | null;
  client: string | null;
  providerId: string | null;
  clientCompanyId: string | null;
  permissions: string[];
  startDate: string | null;
  endDate: string | null;
  scopes: RpoScope[];
  recruiters: RpoRecruiter[];
  openJobs: number;
};

/** omelo_rpo_engagements → both sides of every engagement this workspace is in. */
export function parseEngagements(raw: Json | null): Engagement[] {
  return arr(raw)
    .filter(isObj)
    .map((e) => ({
      id: str(e.id) ?? '',
      title: str(e.title) ?? 'RPO engagement',
      reference: str(e.reference),
      status: str(e.status) ?? 'draft',
      side: e.side === 'provider' ? ('provider' as const) : ('client' as const),
      provider: str(e.provider),
      client: str(e.client),
      providerId: str(e.provider_id),
      clientCompanyId: str(e.client_company_id),
      permissions: strings(e.permissions),
      startDate: str(e.start_date),
      endDate: str(e.end_date),
      scopes: arr(e.scopes)
        .filter(isObj)
        .map((s) => ({
          scopeType: str(s.scope_type) ?? 'organization',
          scopeId: str(s.scope_id),
          label: str(s.label),
        })),
      recruiters: arr(e.recruiters)
        .filter(isObj)
        .map((r) => ({
          personId: str(r.person_id) ?? '',
          role: str(r.role) ?? 'recruiter',
          active: r.active !== false,
          name: str(r.name),
        })),
      openJobs: count(e.open_jobs),
    }))
    .filter((e) => e.id);
}

/** One scope line, as a person reads it: "Engineering department". */
export function rpoScopeText(s: RpoScope): string {
  if (s.scopeType === 'organization') return 'The whole organization';
  const noun = RPO_SCOPE_LABEL[s.scopeType as RpoScopeType] ?? s.scopeType.replace(/_/g, ' ');
  return s.label ? `${s.label} · ${noun.toLowerCase()}` : noun;
}

export type RpoWorkItem = {
  engagementId: string;
  client: string | null;
  clientCompanyId: string | null;
  permissions: string[];
  jobId: string;
  title: string;
  status: string;
  openings: number;
  department: string | null;
  locationText: string | null;
  applicants: number;
  newApplicants: number;
  publishedAt: string | null;
};

/** omelo_rpo_my_work → the client jobs the signed-in recruiter may work on. */
export function parseRpoWork(raw: Json | null): RpoWorkItem[] {
  return arr(raw)
    .filter(isObj)
    .map((w) => ({
      engagementId: str(w.engagement_id) ?? '',
      client: str(w.client),
      clientCompanyId: str(w.client_company_id),
      permissions: strings(w.permissions),
      jobId: str(w.job_id) ?? '',
      title: str(w.title) ?? 'Job',
      status: str(w.status) ?? 'draft',
      openings: count(w.openings),
      department: str(w.department),
      locationText: str(w.location_text),
      applicants: count(w.applicants),
      newApplicants: count(w.new_applicants),
      publishedAt: str(w.published_at),
    }))
    .filter((w) => w.jobId);
}

/** The work list grouped the way it is read: one client at a time. */
export function groupWorkByClient(items: RpoWorkItem[]): {
  engagementId: string;
  client: string;
  clientCompanyId: string | null;
  permissions: string[];
  jobs: RpoWorkItem[];
}[] {
  const map = new Map<string, ReturnType<typeof groupWorkByClient>[number]>();
  for (const w of items) {
    const key = w.engagementId || (w.clientCompanyId ?? 'unknown');
    const g = map.get(key);
    if (g) g.jobs.push(w);
    else
      map.set(key, {
        engagementId: w.engagementId,
        client: w.client ?? 'Client',
        clientCompanyId: w.clientCompanyId,
        permissions: w.permissions,
        jobs: [w],
      });
  }
  return [...map.values()];
}
