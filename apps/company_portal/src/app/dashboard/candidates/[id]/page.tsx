import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { BENEFIT_LABEL, STATE_LABEL, formatPay, timeAgo } from '@/lib/format';
import {
  CLOSED_STATES,
  OFFER_STATUS_LABEL,
  OPEN_OFFER_STATUSES,
  OPEN_STATES,
  PRE_OFFER_STATES,
  PROFICIENCY_LABEL,
  TONE_COLOR,
  calendarDate,
  describeTimeline,
  factorLabel,
  gateLabel,
  monthYear,
  monthsLabel,
  skillName,
  stateTone,
  type ApplicationState,
  type FeatureVector,
  type MatchReason,
} from '@/lib/hiring';
import LocalTime from '../../local-time';
import {
  MoveButton,
  NoteForm,
  RejectForm,
  RescoreButton,
  SendOfferForm,
  WithdrawOfferForm,
} from '../forms';
import { ScheduleInterviewForm, type TeamMember } from '../schedule-form';
import InterviewRounds, { type RoundFeedback, type RoundInterview } from './rounds';
import MessageButton from './message-button';
import type { PlannedRound } from '@/lib/meet';
import {
  PROFILE_ANSWER_SELECT,
  identityScope,
  toEvidenceResult,
  toProfileAnswers,
} from '@/lib/identity';
import {
  CompletenessMeter,
  EvidenceGate,
  EvidencePanel,
  HiringTeamOnly,
  ProfileAnswers,
} from '@/components/identity/evidence';
import { parseClientSubmissions, parseScopedProfile } from '@/lib/agency';
import { countryName, parseCandidateEligibility } from '@/lib/global';
import { EligibilityPanel } from '@/components/global/eligibility';
import {
  NotShared,
  SnapshotAnswers,
  SnapshotContact,
  SnapshotEvidence,
  SnapshotExperience,
  SnapshotNote,
  SubmissionCard,
  SubmittedByBadge,
  isNarrowed,
  type SubmissionAgency,
} from './agency-submission';

const HIRING_ROLES: string[] = ['owner', 'admin', 'recruiter', 'hiring_manager', 'hr'];
const PANEL_ROLES = ['owner', 'admin', 'recruiter', 'hiring_manager', 'hr', 'interviewer'] as const;

type Snapshot = {
  person?: { display_name?: string; location_text?: string };
  work_identity?: { label?: string; headline?: string };
  captured_at?: string;
};

type Answer = { prompt?: string; answer?: unknown; question_id?: string };

function ErrorNote({ label, message }: { label: string; message: string }) {
  return (
    <p className="text-sm" style={{ color: 'var(--color-danger)' }}>
      Could not load {label}: <span className="muted">{message}</span>
    </p>
  );
}

function SectionTitle({ children, aside }: { children: React.ReactNode; aside?: React.ReactNode }) {
  return (
    <div className="flex items-center gap-3 flex-wrap mb-3">
      <h2 className="font-bold flex-1 min-w-0">{children}</h2>
      {aside}
    </div>
  );
}

function StateBadge({ state }: { state: string }) {
  return (
    <span className="pill" style={{ color: TONE_COLOR[stateTone(state)] }}>
      {STATE_LABEL[state] ?? state}
    </span>
  );
}

function Reasons({
  items,
  color,
  mark,
}: {
  items: MatchReason[];
  color: string;
  mark: string;
}) {
  return (
    <ul className="space-y-1.5">
      {items.map((r, i) => (
        <li key={`${r.factor}-${i}`} className="flex items-start gap-2 text-sm">
          <span aria-hidden className="font-bold shrink-0 w-4 text-center" style={{ color }}>
            {mark}
          </span>
          <span className="break-words min-w-0">
            {r.factor && <span className="muted">{factorLabel(r.factor)}: </span>}
            {r.text}
          </span>
        </li>
      ))}
    </ul>
  );
}

export default async function CandidateReviewPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) notFound();
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // Opening a candidate is what makes "viewed" true for the worker. The RPC
  // is a no-op when already viewed; any other failure is shown, not hidden.
  const { error: viewError } = await supabase.rpc('omelo_mark_application_viewed', {
    p_application_id: id,
  });

  const { data: app, error: appError } = await supabase
    .from('applications')
    .select(
      `id, job_id, person_id, work_identity_id, state, match_score, identity_snapshot,
       cover_note, answers, first_viewed_at, applied_at, last_activity_at, closed_at,
       rejection_reason, withdrawal_reason, applied_via,
       jobs ( id, title, location_text, pay_min, pay_max, pay_period, pay_currency ),
       persons!applications_person_id_fkey ( display_name, location_text, headline, highest_education ),
       work_identities (
         label, headline, about, total_experience_months, completeness_score,
         professions!work_identities_profession_id_fkey ( name )
       )`
    )
    .eq('id', id)
    .eq('company_id', ctx.companyId)
    .maybeSingle();

  if (appError) {
    return (
      <div className="max-w-3xl space-y-4">
        <Link href="/dashboard/candidates" className="text-sm underline muted">
          ← Candidates
        </Link>
        <div className="card p-5" style={{ borderColor: 'var(--color-danger)' }}>
          <p className="font-semibold mb-1" style={{ color: 'var(--color-danger)' }}>
            Could not load this application
          </p>
          <p className="text-sm muted">{appError.message}</p>
        </div>
      </div>
    );
  }
  if (!app) notFound();

  // Agency submissions: the consented submission row and the agency's
  // details. Started before the main batch so they load in parallel.
  const isAgency = app.applied_via === 'agency';
  const agencyPromise = isAgency
    ? Promise.all([
        supabase
          .from('candidate_submissions')
          .select('id, recruiter_note, submitted_at, consent_id, snapshot')
          .eq('application_id', app.id)
          .maybeSingle(),
        supabase.rpc('omelo_client_submissions', { p_job_id: app.job_id }),
      ])
    : null;

  const [
    matchRes,
    expRes,
    evidenceRes,
    answerRes,
    langRes,
    eventRes,
    noteRes,
    interviewRes,
    offerRes,
    employmentRes,
    roundsRes,
    teamRes,
    feedbackRes,
    eligibilityRes,
  ] = await Promise.all([
    supabase
      .from('matches')
      .select('score, eligible, gate_failures, feature_vector, engine_version, computed_at')
      .eq('person_id', app.person_id)
      .eq('job_id', app.job_id)
      .order('computed_at', { ascending: false })
      .limit(1)
      .maybeSingle(),
    supabase
      .from('experiences')
      .select(
        'id, employer_name, title, started_on, ended_on, is_current, is_verified, source, description, months_duration, location_text'
      )
      .eq('person_id', app.person_id)
      // Only the identity they applied with, plus history shared across identities.
      .or(identityScope(app.work_identity_id))
      .order('is_current', { ascending: false })
      .order('started_on', { ascending: false, nullsFirst: false }),
    supabase.rpc('omelo_identity_evidence', { p_identity: app.work_identity_id }),
    supabase
      .from('person_attributes')
      .select(PROFILE_ANSWER_SELECT)
      .eq('person_id', app.person_id)
      .eq('work_identity_id', app.work_identity_id),
    supabase
      .from('person_languages')
      .select('language_code, proficiency, languages ( name )')
      .eq('person_id', app.person_id),
    supabase
      .from('application_events')
      .select('id, event_type, actor_type, actor_id, from_state, to_state, reason, metadata, occurred_at')
      .eq('application_id', app.id)
      .order('occurred_at', { ascending: true }),
    supabase
      .from('application_notes')
      .select('id, body, created_at, author_id')
      .eq('application_id', app.id)
      .order('created_at', { ascending: false }),
    supabase
      .from('interviews')
      .select(
        `id, status, round, round_name, round_kind, meeting_mode, scheduled_at, duration_minutes, timezone,
         location_text, instructions, candidate_confirmed_at, completed_at, cancelled_at, cancel_reason,
         interview_rooms ( room_name, status, opens_at, closes_at, started_at, ended_at )`
      )
      .eq('application_id', app.id)
      .order('round', { ascending: true }),
    supabase
      .from('offers')
      .select(
        'id, status, title, pay_amount, pay_period, pay_currency, start_date, expires_at, sent_at, viewed_at, responded_at, decline_reason, conditions, benefits, created_at'
      )
      .eq('application_id', app.id)
      .order('created_at', { ascending: false }),
    supabase
      .from('employments')
      .select('id, title, started_on, status, country_code, pay_amount, pay_period, pay_currency, employment_type')
      .eq('application_id', app.id)
      .maybeSingle(),
    supabase
      .from('job_interview_rounds')
      .select('id, position, name, kind, meeting_mode, duration_minutes')
      .eq('job_id', app.job_id)
      .order('position'),
    supabase
      .from('company_members')
      .select('person_id, role, persons!company_members_person_id_fkey ( display_name )')
      .eq('company_id', ctx.companyId)
      .eq('is_active', true)
      .in('role', [...PANEL_ROLES]),
    supabase
      .from('interview_feedback')
      .select(
        'id, interview_id, interviewer_id, recommendation, overall_rating, strengths, concerns, notes, competencies, skills_assessed, status, submitted_at, updated_at'
      )
      .eq('application_id', app.id)
      .order('updated_at', { ascending: true }),
    // R6: eligibility for this job; authorization details only if the worker shares them.
    supabase.rpc('omelo_candidate_eligibility', { p_job: app.job_id, p_identity: app.work_identity_id }),
  ]);

  const job = app.jobs as unknown as {
    id: string;
    title: string;
    location_text: string | null;
    pay_min: number | null;
    pay_max: number | null;
    pay_period: string | null;
    pay_currency: string | null;
  } | null;
  const person = app.persons as unknown as {
    display_name: string | null;
    location_text: string | null;
    headline: string | null;
    highest_education: string | null;
  } | null;
  const wi = app.work_identities as unknown as {
    label: string;
    headline: string | null;
    about: string | null;
    total_experience_months: number | null;
    completeness_score: number | null;
    professions: { name: string } | null;
  } | null;
  const snap = (app.identity_snapshot ?? {}) as Snapshot;
  const answers = (Array.isArray(app.answers) ? app.answers : []) as Answer[];

  // For an agency submission the application snapshot is the consented,
  // scoped profile. Null for every other application.
  const agencyRes = agencyPromise ? await agencyPromise : null;
  const submissionRow = agencyRes?.[0].data ?? null;
  const scoped = isAgency
    ? (parseScopedProfile(app.identity_snapshot) ?? parseScopedProfile(submissionRow?.snapshot))
    : null;
  const clientSub =
    agencyRes && !agencyRes[1].error
      ? (parseClientSubmissions(agencyRes[1].data).find((s) => s.applicationId === app.id) ?? null)
      : null;
  // A narrowed consent keeps the live profile hidden (RLS); use the snapshot.
  const narrowed = scoped ? isNarrowed(scoped) : false;
  const submissionAgency: SubmissionAgency | null = scoped
    ? clientSub
      ? clientSub.agency
      : { name: scoped.submittedVia?.agency ?? 'An agency', verified: null, independent: false }
    : null;
  const submissionRecruiter = clientSub?.recruiter ?? scoped?.submittedVia?.recruiter ?? null;
  const submittedAt =
    submissionRow?.submitted_at ?? clientSub?.submittedAt ?? scoped?.submittedVia?.submittedAt ?? null;
  const submissionError = agencyRes
    ? [agencyRes[0].error?.message, agencyRes[1].error?.message].filter(Boolean).join(' · ') || null
    : null;

  const name = person?.display_name ?? snap.person?.display_name ?? scoped?.identity.name ?? 'Candidate';
  const headline =
    wi?.headline ?? snap.work_identity?.headline ?? wi?.label ?? scoped?.identity.headline ?? null;

  const match = matchRes.data;
  const fv = (match?.feature_vector ?? null) as FeatureVector | null;
  const score = app.match_score ?? match?.score ?? null;
  const gateFailures = match?.gate_failures ?? fv?.gate_failures ?? [];
  const missingSkills = (fv?.missing_skills ?? []).map(skillName).filter(Boolean);

  const interviews: RoundInterview[] = (interviewRes.data ?? []).map(({ interview_rooms, ...iv }) => ({
    ...iv,
    room: (interview_rooms as unknown as RoundInterview['room']) ?? null,
  }));
  const interviewIds = interviews.map((iv) => iv.id);

  // Panels, and the names people had when invited: teammates' person rows
  // are not readable to each other, but the participant snapshot is.
  const [panelRes, participantRes] = interviewIds.length
    ? await Promise.all([
        supabase
          .from('interview_interviewers')
          .select('interview_id, person_id, is_lead')
          .in('interview_id', interviewIds),
        supabase
          .from('interview_participants')
          .select('person_id, display_name')
          .in('interview_id', interviewIds),
      ])
    : [{ data: null }, { data: null }];
  const panels: Record<string, string[]> = {};
  for (const p of [...(panelRes.data ?? [])].sort((a, b) => Number(b.is_lead) - Number(a.is_lead))) {
    (panels[p.interview_id] ??= []).push(p.person_id);
  }
  const names: Record<string, string> = {};
  for (const p of participantRes.data ?? []) if (p.display_name) names[p.person_id] = p.display_name;

  const plannedRounds: PlannedRound[] = roundsRes.data ?? [];
  const team: TeamMember[] = (teamRes.data ?? []).map((m) => {
    const pn = (m.persons as unknown as { display_name: string | null } | null)?.display_name ?? null;
    return {
      personId: m.person_id,
      role: m.role,
      name: pn ?? names[m.person_id] ?? null,
      isYou: m.person_id === user?.id,
    };
  });
  if (user && !team.some((m) => m.isYou) && (PANEL_ROLES as readonly string[]).includes(ctx.role)) {
    team.unshift({ personId: user.id, role: ctx.role, name: null, isYou: true });
  }
  for (const m of team) if (m.name && !names[m.personId]) names[m.personId] = m.name;
  team.sort((a, b) => Number(b.isYou) - Number(a.isYou));

  const feedback: RoundFeedback[] = feedbackRes.data ?? [];
  const isHiringTeam = HIRING_ROLES.includes(ctx.role);
  const nextRound = (interviews.at(-1)?.round ?? 0) + 1;
  const nextPlanned = plannedRounds.find((r) => r.position === nextRound) ?? null;
  const hasLiveInterview = interviews.some((iv) => iv.status === 'scheduled' || iv.status === 'rescheduled');
  const lastInterview = interviews.at(-1) ?? null;
  const offers = offerRes.data ?? [];
  const openOffer = offers.find((o) => OPEN_OFFER_STATUSES.includes(o.status)) ?? null;
  const latestOffer = offers[0] ?? null;
  const employment = employmentRes.data;

  const state = app.state as ApplicationState;
  const isOpen = OPEN_STATES.includes(state);
  const isPreOffer = PRE_OFFER_STATES.includes(state);
  const isClosed = (CLOSED_STATES as string[]).includes(state);
  // After a completed round with nothing booked, the next step is a decision.
  const decisionDue =
    isPreOffer && isHiringTeam && !hasLiveInterview && lastInterview?.status === 'completed';
  const scheduleProps = {
    applicationId: app.id,
    jobId: app.job_id,
    defaultLocation: job?.location_text ?? null,
    plannedRounds,
    nextRound,
    team,
  };
  const offerDefaults = {
    title: job?.title ?? '',
    payAmount: job?.pay_max ?? job?.pay_min ?? null,
    payPeriod: job?.pay_period ?? null,
    currency: job?.pay_currency ?? null,
  };

  const timeline = describeTimeline(eventRes.data ?? [], user?.id ?? null).reverse();

  const evidence = toEvidenceResult(evidenceRes.data, evidenceRes.error);
  const identityLabel =
    wi?.label ??
    (evidence.status === 'ok' ? evidence.data.identity.label : null) ??
    snap.work_identity?.label ??
    scoped?.identity.label ??
    null;
  const identityProfession =
    wi?.professions?.name ??
    (evidence.status === 'ok' ? evidence.data.identity.profession : null) ??
    scoped?.identity.profession ??
    null;
  const completeness =
    wi?.completeness_score ?? (evidence.status === 'ok' ? evidence.data.identity.completeness : null);
  const profileAnswers = toProfileAnswers(answerRes.data ?? []);
  const answersForbidden = answerRes.error?.code === '42501';

  // Per section: fall back to the snapshot when the scope is narrowed, or the
  // live rows are unreadable / empty but the snapshot has them.
  const snapEvidence = !!scoped && (narrowed || evidence.status !== 'ok');
  const snapAnswers =
    !!scoped && (narrowed || !!answerRes.error || (profileAnswers.length === 0 && (scoped.answers?.length ?? 0) > 0));
  const snapExperience =
    !!scoped &&
    (narrowed || !!expRes.error || ((expRes.data ?? []).length === 0 && (scoped.experience?.length ?? 0) > 0));
  const about = wi?.about ?? scoped?.identity.about ?? null;

  const verifiedExp = (expRes.data ?? []).filter((e) => e.is_verified);
  const selfExp = (expRes.data ?? []).filter((e) => !e.is_verified);

  return (
    <div className="space-y-6 max-w-5xl">
      <Link
        href={`/dashboard/candidates${job ? `?job=${job.id}` : ''}`}
        className="text-sm underline muted"
      >
        ← Candidates{job ? ` for ${job.title}` : ''}
      </Link>

      {viewError && (
        <p className="text-sm" style={{ color: 'var(--color-warn)' }}>
          Could not mark this application as viewed: {viewError.message}
        </p>
      )}

      {/* ---------------------------------------------------------- Header */}
      <header className="card p-5 flex items-start gap-4 flex-wrap">
        <div className="flex-1 min-w-[12rem]">
          <h1 className="text-xl sm:text-2xl font-bold break-words">{name}</h1>
          {identityLabel && (
            <p className="text-sm mt-1 break-words">
              <span className="muted">Applied as:</span>{' '}
              <span className="font-semibold">{identityLabel}</span>
              {identityProfession && identityProfession !== identityLabel ? ` · ${identityProfession}` : ''}
            </p>
          )}
          {completeness != null && (
            <div className="mt-2 max-w-xs">
              <CompletenessMeter score={completeness} />
            </div>
          )}
          {headline && headline !== identityLabel && <p className="text-sm mt-2 break-words">{headline}</p>}
          <p className="text-sm muted mt-1 break-words">
            {[
              monthsLabel(wi?.total_experience_months ?? scoped?.identity.experienceMonths),
              person?.location_text ?? snap.person?.location_text ?? scoped?.identity.location,
            ]
              .filter(Boolean)
              .join(' · ')}
          </p>
          <p className="text-sm muted mt-2 break-words">
            Applied to{' '}
            {job ? (
              <Link href={`/dashboard/jobs/${job.id}`} className="underline">
                {job.title}
              </Link>
            ) : (
              'a job'
            )}{' '}
            · {timeAgo(app.applied_at)}
          </p>
          <div className="flex items-center gap-2 flex-wrap mt-3">
            <StateBadge state={state} />
            {submissionAgency && <SubmittedByBadge agency={submissionAgency} recruiter={submissionRecruiter} />}
            {match &&
              (gateFailures.length === 0 && match.eligible ? (
                <span className="pill" style={{ color: 'var(--color-verified)' }}>
                  Meets all must-haves
                </span>
              ) : (
                gateFailures.map((g) => (
                  <span key={g} className="pill" style={{ color: 'var(--color-danger)' }}>
                    {gateLabel(g)}
                  </span>
                ))
              ))}
          </div>
        </div>
        <div className="text-right shrink-0">
          <div
            className="text-4xl sm:text-5xl font-black leading-none"
            style={{ color: score != null ? 'var(--color-brand-600)' : 'var(--muted)' }}
          >
            {score != null ? `${score}%` : '—'}
          </div>
          <div className="text-xs muted mt-1">match</div>
        </div>
        <div className="basis-full flex flex-wrap gap-2 items-start border-t hairline pt-4">
          <a href="#review" className="btn btn-ghost">
            Review
          </a>
          {isHiringTeam && <MessageButton applicationId={app.id} />}
          {isPreOffer && isHiringTeam && (
            <ScheduleInterviewForm
              {...scheduleProps}
              primary={['shortlisted', 'screening', 'assessment'].includes(state)}
            />
          )}
        </div>
      </header>

      {/* ------------------------------------------ Recruiter submission */}
      {scoped && submissionAgency && (
        <SubmissionCard
          agency={submissionAgency}
          recruiter={submissionRecruiter}
          note={submissionRow?.recruiter_note ?? clientSub?.recruiterNote ?? scoped.submittedVia?.note ?? null}
          consentStatus={clientSub?.consentStatus ?? null}
          scope={scoped.scope}
          submittedAt={submittedAt}
          jobOrder={scoped.submittedVia?.jobOrder ?? null}
          error={submissionError}
        />
      )}

      {/* ------------------------------------------------------ Action bar */}
      {isOpen ? (
        <section className="card p-4" aria-label="Next steps">
          <div className="flex flex-wrap gap-2 items-start">
            {(state === 'applied' || state === 'viewed') && (
              <MoveButton applicationId={app.id} state="shortlisted" label="Shortlist" primary />
            )}
            {(['applied', 'viewed', 'shortlisted'] as ApplicationState[]).includes(state) && (
              <MoveButton applicationId={app.id} state="screening" label="Move to phone screen" />
            )}
            {(['applied', 'viewed', 'shortlisted', 'screening'] as ApplicationState[]).includes(state) && (
              <MoveButton applicationId={app.id} state="assessment" label="Move to assessment" />
            )}
            {isPreOffer && !openOffer && !decisionDue && (
              <SendOfferForm applicationId={app.id} primary={state === 'interview'} defaults={offerDefaults} />
            )}
            {!decisionDue && <RejectForm applicationId={app.id} />}
          </div>
          {decisionDue && (
            <p className="text-sm muted mt-3">
              <a href="#feedback" className="underline">
                Decide the next step
              </a>{' '}
              under Interview rounds.
            </p>
          )}
          {state === 'offer' && (
            <p className="text-sm muted mt-3">
              Waiting for the candidate to reply to your offer. You can withdraw it below.
            </p>
          )}
        </section>
      ) : isClosed ? (
        <section
          className="card p-5"
          style={{ borderColor: TONE_COLOR[stateTone(state)] }}
          aria-label="Final status"
        >
          {state === 'hired' ? (
            <>
              <p className="font-bold" style={{ color: 'var(--color-verified)' }}>
                Hired{employment?.title ? ` as ${employment.title}` : ''}
              </p>
              <p className="text-sm muted mt-1">
                {employment
                  ? `Start date ${calendarDate(employment.started_on)}.${
                      employment.pay_amount != null
                        ? ` Pay ${formatPay({ min: employment.pay_amount, currency: employment.pay_currency, period: employment.pay_period })}.`
                        : ''
                    }${employment.country_code ? ` Works in ${countryName(employment.country_code)}.` : ''} This job is now verified work history on their Omelo profile.`
                  : employmentRes.error
                    ? `Employment record could not be loaded: ${employmentRes.error.message}`
                    : 'Employment record not found.'}
              </p>
            </>
          ) : state === 'rejected' ? (
            <>
              <p className="font-bold">Not moving forward</p>
              {app.rejection_reason && (
                <p className="text-sm mt-1">
                  Reason shown to the candidate: <span className="muted">“{app.rejection_reason}”</span>
                </p>
              )}
            </>
          ) : state === 'withdrawn' ? (
            <>
              <p className="font-bold">The candidate withdrew</p>
              {app.withdrawal_reason && <p className="text-sm muted mt-1">“{app.withdrawal_reason}”</p>}
            </>
          ) : state === 'declined_by_candidate' ? (
            <>
              <p className="font-bold">The candidate declined your offer</p>
              {latestOffer?.decline_reason && (
                <p className="text-sm muted mt-1">“{latestOffer.decline_reason}”</p>
              )}
            </>
          ) : (
            <p className="font-bold">This application has expired</p>
          )}
          {app.closed_at && (
            <p className="text-xs muted mt-2">Closed {timeAgo(app.closed_at)}</p>
          )}
        </section>
      ) : null}

      <div className="grid gap-6 lg:grid-cols-3 items-start">
        {/* ============================================== Main column */}
        <div className="space-y-6 lg:col-span-2 min-w-0">
          {/* ------------------------------------------ Interview rounds */}
          <section className="card p-5 scroll-mt-6" id="feedback">
            <SectionTitle>Interview rounds</SectionTitle>
            {interviewRes.error ? (
              <ErrorNote label="interviews" message={interviewRes.error.message} />
            ) : interviews.length === 0 ? (
              <p className="text-sm muted">
                No interviews yet.
                {nextPlanned ? ` The first planned round is ${nextPlanned.name}.` : ''}
              </p>
            ) : (
              <InterviewRounds
                interviews={interviews}
                feedback={feedback}
                panels={panels}
                names={names}
                userId={user?.id ?? null}
                isHiringTeam={isHiringTeam}
                jobId={app.job_id}
                canManage={isHiringTeam}
              />
            )}
            {feedbackRes.error && <ErrorNote label="feedback" message={feedbackRes.error.message} />}

            {decisionDue && (
              <div className="mt-5 border-t hairline pt-4">
                <p className="font-semibold text-sm mb-1">Decision</p>
                <p className="text-sm muted mb-3">
                  {lastInterview?.round_name ?? 'The interview'} is complete. What happens next?
                </p>
                <div className="flex flex-wrap gap-2 items-start">
                  <ScheduleInterviewForm
                    {...scheduleProps}
                    label={nextPlanned ? `Move to ${nextPlanned.name}` : 'Schedule next round'}
                    defaultRoundName={nextPlanned?.name ?? null}
                    primary
                  />
                  {!openOffer && <SendOfferForm applicationId={app.id} defaults={offerDefaults} />}
                  <RejectForm applicationId={app.id} />
                </div>
              </div>
            )}
          </section>

          {/* -------------------------------------------- Why this match */}
          <section className="card p-5 scroll-mt-6" id="review">
            <SectionTitle
              aside={job && match ? <RescoreButton jobId={job.id} /> : undefined}
            >
              Why this match
            </SectionTitle>
            {matchRes.error ? (
              <ErrorNote label="the match explanation" message={matchRes.error.message} />
            ) : !fv ? (
              <div className="space-y-3">
                <p className="text-sm muted">
                  No match explanation has been computed for this candidate yet.
                </p>
                {job && <RescoreButton jobId={job.id} label="Compute match" primary />}
              </div>
            ) : (
              <div className="space-y-5">
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
                {missingSkills.length > 0 && (
                  <div>
                    <p className="label">Missing required skills</p>
                    <div className="flex flex-wrap gap-2">
                      {missingSkills.map((s) => (
                        <span key={s} className="pill" style={{ color: 'var(--color-warn)' }}>
                          {s}
                        </span>
                      ))}
                    </div>
                  </div>
                )}
                {(fv.unknowns ?? []).length > 0 && (
                  <div>
                    <p className="label">Not on profile yet</p>
                    <Reasons items={fv.unknowns!} color="var(--muted)" mark="?" />
                    <p className="hint">
                      Unknowns are scored as neutral, not as failures. Ask the
                      candidate if they matter for this role.
                    </p>
                  </div>
                )}
                {match && (
                  <p className="text-xs muted">
                    Computed {timeAgo(match.computed_at)} · engine {match.engine_version}
                    {fv.weight_profile ? ` · ${fv.weight_profile} weighting` : ''}
                  </p>
                )}
              </div>
            )}
          </section>

          {/* ---------------------------------------------------- Evidence */}
          <section className="card p-5 scroll-mt-6" id="evidence">
            <SectionTitle
              aside={
                identityLabel ? <span className="text-xs muted">for {identityLabel}</span> : undefined
              }
            >
              Evidence
            </SectionTitle>
            {snapEvidence && scoped ? (
              <>
                <SnapshotEvidence scoped={scoped} />
                <SnapshotNote submittedAt={submittedAt} />
              </>
            ) : (
              <EvidenceGate result={evidence}>{(ev) => <EvidencePanel ev={ev} />}</EvidenceGate>
            )}
          </section>

          {/* --------------------------------------------- Profile answers */}
          <section className="card p-5">
            <SectionTitle>Profile answers</SectionTitle>
            {snapAnswers && scoped ? (
              <SnapshotAnswers scoped={scoped} />
            ) : answersForbidden ? (
              <HiringTeamOnly />
            ) : answerRes.error ? (
              <ErrorNote label="profile answers" message={answerRes.error.message} />
            ) : (
              <ProfileAnswers answers={profileAnswers} />
            )}
          </section>

          {/* ------------------------------------------------ Work history */}
          <section className="card p-5 space-y-5">
            <SectionTitle>Work history</SectionTitle>
            {snapExperience && scoped ? (
              <SnapshotExperience scoped={scoped} />
            ) : expRes.error ? (
              <ErrorNote label="work history" message={expRes.error.message} />
            ) : (expRes.data ?? []).length === 0 ? (
              <p className="text-sm muted">No work history on this work identity yet.</p>
            ) : (
              <ul className="space-y-4">
                {[...verifiedExp, ...selfExp].map((e) => (
                  <li key={e.id} className="flex items-start gap-3">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="font-semibold text-sm break-words">{e.title}</span>
                        {e.is_verified ? (
                          <span
                            className="pill"
                            style={{ color: 'var(--color-verified)', borderColor: 'var(--color-verified)' }}
                          >
                            ✓ Verified by Omelo
                          </span>
                        ) : (
                          <span className="pill">Self-declared</span>
                        )}
                      </div>
                      <div className="text-sm muted break-words">
                        {e.employer_name}
                        {e.location_text ? ` · ${e.location_text}` : ''}
                      </div>
                      <div className="text-xs muted mt-0.5">
                        {monthYear(e.started_on) || 'Start not given'} –{' '}
                        {e.is_current ? 'Present' : monthYear(e.ended_on) || 'end not given'}
                        {e.months_duration ? ` · ${monthsLabel(e.months_duration)}` : ''}
                      </div>
                      {e.description && (
                        <p className="text-sm mt-1 whitespace-pre-line break-words">{e.description}</p>
                      )}
                    </div>
                  </li>
                ))}
              </ul>
            )}

            <div>
              <p className="label">Languages</p>
              {narrowed ? (
                <NotShared />
              ) : langRes.error ? (
                <ErrorNote label="languages" message={langRes.error.message} />
              ) : (langRes.data ?? []).length === 0 ? (
                <p className="text-sm muted">None listed.</p>
              ) : (
                <ul className="text-sm space-y-1">
                  {(langRes.data ?? []).map((l) => (
                    <li key={l.language_code}>
                      {(l.languages as unknown as { name: string } | null)?.name ?? l.language_code}{' '}
                      <span className="muted">· {PROFICIENCY_LABEL[l.proficiency] ?? l.proficiency}</span>
                    </li>
                  ))}
                </ul>
              )}
            </div>

            {about && (
              <div>
                <p className="label">About</p>
                <p className="text-sm whitespace-pre-line break-words">{about}</p>
              </div>
            )}

            {scoped ? (
              <p className="hint">
                {snapExperience
                  ? `Shown as the candidate shared it through ${submissionAgency?.name ?? 'the agency'}. `
                  : ''}
                You see only what the candidate agreed to share with the agency. Other work identities they hold
                stay private.
              </p>
            ) : (
              <p className="hint">
                Everything above is from the {identityLabel ? <strong>{identityLabel}</strong> : 'work'} profile
                this candidate applied with, plus details they share across all their profiles. Other work
                identities they hold stay private.
              </p>
            )}
          </section>

          {/* ------------------------------------------------ Application */}
          <section className="card p-5 space-y-4">
            <SectionTitle>Application</SectionTitle>
            {answers.length > 0 ? (
              <dl className="space-y-3">
                {answers.map((a, i) => (
                  <div key={a.question_id ?? i}>
                    <dt className="text-sm font-medium break-words">{a.prompt ?? `Question ${i + 1}`}</dt>
                    <dd className="text-sm muted break-words">
                      {typeof a.answer === 'boolean'
                        ? a.answer
                          ? 'Yes'
                          : 'No'
                        : a.answer == null || a.answer === ''
                          ? 'No answer'
                          : typeof a.answer === 'object'
                            ? JSON.stringify(a.answer)
                            : String(a.answer)}
                    </dd>
                  </div>
                ))}
              </dl>
            ) : (
              <p className="text-sm muted">No screening answers.</p>
            )}
            {app.cover_note && (
              <div>
                <p className="label">{isAgency ? 'Note from the recruiter' : 'Note from the candidate'}</p>
                <p className="text-sm whitespace-pre-line break-words">{app.cover_note}</p>
              </div>
            )}
            {(snap.work_identity || snap.person) && (
              <div className="surface rounded-lg p-3 text-sm">
                <p className="label">Profile when they applied</p>
                <p className="break-words">
                  {[snap.person?.display_name, snap.work_identity?.headline ?? snap.work_identity?.label, snap.person?.location_text]
                    .filter(Boolean)
                    .join(' · ')}
                </p>
                {snap.captured_at && (
                  <p className="text-xs muted mt-1">Captured {timeAgo(snap.captured_at)}</p>
                )}
              </div>
            )}
          </section>
        </div>

        {/* ============================================== Side column */}
        <div className="space-y-6 min-w-0">
          <EligibilityPanel
            eligibility={parseCandidateEligibility(eligibilityRes.data ?? null)}
            error={eligibilityRes.error?.message ?? null}
            jobTitle={job?.title ?? null}
          />
          {/* ------------------------------------------------------ Offer */}
          {(offerRes.error || offers.length > 0) && (
            <section className="card p-5">
              <SectionTitle>Offer</SectionTitle>
              {offerRes.error ? (
                <ErrorNote label="offers" message={offerRes.error.message} />
              ) : (
                <ul className="space-y-4">
                  {offers.map((o, idx) => {
                    const benefits = Array.isArray(o.benefits) ? (o.benefits as string[]) : [];
                    const isOpenOffer = OPEN_OFFER_STATUSES.includes(o.status);
                    return (
                      <li
                        key={o.id}
                        className={`space-y-2 ${idx > 0 ? 'border-t hairline pt-4 opacity-80' : ''}`}
                      >
                        <div className="flex items-center gap-2 flex-wrap">
                          <span className="font-semibold text-sm break-words">{o.title}</span>
                          <span
                            className="pill"
                            style={{
                              color:
                                o.status === 'accepted'
                                  ? 'var(--color-verified)'
                                  : isOpenOffer
                                    ? 'var(--fg)'
                                    : 'var(--color-danger)',
                            }}
                          >
                            {OFFER_STATUS_LABEL[o.status]}
                          </span>
                        </div>
                        <p className="text-lg font-bold">
                          {formatPay({ min: o.pay_amount, currency: o.pay_currency, period: o.pay_period })}
                        </p>
                        <dl className="text-sm grid grid-cols-[auto_1fr] gap-x-3 gap-y-1">
                          <dt className="muted">Start</dt>
                          <dd>{calendarDate(o.start_date)}</dd>
                          {o.sent_at && (
                            <>
                              <dt className="muted">Sent</dt>
                              <dd>{timeAgo(o.sent_at)}</dd>
                            </>
                          )}
                          {o.viewed_at && (
                            <>
                              <dt className="muted">Seen</dt>
                              <dd>{timeAgo(o.viewed_at)}</dd>
                            </>
                          )}
                          {isOpenOffer && o.expires_at && (
                            <>
                              <dt className="muted">Expires</dt>
                              <dd>
                                <LocalTime iso={o.expires_at} />
                              </dd>
                            </>
                          )}
                          {o.responded_at && !isOpenOffer && (
                            <>
                              <dt className="muted">Closed</dt>
                              <dd>{timeAgo(o.responded_at)}</dd>
                            </>
                          )}
                        </dl>
                        {o.decline_reason && (
                          <p className="text-sm muted break-words">
                            {o.status === 'withdrawn' ? 'Withdrawn' : 'Reason'}: “{o.decline_reason}”
                          </p>
                        )}
                        {o.conditions && (
                          <p className="text-sm break-words">
                            <span className="muted">Conditions:</span> {o.conditions}
                          </p>
                        )}
                        {benefits.length > 0 && (
                          <div className="flex flex-wrap gap-1.5">
                            {benefits.map((b) => (
                              <span key={String(b)} className="pill">
                                {BENEFIT_LABEL[String(b)] ?? String(b)}
                              </span>
                            ))}
                          </div>
                        )}
                        {isOpenOffer && (
                          <div className="pt-1">
                            <WithdrawOfferForm offerId={o.id} />
                          </div>
                        )}
                      </li>
                    );
                  })}
                </ul>
              )}
            </section>
          )}

          {/* ---------------------------------------------------- Contact */}
          {scoped && (
            <section className="card p-5">
              <SectionTitle>Contact details</SectionTitle>
              <SnapshotContact scoped={scoped} />
            </section>
          )}

          {/* ------------------------------------------------------ Notes */}
          <section className="card p-5 space-y-4">
            <SectionTitle>Private notes</SectionTitle>
            <NoteForm applicationId={app.id} />
            {noteRes.error ? (
              <ErrorNote label="notes" message={noteRes.error.message} />
            ) : (
              <ul className="space-y-3">
                {(noteRes.data ?? []).map((n) => (
                  <li key={n.id} className="surface rounded-lg p-3">
                    <p className="text-sm whitespace-pre-line break-words">{n.body}</p>
                    <p className="text-xs muted mt-1.5">
                      {n.author_id && n.author_id === user?.id ? 'You' : 'Your team'} ·{' '}
                      {timeAgo(n.created_at)}
                    </p>
                  </li>
                ))}
              </ul>
            )}
          </section>

          {/* --------------------------------------------------- Timeline */}
          <section className="card p-5">
            <SectionTitle>Timeline</SectionTitle>
            {eventRes.error ? (
              <ErrorNote label="the timeline" message={eventRes.error.message} />
            ) : timeline.length === 0 ? (
              <p className="text-sm muted">No activity yet.</p>
            ) : (
              <ol className="space-y-3">
                {timeline.map((t) => (
                  <li key={t.id} className="flex items-start gap-3">
                    <span
                      aria-hidden
                      className="mt-1.5 h-2 w-2 rounded-full shrink-0"
                      style={{ background: TONE_COLOR[t.tone] }}
                    />
                    <div className="min-w-0">
                      <p className="text-sm font-medium break-words">
                        {t.title}
                        {t.detail ? <span className="font-normal muted"> — {t.detail}</span> : null}
                      </p>
                      <p className="text-xs muted">
                        <LocalTime iso={t.at} />
                      </p>
                    </div>
                  </li>
                ))}
              </ol>
            )}
          </section>
        </div>
      </div>
    </div>
  );
}
