'use client';

import { useRouter } from 'next/navigation';
import { useId, useState, useTransition } from 'react';
import { PAY_PERIODS } from '@/lib/hiring';
import { ASSIGNMENT_ACTION_LABEL, ASSIGNMENT_NEXT } from '@/lib/workforce';
import { buildTimesheet, setAssignmentBilling, setAssignmentStatus } from '../../actions';
import { ErrorLine, OkLine } from '../../ui';

/** Status moves a manager may make, with the end date and reason where they matter. */
export function AssignmentActions({ id, status, today }: { id: string; status: string; today: string }) {
  const uid = useId();
  const router = useRouter();
  const [target, setTarget] = useState<string | null>(null);
  const [reason, setReason] = useState('');
  const [endDate, setEndDate] = useState(today);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const next = ASSIGNMENT_NEXT[status] ?? [];
  if (next.length === 0) return <p className="text-sm muted">No further changes: this assignment is {status.replace(/_/g, ' ')}.</p>;
  const ending = target === 'completed' || target === 'terminated';

  return (
    <div className="space-y-3">
      <div className="flex gap-2 flex-wrap">
        {next.map((s) => (
          <button
            key={s}
            type="button"
            className={s === 'terminated' || s === 'cancelled' ? 'btn btn-ghost' : 'btn btn-primary'}
            style={s === 'terminated' || s === 'cancelled' ? { color: 'var(--color-danger)' } : undefined}
            aria-pressed={target === s}
            onClick={() => {
              setTarget(s);
              setError(null);
            }}
          >
            {s === 'active' && status === 'accepted' ? 'Start now' : ASSIGNMENT_ACTION_LABEL[s] ?? s}
          </button>
        ))}
      </div>
      {target && (
        <form
          className="surface rounded-lg p-3 grid gap-3 sm:grid-cols-2"
          onSubmit={(e) => {
            e.preventDefault();
            setError(null);
            start(async () => {
              const res = await setAssignmentStatus(id, target, reason, ending ? endDate : '');
              if (!res.ok) return setError(res.error);
              setTarget(null);
              setReason('');
              router.refresh();
            });
          }}
        >
          {ending && (
            <div>
              <label className="label" htmlFor={`${uid}d`}>
                Last day
              </label>
              <input id={`${uid}d`} type="date" className="input" value={endDate} onChange={(e) => setEndDate(e.target.value)} />
              <p className="hint">Future shifts after today are released. The worker’s employment ends on this day.</p>
            </div>
          )}
          <div className={ending ? '' : 'sm:col-span-2'}>
            <label className="label" htmlFor={`${uid}r`}>
              Reason {target === 'terminated' ? '*' : '(optional)'}
            </label>
            <input
              id={`${uid}r`}
              className="input"
              maxLength={500}
              required={target === 'terminated'}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder={target === 'completed' ? 'Season finished' : ''}
            />
            <p className="hint">The worker is notified.</p>
          </div>
          <div className="flex gap-2 flex-wrap sm:col-span-2">
            <button className="btn btn-primary" disabled={pending}>
              {pending ? 'Saving…' : `Confirm: ${ASSIGNMENT_ACTION_LABEL[target] ?? target}`}
            </button>
            <button type="button" className="btn btn-ghost" onClick={() => setTarget(null)}>
              Back
            </button>
          </div>
          <ErrorLine text={error} />
        </form>
      )}
    </div>
  );
}

/** Agency pay team: the rate billed to the client (never shown to the worker). */
export function BillingForm({
  id,
  billRate,
  billPeriod,
  note,
}: {
  id: string;
  billRate: number | null;
  billPeriod: string | null;
  note: string | null;
}) {
  const uid = useId();
  const router = useRouter();
  const [v, setV] = useState({ rate: billRate != null ? String(billRate) : '', period: billPeriod ?? 'hour', note: note ?? '' });
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [pending, start] = useTransition();
  return (
    <form
      className="grid gap-3 sm:grid-cols-3"
      onSubmit={(e) => {
        e.preventDefault();
        setError(null);
        setOk(null);
        start(async () => {
          const res = await setAssignmentBilling(id, v.rate, v.period, v.note);
          if (!res.ok) return setError(res.error);
          setOk('Saved. New billing records use this rate.');
          router.refresh();
        });
      }}
    >
      <div>
        <label className="label" htmlFor={`${uid}r`}>
          Bill rate *
        </label>
        <input
          id={`${uid}r`}
          type="number"
          min={0}
          step="0.01"
          required
          className="input"
          value={v.rate}
          onChange={(e) => setV((s) => ({ ...s, rate: e.target.value }))}
        />
      </div>
      <div>
        <label className="label" htmlFor={`${uid}p`}>
          Per
        </label>
        <select id={`${uid}p`} className="input" value={v.period} onChange={(e) => setV((s) => ({ ...s, period: e.target.value }))}>
          {PAY_PERIODS.filter((p) => p.value !== 'per_task').map((p) => (
            <option key={p.value} value={p.value}>
              {p.label.replace('per ', '')}
            </option>
          ))}
        </select>
      </div>
      <div>
        <label className="label" htmlFor={`${uid}n`}>
          Note
        </label>
        <input id={`${uid}n`} className="input" maxLength={500} value={v.note} onChange={(e) => setV((s) => ({ ...s, note: e.target.value }))} />
      </div>
      <div className="sm:col-span-3 flex gap-2 flex-wrap items-center">
        <button className="btn btn-primary" disabled={pending}>
          {pending ? 'Saving…' : 'Save bill rate'}
        </button>
        <OkLine text={ok} />
        <ErrorLine text={error} />
      </div>
    </form>
  );
}

/** Build (or rebuild a draft) timesheet from attendance for a period. */
export function BuildTimesheet({ id, defaultFrom, defaultTo }: { id: string; defaultFrom: string; defaultTo: string }) {
  const uid = useId();
  const router = useRouter();
  const [from, setFrom] = useState(defaultFrom);
  const [to, setTo] = useState(defaultTo);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  return (
    <form
      className="flex gap-3 flex-wrap items-end"
      onSubmit={(e) => {
        e.preventDefault();
        setError(null);
        start(async () => {
          const res = await buildTimesheet(id, from, to);
          if (!res.ok) return setError(res.error);
          router.push(`/dashboard/workforce/timesheets/${res.id}`);
        });
      }}
    >
      <div>
        <label className="label" htmlFor={`${uid}f`}>
          From
        </label>
        <input id={`${uid}f`} type="date" className="input" required value={from} onChange={(e) => setFrom(e.target.value)} />
      </div>
      <div>
        <label className="label" htmlFor={`${uid}t`}>
          To
        </label>
        <input id={`${uid}t`} type="date" className="input" required value={to} onChange={(e) => setTo(e.target.value)} />
      </div>
      <button className="btn btn-ghost" disabled={pending}>
        {pending ? 'Building…' : 'Build timesheet'}
      </button>
      <p className="hint basis-full">
        Collects finished attendance for up to 31 days. The worker submits it; then it is reviewed by the workplace.
      </p>
      <ErrorLine text={error} />
    </form>
  );
}
