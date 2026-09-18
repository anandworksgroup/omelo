'use client';

import { useRouter } from 'next/navigation';
import { useId, useState, useTransition } from 'react';
import { correctAttendance, reviewAttendance } from '../actions';
import { ErrorLine } from '../ui';

/**
 * Approve, adjust (with corrected times) or reject attendance that needs
 * review. Exceptions are for a person to decide — never an automatic penalty.
 */
export function AttendanceReview({
  attendanceId,
  tz,
  defaultIn,
  defaultOut,
  breakMinutes,
  compact = false,
}: {
  attendanceId: string;
  tz: string;
  defaultIn: string;
  defaultOut: string;
  breakMinutes: number;
  compact?: boolean;
}) {
  const uid = useId();
  const router = useRouter();
  const [decision, setDecision] = useState<'approve' | 'adjust' | 'reject'>('approve');
  const [v, setV] = useState({ checkIn: defaultIn, checkOut: defaultOut, breakMinutes: String(breakMinutes), note: '' });
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const [pending, start] = useTransition();
  if (done) return <p className="text-sm" style={{ color: 'var(--color-verified)' }}>{done}</p>;

  return (
    <form
      className={`grid gap-3 ${compact ? 'sm:grid-cols-2' : 'sm:grid-cols-3'}`}
      onSubmit={(e) => {
        e.preventDefault();
        setError(null);
        start(async () => {
          const res = await reviewAttendance(attendanceId, decision, tz, v);
          if (!res.ok) return setError(res.error);
          setDone(decision === 'approve' ? 'Approved.' : decision === 'adjust' ? 'Adjusted and approved.' : 'Rejected — not paid.');
          router.refresh();
        });
      }}
    >
      <fieldset className={compact ? 'sm:col-span-2' : 'sm:col-span-3'}>
        <legend className="sr-only">Decision</legend>
        <div className="inline-flex rounded-lg border hairline p-0.5 surface flex-wrap">
          {(['approve', 'adjust', 'reject'] as const).map((d) => (
            <button
              key={d}
              type="button"
              aria-pressed={decision === d}
              className="px-3 py-1.5 rounded-md text-sm font-semibold"
              style={
                decision === d
                  ? { background: 'var(--bg)', color: d === 'reject' ? 'var(--color-danger)' : 'var(--color-brand-600)', boxShadow: '0 0 0 1px var(--line)' }
                  : { color: 'var(--muted)' }
              }
              onClick={() => setDecision(d)}
            >
              {d === 'approve' ? 'Approve' : d === 'adjust' ? 'Adjust times' : 'Reject'}
            </button>
          ))}
        </div>
      </fieldset>
      {decision === 'adjust' && (
        <>
          <div>
            <label className="label" htmlFor={`${uid}i`}>
              Arrived *
            </label>
            <input id={`${uid}i`} type="datetime-local" className="input" required value={v.checkIn} onChange={(e) => setV((s) => ({ ...s, checkIn: e.target.value }))} />
          </div>
          <div>
            <label className="label" htmlFor={`${uid}o`}>
              Left *
            </label>
            <input id={`${uid}o`} type="datetime-local" className="input" required value={v.checkOut} onChange={(e) => setV((s) => ({ ...s, checkOut: e.target.value }))} />
          </div>
          <div>
            <label className="label" htmlFor={`${uid}b`}>
              Break (min)
            </label>
            <input id={`${uid}b`} type="number" min={0} max={480} className="input" value={v.breakMinutes} onChange={(e) => setV((s) => ({ ...s, breakMinutes: e.target.value }))} />
          </div>
          <p className="hint sm:col-span-3">Times in {tz.replace(/_/g, ' ')}.</p>
        </>
      )}
      <div className={compact ? 'sm:col-span-2' : 'sm:col-span-3'}>
        <label className="label" htmlFor={`${uid}n`}>
          Note {decision === 'reject' ? '* (the worker is told)' : '(optional, the worker is told)'}
        </label>
        <input
          id={`${uid}n`}
          className="input"
          maxLength={500}
          required={decision === 'reject'}
          value={v.note}
          onChange={(e) => setV((s) => ({ ...s, note: e.target.value }))}
        />
      </div>
      <div className="flex gap-2 flex-wrap items-center">
        <button className="btn btn-primary" disabled={pending}>
          {pending ? 'Saving…' : decision === 'approve' ? 'Approve' : decision === 'adjust' ? 'Save adjusted times' : 'Reject'}
        </button>
      </div>
      <ErrorLine text={error} />
    </form>
  );
}

/** Change reviewed attendance, with a reason. Blocked on approved timesheets. */
export function CorrectAttendance({
  attendanceId,
  tz,
  defaultIn,
  defaultOut,
}: {
  attendanceId: string;
  tz: string;
  defaultIn: string;
  defaultOut: string;
}) {
  const uid = useId();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [v, setV] = useState({ checkIn: defaultIn, checkOut: defaultOut, reason: '' });
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  if (!open)
    return (
      <button type="button" className="btn btn-ghost" onClick={() => setOpen(true)}>
        Correct times
      </button>
    );
  return (
    <form
      className="surface rounded-lg p-3 grid gap-3 sm:grid-cols-2"
      onSubmit={(e) => {
        e.preventDefault();
        setError(null);
        start(async () => {
          const res = await correctAttendance(attendanceId, tz, v.checkIn, v.checkOut, v.reason);
          if (!res.ok) return setError(res.error);
          setOpen(false);
          router.refresh();
        });
      }}
    >
      <div>
        <label className="label" htmlFor={`${uid}i`}>
          Arrived *
        </label>
        <input id={`${uid}i`} type="datetime-local" className="input" required value={v.checkIn} onChange={(e) => setV((s) => ({ ...s, checkIn: e.target.value }))} />
      </div>
      <div>
        <label className="label" htmlFor={`${uid}o`}>
          Left *
        </label>
        <input id={`${uid}o`} type="datetime-local" className="input" required value={v.checkOut} onChange={(e) => setV((s) => ({ ...s, checkOut: e.target.value }))} />
      </div>
      <div className="sm:col-span-2">
        <label className="label" htmlFor={`${uid}r`}>
          Reason *
        </label>
        <input
          id={`${uid}r`}
          className="input"
          required
          minLength={5}
          maxLength={500}
          value={v.reason}
          placeholder="Badge reader was down; times from the gate log"
          onChange={(e) => setV((s) => ({ ...s, reason: e.target.value }))}
        />
        <p className="hint">
          Times in {tz.replace(/_/g, ' ')}. Recorded in the history with your name. Not possible once the timesheet is
          approved — reopen it first.
        </p>
      </div>
      <div className="flex gap-2 flex-wrap sm:col-span-2">
        <button className="btn btn-primary" disabled={pending}>
          {pending ? 'Saving…' : 'Save correction'}
        </button>
        <button type="button" className="btn btn-ghost" onClick={() => setOpen(false)}>
          Cancel
        </button>
      </div>
      <ErrorLine text={error} />
    </form>
  );
}
