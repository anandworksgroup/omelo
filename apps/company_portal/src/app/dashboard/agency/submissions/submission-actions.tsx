'use client';

import { useRouter } from 'next/navigation';
import { useId, useState, useTransition } from 'react';
import { OUTCOMES } from '@/lib/agency';
import Dialog from '../../talent/dialog';
import { recordOutcome, withdrawSubmission } from '../actions';
import { OUTCOME_LABEL } from './lib';

function ErrorLine({ message }: { message: string | null }) {
  if (!message) return null;
  return (
    <p className="text-sm break-words" role="alert" style={{ color: 'var(--color-danger)' }}>
      {message}
    </p>
  );
}

export function WithdrawSubmission({ submissionId, candidate }: { submissionId: string; candidate: string }) {
  const uid = useId();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  return (
    <>
      <button type="button" className="btn btn-ghost w-full sm:w-auto" onClick={() => setOpen(true)}>
        Withdraw submission
      </button>
      <Dialog
        open={open}
        onClose={() => !pending && setOpen(false)}
        title={`Withdraw ${candidate}?`}
        description="The client will no longer consider them through your agency for this job order. This cannot be undone."
      >
        <form
          className="space-y-3"
          onSubmit={(e) => {
            e.preventDefault();
            setError(null);
            start(async () => {
              const res = await withdrawSubmission(submissionId, reason);
              if (!res.ok) return setError(res.error);
              setOpen(false);
              router.refresh();
            });
          }}
        >
          <div>
            <label className="label" htmlFor={`${uid}reason`}>
              Reason (optional)
            </label>
            <textarea
              id={`${uid}reason`}
              className="input"
              rows={3}
              maxLength={300}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="e.g. The candidate accepted another job"
            />
          </div>
          <ErrorLine message={error} />
          <div className="flex flex-wrap gap-2 justify-end">
            <button type="button" className="btn btn-ghost w-full sm:w-auto" onClick={() => setOpen(false)} disabled={pending}>
              Keep it
            </button>
            <button
              className="btn btn-primary w-full sm:w-auto"
              style={{ background: 'var(--color-danger)' }}
              disabled={pending}
            >
              {pending ? 'Withdrawing…' : 'Withdraw'}
            </button>
          </div>
        </form>
      </Dialog>
    </>
  );
}

export function RecordOutcome({ submissionId, current }: { submissionId: string; current: string }) {
  const uid = useId();
  const router = useRouter();
  const nextDefault = OUTCOMES[Math.min((OUTCOMES as string[]).indexOf(current) + 1, OUTCOMES.length - 1)] ?? OUTCOMES[0];
  const [status, setStatus] = useState<string>(nextDefault);
  const [note, setNote] = useState('');
  const [startDate, setStartDate] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);
  const [pending, start] = useTransition();

  return (
    <form
      className="space-y-3"
      onSubmit={(e) => {
        e.preventDefault();
        setError(null);
        setDone(false);
        start(async () => {
          const res = await recordOutcome({
            submissionId,
            status,
            note,
            startDate: status === 'hired' && startDate ? startDate : null,
          });
          if (!res.ok) return setError(res.error);
          setNote('');
          setDone(true);
          router.refresh();
        });
      }}
    >
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}status`}>
            What did the client decide?
          </label>
          <select id={`${uid}status`} className="input" value={status} onChange={(e) => setStatus(e.target.value)}>
            {OUTCOMES.map((o) => (
              <option key={o} value={o}>
                {OUTCOME_LABEL[o] ?? o}
              </option>
            ))}
          </select>
        </div>
        {status === 'hired' && (
          <div className="min-w-0">
            <label className="label" htmlFor={`${uid}start`}>
              Start date (optional)
            </label>
            <input
              id={`${uid}start`}
              type="date"
              className="input"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
            />
          </div>
        )}
      </div>
      <div>
        <label className="label" htmlFor={`${uid}note`}>
          {status === 'rejected' ? 'Reason the client gave (optional)' : 'Client’s response (optional)'}
        </label>
        <textarea
          id={`${uid}note`}
          className="input"
          rows={3}
          maxLength={status === 'rejected' ? 500 : 2000}
          value={note}
          onChange={(e) => setNote(e.target.value)}
        />
      </div>
      {status === 'hired' && (
        <p className="text-xs muted">Recording a hire closes this submission and creates a placement you can track.</p>
      )}
      {status === 'rejected' && <p className="text-xs muted">Recording “not selected” closes this submission.</p>}
      <ErrorLine message={error} />
      {done && !error && (
        <p className="text-sm" role="status" style={{ color: 'var(--color-verified)' }}>
          Saved.
        </p>
      )}
      <button className="btn btn-primary w-full sm:w-auto" disabled={pending}>
        {pending ? 'Saving…' : 'Record outcome'}
      </button>
    </form>
  );
}
