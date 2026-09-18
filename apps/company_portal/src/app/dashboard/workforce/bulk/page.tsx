import type { Metadata } from 'next';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { parseJobErrors, wfCan } from '@/lib/workforce';
import LocalTime from '../../local-time';
import BulkProgress from '../bulk-progress';
import { ErrorNote, Notice, PageHeader } from '../ui';

export const metadata: Metadata = { title: 'Bulk jobs · Workforce · Omelo' };

export default async function BulkJobsPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('workforce_jobs')
    .select('id, kind, status, total, processed, succeeded, failed, errors, created_at, finished_at')
    .eq('company_id', ctx.companyId)
    .order('created_at', { ascending: false })
    .limit(50);
  const jobs = data ?? [];
  const canCancel = wfCan(ctx, 'manage_workforce');

  return (
    <div className="space-y-5">
      <PageHeader
        title="Bulk jobs"
        subtitle="Offers, shift assignments and shift generation for many workers run in the background, a few hundred items a minute. Your permission is checked again for every item; failures are listed, never skipped silently. At most 5 run at once."
      />
      {error ? (
        <ErrorNote label="bulk jobs" message={error.message} />
      ) : jobs.length === 0 ? (
        <Notice title="No bulk jobs yet">Offer work to several workers from a requirement, or assign several shifts from the schedule.</Notice>
      ) : (
        <ul className="space-y-3">
          {jobs.map((j) => (
            <li key={j.id} className="space-y-1">
              <p className="text-xs muted">
                Started <LocalTime iso={j.created_at} />
                {j.finished_at ? (
                  <>
                    {' '}
                    · finished <LocalTime iso={j.finished_at} />
                  </>
                ) : null}
              </p>
              <BulkProgress
                canCancel={canCancel}
                initial={{
                  id: j.id,
                  kind: j.kind,
                  status: j.status,
                  total: j.total,
                  processed: j.processed,
                  succeeded: j.succeeded,
                  failed: j.failed,
                  errors: parseJobErrors(j.errors),
                  createdAt: j.created_at,
                  finishedAt: j.finished_at,
                }}
              />
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
