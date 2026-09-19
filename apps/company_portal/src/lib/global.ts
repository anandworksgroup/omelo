/**
 * Release 6 — Global employment & mobility, employer side.
 *
 * Eligibility, country guides and currency conversion come back from
 * SECURITY DEFINER RPCs as jsonb; these helpers parse them defensively
 * (missing keys become empty values, never crashes). The job's global-hiring
 * fields are validated here with the same rules the database trigger
 * (omelo_validate_job_global) applies, so the form can say what is wrong
 * before the round trip. The database still decides.
 */
import type { Json } from '@/lib/supabase/database.types';

type Obj = Record<string, unknown>;
const isObj = (v: unknown): v is Obj => !!v && typeof v === 'object' && !Array.isArray(v);
const arr = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);
const str = (v: unknown): string | null => (typeof v === 'string' && v.trim() ? v : null);
const numOrNull = (v: unknown): number | null => {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
};

/* ------------------------------------------------------------------ */
/* Countries                                                           */
/* ------------------------------------------------------------------ */

export type CountryOption = { code: string; name: string; currency: string | null; timezone: string | null };

const regionNames = (() => {
  try {
    return new Intl.DisplayNames(['en'], { type: 'region' });
  } catch {
    return null;
  }
})();

/** "DE" -> "Germany". Uses the runtime's region names; falls back to the code. */
export function countryName(code: string | null | undefined): string | null {
  if (!code) return null;
  const c = code.trim().toUpperCase();
  try {
    return regionNames?.of(c) ?? c;
  } catch {
    return c;
  }
}

export const COUNTRY_RE = /^[A-Z]{2}$/;
export const CURRENCY_RE = /^[A-Z]{3}$/;

/* ------------------------------------------------------------------ */
/* Eligibility                                                         */
/* ------------------------------------------------------------------ */

export type EligibilityStatus = 'eligible' | 'potentially_eligible' | 'not_eligible';
export type MissingItem = { kind: string; text: string };

export type CardEligibility = {
  status: EligibilityStatus;
  summary: string;
  missing: MissingItem[];
};

export type Authorization = {
  country: string | null;
  status: string | null;
  validFrom: string | null;
  expiresOn: string | null;
  requiresSponsorship: boolean | null;
  restrictions: string | null;
  isVerified: boolean;
};

export type CandidateEligibility = CardEligibility & {
  notes: string[];
  country: string | null;
  sponsorship: string | null;
  authorizationVisibility: string | null;
  /** Null unless the worker chose to share authorization details. */
  authorizations: Authorization[] | null;
  disclaimer: string | null;
};

const STATUSES: EligibilityStatus[] = ['eligible', 'potentially_eligible', 'not_eligible'];

export function parseCardEligibility(raw: unknown): CardEligibility | null {
  if (!isObj(raw)) return null;
  const status = STATUSES.find((s) => s === raw.status);
  if (!status) return null;
  return {
    status,
    summary: str(raw.summary) ?? ELIGIBILITY_LABEL[status],
    missing: arr(raw.missing)
      .map((m) =>
        isObj(m)
          ? { kind: str(m.kind) ?? 'other', text: str(m.text) ?? '' }
          : typeof m === 'string'
            ? { kind: 'other', text: m }
            : null
      )
      .filter((m): m is MissingItem => !!m && !!m.text),
  };
}

export function parseCandidateEligibility(raw: Json | null): CandidateEligibility | null {
  const base = parseCardEligibility(raw);
  if (!base || !isObj(raw)) return null;
  return {
    ...base,
    notes: arr(raw.notes).map((n) => (typeof n === 'string' ? n : '')).filter(Boolean),
    country: str(raw.country),
    sponsorship: str(raw.sponsorship),
    authorizationVisibility: str(raw.authorization_visibility),
    authorizations: Array.isArray(raw.authorizations)
      ? (raw.authorizations as unknown[]).filter(isObj).map((a) => ({
          country: str(a.country),
          status: str(a.status),
          validFrom: str(a.valid_from),
          expiresOn: str(a.expires_on),
          requiresSponsorship: typeof a.requires_sponsorship === 'boolean' ? a.requires_sponsorship : null,
          restrictions: str(a.restrictions),
          isVerified: a.is_verified === true,
        }))
      : null,
    disclaimer: str(raw.disclaimer),
  };
}

/**
 * Labels. "Potentially eligible" means something is missing or unknown — it
 * is never a rejection, and the UI must never word it as one.
 */
export const ELIGIBILITY_LABEL: Record<EligibilityStatus, string> = {
  eligible: 'Eligible',
  potentially_eligible: 'Potentially eligible',
  not_eligible: 'Not currently eligible',
};

export const ELIGIBILITY_COLOR: Record<EligibilityStatus, string> = {
  eligible: 'var(--color-verified)',
  potentially_eligible: 'var(--color-warn)',
  not_eligible: 'var(--muted)',
};

/** "Potentially eligible — missing: Licence: X; Language (German)". */
export function eligibilityText(e: CardEligibility): string {
  const label = ELIGIBILITY_LABEL[e.status];
  if (e.status !== 'potentially_eligible' || e.missing.length === 0) return label;
  return `${label} — missing: ${e.missing.map((m) => m.text).join('; ')}`;
}

export const ELIGIBILITY_FILTERS = ['any', 'eligible', 'potentially_eligible'] as const;
export const ELIGIBILITY_FILTER_LABEL: Record<(typeof ELIGIBILITY_FILTERS)[number], string> = {
  any: 'Anyone',
  eligible: 'Eligible now',
  potentially_eligible: 'Eligible or potentially eligible',
};

export const AUTH_VISIBILITY_LABEL: Record<string, string> = {
  private: 'The candidate keeps their authorization private',
  eligibility_only: 'The candidate shares eligibility only',
  details_with_applications: 'Shared with employers they apply to',
  details_with_visible: 'Shared with employers they are visible to',
};

/* ------------------------------------------------------------------ */
/* Global-hiring fields on a job                                       */
/* ------------------------------------------------------------------ */

export const SPONSORSHIP = ['no', 'yes', 'case_by_case'] as const;
export type Sponsorship = (typeof SPONSORSHIP)[number];
export const SPONSORSHIP_LABEL: Record<Sponsorship, string> = {
  no: 'No sponsorship',
  yes: 'Sponsors work visas',
  case_by_case: 'Sponsorship case by case',
};

export const REMOTE_SCOPES = ['country', 'worldwide', 'timezone', 'countries'] as const;
export type RemoteScope = (typeof REMOTE_SCOPES)[number];
export const REMOTE_SCOPE_LABEL: Record<RemoteScope, string> = {
  country: 'Within the job’s country',
  worldwide: 'Anywhere in the world',
  timezone: 'Within a time-zone range',
  countries: 'In chosen countries',
};

/** Boolean support flags on jobs, in display order. */
export const SUPPORT_FLAGS = [
  'immigration_support',
  'legal_support',
  'visa_fees_covered',
  'travel_assistance',
  'accommodation_assistance',
  'relocation_support',
] as const;
export type SupportFlag = (typeof SUPPORT_FLAGS)[number];
export const SUPPORT_LABEL: Record<SupportFlag, string> = {
  immigration_support: 'Immigration support',
  legal_support: 'Legal support',
  visa_fees_covered: 'Visa fees covered',
  travel_assistance: 'Travel assistance',
  accommodation_assistance: 'Accommodation assistance',
  relocation_support: 'Relocation support',
};

export const TZ_MIN = -720;
export const TZ_MAX = 840;

/** -330 -> "UTC−05:30", 0 -> "UTC±00:00". */
export function utcOffsetLabel(minutes: number): string {
  const sign = minutes === 0 ? '±' : minutes > 0 ? '+' : '−';
  const abs = Math.abs(minutes);
  const hh = String(Math.floor(abs / 60)).padStart(2, '0');
  const mm = String(abs % 60).padStart(2, '0');
  return `UTC${sign}${hh}:${mm}`;
}

/** Every quarter hour from UTC−12:00 to UTC+14:00. */
export const TZ_OPTIONS: number[] = Array.from({ length: (TZ_MAX - TZ_MIN) / 15 + 1 }, (_, i) => TZ_MIN + i * 15);

export type GlobalHiring = {
  country_code: string | null;
  legal_entity_id: string | null;
  sponsorship: Sponsorship;
  sponsorship_type: string | null;
  immigration_support: boolean;
  legal_support: boolean;
  visa_fees_covered: boolean;
  travel_assistance: boolean;
  accommodation_assistance: boolean;
  relocation_support: boolean;
  accepts_non_residents: boolean;
  remote_scope: RemoteScope | null;
  remote_countries: string[];
  remote_tz_min_offset: number | null;
  remote_tz_max_offset: number | null;
};

export const EMPTY_GLOBAL: GlobalHiring = {
  country_code: null,
  legal_entity_id: null,
  sponsorship: 'no',
  sponsorship_type: null,
  immigration_support: false,
  legal_support: false,
  visa_fees_covered: false,
  travel_assistance: false,
  accommodation_assistance: false,
  relocation_support: false,
  accepts_non_residents: false,
  remote_scope: null,
  remote_countries: [],
  remote_tz_min_offset: null,
  remote_tz_max_offset: null,
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * The same rules as the jobs trigger. Returns the first problem, or null.
 * `entities` (when given) is the company's legal entities, to check the
 * chosen one matches the chosen country.
 */
export function validateGlobalHiring(
  g: GlobalHiring,
  workplace: string,
  entities?: { id: string; country_code: string }[]
): string | null {
  if (g.country_code && !COUNTRY_RE.test(g.country_code)) return 'Choose the country from the list.';
  if (g.legal_entity_id) {
    if (!UUID.test(g.legal_entity_id)) return 'Choose the legal entity from the list.';
    const e = entities?.find((x) => x.id === g.legal_entity_id);
    if (entities && !e) return 'That legal entity is not one of your company’s.';
    if (e && g.country_code && e.country_code !== g.country_code)
      return 'The legal entity is in another country than the job. Pick an entity in the job’s country, or none.';
  }
  if (!SPONSORSHIP.includes(g.sponsorship)) return 'Choose whether you sponsor visas.';
  if (g.sponsorship_type && g.sponsorship_type.length > 80) return 'Keep the sponsorship type under 80 characters.';
  if (workplace !== 'remote') return null;
  if (g.remote_scope && !REMOTE_SCOPES.includes(g.remote_scope)) return 'Choose where remote workers can be.';
  if (g.remote_scope === 'country' && !g.country_code)
    return 'Choose the job’s country, or open the remote job wider.';
  if (g.remote_scope === 'countries') {
    if (g.remote_countries.length === 0) return 'Name the countries this remote job is open to.';
    if (g.remote_countries.some((c) => !COUNTRY_RE.test(c))) return 'Choose remote countries from the list.';
  }
  if (g.remote_scope === 'timezone') {
    const { remote_tz_min_offset: lo, remote_tz_max_offset: hi } = g;
    if (lo == null || hi == null) return 'Give the time-zone range for a time-zone-bound remote job.';
    if (lo < TZ_MIN || lo > TZ_MAX || hi < TZ_MIN || hi > TZ_MAX)
      return 'Time zones run from UTC−12:00 to UTC+14:00.';
    if (hi < lo) return 'The time-zone range ends before it starts. Swap the two.';
  }
  return null;
}

/** Only the columns that apply: non-remote jobs clear the remote fields (the trigger does the same). */
export function globalColumns(g: GlobalHiring, workplace: string) {
  const remote = workplace === 'remote';
  const scope = remote ? g.remote_scope : null;
  return {
    country_code: g.country_code,
    legal_entity_id: g.legal_entity_id,
    sponsorship: g.sponsorship,
    sponsorship_type: g.sponsorship === 'no' ? null : g.sponsorship_type,
    immigration_support: g.immigration_support,
    legal_support: g.legal_support,
    visa_fees_covered: g.visa_fees_covered,
    travel_assistance: g.travel_assistance,
    accommodation_assistance: g.accommodation_assistance,
    relocation_support: g.relocation_support,
    accepts_non_residents: g.accepts_non_residents,
    remote_scope: scope,
    remote_countries: scope === 'countries' ? g.remote_countries : [],
    remote_tz_min_offset: scope === 'timezone' ? g.remote_tz_min_offset : null,
    remote_tz_max_offset: scope === 'timezone' ? g.remote_tz_max_offset : null,
  };
}

/** Reads the fields GlobalHiringFields writes into a form. */
export function readGlobalHiring(fd: FormData): GlobalHiring {
  const s = (k: string) => {
    const v = String(fd.get(k) ?? '').trim();
    return v || null;
  };
  const b = (k: string) => fd.get(k) === 'on' || fd.get(k) === 'true';
  const n = (k: string) => {
    const v = s(k);
    if (v == null) return null;
    const x = Number(v);
    return Number.isInteger(x) ? x : null;
  };
  const sponsorship = (s('sponsorship') ?? 'no') as Sponsorship;
  const scope = s('remote_scope') as RemoteScope | null;
  return {
    country_code: s('country_code')?.toUpperCase() ?? null,
    legal_entity_id: s('legal_entity_id'),
    sponsorship,
    sponsorship_type: s('sponsorship_type')?.slice(0, 80) ?? null,
    immigration_support: b('immigration_support'),
    legal_support: b('legal_support'),
    visa_fees_covered: b('visa_fees_covered'),
    travel_assistance: b('travel_assistance'),
    accommodation_assistance: b('accommodation_assistance'),
    relocation_support: b('relocation_support'),
    accepts_non_residents: b('accepts_non_residents'),
    remote_scope: scope,
    remote_countries: [...new Set(fd.getAll('remote_countries').map((c) => String(c).trim().toUpperCase()).filter(Boolean))],
    remote_tz_min_offset: n('remote_tz_min_offset'),
    remote_tz_max_offset: n('remote_tz_max_offset'),
  };
}

/** Turns a database error on the jobs / entities tables into a sentence. */
export function friendlyDbError(e: { message: string; code?: string }): string {
  const m = e.message ?? '';
  if (/jobs_country_fk|country_code_fkey/.test(m)) return 'That country is not one Omelo knows. Choose it from the list.';
  if (/currency_fk|currency_fkey/.test(m)) return 'That currency is not one Omelo knows. Choose it from the list.';
  if (/jobs_legal_entity_fk/.test(m)) return 'That legal entity no longer exists. Choose another.';
  if (/company_legal_entities_default/.test(m))
    return 'Another entity is already the default for that country. Unset it first.';
  if (/company_legal_entities_company_id_country_code_legal_name_key/.test(m))
    return 'You already have an entity with that legal name in that country.';
  if (/legal_name_check/.test(m)) return 'The legal name needs 2 to 200 characters.';
  if (/registration_number_check/.test(m)) return 'Keep the registration number under 80 characters.';
  if (/hiring_notes_check/.test(m)) return 'Keep the hiring notes under 2000 characters.';
  if (/remote_tz_(min|max)_offset_check/.test(m)) return 'Time zones run from UTC−12:00 to UTC+14:00.';
  if (/sponsorship_type_check/.test(m)) return 'Keep the sponsorship type under 80 characters.';
  if (e.code === '42501' && /row-level security/i.test(m))
    return 'Your role cannot change this. Ask an owner or admin.';
  return m;
}

/* ------------------------------------------------------------------ */
/* Country guide                                                       */
/* ------------------------------------------------------------------ */

export type GuideInfo = {
  topic: string;
  title: string;
  summary: string;
  url: string | null;
  source: string | null;
  reviewedAt: string | null;
};
export type GuideLicence = {
  profession: string | null;
  name: string;
  description: string | null;
  level: string | null;
  url: string | null;
  source: string | null;
  reviewedAt: string | null;
};
export type CountryGuide = {
  country: string;
  name: string;
  currency: string | null;
  currencyName: string | null;
  language: string | null;
  timezone: string | null;
  callingCode: string | null;
  region: string | null;
  supported: boolean;
  information: GuideInfo[];
  licences: GuideLicence[];
  disclaimer: string | null;
};

/** Only https links are rendered as links (the tables enforce the same). */
export const safeUrl = (u: unknown): string | null => {
  const s = str(u);
  return s && /^https:\/\//i.test(s) ? s : null;
};

export function parseCountryGuide(raw: Json | null): CountryGuide | null {
  if (!isObj(raw)) return null;
  const country = str(raw.country);
  if (!country) return null;
  return {
    country,
    name: str(raw.name) ?? country,
    currency: str(raw.currency),
    currencyName: str(raw.currency_name),
    language: str(raw.language),
    timezone: str(raw.timezone),
    callingCode: str(raw.calling_code),
    region: str(raw.region),
    supported: raw.omelo_supported === true,
    information: arr(raw.information)
      .filter(isObj)
      .map((i) => ({
        topic: str(i.topic) ?? 'other',
        title: str(i.title) ?? 'Information',
        summary: str(i.summary) ?? '',
        url: safeUrl(i.url),
        source: str(i.source),
        reviewedAt: str(i.reviewed_at),
      })),
    licences: arr(raw.licence_requirements)
      .filter(isObj)
      .map((l) => ({
        profession: str(l.profession),
        name: str(l.name) ?? 'Licence',
        description: str(l.description),
        level: str(l.level),
        url: safeUrl(l.url),
        source: str(l.source),
        reviewedAt: str(l.reviewed_at),
      })),
    disclaimer: str(raw.disclaimer),
  };
}

export const TOPIC_LABEL: Record<string, string> = {
  work_authorization: 'Work authorization',
  documents: 'Documents',
  licensing: 'Licensing',
  hiring: 'Hiring',
  worker_rights: 'Worker rights',
  tax_payroll: 'Tax and payroll',
  official_portal: 'Official portal',
};

/** world_region is stored as a display name ("Middle East"). */
export const regionLabel = (r: string | null) => r?.trim() || 'Other';

/* ------------------------------------------------------------------ */
/* Currency conversion                                                 */
/* ------------------------------------------------------------------ */

export type Conversion = {
  amount: number | null;
  from: string;
  to: string;
  converted: number | null;
  rate: number | null;
  effectiveAt: string | null;
  source: string | null;
  note: string | null;
  indicative: boolean;
};

export function parseConversion(raw: Json | null): Conversion | null {
  if (!isObj(raw)) return null;
  const source = str(raw.source);
  return {
    amount: numOrNull(raw.amount),
    from: str(raw.from) ?? '',
    to: str(raw.to) ?? '',
    converted: numOrNull(raw.converted),
    rate: numOrNull(raw.rate),
    effectiveAt: str(raw.effective_at),
    source,
    note: str(raw.note),
    indicative: !!source && /indicative|not for payments/i.test(source),
  };
}

export type NormalizedPay = {
  currency: string;
  hourly: number | null;
  monthly: number | null;
  yearly: number | null;
  note: string | null;
};

export function parseNormalizedPay(raw: Json | null): NormalizedPay | null {
  if (!isObj(raw)) return null;
  return {
    currency: str(raw.currency) ?? '',
    hourly: numOrNull(raw.hourly),
    monthly: numOrNull(raw.monthly),
    yearly: numOrNull(raw.yearly),
    note: str(raw.note),
  };
}
