'use client';

import { useEffect, useState, useTransition } from 'react';
import { formatMoney } from '@/lib/format';
import { countryName } from '@/lib/global';
import type { MarketInsights } from '@/lib/intelligence';
import { marketForRole } from './market';

type Result = { key: string; data: MarketInsights | null; error: string | null };

/**
 * A small "Market for this role" hint for the chosen profession and country.
 * Figures come straight from omelo_market_insights; when the pay range is
 * missing we say so instead of estimating one.
 */
export default function MarketHint({
  professionId,
  professionName,
  country,
  currency,
}: {
  professionId: string;
  professionName: string | null;
  country: string | null;
  currency: string;
}) {
  const key = `${professionId}|${country ?? ''}|${currency}`;
  // Keyed by the inputs it was fetched for, so a stale answer is never shown.
  const [result, setResult] = useState<Result | null>(null);
  const [loading, startTransition] = useTransition();

  useEffect(() => {
    if (!professionId) return;
    let current = true;
    startTransition(async () => {
      const r = await marketForRole({ professionId, country, currency });
      if (current) setResult({ key: `${professionId}|${country ?? ''}|${currency}`, ...r });
    });
    return () => {
      current = false;
    };
  }, [professionId, country, currency]);

  if (!professionId) return null;
  const r = result && result.key === key ? result : null;
  const where = country ? `in ${countryName(country)}` : 'on Omelo';

  return (
    <aside className="card p-4 text-sm space-y-2" aria-live="polite" aria-busy={loading || !r}>
      <p className="font-bold">Market for this role</p>
      {!r ? (
        <p className="muted">Looking at the market…</p>
      ) : r.error ? (
        <p className="muted">Market data is not available right now.</p>
      ) : !r.data ? (
        <p className="muted">No market data for this role yet.</p>
      ) : (
        <>
          <p>
            <strong className="tabular-nums">{r.data.openJobs.toLocaleString('en-US')}</strong> open{' '}
            {r.data.openJobs === 1 ? 'job' : 'jobs'} for {r.data.profession ?? professionName ?? 'this role'} {where}
            {r.data.openings > r.data.openJobs ? ` (${r.data.openings.toLocaleString('en-US')} openings)` : ''}
            {r.data.workers != null ? ` · ${r.data.workers.toLocaleString('en-US')} workers in this profession` : ''}.
          </p>
          {r.data.pay && r.data.pay.p25 != null && r.data.pay.p75 != null ? (
            <p>
              Typical pay{' '}
              <strong className="tabular-nums">
                {formatMoney(r.data.pay.p25, r.data.pay.currency)} – {formatMoney(r.data.pay.p75, r.data.pay.currency)}
              </strong>{' '}
              a month
              {r.data.pay.median != null ? `, median ${formatMoney(r.data.pay.median, r.data.pay.currency)}` : ''}{' '}
              <span className="muted">(middle half of {r.data.pay.jobs} jobs with pay)</span>.
            </p>
          ) : (
            <p className="muted">Pay range: not enough data. {r.data.note ?? ''}</p>
          )}
          {r.data.skills.length > 0 && (
            <div>
              <p className="muted text-xs mb-1">Skills in demand</p>
              <ul className="flex flex-wrap gap-1.5">
                {r.data.skills.slice(0, 6).map((s) => (
                  <li key={s.id} className="pill text-[0.75rem]">
                    {s.name} <span className="muted tabular-nums">· {s.jobs}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}
          {(r.data.remoteJobs > 0 || r.data.sponsoredJobs > 0) && (
            <p className="text-xs muted">
              {r.data.remoteJobs} remote · {r.data.sponsoredJobs} offering visa sponsorship
            </p>
          )}
        </>
      )}
    </aside>
  );
}
