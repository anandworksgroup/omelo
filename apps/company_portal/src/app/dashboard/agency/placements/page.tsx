import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { PLACEMENT_STATUS, agencyCan, daysLeft, onlyRoles } from '@/lib/agency';
import { requestNow } from '@/lib/hiring';
import { ErrorNote, FilterChips, Notice, PageHeader, PlacementPill, Why, dateText, qs } from '../ui';
import { BASE, first, money, type SearchParams } from '../submissions/lib';
import { WorkTabs } from '../submissions/row';
import { loadPlacements } from './data';
import { EditPlacement } from './placement-editor';

export const metadata: Metadata = { title: 'Placements · Omelo' };

function guaranteeText(iso: string | null, now: number, status: string) {
  if (!iso) return null;
  const d = daysLeft(iso, now);
  if (d == null || status === 'fell_through' || status === 'completed') return null;
  if (d < 0) return 'guarantee over';
  if (d === 0) return 'ends today';
  return `${d} day${d === 1 ? '' : 's'} left`;
}

export default async function PlacementsPage({ searchParams }: { searchParams: SearchParams }) {
  const sp = await searchParams;
  const status = first(sp.status) ?? 'all';
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const canManage = agencyCan(ctx, 'manage_placements');
  const now = requestNow();

  const { items, error } = await loadPlacements(supabase, ctx.companyId);
  const counts = new Map<string, number>();
  for (const p of items) counts.set(p.status, (counts.get(p.status) ?? 0) + 1);
  const shown = status === 'all' ? items : items.filter((p) => p.status === status);

  return (
    <div className="space-y-5 max-w-5xl">
      <PageHeader
        title="Placements"
        subtitle="Candidates you placed. Created automatically when a client hires one of your submissions, or when you record a hire."
      />
      <WorkTabs active="placements" />
      {!canManage && <Why>{onlyRoles('manage_placements', 'update placements')}</Why>}

      <FilterChips
        label="Filter by status"
        active={status}
        hrefFor={(v) => `${BASE}/placements${qs({ status: v })}`}
        options={[
          { value: 'all', label: 'All', count: items.length },
          ...Object.entries(PLACEMENT_STATUS).map(([k, t]) => ({ value: k, label: t.label, count: counts.get(k) ?? 0 })),
        ]}
      />

      {error && !items.length ? (
        <ErrorNote label="placements" message={error} />
      ) : items.length === 0 ? (
        <Notice
          title="No placements yet"
          action={
            <Link href={`${BASE}/offers`} className="btn btn-ghost">
              See offers
            </Link>
          }
        >
          A placement appears when a client on Omelo hires one of your candidates, or when you record “Hired” on a
          submission for an off-platform client.
        </Notice>
      ) : shown.length === 0 ? (
        <Notice title="No placements with this status">Choose another status above.</Notice>
      ) : (
        <>
        {error && <ErrorNote label="candidate names" message={error} />}
        <ul className="grid gap-3">
          {shown.map((p) => {
            const g = guaranteeText(p.guaranteeEndsOn, now, p.status);
            return (
              <li key={p.id} id={`p-${p.id}`} className="card p-4 min-w-0 scroll-mt-20">
                <div className="flex items-start gap-2 flex-wrap">
                  <div className="flex-1 min-w-0">
                    <Link href={`${BASE}/submissions/${p.submissionId}`} className="font-semibold hover:underline break-words">
                      {p.candidate}
                      {p.candidateLabel && <span className="font-normal muted"> as {p.candidateLabel}</span>}
                    </Link>
                    <p className="text-sm muted break-words mt-0.5">
                      {[p.title ?? p.position, p.jobOrder, p.client].filter(Boolean).join(' · ')}
                    </p>
                  </div>
                  <PlacementPill status={p.status} />
                </div>
                <dl className="grid gap-x-4 gap-y-2 mt-3 text-sm grid-cols-2 sm:grid-cols-3">
                  <div className="min-w-0">
                    <dt className="text-xs muted">Start date</dt>
                    <dd>{dateText(p.startDate)}</dd>
                  </div>
                  <div className="min-w-0">
                    <dt className="text-xs muted">Guarantee ends</dt>
                    <dd>
                      {dateText(p.guaranteeEndsOn)}
                      {g && <span className="block text-xs muted">{g}</span>}
                    </dd>
                  </div>
                  <div className="min-w-0">
                    <dt className="text-xs muted">Fee</dt>
                    <dd className={p.feeAmount == null ? 'muted' : 'font-medium'}>{money(p.feeAmount, p.feeCurrency)}</dd>
                  </div>
                </dl>
                {p.notes && <p className="text-sm mt-3 whitespace-pre-line break-words">{p.notes}</p>}
                {canManage && (
                  <div className="mt-3 flex flex-wrap gap-2">
                    <EditPlacement
                      p={{
                        id: p.id,
                        status: p.status,
                        startDate: p.startDate,
                        guaranteeEndsOn: p.guaranteeEndsOn,
                        feeAmount: p.feeAmount,
                        feeCurrency: p.feeCurrency,
                        notes: p.notes,
                        candidate: p.candidate,
                      }}
                    />
                  </div>
                )}
              </li>
            );
          })}
        </ul>
        </>
      )}
    </div>
  );
}
