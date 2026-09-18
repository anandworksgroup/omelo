import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { parseConsents, parseDashboard, type ConsentRow, type SubmissionRow } from '@/lib/agency';
import { ErrorNote, PageHeader, Section, Tile } from '../ui';
import { BASE, loadSubmissions, rate } from '../submissions/lib';
import { WorkTabs } from '../submissions/row';

export const metadata: Metadata = { title: 'Analytics · Omelo' };

/** Consent statuses that mean the candidate said yes (matches omelo_agency_dashboard). */
const ACCEPTED = ['accepted', 'active', 'expired', 'revoked'];
const accepted = (c: ConsentRow) => ACCEPTED.includes(c.status) && !!c.respondedAt;
const placed = (s: SubmissionRow) => !!s.placement && s.placement.status !== 'fell_through';

type Col = { key: string; label: string };
type Row = { id: string; name: string; href?: string; values: Record<string, number> };

function Breakdown({ title, cols, rows, empty }: { title: string; cols: Col[]; rows: Row[]; empty: string }) {
  return (
    <Section title={title}>
      {rows.length === 0 ? (
        <p className="text-sm muted">{empty}</p>
      ) : (
        <div className="overflow-x-auto -mx-4 sm:mx-0 px-4 sm:px-0">
          <table className="w-full text-sm min-w-[28rem]">
            <thead>
              <tr className="text-left text-xs muted border-b hairline">
                <th className="py-2 pr-3 font-medium">Name</th>
                {cols.map((c) => (
                  <th key={c.key} className="py-2 px-2 font-medium text-right whitespace-nowrap">
                    {c.label}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.id} className="border-b hairline last:border-0">
                  <td className="py-2 pr-3 max-w-[16rem] break-words">
                    {r.href ? (
                      <Link href={r.href} className="hover:underline">
                        {r.name}
                      </Link>
                    ) : (
                      r.name
                    )}
                  </td>
                  {cols.map((c) => (
                    <td key={c.key} className="py-2 px-2 text-right tabular-nums">
                      {r.values[c.key] ?? 0}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Section>
  );
}

function bump(m: Map<string, Row>, id: string, name: string, key: string, href?: string) {
  const r = m.get(id) ?? { id, name, href, values: {} };
  r.values[key] = (r.values[key] ?? 0) + 1;
  m.set(id, r);
}

const sorted = (m: Map<string, Row>, key: string) =>
  [...m.values()].sort((a, b) => (b.values[key] ?? 0) - (a.values[key] ?? 0) || a.name.localeCompare(b.name));

export default async function AnalyticsPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  const [dash, cons, subs] = await Promise.all([
    supabase.rpc('omelo_agency_dashboard', { p_agency: ctx.companyId }),
    supabase.rpc('omelo_agency_candidates', { p_agency: ctx.companyId }),
    loadSubmissions(supabase, ctx.companyId),
  ]);
  const d = parseDashboard(dash.data);
  const consents = cons.error ? [] : parseConsents(cons.data);

  const funnel = [
    { label: 'Consent requests', value: d.consentRequests },
    { label: 'Consent given', value: d.consentsAccepted },
    { label: 'Submitted to clients', value: d.submissions },
    { label: 'Reached interview', value: d.interviews },
    { label: 'Received an offer', value: d.offers },
    { label: 'Placed', value: d.placements },
  ];
  const top = Math.max(1, ...funnel.map((f) => f.value));

  // All-time breakdowns.
  const byOrder = new Map<string, Row>();
  const byClient = new Map<string, Row>();
  const byRecruiter = new Map<string, Row>();
  const orderName = (ref: string | null, pos: string | null) => [ref, pos].filter(Boolean).join(' · ') || 'Job order';

  for (const c of consents) {
    const href = c.jobOrderId ? `${BASE}/job-orders/${c.jobOrderId}` : undefined;
    const name = orderName(c.jobOrder, c.position);
    bump(byOrder, c.jobOrderId || name, name, 'requests', href);
    if (accepted(c)) bump(byOrder, c.jobOrderId || name, name, 'accepted', href);
    const rec = c.recruiter ?? 'Unassigned';
    bump(byRecruiter, rec, rec, 'requests');
  }
  for (const s of subs.rows) {
    const href = s.jobOrderId ? `${BASE}/job-orders/${s.jobOrderId}` : undefined;
    const name = orderName(s.jobOrder, s.position);
    bump(byOrder, s.jobOrderId || name, name, 'submitted', href);
    if (s.status === 'hired') bump(byOrder, s.jobOrderId || name, name, 'hired', href);
    const client = s.client ?? 'Client';
    bump(byClient, client, client, 'submissions', `${BASE}/submissions?client=${encodeURIComponent(client)}`);
    if (s.status === 'hired') bump(byClient, client, client, 'hires');
    const rec = s.recruiter ?? 'Unassigned';
    bump(byRecruiter, rec, rec, 'submissions');
    if (placed(s)) bump(byRecruiter, rec, rec, 'placements');
  }

  return (
    <div className="space-y-5 max-w-5xl">
      <PageHeader title="Analytics" subtitle={`How your agency is doing. Tiles and funnel cover the last ${d.days} days.`} />
      <WorkTabs active="analytics" />

      {dash.error ? (
        <ErrorNote label="the last 30 days" message={dash.error.message} />
      ) : (
        <>
          <div className="grid gap-3 grid-cols-2 lg:grid-cols-4">
            <Tile label="Active job orders" value={d.activeJobOrders} hint={`${d.openings} openings`} />
            <Tile label="Candidates sourced" value={d.candidatesSourced} hint="asked or saved to a pool" />
            <Tile label="Consent requests" value={d.consentRequests} hint={`${d.consentsAccepted} said yes`} />
            <Tile label="Submissions" value={d.submissions} href={`${BASE}/submissions`} />
            <Tile label="Interviews" value={d.interviews} hint="of those submissions" href={`${BASE}/interviews`} />
            <Tile label="Offers" value={d.offers} href={`${BASE}/offers`} />
            <Tile label="Placements" value={d.placements} hint="excluding fell through" href={`${BASE}/placements`} />
          </div>

          <Section title="Funnel, last 30 days">
            <p className="text-xs muted">Each percentage is the share of the step above it.</p>
            <ol className="space-y-3">
              {funnel.map((f, i) => {
                const r = i === 0 ? null : rate(f.value, funnel[i - 1].value);
                return (
                  <li key={f.label} className="min-w-0">
                    <div className="flex flex-wrap items-baseline gap-x-2 text-sm">
                      <span className="font-medium flex-1 min-w-0 break-words">{f.label}</span>
                      <span className="tabular-nums font-bold">{f.value}</span>
                      {i > 0 && <span className="text-xs muted tabular-nums w-12 text-right">{r == null ? '—' : `${r}%`}</span>}
                    </div>
                    <div className="h-2.5 rounded-full mt-1" style={{ background: 'var(--surface)' }}>
                      <div
                        className="h-2.5 rounded-full"
                        style={{
                          width: `${Math.max(f.value ? 2 : 0, (f.value / top) * 100)}%`,
                          background: 'var(--color-brand-600)',
                        }}
                      />
                    </div>
                  </li>
                );
              })}
            </ol>
          </Section>
        </>
      )}

      <h2 className="font-bold text-lg pt-2">All time</h2>
      {cons.error && <ErrorNote label="consent requests" message={cons.error.message} />}
      {subs.error && <ErrorNote label="submissions" message={subs.error} />}

      <Breakdown
        title="By job order"
        empty="No consent requests or submissions yet."
        cols={[
          { key: 'requests', label: 'Requests' },
          { key: 'accepted', label: 'Consent given' },
          { key: 'submitted', label: 'Submitted' },
          { key: 'hired', label: 'Hired' },
        ]}
        rows={sorted(byOrder, 'submitted')}
      />
      <Breakdown
        title="By client"
        empty="No submissions yet."
        cols={[
          { key: 'submissions', label: 'Submissions' },
          { key: 'hires', label: 'Hires' },
        ]}
        rows={sorted(byClient, 'submissions')}
      />
      <Breakdown
        title="By recruiter"
        empty="No activity yet."
        cols={[
          { key: 'requests', label: 'Requests' },
          { key: 'submissions', label: 'Submissions' },
          { key: 'placements', label: 'Placements' },
        ]}
        rows={sorted(byRecruiter, 'submissions')}
      />
    </div>
  );
}
