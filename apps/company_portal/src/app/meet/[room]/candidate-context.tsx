'use client';

import { useEffect, useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import { formatPay, experienceLabel, WORK_TYPE_LABEL, WORKPLACE_LABEL } from '@/lib/format';
import {
  PROFICIENCY_LABEL,
  calendarDate,
  gateLabel,
  monthYear,
  monthsLabel,
  skillName,
  type FeatureVector,
  type MatchReason,
} from '@/lib/hiring';
import { Restricted } from './ui';

const HIRING_ROLES = ['owner', 'admin', 'recruiter', 'hiring_manager', 'hr'];

type Section<T> = { data: T; error: string | null };

type Profile = {
  name: string | null;
  location: string | null;
  headline: string | null;
  education: string | null;
  identityLabel: string | null;
  about: string | null;
  totalMonths: number | null;
  profession: string | null;
  matchScore: number | null;
  coverNote: string | null;
  appliedAt: string | null;
};

type Experience = {
  id: string;
  employer_name: string;
  title: string;
  started_on: string | null;
  ended_on: string | null;
  is_current: boolean;
  is_verified: boolean;
  description: string | null;
  months_duration: number | null;
  location_text: string | null;
};

type SkillRow = { id: string; proficiency: string | null; is_verified: boolean; name: string };
type LanguageRow = { code: string; name: string; proficiency: string };
type LicenceRow = { id: string; name: string; license_class: string | null; is_verified: boolean; expires_on: string | null };

type Job = {
  title: string;
  description: string | null;
  location_text: string | null;
  work_type: string;
  workplace_type: string;
  min_experience_months: number | null;
  accepts_no_experience: boolean;
  pay: string;
  profession: string | null;
  skills: { name: string; level: string; weight: number }[];
};

type Match = { score: number | null; eligible: boolean | null; gates: string[]; fv: FeatureVector | null } | null;

export type CandidateContext = {
  loading: boolean;
  /** False for panel members whose company role is only `interviewer`. */
  isHiringTeam: boolean;
  profile: Section<Profile | null>;
  experiences: Section<Experience[]>;
  skills: Section<SkillRow[]>;
  languages: Section<LanguageRow[]>;
  licences: Section<LicenceRow[]>;
  job: Section<Job | null>;
  match: Section<Match>;
};

const empty = <T,>(data: T): Section<T> => ({ data, error: null });

const INITIAL: CandidateContext = {
  loading: true,
  isHiringTeam: false,
  profile: empty(null),
  experiences: empty([]),
  skills: empty([]),
  languages: empty([]),
  licences: empty([]),
  job: empty(null),
  match: empty(null),
};

/**
 * Everything the interviewer needs beside the video, read through RLS as the
 * signed-in user. Sections the database hides are reported as restricted,
 * never worked around.
 */
export function useCandidateContext(interviewId: string, applicationId: string) {
  const [ctx, setCtx] = useState<CandidateContext>(INITIAL);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const supabase = createClient();
      const {
        data: { user },
      } = await supabase.auth.getUser();
      const { data: iv, error: ivError } = await supabase
        .from('interviews')
        .select('company_id, job_id, person_id')
        .eq('id', interviewId)
        .maybeSingle();
      if (cancelled) return;
      if (!iv || !user) {
        const err = ivError?.message ?? 'Interview details are not available.';
        setCtx({ ...INITIAL, loading: false, profile: { data: null, error: err }, job: { data: null, error: err } });
        return;
      }

      const [memberRes, appRes, jobRes] = await Promise.all([
        supabase
          .from('company_members')
          .select('role')
          .eq('company_id', iv.company_id)
          .eq('person_id', user.id)
          .eq('is_active', true)
          .maybeSingle(),
        supabase
          .from('applications')
          .select(
            `match_score, cover_note, applied_at,
             persons!applications_person_id_fkey ( display_name, location_text, headline, highest_education ),
             work_identities ( label, headline, about, total_experience_months,
               professions!work_identities_profession_id_fkey ( name ) )`
          )
          .eq('id', applicationId)
          .maybeSingle(),
        supabase
          .from('jobs')
          .select(
            `title, description, location_text, work_type, workplace_type, min_experience_months,
             accepts_no_experience, pay_min, pay_max, pay_period, pay_currency, pay_negotiable,
             professions ( name ),
             job_skills ( requirement_level, weight, skills ( name ) )`
          )
          .eq('id', iv.job_id)
          .maybeSingle(),
      ]);
      const isHiringTeam = HIRING_ROLES.includes(memberRes.data?.role ?? '');

      const next: CandidateContext = { ...INITIAL, loading: false, isHiringTeam };

      if (appRes.error) next.profile = { data: null, error: appRes.error.message };
      else if (appRes.data) {
        const a = appRes.data;
        const p = a.persons as unknown as {
          display_name: string | null;
          location_text: string | null;
          headline: string | null;
          highest_education: string | null;
        } | null;
        const wi = a.work_identities as unknown as {
          label: string;
          headline: string | null;
          about: string | null;
          total_experience_months: number | null;
          professions: { name: string } | null;
        } | null;
        next.profile = {
          error: null,
          data: {
            name: p?.display_name ?? null,
            location: p?.location_text ?? null,
            headline: wi?.headline ?? p?.headline ?? null,
            education: p?.highest_education ?? null,
            identityLabel: wi?.label ?? null,
            about: wi?.about ?? null,
            totalMonths: wi?.total_experience_months ?? null,
            profession: wi?.professions?.name ?? null,
            matchScore: a.match_score,
            coverNote: a.cover_note,
            appliedAt: a.applied_at,
          },
        };
      }

      if (jobRes.error) next.job = { data: null, error: jobRes.error.message };
      else if (jobRes.data) {
        const j = jobRes.data;
        next.job = {
          error: null,
          data: {
            title: j.title,
            description: j.description,
            location_text: j.location_text,
            work_type: j.work_type,
            workplace_type: j.workplace_type,
            min_experience_months: j.min_experience_months,
            accepts_no_experience: j.accepts_no_experience,
            pay: formatPay({
              min: j.pay_min,
              max: j.pay_max,
              currency: j.pay_currency,
              period: j.pay_period,
              negotiable: j.pay_negotiable,
            }),
            profession: (j.professions as unknown as { name: string } | null)?.name ?? null,
            skills: (j.job_skills ?? [])
              .map((s) => ({
                name: (s.skills as unknown as { name: string } | null)?.name ?? '',
                level: s.requirement_level as string,
                weight: s.weight,
              }))
              .filter((s) => s.name),
          },
        };
      }

      // Candidate profile tables are readable to the hiring team only.
      if (isHiringTeam) {
        const [expRes, skillRes, langRes, licRes, matchRes] = await Promise.all([
          supabase
            .from('experiences')
            .select(
              'id, employer_name, title, started_on, ended_on, is_current, is_verified, description, months_duration, location_text'
            )
            .eq('person_id', iv.person_id)
            .order('is_current', { ascending: false })
            .order('started_on', { ascending: false, nullsFirst: false }),
          supabase
            .from('person_skills')
            .select('id, proficiency, is_verified, skills ( name )')
            .eq('person_id', iv.person_id),
          supabase
            .from('person_languages')
            .select('language_code, proficiency, languages ( name )')
            .eq('person_id', iv.person_id),
          supabase
            .from('person_licenses')
            .select('id, name, license_class, is_verified, expires_on')
            .eq('person_id', iv.person_id),
          supabase
            .from('matches')
            .select('score, eligible, gate_failures, feature_vector')
            .eq('person_id', iv.person_id)
            .eq('job_id', iv.job_id)
            .order('computed_at', { ascending: false })
            .limit(1)
            .maybeSingle(),
        ]);
        next.experiences = { data: (expRes.data ?? []) as Experience[], error: expRes.error?.message ?? null };
        next.skills = {
          data: (skillRes.data ?? []).map((s) => ({
            id: s.id,
            proficiency: s.proficiency,
            is_verified: s.is_verified,
            name: (s.skills as unknown as { name: string } | null)?.name ?? 'Skill',
          })),
          error: skillRes.error?.message ?? null,
        };
        next.languages = {
          data: (langRes.data ?? []).map((l) => ({
            code: l.language_code,
            name: (l.languages as unknown as { name: string } | null)?.name ?? l.language_code,
            proficiency: l.proficiency,
          })),
          error: langRes.error?.message ?? null,
        };
        next.licences = { data: (licRes.data ?? []) as LicenceRow[], error: licRes.error?.message ?? null };
        next.match = {
          data: matchRes.data
            ? {
                score: matchRes.data.score,
                eligible: matchRes.data.eligible,
                gates: matchRes.data.gate_failures ?? [],
                fv: (matchRes.data.feature_vector ?? null) as FeatureVector | null,
              }
            : null,
          error: matchRes.error?.message ?? null,
        };
      }

      if (!cancelled) setCtx(next);
    })();
    return () => {
      cancelled = true;
    };
  }, [interviewId, applicationId]);

  return ctx;
}

/* ------------------------------------------------------------------ */
/* Sections                                                            */
/* ------------------------------------------------------------------ */

function Err({ message }: { message: string }) {
  return (
    <p className="text-sm" style={{ color: 'var(--color-danger)' }}>
      Could not load this: <span className="muted">{message}</span>
    </p>
  );
}

function Loading() {
  return <p className="text-sm muted">Loading…</p>;
}

export function CandidateTab({ ctx, fallbackName }: { ctx: CandidateContext; fallbackName: string | null }) {
  if (ctx.loading) return <Loading />;
  if (ctx.profile.error) return <Err message={ctx.profile.error} />;
  const p = ctx.profile.data;
  // Interviewer-only members can read the application row but not the person.
  const hidden = !ctx.isHiringTeam || !p?.name;
  const score = p?.matchScore ?? ctx.match.data?.score ?? null;
  return (
    <div className="space-y-4">
      <div className="flex items-start gap-3">
        <div className="flex-1 min-w-0">
          <p className="text-lg font-bold break-words">{p?.name ?? fallbackName ?? 'Candidate'}</p>
          {!hidden && p?.headline && <p className="text-sm break-words">{p.headline}</p>}
          {!hidden && (
            <p className="text-sm muted break-words">
              {[p?.profession, monthsLabel(p?.totalMonths), p?.location].filter(Boolean).join(' · ')}
            </p>
          )}
        </div>
        {ctx.isHiringTeam && (
          <div className="text-right shrink-0">
            <div className="text-3xl font-black leading-none" style={{ color: 'var(--color-brand-600)' }}>
              {score != null ? `${score}%` : '—'}
            </div>
            <div className="text-xs muted">match</div>
          </div>
        )}
      </div>
      {hidden ? (
        <Restricted />
      ) : (
        <>
          {p?.education && (
            <div>
              <p className="label">Education</p>
              <p className="text-sm">{p.education.replace(/_/g, ' ')}</p>
            </div>
          )}
          {p?.about && (
            <div>
              <p className="label">About</p>
              <p className="text-sm whitespace-pre-line break-words">{p.about}</p>
            </div>
          )}
          {p?.coverNote && (
            <div>
              <p className="label">Note with their application</p>
              <p className="text-sm whitespace-pre-line break-words">{p.coverNote}</p>
            </div>
          )}
          {ctx.languages.data.length > 0 && (
            <div>
              <p className="label">Languages</p>
              <p className="text-sm">
                {ctx.languages.data
                  .map((l) => `${l.name} (${PROFICIENCY_LABEL[l.proficiency] ?? l.proficiency})`)
                  .join(', ')}
              </p>
            </div>
          )}
          {ctx.licences.data.length > 0 && (
            <div>
              <p className="label">Licences</p>
              <ul className="text-sm space-y-0.5">
                {ctx.licences.data.map((l) => (
                  <li key={l.id} className="break-words">
                    {l.name}
                    {l.license_class ? ` (${l.license_class})` : ''}
                    {l.is_verified ? (
                      <span style={{ color: 'var(--color-verified)' }}> · verified</span>
                    ) : null}
                    {l.expires_on ? <span className="muted"> · expires {calendarDate(l.expires_on)}</span> : null}
                  </li>
                ))}
              </ul>
            </div>
          )}
        </>
      )}
    </div>
  );
}

export function ExperienceTab({ ctx }: { ctx: CandidateContext }) {
  if (ctx.loading) return <Loading />;
  if (!ctx.isHiringTeam) return <Restricted />;
  if (ctx.experiences.error) return <Err message={ctx.experiences.error} />;
  const list = [...ctx.experiences.data].sort((a, b) => Number(b.is_verified) - Number(a.is_verified));
  if (list.length === 0) return <p className="text-sm muted">No work history on profile yet.</p>;
  return (
    <ul className="space-y-4">
      {list.map((e) => (
        <li key={e.id}>
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-semibold text-sm break-words">{e.title}</span>
            {e.is_verified ? (
              <span className="pill" style={{ color: 'var(--color-verified)' }}>
                ✓ Verified
              </span>
            ) : (
              <span className="pill">Self-declared</span>
            )}
          </div>
          <p className="text-sm muted break-words">
            {e.employer_name}
            {e.location_text ? ` · ${e.location_text}` : ''}
          </p>
          <p className="text-xs muted">
            {monthYear(e.started_on) || 'Start not given'} – {e.is_current ? 'Present' : monthYear(e.ended_on) || '—'}
            {e.months_duration ? ` · ${monthsLabel(e.months_duration)}` : ''}
          </p>
          {e.description && <p className="text-sm mt-1 whitespace-pre-line break-words">{e.description}</p>}
        </li>
      ))}
    </ul>
  );
}

export function SkillsTab({ ctx }: { ctx: CandidateContext }) {
  if (ctx.loading) return <Loading />;
  if (!ctx.isHiringTeam) return <Restricted />;
  if (ctx.skills.error) return <Err message={ctx.skills.error} />;
  const required = new Set(
    (ctx.job.data?.skills ?? []).map((s) => s.name.toLowerCase())
  );
  if (ctx.skills.data.length === 0) return <p className="text-sm muted">No skills on profile yet.</p>;
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        {ctx.skills.data.map((s) => (
          <span
            key={s.id}
            className="pill"
            style={{
              color: s.is_verified ? 'var(--color-verified)' : 'var(--fg)',
              borderColor: required.has(s.name.toLowerCase()) ? 'var(--color-brand-400)' : undefined,
            }}
          >
            {s.is_verified ? '✓ ' : ''}
            {s.name}
            {s.proficiency && <span className="muted font-normal">· {PROFICIENCY_LABEL[s.proficiency] ?? s.proficiency}</span>}
          </span>
        ))}
      </div>
      <p className="hint">Outlined skills are ones this job asks for. ✓ means verified by Omelo.</p>
    </div>
  );
}

export function JobTab({ ctx }: { ctx: CandidateContext }) {
  if (ctx.loading) return <Loading />;
  if (ctx.job.error) return <Err message={ctx.job.error} />;
  const j = ctx.job.data;
  if (!j) return <p className="text-sm muted">Job details are not available.</p>;
  const required = j.skills.filter((s) => s.level === 'required');
  const preferred = j.skills.filter((s) => s.level !== 'required');
  return (
    <div className="space-y-4">
      <div>
        <p className="font-bold break-words">{j.title}</p>
        <p className="text-sm muted break-words">
          {[j.profession, j.location_text, WORKPLACE_LABEL[j.workplace_type] ?? j.workplace_type].filter(Boolean).join(' · ')}
        </p>
      </div>
      <div className="flex flex-wrap gap-2">
        <span className="pill">{WORK_TYPE_LABEL[j.work_type] ?? j.work_type}</span>
        <span className="pill">{experienceLabel(j.min_experience_months, j.accepts_no_experience)}</span>
        <span className="pill">{j.pay}</span>
      </div>
      {required.length > 0 && (
        <div>
          <p className="label">Required skills</p>
          <div className="flex flex-wrap gap-2">
            {required.map((s) => (
              <span key={s.name} className="pill !text-[var(--fg)]">
                {s.name}
              </span>
            ))}
          </div>
        </div>
      )}
      {preferred.length > 0 && (
        <div>
          <p className="label">Helpful, not required</p>
          <div className="flex flex-wrap gap-2">
            {preferred.map((s) => (
              <span key={s.name} className="pill">
                {s.name}
              </span>
            ))}
          </div>
        </div>
      )}
      {j.description && (
        <div>
          <p className="label">The work</p>
          <p className="text-sm whitespace-pre-line break-words">{j.description}</p>
        </div>
      )}
    </div>
  );
}

function Reasons({ items, color, mark }: { items: MatchReason[]; color: string; mark: string }) {
  return (
    <ul className="space-y-1.5">
      {items.map((r, i) => (
        <li key={`${r.factor}-${i}`} className="flex items-start gap-2 text-sm">
          <span aria-hidden className="font-bold shrink-0 w-4 text-center" style={{ color }}>
            {mark}
          </span>
          <span className="break-words min-w-0">{r.text}</span>
        </li>
      ))}
    </ul>
  );
}

export function MatchTab({ ctx }: { ctx: CandidateContext }) {
  if (ctx.loading) return <Loading />;
  if (!ctx.isHiringTeam) return <Restricted />;
  if (ctx.match.error) return <Err message={ctx.match.error} />;
  const m = ctx.match.data;
  if (!m?.fv) return <p className="text-sm muted">No match analysis has been computed for this candidate yet.</p>;
  const fv = m.fv;
  const missing = (fv.missing_skills ?? []).map(skillName).filter(Boolean);
  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2 flex-wrap">
        <span className="text-2xl font-black" style={{ color: 'var(--color-brand-600)' }}>
          {m.score != null ? `${m.score}%` : '—'}
        </span>
        {m.gates.length === 0 && m.eligible ? (
          <span className="pill" style={{ color: 'var(--color-verified)' }}>
            Meets all must-haves
          </span>
        ) : (
          m.gates.map((g) => (
            <span key={g} className="pill" style={{ color: 'var(--color-danger)' }}>
              {gateLabel(g)}
            </span>
          ))
        )}
      </div>
      {(fv.strengths ?? []).length > 0 && (
        <div>
          <p className="label">Strengths</p>
          <Reasons items={fv.strengths!} color="var(--color-verified)" mark="✓" />
        </div>
      )}
      {(fv.gaps ?? []).length > 0 && (
        <div>
          <p className="label">Gaps</p>
          <Reasons items={fv.gaps!} color="var(--color-warn)" mark="!" />
        </div>
      )}
      {missing.length > 0 && (
        <div>
          <p className="label">Missing required skills</p>
          <div className="flex flex-wrap gap-2">
            {missing.map((s) => (
              <span key={s} className="pill" style={{ color: 'var(--color-warn)' }}>
                {s}
              </span>
            ))}
          </div>
        </div>
      )}
      {(fv.unknowns ?? []).length > 0 && (
        <div>
          <p className="label">Unknowns — good to ask about</p>
          <Reasons items={fv.unknowns!} color="var(--muted)" mark="?" />
        </div>
      )}
    </div>
  );
}
