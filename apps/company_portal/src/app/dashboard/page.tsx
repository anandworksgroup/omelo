import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { STATE_LABEL, timeAgo } from '@/lib/format';

export default async function DashboardPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  const [{ data: jobs }, { data: apps }, { data: ent }] = await Promise.all([
    supabase
      .from('jobs')
      .select('id, title, status, applicant_count, view_count, published_at')
      .eq('company_id', ctx.companyId)
      .order('created_at', { ascending: false }),
    supabase
      .from('applications')
      .select('id, state, applied_at, last_activity_at, job_id')
      .eq('company_id', ctx.companyId),
    supabase
      .from('company_entitlements')
      .select('plan, active_job_slots, talent_search_enabled')
      .eq('company_id', ctx.companyId)
      .maybeSingle(),
  ]);

  const published = (jobs ?? []).filter((j) => j.status === 'published');
  const drafts = (jobs ?? []).filter((j) => j.status === 'draft');
  const all = apps ?? [];

  const byState = (s: string) => all.filter((a) => a.state === s).length;

  // The stale-application count is deliberately the first thing on the page.
  const STALE_DAYS = 5;
  const stale = all.filter((a) => {
    if (['hired', 'rejected', 'withdrawn', 'expired', 'declined_by_candidate'].includes(a.state))
      return false;
    const days =
      (Date.now() - new Date(a.last_activity_at).getTime()) / 86_400_000;
    return days >= STALE_DAYS;
  }).length;

  const stats = [
    { label: 'Published jobs', value: published.length },
    { label: 'Applications', value: all.length },
    { label: 'Shortlisted', value: byState('shortlisted') },
    { label: 'Interviews', value: byState('interview') },
    { label: 'Hired', value: byState('hired') },
  ];

  return (
    <div className="space-y-8">
      <div className="flex items-start justify-between gap-4 flex-wrap">
        <div>
          <h1 className="text-2xl font-bold">{ctx.companyName}</h1>
          <p className="muted text-sm mt-1">
            {ent?.plan === 'free' ? 'Free plan' : ent?.plan} ·{' '}
            {published.length}/{ent?.active_job_slots ?? 3} job slots used
          </p>
        </div>
        <Link href="/dashboard/jobs/new" className="btn btn-primary">
          Post a job
        </Link>
      </div>

      {stale > 0 && (
        <div
          className="card p-4 flex items-start gap-3"
          style={{ borderColor: 'var(--color-warn)' }}
        >
          <span aria-hidden>⚠</span>
          <div className="text-sm leading-relaxed">
            <strong>
              {stale} application{stale === 1 ? ' has' : 's have'} had no
              response for {STALE_DAYS}+ days.
            </strong>{' '}
            <span className="muted">
              Candidates can see this, and it affects your response rate on
              every job you post.
            </span>{' '}
            <Link href="/dashboard/candidates" className="underline">
              Review them
            </Link>
          </div>
        </div>
      )}

      <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">
        {stats.map((s) => (
          <div key={s.label} className="card p-4">
            <div className="text-2xl font-bold">{s.value}</div>
            <div className="text-xs muted mt-1">{s.label}</div>
          </div>
        ))}
      </div>

      <section>
        <div className="flex items-center justify-between mb-3">
          <h2 className="font-bold text-lg">Your jobs</h2>
          <Link href="/dashboard/jobs" className="text-sm underline muted">
            See all
          </Link>
        </div>

        {(jobs ?? []).length === 0 ? (
          <div className="card p-8 text-center">
            <p className="font-semibold mb-1">No jobs yet</p>
            <p className="text-sm muted mb-5">
              Your first job takes about five minutes to post.
            </p>
            <Link href="/dashboard/jobs/new" className="btn btn-primary">
              Post a job
            </Link>
          </div>
        ) : (
          <div className="card divide-y" style={{ borderColor: 'var(--line)' }}>
            {(jobs ?? []).slice(0, 6).map((j) => {
              const jobApps = all.filter((a) => a.job_id === j.id);
              return (
                <Link
                  key={j.id}
                  href={`/dashboard/jobs/${j.id}`}
                  className="flex items-center gap-4 p-4 hover:opacity-80"
                >
                  <div className="min-w-0 flex-1">
                    <div className="font-semibold truncate">{j.title}</div>
                    <div className="text-xs muted mt-0.5">
                      {j.status === 'published'
                        ? `Published ${timeAgo(j.published_at)}`
                        : j.status}{' '}
                      · {j.view_count} views
                    </div>
                  </div>
                  <div className="text-right">
                    <div className="font-bold">{jobApps.length}</div>
                    <div className="text-xs muted">applicants</div>
                  </div>
                </Link>
              );
            })}
          </div>
        )}
      </section>

      {drafts.length > 0 && (
        <p className="text-sm muted">
          {drafts.length} draft{drafts.length === 1 ? '' : 's'} not visible to
          workers yet.
        </p>
      )}

      <section className="card p-5">
        <h2 className="font-bold mb-1">What workers see</h2>
        <p className="text-sm muted leading-relaxed">
          Every application shows its true state —{' '}
          {Object.values(STATE_LABEL).slice(0, 6).join(', ').toLowerCase()} — and
          the time since your last action. You can name your own pipeline
          stages, but you cannot hide movement or let an application go silent.
        </p>
      </section>
    </div>
  );
}
