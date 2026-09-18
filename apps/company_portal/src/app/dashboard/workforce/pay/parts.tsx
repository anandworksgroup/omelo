'use client';

import { useRouter } from 'next/navigation';
import { useId, useState, useTransition } from 'react';
import { BILLING_NEXT, PAYMENT_NEXT, billingTone, hours, money, nice, paymentTone } from '@/lib/workforce';
import {
  addEarningAdjustment,
  approveEarnings,
  deleteOvertimePolicy,
  recordPayment,
  saveOvertimePolicy,
  updateBillingStatus,
  updatePayment,
  type OvertimeInput,
} from '../actions';
import { ErrorLine, TonePill } from '../ui';

/* ------------------------------------------------------------------ */
/* Earnings                                                            */
/* ------------------------------------------------------------------ */

export function EarningActions({
  id,
  status,
  currency,
  remaining,
}: {
  id: string;
  status: string;
  currency: string;
  /** Approved gross minus scheduled / processing / paid payments. */
  remaining: number;
}) {
  const uid = useId();
  const router = useRouter();
  const [mode, setMode] = useState<'none' | 'adjust' | 'pay'>('none');
  const [adj, setAdj] = useState({ amount: '', reason: '' });
  const [pay, setPay] = useState({ amount: remaining > 0 ? remaining.toFixed(2) : '', status: 'scheduled', provider: '', reference: '', scheduledFor: '' });
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const canAdjust = status === 'calculated' || status === 'approved';
  const canPay = ['approved', 'scheduled', 'processing', 'failed'].includes(status) && remaining > 0;

  return (
    <div className="space-y-3">
      <div className="flex gap-2 flex-wrap">
        {status === 'calculated' && (
          <button
            type="button"
            className="btn btn-primary"
            disabled={pending}
            onClick={() =>
              start(async () => {
                setError(null);
                const res = await approveEarnings(id);
                if (!res.ok) return setError(res.error);
                router.refresh();
              })
            }
          >
            Approve earnings
          </button>
        )}
        {canAdjust && (
          <button type="button" className="btn btn-ghost" aria-pressed={mode === 'adjust'} onClick={() => setMode(mode === 'adjust' ? 'none' : 'adjust')}>
            Adjust
          </button>
        )}
        {canPay && (
          <button type="button" className="btn btn-ghost" aria-pressed={mode === 'pay'} onClick={() => setMode(mode === 'pay' ? 'none' : 'pay')}>
            Record a payment
          </button>
        )}
      </div>
      {status === 'calculated' && <p className="hint">Approving locks the timesheet. Adjust first if something is wrong.</p>}
      {mode === 'adjust' && (
        <form
          className="surface rounded-lg p-3 grid gap-3 sm:grid-cols-3"
          onSubmit={(e) => {
            e.preventDefault();
            setError(null);
            start(async () => {
              const res = await addEarningAdjustment(id, adj.amount, adj.reason);
              if (!res.ok) return setError(res.error);
              setMode('none');
              setAdj({ amount: '', reason: '' });
              router.refresh();
            });
          }}
        >
          <div>
            <label className="label" htmlFor={`${uid}a`}>
              Amount ({currency}) *
            </label>
            <input id={`${uid}a`} type="number" step="0.01" className="input" required value={adj.amount} onChange={(e) => setAdj((s) => ({ ...s, amount: e.target.value }))} />
            <p className="hint">Use a minus sign to reduce.</p>
          </div>
          <div className="sm:col-span-2">
            <label className="label" htmlFor={`${uid}r`}>
              Reason * (the worker sees it)
            </label>
            <input id={`${uid}r`} className="input" required minLength={3} maxLength={300} value={adj.reason} onChange={(e) => setAdj((s) => ({ ...s, reason: e.target.value }))} />
          </div>
          <div className="sm:col-span-3">
            <button className="btn btn-primary" disabled={pending}>
              {pending ? 'Saving…' : 'Add adjustment'}
            </button>
          </div>
        </form>
      )}
      {mode === 'pay' && (
        <form
          className="surface rounded-lg p-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-5"
          onSubmit={(e) => {
            e.preventDefault();
            setError(null);
            start(async () => {
              const res = await recordPayment(id, pay);
              if (!res.ok) return setError(res.error);
              setMode('none');
              router.refresh();
            });
          }}
        >
          <div>
            <label className="label" htmlFor={`${uid}pa`}>
              Amount *
            </label>
            <input
              id={`${uid}pa`}
              type="number"
              min={0.01}
              max={remaining}
              step="0.01"
              className="input"
              required
              value={pay.amount}
              onChange={(e) => setPay((s) => ({ ...s, amount: e.target.value }))}
            />
            <p className="hint">Up to {money(remaining, currency)}.</p>
          </div>
          <div>
            <label className="label" htmlFor={`${uid}ps`}>
              Status
            </label>
            <select id={`${uid}ps`} className="input" value={pay.status} onChange={(e) => setPay((s) => ({ ...s, status: e.target.value }))}>
              <option value="scheduled">Scheduled</option>
              <option value="processing">Processing</option>
              <option value="paid">Paid</option>
            </select>
          </div>
          <div>
            <label className="label" htmlFor={`${uid}pd`}>
              Scheduled for
            </label>
            <input id={`${uid}pd`} type="date" className="input" value={pay.scheduledFor} onChange={(e) => setPay((s) => ({ ...s, scheduledFor: e.target.value }))} />
          </div>
          <div>
            <label className="label" htmlFor={`${uid}pp`}>
              Paid via
            </label>
            <input id={`${uid}pp`} className="input" maxLength={60} placeholder="Bank transfer" value={pay.provider} onChange={(e) => setPay((s) => ({ ...s, provider: e.target.value }))} />
          </div>
          <div>
            <label className="label" htmlFor={`${uid}pr`}>
              Reference
            </label>
            <input id={`${uid}pr`} className="input" maxLength={120} placeholder="UTR / transaction ID" value={pay.reference} onChange={(e) => setPay((s) => ({ ...s, reference: e.target.value }))} />
          </div>
          <p className="hint sm:col-span-2 lg:col-span-5">
            Omelo records the payment you made through your bank or payroll; it does not move money. A payroll provider
            can be connected later.
          </p>
          <div className="sm:col-span-2 lg:col-span-5">
            <button className="btn btn-primary" disabled={pending}>
              {pending ? 'Saving…' : 'Record payment'}
            </button>
          </div>
        </form>
      )}
      <ErrorLine text={error} />
    </div>
  );
}

export function PaymentRow({
  id,
  status,
  amount,
  currency,
  label,
}: {
  id: string;
  status: string;
  amount: number;
  currency: string;
  label: string;
}) {
  const uid = useId();
  const router = useRouter();
  const [target, setTarget] = useState<string | null>(null);
  const [ref, setRef] = useState('');
  const [why, setWhy] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const next = PAYMENT_NEXT[status] ?? [];
  return (
    <li className="py-2 space-y-2">
      <div className="flex items-center gap-2 flex-wrap text-sm">
        <span className="tabular-nums font-semibold">{money(amount, currency)}</span>
        <TonePill tone={paymentTone(status)} />
        <span className="text-xs muted flex-1 min-w-[10rem] break-words">{label}</span>
        {next.map((s) => (
          <button key={s} type="button" className="text-xs underline" onClick={() => setTarget(target === s ? null : s)}>
            Mark {s}
          </button>
        ))}
      </div>
      {target && (
        <form
          className="surface rounded-lg p-2 flex gap-2 flex-wrap items-end"
          onSubmit={(e) => {
            e.preventDefault();
            setError(null);
            start(async () => {
              const res = await updatePayment(id, target, ref, why);
              if (!res.ok) return setError(res.error);
              setTarget(null);
              router.refresh();
            });
          }}
        >
          <div className="flex-1 min-w-[10rem]">
            <label className="label" htmlFor={`${uid}r`}>
              Reference
            </label>
            <input id={`${uid}r`} className="input" maxLength={120} value={ref} onChange={(e) => setRef(e.target.value)} />
          </div>
          {target === 'failed' && (
            <div className="flex-1 min-w-[10rem]">
              <label className="label" htmlFor={`${uid}w`}>
                Why it failed *
              </label>
              <input id={`${uid}w`} className="input" required maxLength={300} value={why} onChange={(e) => setWhy(e.target.value)} />
            </div>
          )}
          <button className="btn btn-primary" disabled={pending} style={{ height: 38 }}>
            Mark {target}
          </button>
          <ErrorLine text={error} />
        </form>
      )}
    </li>
  );
}

/* ------------------------------------------------------------------ */
/* Overtime policies                                                   */
/* ------------------------------------------------------------------ */

export type Policy = {
  id: string;
  name: string;
  country_code: string | null;
  daily_threshold_minutes: number | null;
  weekly_threshold_minutes: number | null;
  multiplier: number;
  max_overtime_minutes_week: number | null;
  standard_minutes_per_day: number;
  standard_minutes_per_week: number;
  notes: string | null;
};

const s = (v: number | string | null | undefined) => (v == null ? '' : String(v));

function PolicyForm({ p, onDone }: { p: Policy | null; onDone: () => void }) {
  const uid = useId();
  const router = useRouter();
  const [v, setV] = useState<OvertimeInput>({
    name: p?.name ?? '',
    country_code: p?.country_code ?? '',
    daily_threshold_minutes: s(p?.daily_threshold_minutes),
    weekly_threshold_minutes: s(p?.weekly_threshold_minutes),
    multiplier: s(p?.multiplier ?? 1.5),
    max_overtime_minutes_week: s(p?.max_overtime_minutes_week),
    standard_minutes_per_day: s(p?.standard_minutes_per_day ?? 480),
    standard_minutes_per_week: s(p?.standard_minutes_per_week ?? 2880),
    notes: p?.notes ?? '',
  });
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const set = (k: keyof OvertimeInput) => (e: React.ChangeEvent<HTMLInputElement>) => setV((x) => ({ ...x, [k]: e.target.value }));
  const num = (k: keyof OvertimeInput, label: string, hint?: string, step = '1') => (
    <div>
      <label className="label" htmlFor={`${uid}${k}`}>
        {label}
      </label>
      <input id={`${uid}${k}`} type="number" min={0} step={step} className="input" value={v[k]} onChange={set(k)} />
      {hint && <p className="hint">{hint}</p>}
    </div>
  );
  return (
    <form
      className="surface rounded-lg p-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-4"
      onSubmit={(e) => {
        e.preventDefault();
        setError(null);
        start(async () => {
          const res = await saveOvertimePolicy(p?.id ?? null, v);
          if (!res.ok) return setError(res.error);
          router.refresh();
          onDone();
        });
      }}
    >
      <div className="sm:col-span-2">
        <label className="label" htmlFor={`${uid}n`}>
          Name *
        </label>
        <input id={`${uid}n`} className="input" required maxLength={80} value={v.name} onChange={set('name')} placeholder="Delhi warehouse overtime" />
      </div>
      <div>
        <label className="label" htmlFor={`${uid}c`}>
          Country
        </label>
        <input id={`${uid}c`} className="input uppercase" maxLength={2} value={v.country_code} onChange={set('country_code')} placeholder="IN" />
      </div>
      {num('multiplier', 'Multiplier *', 'e.g. 1.5 = time and a half', '0.01')}
      {num('daily_threshold_minutes', 'Daily threshold (min)', 'Overtime after this many minutes a day')}
      {num('weekly_threshold_minutes', 'Weekly threshold (min)', 'Overtime after this many minutes a week')}
      {num('max_overtime_minutes_week', 'Weekly overtime cap (min)', 'Optional')}
      <div />
      {num('standard_minutes_per_day', 'Standard day (min)', 'Converts daily pay to an hourly rate')}
      {num('standard_minutes_per_week', 'Standard week (min)', 'Converts weekly or monthly pay to an hourly rate')}
      <div className="sm:col-span-2">
        <label className="label" htmlFor={`${uid}no`}>
          Notes
        </label>
        <input id={`${uid}no`} className="input" maxLength={1000} value={v.notes} onChange={set('notes')} placeholder="Source of the rule" />
      </div>
      <div className="flex gap-2 flex-wrap sm:col-span-2 lg:col-span-4">
        <button className="btn btn-primary" disabled={pending}>
          {pending ? 'Saving…' : p ? 'Save policy' : 'Add policy'}
        </button>
        <button type="button" className="btn btn-ghost" onClick={onDone}>
          Cancel
        </button>
      </div>
      <ErrorLine text={error} />
    </form>
  );
}

export function OvertimePolicies({ policies }: { policies: Policy[] }) {
  const router = useRouter();
  const [editing, setEditing] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  return (
    <div className="space-y-3">
      {policies.length === 0 && editing !== 'new' && <p className="text-sm muted">No overtime policies. Without one, extra hours are paid at the normal rate.</p>}
      <ul className="space-y-2">
        {policies.map((p) =>
          editing === p.id ? (
            <li key={p.id}>
              <PolicyForm p={p} onDone={() => setEditing(null)} />
            </li>
          ) : (
            <li key={p.id} className="flex items-center gap-3 flex-wrap text-sm">
              <span className="flex-1 min-w-[12rem] break-words">
                <span className="font-semibold">{p.name}</span>
                <span className="muted">
                  {' '}
                  · ×{p.multiplier}
                  {p.daily_threshold_minutes != null ? ` after ${hours(p.daily_threshold_minutes)}/day` : ''}
                  {p.weekly_threshold_minutes != null ? ` after ${hours(p.weekly_threshold_minutes)}/week` : ''}
                  {p.max_overtime_minutes_week != null ? ` · cap ${hours(p.max_overtime_minutes_week)}/week` : ''}
                  {p.country_code ? ` · ${p.country_code}` : ''}
                </span>
              </span>
              <button type="button" className="text-sm underline" onClick={() => setEditing(p.id)}>
                Edit
              </button>
              <button
                type="button"
                className="text-sm underline muted"
                disabled={pending}
                onClick={() =>
                  start(async () => {
                    setError(null);
                    const res = await deleteOvertimePolicy(p.id);
                    if (!res.ok) return setError(res.error);
                    router.refresh();
                  })
                }
              >
                Delete
              </button>
            </li>
          )
        )}
      </ul>
      {editing === 'new' ? (
        <PolicyForm p={null} onDone={() => setEditing(null)} />
      ) : (
        <button type="button" className="btn btn-ghost" onClick={() => setEditing('new')}>
          Add an overtime policy
        </button>
      )}
      <ErrorLine text={error} />
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Agency billing                                                      */
/* ------------------------------------------------------------------ */

export function BillingActions({ id, status }: { id: string; status: string }) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const next = BILLING_NEXT[status] ?? [];
  if (next.length === 0) return <TonePill tone={billingTone(status)} />;
  return (
    <span className="inline-flex gap-2 items-center flex-wrap">
      <TonePill tone={billingTone(status)} />
      {next.map((n) => (
        <button
          key={n}
          type="button"
          className="text-xs underline"
          style={n === 'void' ? { color: 'var(--color-danger)' } : undefined}
          disabled={pending}
          onClick={() =>
            start(async () => {
              setError(null);
              const res = await updateBillingStatus(id, n);
              if (!res.ok) return setError(res.error);
              router.refresh();
            })
          }
        >
          {n === 'invoiced' ? 'Mark invoiced' : n === 'paid' ? 'Mark paid' : nice(n)}
        </button>
      ))}
      <ErrorLine text={error} />
    </span>
  );
}
