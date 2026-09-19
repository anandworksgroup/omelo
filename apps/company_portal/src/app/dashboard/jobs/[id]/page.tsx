import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import {
  BENEFIT_LABEL,
  SHIFT_LABEL,
  STATE_LABEL,
  WORKPLACE_LABEL,
  WORK_TYPE_LABEL,
  experienceLabel,
  formatPay,
  timeAgo,
} from '@/lib/format';
import { closeJob, pauseJob, publishJob } from '../../actions';
import { TALENT_ROLES, parseFunnel, parseInvitations } from '@/lib/talent';
import RoundsEditor from './rounds-editor';
import FunnelPanel from './funnel';
import InvitationsPanel from './invitations';
import GlobalHiringEditor from './global-editor';
import { loadGlobalOptions } from '@/lib/global-data';
import {
  REMOTE_SCOPE_LABEL,
  SPONSORSHIP_LABEL,
  SUPPORT_FLAGS,
  SUPPORT_LABEL,
  countryName,
  parseNormalizedPay,
  utcOffsetLabel,
  type GlobalHiring,
  type RemoteScope,
  type Sponsorship,
} from '@/lib/global';
import { formatMoney } from '@/lib/format';

export default async function JobDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  const { data: job } = await supabase
    .from('jobs')
    .select(
      `id, title, status, description, location_text, workplace_type, work_type,
       shift_types, hours_per_week, working_days, is_immediate_start, openings,
       pay_min, pay_max, pay_period, pay_currency, pay_negotiable,
       min_experience_months, accepts_no_experience, requires_resume,
       quick_apply_enabled, applicant_count, view_count, published_at, created_at,
       country_code, legal_entity_id, sponsorship, sponsorship_type, immigration_support, legal_support,
       visa_fees_covered, travel_assistance, accommodation_assistance, relocation_support,
       accepts_non_residents, remote_scope, remote_countries, remote_tz_min_offset, remote_tz_max_offset,
       company_legal_entities ( legal_name ),
       professions ( name ),
       job_benefits ( benefit_type ),
       job_skills ( requirement_level, skills ( name ) ),
       job_questions ( prompt ),
       job_stages ( name, position, maps_to_state )`
    )
    .eq('id', id)
    .eq('company_id', ctx.companyId)
    .maybeSingle();

  if (!job) notFound();

  const { data: apps } = await supabase
    .from('applications')
    .select('id, state, applied_at, last_activity_at, match_score')
    .eq('job_id', id)
    .order('applied_at', { ascending: false });

  const { data: plannedRounds, error: roundsError } = await supabase
    .from('job_interview_rounds')
    .select('id, position, name, kind, meeting_mode, duration_minutes')
    .eq('job_id', id)
    .order('position');
  const canEditRounds = ['owner', 'admin', 'recruiter', 'hiring_manager', 'hr'].includes(ctx.role);

  const payAmount = job.pay_max ?? job.pay_min;
  const [funnelRes, invitationsRes, global, normRes] = await Promise.all([
    supabase.rpc('omelo_job_funnel', { p_job_id: id }),
    supabase.rpc('omelo_job_invitations', { p_job_id: id }),
    loadGlobalOptions(supabase, ctx.companyId),
    payAmount != null && job.pay_period && job.pay_currency
      ? supabase.rpc('omelo_normalized_pay', {
          p_amount: payAmount,
          p_period: job.pay_period,
          p_currency: job.pay_currency,
        })
      : Promise.resolve({ data: null, error: null }),
  ]);
  const normalized = parseNormalizedPay(normRes.data ?? null);
  const globalValues: GlobalHiring = {
    country_code: job.country_code?.trim() ?? null,
    legal_entity_id: job.legal_entity_id,
    sponsorship: (job.sponsorship ?? 'no') as Sponsorship,
    sponsorship_type: job.sponsorship_type,
    immigration_support: job.immigration_support,
    legal_support: job.legal_support,
    visa_fees_covered: job.visa_fees_covered,
    travel_assistance: job.travel_assistance,
    accommodation_assistance: job.accommodation_assistance,
    relocation_support: job.relocation_support ?? false,
    accepts_non_residents: job.accepts_non_residents ?? false,
    remote_scope: (job.remote_scope ?? null) as RemoteScope | null,
    remote_countries: (job.remote_countries ?? []).map((c) => c.trim()),
    remote_tz_min_offset: job.remote_tz_min_offset,
    remote_tz_max_offset: job.remote_tz_max_offset,
  };
  const supports = SUPPORT_FLAGS.filter((f) => globalValues[f]);
  const entityName =
    (job.company_legal_entities as unknown as { legal_name: string } | null)?.legal_name ?? null;
  const canEditJob = ['owner', 'admin', 'recruiter'].includes(ctx.role);
  const funnel = funnelRes.error ? null : parseFunnel(funnelRes.data);
  const invitations = parseInvitations(invitationsRes.data).map((inv) => ({
    ...inv,
    sentAgo: timeAgo(inv.sentAt),
    answeredAgo: timeAgo(inv.respondedAt),
  }));
  const canUseTalent = TALENT_ROLES.includes(ctx.role);

  const stages = [...(job.job_stages ?? [])].sort((a, b) => a.position - b.position);
  const required = (job.job_skills ?? []).filter((s) => s.requirement_level === 'required');
  const preferred = (job.job_skills ?? []).filter((s) => s.requirement_level !== 'required');
  const isPublished = job.status === 'published';

  return (
    <div className="space-y-8 max-w-3xl">
      <div>
        <Link href="/dashboard/jobs" className="text-sm underline muted">
          ← All jobs
        </Link>
        <div className="flex items-start gap-3 mt-3 flex-wrap">
          <h1 className="text-xl sm:text-2xl font-bold flex-1 min-w-0 break-words">
            {job.title}
          </h1>
          <span className="pill">{job.status}</span>
        </div>
        <p className="muted text-sm mt-1">
          {job.professions?.name ?? '—'} · {job.location_text ?? '—'} ·{' '}
          {WORKPLACE_LABEL[job.workplace_type] ?? job.workplace_type}
        </p>
      </div>

      {/* Publish controls */}
      <div className="card p-5">
        {!isPublished ? (
          <>
            <h2 className="font-bold mb-1">Not visible to workers yet</h2>
            <p className="text-sm muted mb-4 leading-relaxed">
              Publishing makes this job appear in nearby search immediately for
              workers within range.
            </p>
            <form action={publishJob}>
              <input type="hidden" name="job_id" value={job.id} />
              <button className="btn btn-primary">Publish job</button>
            </form>
          </>
        ) : (
          <>
            <h2 className="font-bold mb-1" style={{ color: 'var(--color-verified)' }}>
              Live — published {timeAgo(job.published_at)}
            </h2>
            <p className="text-sm muted mb-4">
              {job.view_count} views · {apps?.length ?? 0} applications
            </p>
            <div className="flex gap-2 flex-wrap">
              {canUseTalent && (
                <Link href={`/dashboard/talent?job=${job.id}`} className="btn btn-primary">
                  Find candidates
                </Link>
              )}
              <Link href={`/dashboard/workforce/requirements/new?job=${job.id}`} className="btn btn-ghost">
                Staff it
              </Link>
              <form action={pauseJob}>
                <input type="hidden" name="job_id" value={job.id} />
                <button className="btn btn-ghost">Pause</button>
              </form>
              <form action={closeJob}>
                <input type="hidden" name="job_id" value={job.id} />
                <button className="btn btn-ghost">Close</button>
              </form>
            </div>
          </>
        )}
      </div>

      {/* What the worker sees */}
      <section className="card p-5 space-y-4">
        <h2 className="font-bold">What workers see</h2>

        <div className="text-lg font-bold">
          {formatPay({
            min: job.pay_min,
            max: job.pay_max,
            currency: job.pay_currency,
            period: job.pay_period,
            negotiable: job.pay_negotiable,
          })}
        </div>
        {normalized && normalized.monthly != null && job.pay_period !== 'month' && (
          <p className="text-xs muted -mt-2">
            About {formatMoney(normalized.monthly, normalized.currency)} a month
            {normalized.yearly != null ? ` · ${formatMoney(normalized.yearly, normalized.currency)} a year` : ''}
            {normalized.hourly != null && job.pay_period !== 'hour'
              ? ` · ${formatMoney(normalized.hourly, normalized.currency)} an hour`
              : ''}{' '}
            (8-hour days, 26 days a month)
          </p>
        )}

        <div className="flex flex-wrap gap-2">
          <span className="pill">{WORK_TYPE_LABEL[job.work_type] ?? job.work_type}</span>
          {(job.shift_types ?? []).map((s: string) => (
            <span key={s} className="pill">
              {SHIFT_LABEL[s] ?? s}
            </span>
          ))}
          <span className="pill" style={{ color: 'var(--color-verified)' }}>
            {experienceLabel(job.min_experience_months, job.accepts_no_experience)}
          </span>
          {job.is_immediate_start && <span className="pill">Immediate start</span>}
          {job.quick_apply_enabled && <span className="pill">Quick apply</span>}
        </div>

        {(job.job_benefits ?? []).length > 0 && (
          <div>
            <p className="label">Benefits</p>
            <div className="flex flex-wrap gap-2">
              {(job.job_benefits ?? []).map((b) => (
                <span key={b.benefit_type} className="pill" style={{ color: 'var(--color-verified)' }}>
                  {BENEFIT_LABEL[b.benefit_type] ?? b.benefit_type}
                </span>
              ))}
            </div>
          </div>
        )}

        {required.length > 0 && (
          <div>
            <p className="label">Required</p>
            <div className="flex flex-wrap gap-2">
              {required.map((s, i) => (
                <span key={i} className="pill">
                  {s.skills?.name}
                </span>
              ))}
            </div>
            {preferred.length > 0 && (
              <>
                <p className="label mt-3">Helpful, not required</p>
                <div className="flex flex-wrap gap-2">
                  {preferred.map((s, i) => (
                    <span key={i} className="pill">
                      {s.skills?.name}
                    </span>
                  ))}
                </div>
              </>
            )}
          </div>
        )}

        {job.description && (
          <div>
            <p className="label">The work</p>
            <p className="text-sm leading-relaxed whitespace-pre-line">{job.description}</p>
          </div>
        )}

        {(job.job_questions ?? []).length > 0 && (
          <div>
            <p className="label">Screening question</p>
            <p className="text-sm">{job.job_questions[0].prompt}</p>
          </div>
        )}
      </section>

      {/* Global hiring */}
      <section className="card p-5 space-y-4">
        <h2 className="font-bold">Global hiring</h2>
        <dl className="text-sm grid grid-cols-1 sm:grid-cols-[auto_1fr] gap-x-4 gap-y-1.5">
          <dt className="muted">Country</dt>
          <dd>{countryName(globalValues.country_code) ?? 'Not set'}</dd>
          <dt className="muted">Legal entity</dt>
          <dd className="break-words">{entityName ?? 'None'}</dd>
          <dt className="muted">Sponsorship</dt>
          <dd>
            {SPONSORSHIP_LABEL[globalValues.sponsorship] ?? globalValues.sponsorship}
            {globalValues.sponsorship !== 'no' && globalValues.sponsorship_type
              ? ` · ${globalValues.sponsorship_type}`
              : ''}
          </dd>
          <dt className="muted">Applicants abroad</dt>
          <dd>{globalValues.accepts_non_residents ? 'Welcome to apply' : 'Not accepted'}</dd>
          {job.workplace_type === 'remote' && (
            <>
              <dt className="muted">Remote from</dt>
              <dd className="break-words">
                {globalValues.remote_scope === 'countries'
                  ? globalValues.remote_countries.map((c) => countryName(c)).join(', ')
                  : globalValues.remote_scope === 'timezone' &&
                      globalValues.remote_tz_min_offset != null &&
                      globalValues.remote_tz_max_offset != null
                    ? `${utcOffsetLabel(globalValues.remote_tz_min_offset)} to ${utcOffsetLabel(globalValues.remote_tz_max_offset)}`
                    : globalValues.remote_scope
                      ? REMOTE_SCOPE_LABEL[globalValues.remote_scope]
                      : 'Not specified'}
              </dd>
            </>
          )}
        </dl>
        {supports.length > 0 && (
          <div className="flex flex-wrap gap-2">
            {supports.map((f) => (
              <span key={f} className="pill" style={{ color: 'var(--color-verified)' }}>
                {SUPPORT_LABEL[f]}
              </span>
            ))}
          </div>
        )}
        {globalValues.country_code && (
          <p className="text-sm">
            <Link href={`/dashboard/global/countries/${globalValues.country_code}`} className="underline">
              Hiring in {countryName(globalValues.country_code)}: country guide
            </Link>
          </p>
        )}
        {canEditJob && (
          <GlobalHiringEditor
            jobId={job.id}
            workplace={job.workplace_type}
            initial={globalValues}
            countries={global.countries}
            entities={global.entities}
          />
        )}
      </section>

      {/* Interview process */}
      {roundsError ? (
        <section className="card p-5">
          <h2 className="font-bold mb-1">Interview process</h2>
          <p className="text-sm" style={{ color: 'var(--color-danger)' }}>
            Could not load the interview process: <span className="muted">{roundsError.message}</span>
          </p>
        </section>
      ) : (
        <RoundsEditor jobId={job.id} rounds={plannedRounds ?? []} canEdit={canEditRounds} />
      )}

      {/* Funnel */}
      <FunnelPanel funnel={funnel} error={funnelRes.error?.message} />

      {/* Invitations */}
      <InvitationsPanel
        jobId={job.id}
        invitations={invitations}
        error={invitationsRes.error?.message}
        canManage={canUseTalent}
        canSearch={canUseTalent && isPublished}
      />

      {/* Pipeline */}
      <section className="card p-5">
        <h2 className="font-bold mb-1">Your pipeline</h2>
        <p className="text-sm muted mb-4 leading-relaxed">
          You can rename these stages. The right column is what the candidate
          sees, and it cannot be hidden or faked.
        </p>
        <div className="text-sm">
          {stages.map((s) => (
            <div key={s.position} className="flex justify-between py-2 border-b hairline last:border-0">
              <span className="font-medium">{s.name}</span>
              <span className="muted">{STATE_LABEL[s.maps_to_state] ?? s.maps_to_state}</span>
            </div>
          ))}
        </div>
      </section>

      {/* Applicants */}
      <section>
        <h2 className="font-bold text-lg mb-3">
          Applicants ({apps?.length ?? 0})
        </h2>
        {(apps ?? []).length === 0 ? (
          <div className="card p-8 text-center text-sm muted">
            {isPublished
              ? 'No applications yet. Workers nearby can see this job now.'
              : 'Publish the job to start receiving applications.'}
          </div>
        ) : (
          <div className="card divide-y" style={{ borderColor: 'var(--line)' }}>
            {(apps ?? []).map((a) => (
              <div key={a.id} className="p-4 flex items-center gap-4">
                <div className="flex-1 min-w-0">
                  <div className="font-semibold text-sm">
                    Candidate · applied {timeAgo(a.applied_at)}
                  </div>
                  <div className="text-xs muted mt-0.5">
                    {STATE_LABEL[a.state] ?? a.state}
                  </div>
                </div>
                {a.match_score != null && (
                  <span className="pill">{a.match_score}% match</span>
                )}
                <Link href={`/dashboard/candidates/${a.id}`} className="text-sm underline">
                  Review
                </Link>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
