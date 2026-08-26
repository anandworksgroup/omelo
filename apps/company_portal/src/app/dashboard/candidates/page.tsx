import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { STATE_LABEL, timeAgo } from '@/lib/format';

export default async function CandidatesPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  // `professions` must be disambiguated: work_identities reaches it both
  // directly via profession_id and many-to-many via person_professions, so an
  // unqualified embed returns HTTP 300 and no rows.
  const { data: apps, error } = await supabase
    .from('applications')
    .select(
      `id, state, applied_at, last_activity_at, first_viewed_at, match_score,
       jobs ( id, title ),
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

  const rows = apps ?? [];
  const STALE_DAYS = 5;
  const isStale = (a: (typeof rows)[number]) => {
    if (['hired', 'rejected', 'withdrawn', 'expired', 'declined_by_candidate'].includes(a.state))
      return false;
    return (Date.now() - new Date(a.last_activity_at).getTime()) / 86_400_000 >= STALE_DAYS;
  };

  return (
    <div className="space-y-6 max-w-4xl">
      <div>
        <h1 className="text-2xl font-bold">Candidates</h1>
        <p className="muted text-sm mt-1">
          Everyone who applied to any of your jobs.
        </p>
      </div>

      {rows.length === 0 ? (
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
        <div className="card divide-y" style={{ borderColor: 'var(--line)' }}>
          {rows.map((a) => {
            const wi = a.work_identities as unknown as {
              label: string;
              headline: string | null;
              professions: { name: string } | null;
            } | null;
            const job = a.jobs as unknown as { id: string; title: string } | null;

            return (
              <div key={a.id} className="p-4 flex items-start gap-4 flex-wrap">
                <div className="flex-1 min-w-0">
                  <div className="font-semibold text-sm">
                    {wi?.professions?.name ?? wi?.label ?? 'Candidate'}
                  </div>
                  <div className="text-xs muted mt-0.5">
                    Applied to{' '}
                    {job ? (
                      <Link href={`/dashboard/jobs/${job.id}`} className="underline">
                        {job.title}
                      </Link>
                    ) : (
                      'a job'
                    )}{' '}
                    · {timeAgo(a.applied_at)}
                  </div>
                  {isStale(a) && (
                    <div className="text-xs mt-1.5" style={{ color: 'var(--color-warn)' }}>
                      No response for {Math.floor((Date.now() - new Date(a.last_activity_at).getTime()) / 86_400_000)} days
                      — the candidate can see this
                    </div>
                  )}
                </div>

                <div className="flex items-center gap-3">
                  {a.match_score != null && <span className="pill">{a.match_score}%</span>}
                  <span className="pill">{STATE_LABEL[a.state] ?? a.state}</span>
                </div>
              </div>
            );
          })}
        </div>
      )}

      <div className="card p-5">
        <h2 className="font-bold mb-1">Not built yet</h2>
        <p className="text-sm muted leading-relaxed">
          Opening a candidate, moving pipeline stages, messaging, and the
          rejection flow with a required reason are specified in architecture/A2
          §7 but not implemented. Opening a candidate must go through{' '}
          <code className="text-xs">omelo_mark_application_viewed()</code> so the
          worker sees an honest <em>viewed</em> state.
        </p>
      </div>
    </div>
  );
}
