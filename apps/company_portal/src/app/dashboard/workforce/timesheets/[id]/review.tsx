'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useId, useState, useTransition } from 'react';
import { reopenTimesheet, reviewTimesheet, startTimesheetReview } from '../../actions';
import { ErrorLine, OkLine } from '../../ui';

export function TimesheetDecision({
  id,
  status,
  pendingExceptions,
  canPayLink,
}: {
  id: string;
  status: string;
  pendingExceptions: number;
  canPayLink: boolean;
}) {
  const uid = useId();
  const router = useRouter();
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [earning, setEarning] = useState<string | null>(null);
  const [pending, start] = useTransition();

  return (
    <div className="space-y-3">
      {status === 'submitted' && (
        <button
          type="button"
          className="btn btn-ghost"
          disabled={pending}
          onClick={() =>
            start(async () => {
              setError(null);
              const res = await startTimesheetReview(id);
              if (!res.ok) return setError(res.error);
              router.refresh();
            })
          }
        >
          Mark as under review
        </button>
      )}
      {pendingExceptions > 0 && (
        <p className="text-sm" style={{ color: 'var(--color-warn)' }}>
          {pendingExceptions} attendance exception{pendingExceptions === 1 ? '' : 's'} must be resolved before approval.{' '}
          <Link href="/dashboard/workforce/approvals#exceptions" className="underline">
            Resolve
          </Link>
        </p>
      )}
      <div className="flex gap-2 flex-wrap items-end">
        <div className="flex-1 min-w-[12rem]">
          <label className="label" htmlFor={`${uid}r`}>
            Reason (required to return it; the worker is told)
          </label>
          <input id={`${uid}r`} className="input" maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)} />
        </div>
        <button
          type="button"
          className="btn btn-primary"
          disabled={pending}
          onClick={() =>
            start(async () => {
              setError(null);
              setOk(null);
              const res = await reviewTimesheet(id, true, reason);
              if (!res.ok) return setError(res.error);
              setOk('Approved. Earnings were calculated for the pay team to approve.');
              setEarning(res.earningId);
              router.refresh();
            })
          }
        >
          Approve
        </button>
        <button
          type="button"
          className="btn btn-ghost"
          style={{ color: 'var(--color-danger)' }}
          disabled={pending}
          onClick={() =>
            start(async () => {
              setError(null);
              setOk(null);
              const res = await reviewTimesheet(id, false, reason);
              if (!res.ok) return setError(res.error);
              setOk('Returned to the worker.');
              router.refresh();
            })
          }
        >
          Return to worker
        </button>
      </div>
      <OkLine text={ok} />
      {earning && canPayLink && (
        <Link href={`/dashboard/workforce/pay?earning=${earning}#e-${earning}`} className="text-sm underline">
          Open the earnings
        </Link>
      )}
      <ErrorLine text={error} />
    </div>
  );
}

export function ReopenTimesheet({ id }: { id: string }) {
  const uid = useId();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  if (!open)
    return (
      <button type="button" className="btn btn-ghost" onClick={() => setOpen(true)}>
        Reopen for correction
      </button>
    );
  return (
    <form
      className="surface rounded-lg p-3 flex gap-3 flex-wrap items-end"
      onSubmit={(e) => {
        e.preventDefault();
        setError(null);
        start(async () => {
          const res = await reopenTimesheet(id, reason);
          if (!res.ok) return setError(res.error);
          setOpen(false);
          router.refresh();
        });
      }}
    >
      <div className="flex-1 min-w-[12rem]">
        <label className="label" htmlFor={`${uid}r`}>
          Reason *
        </label>
        <input id={`${uid}r`} className="input" required minLength={5} maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)} />
        <p className="hint">Only while nothing has been paid. Earnings are reversed and draft bills voided; it goes back under review.</p>
      </div>
      <button className="btn btn-primary" disabled={pending}>
        {pending ? 'Reopening…' : 'Reopen'}
      </button>
      <button type="button" className="btn btn-ghost" onClick={() => setOpen(false)}>
        Cancel
      </button>
      <ErrorLine text={error} />
    </form>
  );
}
