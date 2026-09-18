'use client';

import { useRouter } from 'next/navigation';
import { useId, useState, useTransition } from 'react';
import { PLACEMENT_NEXT, placementTone } from '@/lib/agency';
import Dialog from '../../talent/dialog';
import { updatePlacement } from '../actions';
import { PLACEMENT_MOVE_LABEL } from '../submissions/lib';

export type EditablePlacement = {
  id: string;
  status: string;
  startDate: string | null;
  guaranteeEndsOn: string | null;
  feeAmount: number | null;
  feeCurrency: string | null;
  notes: string | null;
  candidate: string;
};

const day = (d: string | null) => (d ? d.slice(0, 10) : '');

export function EditPlacement({ p }: { p: EditablePlacement }) {
  const uid = useId();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [status, setStatus] = useState(p.status);
  const [startDate, setStartDate] = useState(day(p.startDate));
  const [guarantee, setGuarantee] = useState(day(p.guaranteeEndsOn));
  const [fee, setFee] = useState(p.feeAmount == null ? '' : String(p.feeAmount));
  const [currency, setCurrency] = useState(p.feeCurrency ?? 'INR');
  const [notes, setNotes] = useState(p.notes ?? '');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  const next = PLACEMENT_NEXT[p.status] ?? [];
  const reset = () => {
    setStatus(p.status);
    setStartDate(day(p.startDate));
    setGuarantee(day(p.guaranteeEndsOn));
    setFee(p.feeAmount == null ? '' : String(p.feeAmount));
    setCurrency(p.feeCurrency ?? 'INR');
    setNotes(p.notes ?? '');
    setError(null);
  };

  return (
    <>
      <button
        type="button"
        className="btn btn-ghost w-full sm:w-auto"
        onClick={() => {
          reset();
          setOpen(true);
        }}
      >
        Update
      </button>
      <Dialog
        open={open}
        onClose={() => !pending && setOpen(false)}
        title={`Placement: ${p.candidate}`}
        description="Keep the start, guarantee and the fee you agreed with the client up to date."
      >
        <form
          className="space-y-3"
          onSubmit={(e) => {
            e.preventDefault();
            setError(null);
            const feeTrim = fee.trim();
            const feeNum = feeTrim === '' ? null : Number(feeTrim);
            if (feeNum != null && (!Number.isFinite(feeNum) || feeNum < 0)) return setError('The fee must be 0 or more.');
            start(async () => {
              const res = await updatePlacement({
                placementId: p.id,
                ...(status !== p.status ? { status } : {}),
                startDate: startDate || null,
                guaranteeEndsOn: guarantee || null,
                feeAmount: feeNum,
                feeCurrency: currency.trim().toUpperCase() || (feeNum != null ? 'INR' : null),
                notes: notes.trim() || null,
              });
              if (!res.ok) return setError(res.error);
              setOpen(false);
              router.refresh();
            });
          }}
        >
          <div>
            <label className="label" htmlFor={`${uid}status`}>
              Status
            </label>
            {next.length ? (
              <select id={`${uid}status`} className="input" value={status} onChange={(e) => setStatus(e.target.value)}>
                <option value={p.status}>{placementTone(p.status).label} (no change)</option>
                {next.map((s) => (
                  <option key={s} value={s}>
                    {PLACEMENT_MOVE_LABEL[s] ?? placementTone(s).label}
                  </option>
                ))}
              </select>
            ) : (
              <p className="text-sm muted">
                {placementTone(p.status).label}. This placement is final, so its status cannot change.
              </p>
            )}
            {status === 'fell_through' && status !== p.status && (
              <p className="text-xs mt-1" style={{ color: 'var(--color-danger)' }}>
                “Fell through” is final and cannot be undone.
              </p>
            )}
          </div>
          <div className="grid gap-3 sm:grid-cols-2">
            <div className="min-w-0">
              <label className="label" htmlFor={`${uid}start`}>
                Start date
              </label>
              <input id={`${uid}start`} type="date" className="input" value={startDate} onChange={(e) => setStartDate(e.target.value)} />
            </div>
            <div className="min-w-0">
              <label className="label" htmlFor={`${uid}guar`}>
                Guarantee ends
              </label>
              <input id={`${uid}guar`} type="date" className="input" value={guarantee} onChange={(e) => setGuarantee(e.target.value)} />
            </div>
          </div>
          <div className="grid gap-3 grid-cols-[minmax(0,1fr)_6rem]">
            <div className="min-w-0">
              <label className="label" htmlFor={`${uid}fee`}>
                Agreed fee
              </label>
              <input
                id={`${uid}fee`}
                type="number"
                inputMode="decimal"
                min={0}
                step="any"
                className="input"
                value={fee}
                placeholder="Not set"
                onChange={(e) => setFee(e.target.value)}
              />
            </div>
            <div className="min-w-0">
              <label className="label" htmlFor={`${uid}cur`}>
                Currency
              </label>
              <input
                id={`${uid}cur`}
                className="input uppercase"
                value={currency}
                maxLength={3}
                pattern="[A-Za-z]{3}"
                title="Three-letter code, e.g. INR"
                onChange={(e) => setCurrency(e.target.value.toUpperCase())}
              />
            </div>
          </div>
          <div>
            <label className="label" htmlFor={`${uid}notes`}>
              Notes
            </label>
            <textarea
              id={`${uid}notes`}
              className="input"
              rows={3}
              maxLength={2000}
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
            />
          </div>
          {error && (
            <p className="text-sm break-words" role="alert" style={{ color: 'var(--color-danger)' }}>
              {error}
            </p>
          )}
          <div className="flex flex-wrap gap-2 justify-end">
            <button type="button" className="btn btn-ghost w-full sm:w-auto" onClick={() => setOpen(false)} disabled={pending}>
              Cancel
            </button>
            <button className="btn btn-primary w-full sm:w-auto" disabled={pending}>
              {pending ? 'Saving…' : 'Save'}
            </button>
          </div>
        </form>
      </Dialog>
    </>
  );
}
