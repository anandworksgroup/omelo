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
                <Link href={`/dashboard/candidates`} className="text-sm underline">
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
