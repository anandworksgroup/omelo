import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { STATE_LABEL, daysSince, timeAgo } from '@/lib/format';

export default async function DashboardPage() {
  const ctx = (await getCompanyContext())!;
  // R10: one Overview for every organization. An agency used to be sent to its
  // own dashboard from here, which was the clearest sign that Omelo had two
  // products. Client work has its own section in the menu instead.
  const supabase = await createClient();

  const [{ data: jobs }, { data: apps }, { data: ent }] = await Promise.all([
    supabase
      .from('jobs')
      .select('id, title, status, applicant_count, view_count, published_at')
      .eq('company_id', ctx.companyId)
      .order('created_at', { ascending: false }),
    supabase
      .from('applications')
      .select('id, state, applied_at, last_activity_at, first_viewed_at, job_id')
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
    return daysSince(a.last_activity_at) >= STALE_DAYS;
  }).length;

  // Each number is a question someone is about to ask, so each one goes to
  // the screen that answers it. `lead` marks the two that are about to need
  // doing — they get the brand wash so the eye lands there first.
  const stats = [
    {
      // "New" means nobody on the team has opened it yet, whatever its state.
      label: 'New',
      value: all.filter((a) => !a.first_viewed_at).length,
      href: '/dashboard/candidates',
      lead: true,
    },
    { label: 'Interviews', value: byState('interview'), href: '/dashboard/interviews', lead: true },
    { label: 'Published jobs', value: published.length, href: '/dashboard/jobs' },
    { label: 'Applications', value: all.length, href: '/dashboard/candidates' },
    { label: 'Shortlisted', value: byState('shortlisted'), href: '/dashboard/candidates' },
    { label: 'Hired', value: byState('hired'), href: '/dashboard/candidates' },
  ];

  return (
    <div className="space-y-8">
      <div className="flex items-start justify-between gap-4 flex-wrap">
        <div className="min-w-0">
          <h1 className="break-words">{ctx.companyName}</h1>
          <p className="muted text-sm mt-1">
            {ent?.plan === 'free' ? 'Free plan' : ent?.plan} ·{' '}
            {published.length}/{ent?.active_job_slots ?? 3} job slots used
          </p>
        </div>
        <Link href="/dashboard/jobs/new" className="btn btn-primary w-full sm:w-auto">
          Post a job
        </Link>
      </div>

      {stale > 0 && (
        <div className="card p-4 flex items-start gap-3" style={{ borderColor: 'var(--color-warn)' }}>
          <svg
            width="20"
            height="20"
            viewBox="0 0 20 20"
            aria-hidden
            className="shrink-0 mt-0.5"
            fill="none"
            stroke="var(--color-warn)"
            strokeWidth="1.7"
            strokeLinecap="round"
          >
            <path d="M10 2.5 18.5 17h-17L10 2.5Z" strokeLinejoin="round" />
            <path d="M10 8v4M10 14.5v.01" />
          </svg>
          <div className="flex-1 text-sm leading-relaxed">
            <strong>
              {stale} application{stale === 1 ? ' has' : 's have'} had no response for{' '}
              {STALE_DAYS}+ days.
            </strong>{' '}
            <span className="muted">
              Candidates can see this, and it affects your response rate on every job you
              post.
            </span>
          </div>
          <Link href="/dashboard/candidates" className="btn btn-ghost btn-sm shrink-0">
            Review
          </Link>
        </div>
      )}

      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
        {stats.map((s) => {
          const highlight = s.lead && s.value > 0;
          return (
            <Link
              key={s.label}
              href={s.href}
              className="card card-interactive p-4"
              style={
                highlight
                  ? { background: 'var(--brand-wash)', borderColor: 'transparent' }
                  : undefined
              }
            >
              <div
                className="text-2xl font-bold tnum"
                style={highlight ? { color: 'var(--brand-ink)' } : undefined}
              >
                {s.value}
              </div>
              <div className={`text-xs mt-1 ${highlight ? '' : 'muted'}`}>{s.label}</div>
            </Link>
          );
        })}
      </div>

      <section>
        <div className="flex items-center justify-between mb-3">
          <h2>Your jobs</h2>
          <Link href="/dashboard/jobs" className="link text-sm">
            See all
          </Link>
        </div>

        {(jobs ?? []).length === 0 ? (
          <div className="empty">
            <p className="empty-title">No jobs yet</p>
            <p className="empty-body">
              Your first job takes about five minutes to post, and workers within range see
              it as soon as it is live.
            </p>
            <Link href="/dashboard/jobs/new" className="btn btn-primary mt-1">
              Post a job
            </Link>
          </div>
        ) : (
          <div className="card divide-y hairline overflow-hidden">
            {(jobs ?? []).slice(0, 6).map((j) => {
              const jobApps = all.filter((a) => a.job_id === j.id);
              const unseen = jobApps.filter((a) => !a.first_viewed_at).length;
              return (
                <Link
                  key={j.id}
                  href={`/dashboard/jobs/${j.id}`}
                  className="flex items-center gap-4 p-4 row-link"
                >
                  <div className="min-w-0 flex-1">
                    <div className="font-semibold truncate">{j.title}</div>
                    <div className="text-xs muted mt-1 flex items-center gap-2 flex-wrap">
                      {j.status === 'published' ? (
                        <span className="pill pill-success">
                          <span className="dot" /> Live
                        </span>
                      ) : (
                        <span className="pill">
                          {j.status === 'draft' ? 'Draft' : j.status.replace(/_/g, ' ')}
                        </span>
                      )}
                      <span>
                        {j.status === 'published'
                          ? `Published ${timeAgo(j.published_at)}`
                          : 'Not visible to workers'}{' '}
                        · {j.view_count} views
                      </span>
                    </div>
                  </div>
                  {unseen > 0 && <span className="pill pill-brand">{unseen} new</span>}
                  <div className="text-right">
                    <div className="font-bold tnum">{jobApps.length}</div>
                    <div className="text-xs muted">
                      applicant{jobApps.length === 1 ? '' : 's'}
                    </div>
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

      <section className="panel p-5">
        <h3 className="mb-1">What workers see</h3>
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
