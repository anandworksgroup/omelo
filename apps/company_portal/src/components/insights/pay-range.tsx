/**
 * The job's monthly pay against a market range (p25 / median / p75), on one
 * small bar in the job's currency. Every value is printed as text beside the
 * bar; when the database has no range we say "Not enough data" and draw
 * nothing — no invented numbers.
 */
import { formatMoney } from '@/lib/format';
import type { Percentiles } from '@/lib/intelligence';

export function PayRange({
  title,
  range,
  job,
  currency,
  sampleLabel,
}: {
  title: string;
  range: Percentiles | null;
  job: number | null;
  currency: string | null;
  /** e.g. "jobs" or "workers" — what n counts. */
  sampleLabel: string;
}) {
  const money = (v: number | null) => (v == null ? '—' : formatMoney(v, currency));
  const complete = range && range.p25 != null && range.median != null && range.p75 != null;

  if (!range || !complete) {
    return (
      <div className="min-w-0">
        <p className="text-sm font-semibold">{title}</p>
        <p className="text-sm muted mt-0.5">Not enough data</p>
      </div>
    );
  }

  const { p25, median, p75 } = range as { p25: number; median: number; p75: number };
  const values = [p25, p75, ...(job != null ? [job] : [])];
  const lo = Math.min(...values);
  const hi = Math.max(...values);
  const pad = Math.max((hi - lo) * 0.15, hi * 0.05, 1);
  const min = Math.max(0, lo - pad);
  const max = hi + pad;
  const at = (v: number) => `${((v - min) / (max - min)) * 100}%`;
  const summary =
    `${title}: 25th percentile ${money(p25)}, median ${money(median)}, 75th percentile ${money(p75)}` +
    (job != null ? `; this job ${money(job)}` : '');

  return (
    <div className="min-w-0">
      <p className="text-sm font-semibold">
        {title} <span className="muted font-normal">· {range.n} {sampleLabel}</span>
      </p>
      <div className="relative h-8 mt-2" role="img" aria-label={summary}>
        <div className="absolute inset-x-0 top-3 h-2 rounded-full surface" style={{ boxShadow: 'inset 0 0 0 1px var(--line)' }} />
        <div
          className="absolute top-3 h-2 rounded-full"
          style={{ left: at(p25), width: `calc(${at(p75)} - ${at(p25)})`, background: 'var(--color-brand-200)' }}
        />
        <div className="absolute top-2 h-4 w-0.5" style={{ left: at(median), background: 'var(--color-brand-700)' }} />
        {job != null && (
          <div
            className="absolute w-3.5 h-3.5 -ml-[7px] rounded-full border-2"
            style={{ left: at(job), top: '9px', background: 'var(--color-accent-500)', borderColor: 'var(--bg)' }}
          />
        )}
      </div>
      <dl className="grid grid-cols-3 gap-2 text-xs mt-1">
        <div>
          <dt className="muted">25th pct</dt>
          <dd className="font-semibold tabular-nums">{money(p25)}</dd>
        </div>
        <div className="text-center">
          <dt className="muted">Median</dt>
          <dd className="font-semibold tabular-nums">{money(median)}</dd>
        </div>
        <div className="text-right">
          <dt className="muted">75th pct</dt>
          <dd className="font-semibold tabular-nums">{money(p75)}</dd>
        </div>
      </dl>
    </div>
  );
}
