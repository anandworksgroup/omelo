'use client';

import { useRouter } from 'next/navigation';
import { useId, useState, useTransition } from 'react';
import { reviewLeave } from '../actions';
import { ErrorLine } from '../ui';

export default function LeaveReview({ leaveId }: { leaveId: string }) {
  const uid = useId();
  const router = useRouter();
  const [note, setNote] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const [pending, start] = useTransition();
  if (done) return <p className="text-sm" style={{ color: 'var(--color-verified)' }}>{done}</p>;
  const act = (approve: boolean) =>
    start(async () => {
      setError(null);
      const res = await reviewLeave(leaveId, approve, note);
      if (!res.ok) return setError(res.error);
      setDone(approve ? 'Approved. Their shifts in this period are marked on leave.' : 'Not approved.');
      router.refresh();
    });
  return (
    <div className="flex gap-2 flex-wrap items-end">
      <div className="flex-1 min-w-[12rem]">
        <label className="label" htmlFor={`${uid}n`}>
          Note (the worker is told)
        </label>
        <input id={`${uid}n`} className="input" maxLength={500} value={note} onChange={(e) => setNote(e.target.value)} />
      </div>
      <button type="button" className="btn btn-primary" disabled={pending} onClick={() => act(true)}>
        Approve
      </button>
      <button type="button" className="btn btn-ghost" style={{ color: 'var(--color-danger)' }} disabled={pending} onClick={() => act(false)}>
        Reject
      </button>
      <ErrorLine text={error} />
    </div>
  );
}
