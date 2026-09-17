/**
 * Shared vocabulary for interview rounds and Omelo Meet (architecture/A6).
 *
 * The database owns every rule (join window, who may admit, what is private).
 * This file only decides how the portal words things and what it offers.
 */

export type MeetingMode = 'omelo_meet' | 'phone' | 'in_person';
export type RoundKind =
  | 'screening'
  | 'technical'
  | 'practical'
  | 'hiring_manager'
  | 'culture'
  | 'final'
  | 'general';

export const MEETING_MODE_LABEL: Record<MeetingMode, string> = {
  omelo_meet: 'Omelo Meet video',
  phone: 'Phone',
  in_person: 'In person',
};

export function meetingModeLabel(mode: string | null | undefined) {
  return MEETING_MODE_LABEL[(mode ?? '') as MeetingMode] ?? 'Interview';
}

export const ROUND_KINDS: { value: RoundKind; label: string }[] = [
  { value: 'screening', label: 'Screening' },
  { value: 'technical', label: 'Technical' },
  { value: 'practical', label: 'Practical' },
  { value: 'hiring_manager', label: 'Hiring manager' },
  { value: 'culture', label: 'Culture' },
  { value: 'final', label: 'Final' },
  { value: 'general', label: 'General' },
];

export function roundKindLabel(kind: string | null | undefined) {
  return ROUND_KINDS.find((k) => k.value === kind)?.label ?? 'General';
}

/** Common round names offered in the schedule form, with their kind. */
export const ROUND_PRESETS: { name: string; kind: RoundKind; mode?: MeetingMode; duration?: number }[] = [
  { name: 'Screening call', kind: 'screening', duration: 15 },
  { name: 'Technical Interview', kind: 'technical', duration: 60 },
  { name: 'System Design', kind: 'technical', duration: 60 },
  { name: 'Practical test / Trial shift', kind: 'practical', mode: 'in_person', duration: 90 },
  { name: 'Hiring Manager', kind: 'hiring_manager', duration: 45 },
  { name: 'Final Interview', kind: 'final', duration: 45 },
];

export const DURATIONS = [15, 30, 45, 60, 90];

export type PlannedRound = {
  id: string;
  position: number;
  name: string;
  kind: string;
  meeting_mode: string;
  duration_minutes: number;
};

/* ------------------------------------------------------------------ */
/* Feedback                                                            */
/* ------------------------------------------------------------------ */

export type Recommendation = 'strong_hire' | 'hire' | 'further_review' | 'no_hire';

export const RECOMMENDATION_OPTIONS: { value: Recommendation; label: string; tone: string }[] = [
  { value: 'strong_hire', label: 'Strong Hire', tone: 'var(--color-verified)' },
  { value: 'hire', label: 'Hire', tone: 'var(--color-verified)' },
  { value: 'further_review', label: 'Further Review', tone: 'var(--color-warn)' },
  { value: 'no_hire', label: 'No Hire', tone: 'var(--color-danger)' },
];

export function recommendationLabel(r: string | null | undefined) {
  return RECOMMENDATION_OPTIONS.find((o) => o.value === r) ?? null;
}

export type Assessment = 'strong' | 'meets' | 'needs_development' | 'not_assessed';

export const ASSESSMENT_OPTIONS: { value: Assessment; label: string; tone: string }[] = [
  { value: 'strong', label: 'Strong', tone: 'var(--color-verified)' },
  { value: 'meets', label: 'Meets', tone: 'var(--fg)' },
  { value: 'needs_development', label: 'Needs development', tone: 'var(--color-warn)' },
  { value: 'not_assessed', label: 'Not assessed', tone: 'var(--muted)' },
];

export const DEFAULT_COMPETENCIES = [
  'Technical skills',
  'Communication',
  'Problem solving',
  'Teamwork',
  'Reliability',
];

export type Evaluation = 'strong' | 'good' | 'weak' | 'not_asked';

export const EVALUATION_OPTIONS: { value: Evaluation; label: string; tone: string }[] = [
  { value: 'strong', label: 'Strong', tone: 'var(--color-verified)' },
  { value: 'good', label: 'Good', tone: 'var(--fg)' },
  { value: 'weak', label: 'Weak', tone: 'var(--color-warn)' },
  { value: 'not_asked', label: 'Not asked', tone: 'var(--muted)' },
];

export type Competency = { name: string; assessment: Assessment };
export type SkillAssessed = { skill_id?: string | null; name: string; demonstrated: boolean };

export function asCompetencies(v: unknown): Competency[] {
  return Array.isArray(v)
    ? v
        .filter((c): c is { name: string; assessment?: string } => !!c && typeof c.name === 'string')
        .map((c) => ({
          name: c.name,
          assessment: (ASSESSMENT_OPTIONS.some((o) => o.value === c.assessment)
            ? c.assessment
            : 'not_assessed') as Assessment,
        }))
    : [];
}

export function asSkills(v: unknown): SkillAssessed[] {
  return Array.isArray(v)
    ? v
        .filter((s): s is { name: string; skill_id?: string; demonstrated?: boolean } => !!s && typeof s.name === 'string')
        .map((s) => ({ skill_id: s.skill_id ?? null, name: s.name, demonstrated: !!s.demonstrated }))
    : [];
}

/* ------------------------------------------------------------------ */
/* Join window                                                         */
/* ------------------------------------------------------------------ */

export const ROOM_NAME_RE = /^om-[0-9a-f]{36}$/;

export type JoinWindow =
  | { kind: 'before'; ms: number }
  | { kind: 'open' }
  | { kind: 'closed' };

export function joinWindow(opensAt: string, closesAt: string, now: number): JoinWindow {
  const open = new Date(opensAt).getTime();
  const close = new Date(closesAt).getTime();
  if (now < open) return { kind: 'before', ms: open - now };
  if (now > close) return { kind: 'closed' };
  return { kind: 'open' };
}

/** 00:18:42, or "2 days" when far away. */
export function countdown(ms: number) {
  const total = Math.max(0, Math.floor(ms / 1000));
  const days = Math.floor(total / 86_400);
  if (days >= 2) return `${days} days`;
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  return [h, m, s].map((n) => String(n).padStart(2, '0')).join(':');
}

export function initials(name: string | null | undefined) {
  const parts = (name ?? '').trim().split(/\s+/).filter(Boolean);
  return ((parts[0]?.[0] ?? '?') + (parts.length > 1 ? parts[parts.length - 1][0] : '')).toUpperCase();
}
