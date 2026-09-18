import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { STATE_LABEL, timeAgo } from '@/lib/format';
import {
  CLOSED_STATES,
  PIPELINE_TABS,
  TONE_COLOR,
  requestNow,
  stateTone,
  type ApplicationState,
} from '@/lib/hiring';
import { RescoreButton } from './forms';
import { SubmissionList, ViewTabs } from './agency-views';

type Search = { tab?: string; job?: string; view?: string };

export default async function CandidatesPage({
  searchParams,
}: {
  searchParams: Promise<Search>;
}) {
  const { tab: tabParam, job: jobFilter, view: viewParam } = await searchParams;
  const view = viewParam === 'agency' ? 'agency' : 'all';
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  // `professions` must be disambiguated: work_identities reaches it both
  // directly via profession_id and many-to-many via person_professions, so an
  // unqualified embed returns HTTP 300 and no rows. `persons` likewise: an
  // application points at persons twice (person_id and rejected_by).
  const { data: apps, error } = await supabase
    .from('applications')
    .select(
      `id, job_id, state, applied_at, last_activity_at, first_viewed_at, match_score,
       identity_snapshot, applied_via,
       jobs ( id, title ),
       persons!applications_person_id_fkey ( display_name ),
       work_identities (
         label, headline,
         professions!work_identities_profession_id_fkey ( name )
       )`
    )
    .eq('company_id', ctx.companyId)
    .order('applied_at', { ascending: false });

  // Never swallow the error — an empty list and a broken query look identical
  // to a user, and that is how a silent regression ships.
  if (error) {
    return (
      <div className="max-w-3xl space-y-4">
        <h1 className="text-2xl font-bold">Candidates</h1>
        <div className="card p-5" style={{ borderColor: 'var(--color-danger)' }}>
          <p className="font-semibold mb-1" style={{ color: 'var(--color-danger)' }}>
            Could not load candidates
          </p>
          <p className="text-sm muted">{error.message}</p>
        </div>
      </div>
    );
  }

  const all = apps ?? [];

  // Jobs that have applicants, for the filter and per-job re-scoring.
  const jobMap = new Map<string, { id: string; title: string; count: number }>();
  for (const a of all) {
    const j = a.jobs as unknown as { id: string; title: string } | null;
    if (!j) continue;
    const entry = jobMap.get(j.id) ?? { ...j, count: 0 };
    entry.count++;
    jobMap.set(j.id, entry);
  }
  const jobs = [...jobMap.values()].sort((a, b) => a.title.localeCompare(b.title));
  const activeJob = jobFilter ? jobMap.get(jobFilter) ?? null : null;

  const scoped = activeJob ? all.filter((a) => a.job_id === activeJob.id) : all;
  const inTab = (key: string, state: ApplicationState) => {
    const t = PIPELINE_TABS.find((x) => x.key === key);
    return !t || t.states === null || (t.states as readonly string[]).includes(state);
  };
  const tab = PIPELINE_TABS.some((t) => t.key === tabParam) ? tabParam! : 'all';

  const rows = scoped
    .filter((a) => inTab(tab, a.state))
    .sort((a, b) => {
      const sa = a.match_score ?? -1;
      const sb = b.match_score ?? -1;
      if (sb !== sa) return sb - sa;
      return new Date(b.applied_at).getTime() - new Date(a.applied_at).getTime();
    });

  const href = (t: string, job: string | null) => {
    const p = new URLSearchParams();
    if (view === 'agency') p.set('view', 'agency');
    if (t !== 'all') p.set('tab', t);
    if (job) p.set('job', job);
    const s = p.toString();
    return `/dashboard/candidates${s ? `?${s}` : ''}`;
  };

  // Switching view keeps the job filter but resets the stage tab.
  const viewHref = (v: 'all' | 'agency', job: string | null) => {
    const p = new URLSearchParams();
    if (v === 'agency') p.set('view', 'agency');
    if (job) p.set('job', job);
    const s = p.toString();
    return `/dashboard/candidates${s ? `?${s}` : ''}`;
  };

  const STALE_DAYS = 5;
  const staleDays = (a: (typeof all)[number]) => {
    if ((CLOSED_STATES as string[]).includes(a.state)) return 0;
    const d = Math.floor((requestNow() - new Date(a.last_activity_at).getTime()) / 86_400_000);
    return d >= STALE_DAYS ? d : 0;
  };

  return (
    <div className="space-y-6 max-w-4xl">
      <div className="flex items-start gap-3 flex-wrap">
        <div className="flex-1 min-w-0">
          <h1 className="text-xl sm:text-2xl font-bold">Candidates</h1>
          <p className="muted text-sm mt-1">
            {activeJob ? (
              <>
                Applicants for <strong>{activeJob.title}</strong> ·{' '}
                <Link href={href(tab, null)} className="underline">
                  all jobs
                </Link>
              </>
            ) : view === 'agency' ? (
              'Candidates recruiters put forward for your jobs, with the candidate’s consent.'
            ) : (
              'Everyone who applied to any of your jobs, best match first.'
            )}
          </p>
        </div>
        {activeJob && <RescoreButton jobId={activeJob.id} label="Re-score applicants" />}
      </div>

      <ViewTabs
        view={view}
        allHref={viewHref('all', activeJob?.id ?? null)}
        agencyHref={viewHref('agency', activeJob?.id ?? null)}
        agencyCount={all.filter((a) => a.applied_via === 'agency').length}
      />

      {view === 'agency' ? (
        <SubmissionList jobId={activeJob?.id ?? null} jobTitle={activeJob?.title ?? null} />
      ) : all.length === 0 ? (
        <div className="card p-10 text-center">
          <p className="font-semibold mb-1">No applications yet</p>
          <p className="text-sm muted mb-5">
            Once a job is published, workers within range see it immediately.
          </p>
          <Link href="/dashboard/jobs" className="btn btn-primary">
            View your jobs
          </Link>
        </div>
      ) : (
        <>
          {/* State tabs — horizontal scroll on phone rather than page overflow */}
          <nav
            aria-label="Filter by stage"
            className="flex gap-1.5 overflow-x-auto pb-1 -mx-4 px-4 sm:mx-0 sm:px-0 sm:flex-wrap"
          >
            {PIPELINE_TABS.map((t) => {
              const count = scoped.filter((a) => inTab(t.key, a.state)).length;
              const active = t.key === tab;
              return (
                <Link
                  key={t.key}
                  href={href(t.key, activeJob?.id ?? null)}
                  aria-current={active ? 'page' : undefined}
                  className="px-3 py-1.5 rounded-lg text-sm font-medium whitespace-nowrap border hairline"
                  style={
                    active
                      ? { background: 'var(--color-brand-600)', color: '#fff', borderColor: 'transparent' }
                      : { background: 'var(--surface)' }
                  }
                >
                  {t.label} <span className={active ? 'opacity-80' : 'muted'}>{count}</span>
                </Link>
              );
            })}
          </nav>

          {rows.length === 0 ? (
            <div className="card p-8 text-center text-sm muted">
              No candidates in this stage.
            </div>
          ) : (
            <div className="card divide-y" style={{ borderColor: 'var(--line)' }}>
              {rows.map((a) => {
                const wi = a.work_identities as unknown as {
                  label: string;
                  headline: string | null;
                  professions: { name: string } | null;
                } | null;
                const job = a.jobs as unknown as { id: string; title: string } | null;
                const person = a.persons as unknown as { display_name: string | null } | null;
                const snap = a.identity_snapshot as {
                  person?: { display_name?: string };
                  work_identity?: { label?: string };
                } | null;
                const name = person?.display_name ?? snap?.person?.display_name ?? 'Candidate';
                // The work identity they applied with — an employer never sees the others.
                const identityLabel = wi?.label ?? snap?.work_identity?.label ?? null;
                const unread = !a.first_viewed_at;
                const stale = staleDays(a);

                return (
                  <Link
                    key={a.id}
                    href={`/dashboard/candidates/${a.id}`}
                    className="p-4 flex items-start gap-3 sm:gap-4 hover:bg-[var(--surface)]"
                  >
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="font-semibold text-sm break-words">{name}</span>
                        {a.applied_via === 'agency' && (
                          <span className="pill" title="Submitted by a recruiter with the candidate's consent">
                            Via agency
                          </span>
                        )}
                        {unread && (
                          <span
                            className="pill"
                            style={{ color: 'var(--color-warn)', borderColor: 'var(--color-warn)' }}
                          >
                            Unread
                          </span>
                        )}
                      </div>
                      <div className="text-xs muted mt-0.5 break-words">
                        {identityLabel ? (
                          <>
                            as <span className="font-medium" style={{ color: 'var(--fg)' }}>{identityLabel}</span>
                            {wi?.professions?.name && wi.professions.name !== identityLabel
                              ? ` · ${wi.professions.name}`
                              : ''}
                          </>
                        ) : (
                          wi?.professions?.name ?? '—'
                        )}
                      </div>
                      <div className="text-xs muted mt-0.5 break-words">
                        {job?.title ?? 'A job'} · applied {timeAgo(a.applied_at)}
                      </div>
                      {stale > 0 && (
                        <div className="text-xs mt-1.5" style={{ color: 'var(--color-warn)' }}>
                          No response for {stale} days — the candidate can see this
                        </div>
                      )}
                    </div>

                    <div className="flex flex-col items-end gap-1.5 shrink-0">
                      <span
                        className="pill"
                        title="Match score"
                        style={a.match_score != null ? { color: 'var(--fg)' } : undefined}
                      >
                        {a.match_score != null ? `${a.match_score}%` : '—'}
                      </span>
                      <span className="pill" style={{ color: TONE_COLOR[stateTone(a.state)] }}>
                        {STATE_LABEL[a.state] ?? a.state}
                      </span>
                    </div>
                  </Link>
                );
              })}
            </div>
          )}

          {/* Per-job filter and re-scoring */}
          <section className="card p-5">
            <h2 className="font-bold mb-1">By job</h2>
            <p className="text-sm muted mb-4 leading-relaxed">
              Match scores are stored when a worker applies. Re-score after
              candidates update their profiles or you change a job&apos;s
              requirements.
            </p>
            <div className="divide-y" style={{ borderColor: 'var(--line)' }}>
              {jobs.map((j) => (
                <div key={j.id} className="py-3 flex items-center gap-3 flex-wrap">
                  <Link
                    href={href(tab, j.id)}
                    className="flex-1 min-w-0 text-sm font-medium underline break-words"
                  >
                    {j.title}
                  </Link>
                  <span className="text-xs muted">
                    {j.count} applicant{j.count === 1 ? '' : 's'}
                  </span>
                  <RescoreButton jobId={j.id} />
                </div>
              ))}
            </div>
          </section>
        </>
      )}
    </div>
  );
}
