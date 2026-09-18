import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { ErrorNote, Notice, PageHeader, PlacementPill, Section, dateText } from '../ui';
import { BASE, money } from '../submissions/lib';
import { WorkTabs } from '../submissions/row';
import { loadPlacements, type PlacementItem } from '../placements/data';

export const metadata: Metadata = { title: 'Billing · Omelo' };

function totals(items: PlacementItem[]) {
  const m = new Map<string, number>();
  for (const p of items) {
    if (p.feeAmount == null) continue;
    const c = p.feeCurrency || 'INR';
    m.set(c, (m.get(c) ?? 0) + p.feeAmount);
  }
  return [...m.entries()].sort((a, b) => a[0].localeCompare(b[0]));
}

export default async function BillingPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const { items, error } = await loadPlacements(supabase, ctx.companyId);

  const withFee = items.filter((p) => p.feeAmount != null);
  const live = withFee.filter((p) => p.status !== 'fell_through');
  const fell = withFee.filter((p) => p.status === 'fell_through');
  const noFee = items.filter((p) => p.feeAmount == null && p.status !== 'fell_through').length;
  const agreed = totals(live);
  const lost = totals(fell);

  return (
    <div className="space-y-5 max-w-5xl">
      <PageHeader title="Billing" subtitle="Placement fees you have agreed with clients." />
      <WorkTabs active="billing" />
      <div className="card p-4 text-sm leading-relaxed" style={{ borderTop: '3px solid var(--color-brand-600)' }}>
        Invoicing comes later — this is a record of fees you have agreed. Omelo does not bill your clients or take
        payments for you.
      </div>

      {error && !items.length ? (
        <ErrorNote label="placements" message={error} />
      ) : items.length === 0 ? (
        <Notice
          title="No placements yet"
          action={
            <Link href={`${BASE}/placements`} className="btn btn-ghost">
              Placements
            </Link>
          }
        >
          Fees are recorded on placements. A placement appears when one of your candidates is hired.
        </Notice>
      ) : (
        <>
          <div className="grid gap-3 sm:grid-cols-2">
            <div className="card p-4 min-w-0">
              <p className="text-sm font-semibold">Agreed fees</p>
              <p className="text-xs muted">Starting soon, working and completed placements</p>
              {agreed.length ? (
                <ul className="mt-2 space-y-1">
                  {agreed.map(([cur, sum]) => (
                    <li key={cur} className="text-2xl font-black tabular-nums break-words">
                      {money(sum, cur)}
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="text-sm muted mt-2">No fees set yet.</p>
              )}
            </div>
            <div className="card p-4 min-w-0">
              <p className="text-sm font-semibold">Placements with no fee set</p>
              <p className="text-2xl font-black tabular-nums mt-2">{noFee}</p>
              {noFee > 0 && (
                <Link href={`${BASE}/placements`} className="text-sm underline muted">
                  Add the fee on Placements
                </Link>
              )}
            </div>
          </div>
          {lost.length > 0 && (
            <p className="text-sm muted break-words">
              Fell through (not counted above): {lost.map(([c, s]) => money(s, c)).join(' · ')}
            </p>
          )}

          <Section title={`Placements with a fee (${withFee.length})`}>
            {error && <ErrorNote label="candidate names" message={error} />}
            {withFee.length === 0 ? (
              <p className="text-sm muted">
                None yet. Open{' '}
                <Link href={`${BASE}/placements`} className="underline">
                  Placements
                </Link>{' '}
                and use Update to record the fee you agreed.
              </p>
            ) : (
              <ul className="divide-y hairline -my-2">
                {withFee.map((p) => (
                  <li key={p.id} className="py-3 flex flex-wrap items-start gap-x-4 gap-y-1 min-w-0">
                    <div className="flex-1 min-w-[12rem]">
                      <Link href={`${BASE}/placements#p-${p.id}`} className="font-semibold hover:underline break-words">
                        {p.candidate}
                      </Link>
                      <p className="text-sm muted break-words">
                        {[p.title ?? p.position, p.client].filter(Boolean).join(' · ')}
                      </p>
                      <p className="text-xs muted">Starts {dateText(p.startDate)}</p>
                    </div>
                    <div className="flex flex-wrap items-center gap-2 sm:flex-col sm:items-end">
                      <span
                        className={`font-bold tabular-nums ${p.status === 'fell_through' ? 'line-through muted' : ''}`}
                      >
                        {money(p.feeAmount, p.feeCurrency)}
                      </span>
                      <PlacementPill status={p.status} />
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </Section>
        </>
      )}
    </div>
  );
}
