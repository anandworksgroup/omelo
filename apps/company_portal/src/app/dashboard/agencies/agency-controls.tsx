'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useId, useState, useTransition } from 'react';
import { connectJob, endLink, respondToLink } from './actions';

function ErrorLine({ message }: { message: string | null }) {
  if (!message) return null;
  return (
    <p className="text-sm basis-full break-words" role="alert" style={{ color: 'var(--color-danger)' }}>
      {message}
    </p>
  );
}

/* ------------------------------------------------------------------ */
/* Confirm / decline a pending link                                     */
/* ------------------------------------------------------------------ */

export function RespondToLink({ clientId, agencyName }: { clientId: string; agencyName: string }) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [declining, setDeclining] = useState(false);

  function answer(accept: boolean) {
    setError(null);
    start(async () => {
      const res = await respondToLink(clientId, accept);
      if (!res.ok) return setError(res.error);
      setDeclining(false);
      router.refresh();
    });
  }

  if (declining) {
    return (
      <div className="surface rounded-lg p-3 space-y-3 w-full">
        <p className="text-sm break-words">
          Decline {agencyName}? They will not be able to connect job orders to your jobs. They can ask again later.
        </p>
        <div className="flex gap-2 flex-wrap">
          <button
            type="button"
            className="btn btn-primary w-full sm:w-auto"
            style={{ background: 'var(--color-danger)' }}
            onClick={() => answer(false)}
            disabled={pending}
          >
            {pending ? 'Saving…' : 'Decline'}
          </button>
          <button
            type="button"
            className="btn btn-ghost w-full sm:w-auto"
            onClick={() => setDeclining(false)}
            disabled={pending}
          >
            Cancel
          </button>
        </div>
        <ErrorLine message={error} />
      </div>
    );
  }

  return (
    <div className="flex gap-2 flex-wrap w-full">
      <button
        type="button"
        className="btn btn-primary w-full sm:w-auto"
        onClick={() => answer(true)}
        disabled={pending}
      >
        {pending ? 'Saving…' : 'Confirm'}
      </button>
      <button
        type="button"
        className="btn btn-ghost w-full sm:w-auto"
        onClick={() => setDeclining(true)}
        disabled={pending}
      >
        Decline
      </button>
      <ErrorLine message={error} />
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* End a confirmed relationship                                          */
/* ------------------------------------------------------------------ */

export function EndRelationship({
  clientId,
  agencyName,
  hint,
}: {
  clientId: string;
  agencyName: string;
  /** Shown when the viewer's role probably cannot do this; the database decides. */
  hint: string | null;
}) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [confirming, setConfirming] = useState(false);

  function end() {
    setError(null);
    start(async () => {
      const res = await endLink(clientId);
      if (!res.ok) return setError(res.error);
      setConfirming(false);
      router.refresh();
    });
  }

  if (!confirming) {
    return (
      <div className="space-y-1 w-full sm:w-auto">
        <button type="button" className="btn btn-ghost w-full sm:w-auto" onClick={() => setConfirming(true)}>
          End relationship
        </button>
        {hint && <p className="hint !mt-0">{hint}</p>}
      </div>
    );
  }

  return (
    <div className="surface rounded-lg p-3 space-y-3 w-full">
      <p className="text-sm break-words">
        End the relationship with {agencyName}? Their job orders are disconnected from your jobs, so new
        submissions no longer reach your pipeline. Candidates already in your pipeline stay there.
      </p>
      <div className="flex gap-2 flex-wrap">
        <button
          type="button"
          className="btn btn-primary w-full sm:w-auto"
          style={{ background: 'var(--color-danger)' }}
          onClick={end}
          disabled={pending}
        >
          {pending ? 'Ending…' : 'End relationship'}
        </button>
        <button
          type="button"
          className="btn btn-ghost w-full sm:w-auto"
          onClick={() => setConfirming(false)}
          disabled={pending}
        >
          Cancel
        </button>
      </div>
      <ErrorLine message={error} />
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Connect a job order to one of the company's jobs                      */
/* ------------------------------------------------------------------ */

export type JobChoice = { id: string; title: string; status: string };

const STATUS_NOTE: Record<string, string> = {
  draft: 'draft',
  pending_review: 'in review',
  paused: 'paused',
};

export function ConnectJob({
  jobOrderId,
  current,
  jobs,
  hint,
}: {
  jobOrderId: string;
  current: { id: string; title: string | null } | null;
  jobs: JobChoice[];
  hint: string | null;
}) {
  const uid = useId();
  const router = useRouter();
  const [pending, start] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  const choices = jobs.filter((j) => j.id !== current?.id);
  const [jobId, setJobId] = useState(choices[0]?.id ?? '');

  function save() {
    setError(null);
    if (!jobId) return setError('Choose one of your jobs.');
    start(async () => {
      const res = await connectJob(jobOrderId, jobId);
      if (!res.ok) return setError(res.error);
      setEditing(false);
      router.refresh();
    });
  }

  if (current && !editing) {
    return (
      <div className="flex items-center gap-2 flex-wrap text-sm">
        <span className="muted">Connected to</span>
        <Link href={`/dashboard/jobs/${current.id}`} className="font-semibold underline break-words min-w-0">
          {current.title ?? 'your job'}
        </Link>
        {choices.length > 0 && (
          <button type="button" className="underline muted text-sm" onClick={() => setEditing(true)}>
            Change
          </button>
        )}
      </div>
    );
  }

  if (choices.length === 0) {
    return (
      <p className="text-sm muted">
        {current ? 'No other job to connect.' : 'You have no open jobs to connect.'}{' '}
        <Link href="/dashboard/jobs" className="underline">
          Your jobs
        </Link>
      </p>
    );
  }

  return (
    <div className="space-y-2">
      <label className="label" htmlFor={`${uid}job`}>
        {current ? 'Connect a different job' : 'Connect a job'}
      </label>
      <div className="flex gap-2 flex-wrap items-start">
        <select
          id={`${uid}job`}
          className="input flex-1 min-w-0 basis-full sm:basis-auto"
          value={jobId}
          onChange={(e) => setJobId(e.target.value)}
          disabled={pending}
        >
          {choices.map((j) => (
            <option key={j.id} value={j.id}>
              {j.title}
              {STATUS_NOTE[j.status] ? ` (${STATUS_NOTE[j.status]})` : ''}
            </option>
          ))}
        </select>
        <button type="button" className="btn btn-primary w-full sm:w-auto" onClick={save} disabled={pending}>
          {pending ? 'Connecting…' : 'Connect'}
        </button>
        {current && (
          <button
            type="button"
            className="btn btn-ghost w-full sm:w-auto"
            onClick={() => {
              setEditing(false);
              setError(null);
            }}
            disabled={pending}
          >
            Cancel
          </button>
        )}
      </div>
      <p className="hint !mt-0">
        Candidates this agency submits for this order will land in that job&apos;s pipeline, with exactly the
        information they agreed to share. Without a connected job the agency tracks outcomes itself.
      </p>
      {hint && <p className="hint !mt-0">{hint}</p>}
      <ErrorLine message={error} />
    </div>
  );
}
