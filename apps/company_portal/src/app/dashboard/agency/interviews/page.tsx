import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { ErrorNote, Notice, PageHeader } from '../ui';
import { BASE, loadSubmissions } from '../submissions/lib';
import { SubmissionCard, WorkTabs } from '../submissions/row';

export const metadata: Metadata = { title: 'Interviews · Omelo' };

export default async function InterviewsPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const { rows, error } = await loadSubmissions(supabase, ctx.companyId);

  const interviewing = rows
    .filter((r) => r.status === 'interview' || r.nextInterview)
    .sort((a, b) => {
      // Scheduled ones first, soonest first; the rest by most recent change.
      if (a.nextInterview && b.nextInterview) return a.nextInterview.localeCompare(b.nextInterview);
      if (a.nextInterview) return -1;
      if (b.nextInterview) return 1;
      return (b.updatedAt ?? '').localeCompare(a.updatedAt ?? '');
    });
  const scheduled = interviewing.filter((r) => r.nextInterview);
  const unscheduled = interviewing.filter((r) => !r.nextInterview);

  return (
    <div className="space-y-5 max-w-5xl">
      <PageHeader title="Interviews" subtitle="Candidates you submitted who are interviewing with a client." />
      <WorkTabs active="interviews" />

      <div className="card p-4 text-sm muted leading-relaxed space-y-1">
        <p>
          <span className="font-semibold" style={{ color: 'var(--fg)' }}>
            Clients on Omelo
          </span>{' '}
          schedule interviews with their own team; the candidate sees them in their app and the time shows here.
        </p>
        <p>
          <span className="font-semibold" style={{ color: 'var(--fg)' }}>
            Off-platform clients
          </span>{' '}
          arrange interviews outside Omelo: open the submission and record the client’s outcome as it happens.
        </p>
      </div>

      {error ? (
        <ErrorNote label="interviews" message={error} />
      ) : interviewing.length === 0 ? (
        <Notice
          title="No interviews right now"
          action={
            <Link href={`${BASE}/submissions`} className="btn btn-ghost">
              See submissions
            </Link>
          }
        >
          When a client moves one of your submissions to interview, it appears here.
        </Notice>
      ) : (
        <>
          {scheduled.length > 0 && (
            <section className="space-y-3">
              <h2 className="font-bold">Coming up ({scheduled.length})</h2>
              <ul className="grid gap-3">
                {scheduled.map((r) => (
                  <SubmissionCard key={r.id} row={r} />
                ))}
              </ul>
            </section>
          )}
          {unscheduled.length > 0 && (
            <section className="space-y-3">
              <h2 className="font-bold">Interviewing, no time on Omelo ({unscheduled.length})</h2>
              <p className="text-sm muted">
                Either the client has not booked the next interview yet, or they are off-platform and arrange it
                themselves.
              </p>
              <ul className="grid gap-3">
                {unscheduled.map((r) => (
                  <SubmissionCard key={r.id} row={r} />
                ))}
              </ul>
            </section>
          )}
        </>
      )}
    </div>
  );
}
