'use client';

import { useRouter } from 'next/navigation';
import { useId, useState, useTransition } from 'react';
import { hours } from '@/lib/workforce';
import { assignShift, cancelShift, recordAttendance, unassignShift, updateShift, type BatchResult } from '../../actions';
import { ErrorLine, OkLine } from '../../ui';

function BatchErrors({ result, names }: { result: BatchResult | null; names: Record<string, string> }) {
  if (!result || result.errors.length === 0) return null;
  return (
    <ul className="text-sm space-y-1 basis-full" role="alert">
      {result.errors.map((e, i) => (
        <li key={i} className="break-words" style={{ color: 'var(--color-danger)' }}>
          <strong>{names[e.assignmentId] ?? 'Worker'}:</strong> {e.error}
        </li>
      ))}
    </ul>
  );
}

/** Edit times / headcount / instructions, or cancel (workers are notified). */
export function ShiftEditor({
  id,
  tz,
  startsAt,
  endsAt,
  breakMinutes,
  requiredWorkers,
  instructions,
}: {
  id: string;
  tz: string;
  startsAt: string;
  endsAt: string;
  breakMinutes: number;
  requiredWorkers: number;
  instructions: string;
}) {
  const uid = useId();
  const router = useRouter();
  const [mode, setMode] = useState<'none' | 'edit' | 'cancel'>('none');
  const [v, setV] = useState({
    starts_at: startsAt,
    ends_at: endsAt,
    break_minutes: String(breakMinutes),
    required_workers: String(requiredWorkers),
    instructions,
  });
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const set = (k: keyof typeof v) => (e: React.ChangeEvent<HTMLInputElement>) => setV((s) => ({ ...s, [k]: e.target.value }));

  return (
    <div className="space-y-3">
      <div className="flex gap-2 flex-wrap">
        <button type="button" className="btn btn-ghost" aria-pressed={mode === 'edit'} onClick={() => setMode(mode === 'edit' ? 'none' : 'edit')}>
          Edit shift
        </button>
        <button
          type="button"
          className="btn btn-ghost"
          style={{ color: 'var(--color-danger)' }}
          aria-pressed={mode === 'cancel'}
          onClick={() => setMode(mode === 'cancel' ? 'none' : 'cancel')}
        >
          Cancel shift
        </button>
      </div>
      {mode === 'edit' && (
        <form
          className="surface rounded-lg p-3 grid gap-3 sm:grid-cols-2"
          onSubmit={(e) => {
            e.preventDefault();
            setError(null);
            start(async () => {
              const res = await updateShift(id, tz, v);
              if (!res.ok) return setError(res.error);
              setMode('none');
              router.refresh();
            });
          }}
        >
          <p className="hint sm:col-span-2">Times in {tz.replace(/_/g, ' ')}. Assigned workers are notified; a shift cannot move after anyone checked in.</p>
          <div>
            <label className="label" htmlFor={`${uid}s`}>
              Starts
            </label>
            <input id={`${uid}s`} type="datetime-local" className="input" required value={v.starts_at} onChange={set('starts_at')} />
          </div>
          <div>
            <label className="label" htmlFor={`${uid}e`}>
              Ends
            </label>
            <input id={`${uid}e`} type="datetime-local" className="input" required value={v.ends_at} onChange={set('ends_at')} />
          </div>
          <div>
            <label className="label" htmlFor={`${uid}b`}>
              Break (min)
            </label>
            <input id={`${uid}b`} type="number" min={0} max={480} className="input" value={v.break_minutes} onChange={set('break_minutes')} />
          </div>
          <div>
            <label className="label" htmlFor={`${uid}r`}>
              Workers needed
            </label>
            <input id={`${uid}r`} type="number" min={1} className="input" value={v.required_workers} onChange={set('required_workers')} />
          </div>
          <div className="sm:col-span-2">
            <label className="label" htmlFor={`${uid}i`}>
              Instructions
            </label>
            <input id={`${uid}i`} className="input" maxLength={2000} value={v.instructions} onChange={set('instructions')} />
          </div>
          <div className="flex gap-2 flex-wrap sm:col-span-2">
            <button className="btn btn-primary" disabled={pending}>
              {pending ? 'Saving…' : 'Save'}
            </button>
          </div>
          <ErrorLine text={error} />
        </form>
      )}
      {mode === 'cancel' && (
        <form
          className="surface rounded-lg p-3 flex gap-3 flex-wrap items-end"
          onSubmit={(e) => {
            e.preventDefault();
            setError(null);
            start(async () => {
              const res = await cancelShift(id, reason);
              if (!res.ok) return setError(res.error);
              setMode('none');
              router.refresh();
            });
          }}
        >
          <div className="flex-1 min-w-[12rem]">
            <label className="label" htmlFor={`${uid}c`}>
              Reason (workers are told) *
            </label>
            <input id={`${uid}c`} className="input" required minLength={3} maxLength={300} value={reason} onChange={(e) => setReason(e.target.value)} />
          </div>
          <button className="btn btn-primary" disabled={pending} style={{ background: 'var(--color-danger)' }}>
            {pending ? 'Cancelling…' : 'Cancel this shift'}
          </button>
          <ErrorLine text={error} />
        </form>
      )}
    </div>
  );
}

/** Assign (or offer as an extra shift) from the requirement's accepted/active workers. */
export function AssignPanel({
  shiftId,
  workers,
  open,
}: {
  shiftId: string;
  workers: { id: string; label: string; detail: string }[];
  open: number;
}) {
  const router = useRouter();
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [result, setResult] = useState<BatchResult | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const names = Object.fromEntries(workers.map((w) => [w.id, w.label]));
  if (workers.length === 0)
    return <p className="text-sm muted">Everyone with an accepted or active assignment on this requirement is already on this shift.</p>;

  const run = (offer: boolean) =>
    start(async () => {
      setError(null);
      setOk(null);
      setResult(null);
      const res = await assignShift(shiftId, [...picked], offer);
      if (!res.ok) return setError(res.error);
      setResult(res);
      setOk(offer ? `${res.done} offered as an extra shift.` : `${res.done} assigned.`);
      setPicked(new Set());
      router.refresh();
    });

  return (
    <div className="space-y-3">
      <ul className="max-h-72 overflow-y-auto divide-y" style={{ borderColor: 'var(--line)' }}>
        {workers.map((w) => (
          <li key={w.id} className="py-2">
            <label className="flex gap-3 items-center text-sm">
              <input
                type="checkbox"
                className="w-4 h-4"
                checked={picked.has(w.id)}
                onChange={() =>
                  setPicked((p) => {
                    const n = new Set(p);
                    if (n.has(w.id)) n.delete(w.id);
                    else n.add(w.id);
                    return n;
                  })
                }
              />
              <span className="min-w-0">
                <span className="font-semibold break-words">{w.label}</span>
                <span className="block text-xs muted break-words">{w.detail}</span>
              </span>
            </label>
          </li>
        ))}
      </ul>
      <div className="flex gap-2 flex-wrap items-center">
        <button type="button" className="btn btn-primary" disabled={pending || picked.size === 0} onClick={() => run(false)}>
          Assign {picked.size || ''}
        </button>
        <button type="button" className="btn btn-ghost" disabled={pending || picked.size === 0} onClick={() => run(true)}>
          Offer as extra shift
        </button>
        <span className="text-xs muted">{open} place{open === 1 ? '' : 's'} open</span>
        <OkLine text={ok} />
        <ErrorLine text={error} />
        <BatchErrors result={result} names={names} />
      </div>
      <p className="hint">Assigning puts them on the shift now. Offering lets them accept in the app; the first to accept fill the places.</p>
    </div>
  );
}

/** Replacement candidates: free at this time, not on leave, within their assignment dates. */
export function ReplacementList({
  shiftId,
  candidates,
}: {
  shiftId: string;
  candidates: { assignmentId: string; name: string; title: string | null; minutesThisWeek: number; offered: boolean }[];
}) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<Record<string, string>>({});
  const [pending, start] = useTransition();
  const act = (ids: string[], offer: boolean) =>
    start(async () => {
      setError(null);
      const res = await assignShift(shiftId, ids, offer);
      if (!res.ok) return setError(res.error);
      const d: Record<string, string> = {};
      for (const id of ids) {
        const e = res.errors.find((x) => x.assignmentId === id);
        d[id] = e ? e.error : offer ? 'Offered' : 'Assigned';
      }
      setDone((x) => ({ ...x, ...d }));
      router.refresh();
    });
  if (candidates.length === 0) return <p className="text-sm muted">No one on this requirement is free for this shift.</p>;
  const notOffered = candidates.filter((c) => !c.offered && !done[c.assignmentId]).map((c) => c.assignmentId);
  return (
    <div className="space-y-2">
      <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
        {candidates.map((c) => (
          <li key={c.assignmentId} className="py-2 flex items-center gap-2 flex-wrap text-sm">
            <span className="flex-1 min-w-[10rem] break-words">
              <span className="font-semibold">{c.name}</span>
              <span className="muted text-xs"> · {hours(c.minutesThisWeek)} booked this week</span>
            </span>
            {done[c.assignmentId] ? (
              <span className="text-xs break-words">{done[c.assignmentId]}</span>
            ) : c.offered ? (
              <span className="pill">Offered</span>
            ) : (
              <>
                <button type="button" className="btn btn-ghost" style={{ height: 32 }} disabled={pending} onClick={() => act([c.assignmentId], true)}>
                  Offer
                </button>
                <button type="button" className="btn btn-ghost" style={{ height: 32 }} disabled={pending} onClick={() => act([c.assignmentId], false)}>
                  Assign
                </button>
              </>
            )}
          </li>
        ))}
      </ul>
      {notOffered.length > 1 && (
        <button type="button" className="btn btn-ghost" disabled={pending} onClick={() => act(notOffered.slice(0, 200), true)}>
          Offer to all {notOffered.length}
        </button>
      )}
      <ErrorLine text={error} />
    </div>
  );
}

/** Supervisor confirmation of arrival / departure, and removal before check-in. */
export function WorkerActions({
  shiftWorkerId,
  tz,
  defaultIn,
  defaultOut,
  canRecord,
  canUnassign,
  recorded,
}: {
  shiftWorkerId: string;
  tz: string;
  defaultIn: string;
  defaultOut: string;
  canRecord: boolean;
  canUnassign: boolean;
  recorded: boolean;
}) {
  const uid = useId();
  const router = useRouter();
  const [mode, setMode] = useState<'none' | 'record' | 'remove'>('none');
  const [v, setV] = useState({ in: defaultIn, out: defaultOut, note: '' });
  const [reason, setReason] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  if (!canRecord && !canUnassign) return null;
  return (
    <div className="basis-full space-y-2">
      <div className="flex gap-3 flex-wrap">
        {canRecord && (
          <button type="button" className="text-sm underline" onClick={() => setMode(mode === 'record' ? 'none' : 'record')}>
            {recorded ? 'Record times again' : 'Record attendance'}
          </button>
        )}
        {canUnassign && (
          <button type="button" className="text-sm underline muted" onClick={() => setMode(mode === 'remove' ? 'none' : 'remove')}>
            Remove from shift
          </button>
        )}
      </div>
      {mode === 'record' && (
        <form
          className="surface rounded-lg p-3 grid gap-3 sm:grid-cols-3"
          onSubmit={(e) => {
            e.preventDefault();
            setError(null);
            start(async () => {
              const res = await recordAttendance(shiftWorkerId, tz, v.in, v.out, v.note);
              if (!res.ok) return setError(res.error);
              setMode('none');
              router.refresh();
            });
          }}
        >
          <div>
            <label className="label" htmlFor={`${uid}i`}>
              Arrived *
            </label>
            <input id={`${uid}i`} type="datetime-local" className="input" required value={v.in} onChange={(e) => setV((s) => ({ ...s, in: e.target.value }))} />
          </div>
          <div>
            <label className="label" htmlFor={`${uid}o`}>
              Left
            </label>
            <input id={`${uid}o`} type="datetime-local" className="input" value={v.out} onChange={(e) => setV((s) => ({ ...s, out: e.target.value }))} />
          </div>
          <div>
            <label className="label" htmlFor={`${uid}n`}>
              Note
            </label>
            <input id={`${uid}n`} className="input" maxLength={500} value={v.note} placeholder="Sign-in sheet" onChange={(e) => setV((s) => ({ ...s, note: e.target.value }))} />
          </div>
          <p className="hint sm:col-span-3">
            Times in {tz.replace(/_/g, ' ')}. With a departure time the record counts as approved by you; without, the worker is shown as checked in.
          </p>
          <div className="flex gap-2 flex-wrap sm:col-span-3">
            <button className="btn btn-primary" disabled={pending}>
              {pending ? 'Saving…' : 'Save attendance'}
            </button>
          </div>
          <ErrorLine text={error} />
        </form>
      )}
      {mode === 'remove' && (
        <form
          className="surface rounded-lg p-3 flex gap-3 flex-wrap items-end"
          onSubmit={(e) => {
            e.preventDefault();
            setError(null);
            start(async () => {
              const res = await unassignShift(shiftWorkerId, reason);
              if (!res.ok) return setError(res.error);
              setMode('none');
              router.refresh();
            });
          }}
        >
          <div className="flex-1 min-w-[12rem]">
            <label className="label" htmlFor={`${uid}r`}>
              Reason (the worker is told)
            </label>
            <input id={`${uid}r`} className="input" maxLength={300} value={reason} onChange={(e) => setReason(e.target.value)} />
          </div>
          <button className="btn btn-ghost" disabled={pending} style={{ color: 'var(--color-danger)' }}>
            {pending ? 'Removing…' : 'Remove'}
          </button>
          <ErrorLine text={error} />
        </form>
      )}
    </div>
  );
}
