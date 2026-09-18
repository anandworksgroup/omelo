'use client';

import { useState, useTransition } from 'react';
import { startBulkAssignShifts } from '../actions';
import BulkProgress, { type JobState } from '../bulk-progress';
import { ErrorLine } from '../ui';

/**
 * Put many workers on many shifts at once (shifts × workers items), as a
 * background job. Each pair is checked again: conflicts, leave, full shifts
 * and assignment dates come back as errors, never silently skipped.
 */
export default function BulkAssign({
  shifts,
  workers,
}: {
  shifts: { id: string; label: string }[];
  workers: { id: string; label: string }[];
}) {
  const [open, setOpen] = useState(false);
  const [sh, setSh] = useState<Set<string>>(new Set());
  const [wk, setWk] = useState<Set<string>>(new Set());
  const [job, setJob] = useState<{ state: JobState; labels: Record<number, string> } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const flip = (set: Set<string>, id: string) => {
    const n = new Set(set);
    if (n.has(id)) n.delete(id);
    else n.add(id);
    return n;
  };
  if (!open)
    return (
      <button type="button" className="btn btn-ghost" onClick={() => setOpen(true)} disabled={!shifts.length || !workers.length}>
        Assign workers to several shifts
      </button>
    );
  const total = sh.size * wk.size;
  return (
    <div className="card p-4 space-y-3">
      <div className="grid gap-4 sm:grid-cols-2">
        <fieldset className="min-w-0">
          <legend className="label">Shifts this week ({sh.size})</legend>
          <button type="button" className="text-xs underline muted mb-1" onClick={() => setSh(sh.size === shifts.length ? new Set() : new Set(shifts.map((s) => s.id)))}>
            {sh.size === shifts.length ? 'None' : 'All'}
          </button>
          <ul className="max-h-60 overflow-y-auto space-y-1">
            {shifts.map((s) => (
              <li key={s.id}>
                <label className="flex gap-2 items-center text-sm">
                  <input type="checkbox" checked={sh.has(s.id)} onChange={() => setSh((x) => flip(x, s.id))} />
                  <span className="break-words">{s.label}</span>
                </label>
              </li>
            ))}
          </ul>
        </fieldset>
        <fieldset className="min-w-0">
          <legend className="label">Workers ({wk.size})</legend>
          <button type="button" className="text-xs underline muted mb-1" onClick={() => setWk(wk.size === workers.length ? new Set() : new Set(workers.map((w) => w.id)))}>
            {wk.size === workers.length ? 'None' : 'All'}
          </button>
          <ul className="max-h-60 overflow-y-auto space-y-1">
            {workers.map((w) => (
              <li key={w.id}>
                <label className="flex gap-2 items-center text-sm">
                  <input type="checkbox" checked={wk.has(w.id)} onChange={() => setWk((x) => flip(x, w.id))} />
                  <span className="break-words">{w.label}</span>
                </label>
              </li>
            ))}
          </ul>
        </fieldset>
      </div>
      <div className="flex gap-2 flex-wrap items-center">
        <button
          type="button"
          className="btn btn-primary"
          disabled={pending || total === 0}
          onClick={() =>
            start(async () => {
              setError(null);
              const shiftIds = [...sh];
              const workerIds = [...wk];
              const res = await startBulkAssignShifts(shiftIds, workerIds);
              if (!res.ok) return setError(res.error);
              const labels: Record<number, string> = {};
              for (let i = 0; i < shiftIds.length * workerIds.length; i++) {
                const s = shifts.find((x) => x.id === shiftIds[Math.floor(i / workerIds.length)]);
                const w = workers.find((x) => x.id === workerIds[i % workerIds.length]);
                labels[i] = `${w?.label ?? 'Worker'} → ${s?.label ?? 'shift'}`;
              }
              setJob({ state: { id: res.jobId, kind: 'assign_shifts', status: 'queued', total: shiftIds.length * workerIds.length, processed: 0, succeeded: 0, failed: 0, errors: [], createdAt: null, finishedAt: null }, labels });
            })
          }
        >
          Assign {total ? total.toLocaleString('en-IN') : ''} in the background
        </button>
        <button type="button" className="btn btn-ghost" onClick={() => setOpen(false)}>
          Close
        </button>
        <ErrorLine text={error} />
      </div>
      {job && <BulkProgress initial={job.state} canCancel labelFor={job.labels} />}
    </div>
  );
}
