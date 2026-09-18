'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useState, useTransition } from 'react';
import { createClient } from '@/lib/supabase/client';
import { JOB_KIND_LABEL, jobTone, parseJobErrors, type JobError } from '@/lib/workforce';
import { cancelWorkforceJob } from './actions';
import { ErrorLine, ProgressBar, TonePill } from './ui';

export type JobState = {
  id: string;
  kind: string;
  status: string;
  total: number;
  processed: number;
  succeeded: number;
  failed: number;
  errors: JobError[];
  createdAt: string | null;
  finishedAt: string | null;
};

const LIVE = new Set(['queued', 'running']);

/**
 * A bulk operation's progress. The database processes queued jobs every
 * minute; this polls workforce_jobs (readable to the company's members) until
 * the job finishes, then refreshes the page's server data once.
 */
export default function BulkProgress({
  initial,
  canCancel,
  labelFor,
}: {
  initial: JobState;
  canCancel: boolean;
  /** Describe item N of the job (for the error list). */
  labelFor?: Record<number, string>;
}) {
  const router = useRouter();
  const [job, setJob] = useState<JobState>(initial);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const live = LIVE.has(job.status);

  useEffect(() => {
    if (!live) return;
    const supabase = createClient();
    let stopped = false;
    const tick = async () => {
      const { data } = await supabase
        .from('workforce_jobs')
        .select('id, kind, status, total, processed, succeeded, failed, errors, created_at, finished_at')
        .eq('id', job.id)
        .maybeSingle();
      if (stopped || !data) return;
      setJob({
        id: data.id,
        kind: data.kind,
        status: data.status,
        total: data.total,
        processed: data.processed,
        succeeded: data.succeeded,
        failed: data.failed,
        errors: parseJobErrors(data.errors),
        createdAt: data.created_at,
        finishedAt: data.finished_at,
      });
      if (!LIVE.has(data.status)) router.refresh();
    };
    const t = setInterval(tick, 4000);
    return () => {
      stopped = true;
      clearInterval(t);
    };
  }, [live, job.id, router]);

  return (
    <div className="surface rounded-lg p-3 space-y-2">
      <div className="flex items-center gap-2 flex-wrap">
        <p className="font-semibold text-sm flex-1 min-w-[10rem]">{JOB_KIND_LABEL[job.kind] ?? job.kind}</p>
        <TonePill tone={jobTone(job.status)} />
      </div>
      <ProgressBar value={job.processed} max={job.total} label="Bulk operation progress" />
      <p className="text-xs muted tabular-nums">
        {job.processed.toLocaleString('en-IN')} of {job.total.toLocaleString('en-IN')} processed ·{' '}
        {job.succeeded.toLocaleString('en-IN')} done · {job.failed.toLocaleString('en-IN')} failed
        {job.status === 'queued' ? ' · starts within a minute' : ''}
      </p>
      {job.errors.length > 0 && (
        <details className="text-sm">
          <summary className="cursor-pointer font-semibold" style={{ color: 'var(--color-danger)' }}>
            {job.errors.length === 1 ? '1 error' : `${job.errors.length} errors`}
            {job.failed > job.errors.length ? ` (first ${job.errors.length} shown)` : ''}
          </summary>
          <ul className="mt-2 space-y-1 max-h-60 overflow-y-auto">
            {job.errors.map((e, i) => (
              <li key={i} className="break-words text-xs">
                <span className="font-semibold">
                  {e.item != null ? (labelFor?.[e.item] ?? `Item ${e.item + 1}`) : 'Item'}:
                </span>{' '}
                {e.error}
              </li>
            ))}
          </ul>
        </details>
      )}
      <div className="flex gap-2 flex-wrap items-center">
        {live && canCancel && (
          <button
            type="button"
            className="btn btn-ghost"
            style={{ height: 34 }}
            disabled={pending}
            onClick={() =>
              start(async () => {
                setError(null);
                const res = await cancelWorkforceJob(job.id);
                if (!res.ok) return setError(res.error);
                setJob((j) => ({ ...j, status: 'cancelled' }));
                router.refresh();
              })
            }
          >
            Cancel the rest
          </button>
        )}
        <Link href="/dashboard/workforce/bulk" className="text-xs underline muted">
          All bulk jobs
        </Link>
        <ErrorLine text={error} />
      </div>
    </div>
  );
}
