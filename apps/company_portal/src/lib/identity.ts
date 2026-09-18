/**
 * Release 2 — universal professional identity, employer side.
 *
 * A worker can hold several work identities (Driver, Cook, Engineer…). An
 * employer only ever sees the identity the candidate applied with, plus rows
 * the worker shares across identities. These helpers shape what the database
 * returns for that one identity; they never widen it.
 */
import type { Json } from '@/lib/supabase/database.types';

export type EvidenceType =
  | 'verified_employment'
  | 'employer_verified'
  | 'assessment'
  | 'experience'
  | 'project'
  | 'self_declared';

export type EvidenceItem = { type: EvidenceType; label: string; verified: boolean };

export type EvidenceSkill = {
  skill_id: string;
  name: string;
  proficiency: string | null;
  months_used: number | null;
  verified: boolean;
  evidence: EvidenceItem[];
};

export type IdentityEvidence = {
  identity: { id: string; label: string; profession: string | null; completeness: number | null };
  skills: EvidenceSkill[];
  verified_employment: {
    employer: string;
    title: string;
    started_on: string | null;
    ended_on: string | null;
    is_current: boolean;
  }[];
  licences: { name: string | null; class: string | null; verified: boolean; expires_on: string | null }[];
  credentials: { name: string; issuer: string | null; verified: boolean; expires_on: string | null }[];
  trust: { email_verified: boolean; phone_verified: boolean; identity_verified: boolean };
};

/** Result of `omelo_identity_evidence`, with the permission case split out. */
export type EvidenceResult =
  | { status: 'ok'; data: IdentityEvidence }
  | { status: 'forbidden' }
  | { status: 'error'; message: string };

/** 42501 — the viewer may not see this identity (e.g. not on the hiring team). */
export const FORBIDDEN_CODE = '42501';

const arr = <T>(v: unknown): T[] => (Array.isArray(v) ? (v as T[]) : []);

/** Defensive parse of the RPC's jsonb; missing keys become empty, not crashes. */
export function parseEvidence(raw: Json | null): IdentityEvidence | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const r = raw as Record<string, unknown>;
  const id = (r.identity ?? {}) as Record<string, unknown>;
  const trust = (r.trust ?? {}) as Record<string, unknown>;
  const skills = arr<EvidenceSkill>(r.skills).map((s) => ({
    ...s,
    evidence: arr<EvidenceItem>(s.evidence),
  }));
  // Verified first, then longest use, then name — the RPC already orders this
  // way; sorting again keeps the UI honest if that ever changes.
  skills.sort(
    (a, b) =>
      Number(b.verified) - Number(a.verified) ||
      (b.months_used ?? -1) - (a.months_used ?? -1) ||
      a.name.localeCompare(b.name)
  );
  return {
    identity: {
      id: String(id.id ?? ''),
      label: String(id.label ?? ''),
      profession: (id.profession as string | null) ?? null,
      completeness: typeof id.completeness === 'number' ? id.completeness : null,
    },
    skills,
    verified_employment: arr(r.verified_employment),
    licences: arr(r.licences),
    credentials: arr(r.credentials),
    trust: {
      email_verified: trust.email_verified === true,
      phone_verified: trust.phone_verified === true,
      identity_verified: trust.identity_verified === true,
    },
  };
}

export function toEvidenceResult(
  data: Json | null,
  error: { code?: string; message: string } | null
): EvidenceResult {
  if (error) {
    return error.code === FORBIDDEN_CODE
      ? { status: 'forbidden' }
      : { status: 'error', message: error.message };
  }
  const parsed = parseEvidence(data);
  return parsed ? { status: 'ok', data: parsed } : { status: 'error', message: 'No evidence returned.' };
}

export type Badge = { key: string; text: string; verified: boolean; title?: string };

function yearsText(months: number) {
  if (months < 12) return `${months} mo experience`;
  const y = Math.round((months / 12) * 10) / 10;
  return `${y} yr${y === 1 ? '' : 's'} experience`;
}

/**
 * Short badges for one skill. "Self-declared" is shown only when nothing
 * verified backs the skill — otherwise it would undersell real evidence.
 */
export function skillBadges(s: EvidenceSkill): Badge[] {
  const out: Badge[] = [];
  const hasVerified = s.evidence.some((e) => e.verified);
  s.evidence.forEach((e, i) => {
    const key = `${e.type}-${i}`;
    switch (e.type) {
      case 'verified_employment':
        out.push({ key, text: 'Verified employment ✓', verified: true, title: e.label });
        break;
      case 'employer_verified':
        out.push({ key, text: 'Employer-confirmed ✓', verified: true, title: e.label });
        break;
      case 'assessment':
        out.push({ key, text: 'Assessment ✓', verified: true, title: e.label });
        break;
      case 'experience':
        out.push({
          key,
          text: s.months_used ? yearsText(s.months_used) : e.label,
          verified: false,
          title: e.label,
        });
        break;
      case 'project':
        out.push({ key, text: e.label, verified: false });
        break;
      case 'self_declared':
        if (!hasVerified) out.push({ key, text: 'Self-declared', verified: false, title: e.label });
        break;
    }
  });
  return out;
}

/* ------------------------------------------------------------------ */
/* Adaptive profile answers                                            */
/* ------------------------------------------------------------------ */

export type AttributeDataType =
  | 'text'
  | 'long_text'
  | 'number'
  | 'boolean'
  | 'single_select'
  | 'multi_select'
  | 'date'
  | 'years'
  | 'file'
  | 'location';

export type ProfileAnswer = {
  id: string;
  label: string;
  dataType: AttributeDataType;
  position: number;
  /** A list for multi_select, otherwise a single display string. */
  value: string | string[];
};

type AttributeRow = {
  id: string;
  value_text: string | null;
  value_number: number | null;
  value_bool: boolean | null;
  value_date: string | null;
  value_json: Json | null;
  profile_attributes: unknown;
};

function jsonText(v: Json | null): string | null {
  if (v == null) return null;
  if (typeof v === 'string') return v;
  if (typeof v === 'object' && !Array.isArray(v)) {
    const o = v as Record<string, unknown>;
    const t = o.label ?? o.name ?? o.text ?? o.city;
    if (typeof t === 'string') return t;
  }
  return JSON.stringify(v);
}

function dateText(d: string) {
  return new Date(d.slice(0, 10) + 'T00:00:00Z').toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    timeZone: 'UTC',
  });
}

/** Format a `person_attributes` row per its attribute's data type. */
export function toProfileAnswer(row: AttributeRow): ProfileAnswer | null {
  const a = row.profile_attributes as {
    label: string;
    data_type: AttributeDataType;
    unit: string | null;
    position: number | null;
  } | null;
  if (!a) return null;
  const unit = a.unit ? ` ${a.unit}` : '';
  let value: string | string[] | null = null;
  switch (a.data_type) {
    case 'multi_select':
      value = Array.isArray(row.value_json)
        ? row.value_json.map((x) => jsonText(x) ?? '').filter(Boolean)
        : null;
      if (value && value.length === 0) value = null;
      break;
    case 'boolean':
      value = row.value_bool == null ? null : row.value_bool ? 'Yes' : 'No';
      break;
    case 'years':
      value =
        row.value_number == null
          ? null
          : `${row.value_number} year${row.value_number === 1 ? '' : 's'}`;
      break;
    case 'number':
      value = row.value_number == null ? null : `${row.value_number.toLocaleString('en-IN')}${unit}`;
      break;
    case 'date':
      value = row.value_date ? dateText(row.value_date) : null;
      break;
    case 'location':
      value = row.value_text ?? jsonText(row.value_json);
      break;
    case 'file':
      value = row.value_text ? 'File provided' : null;
      break;
    default:
      value = row.value_text ? `${row.value_text}${a.data_type === 'text' ? unit : ''}` : null;
  }
  if (value == null || value === '') return null;
  return { id: row.id, label: a.label, dataType: a.data_type, position: a.position ?? 0, value };
}

export function toProfileAnswers(rows: AttributeRow[]): ProfileAnswer[] {
  return rows
    .map(toProfileAnswer)
    .filter((x): x is ProfileAnswer => x !== null)
    .sort((a, b) => a.position - b.position || a.label.localeCompare(b.label));
}

/** Select for `person_attributes` joined to its definition. */
export const PROFILE_ANSWER_SELECT =
  'id, value_text, value_number, value_bool, value_date, value_json, profile_attributes ( label, data_type, unit, position )';

/** PostgREST filter: this identity's rows, plus rows shared across identities. */
export const identityScope = (identityId: string) =>
  `work_identity_id.is.null,work_identity_id.eq.${identityId}`;
