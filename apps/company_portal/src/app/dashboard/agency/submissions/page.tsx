import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { SUBMISSION_STATUSES, submissionTone } from '@/lib/agency';
import { ErrorNote, FilterChips, Notice, PageHeader, qs } from '../ui';
import { BASE, first, loadSubmissions, type SearchParams } from './lib';
import { SubmissionCard, WorkTabs } from './row';

export const metadata: Metadata = { title: 'Submissions · Omelo' };

export default async function SubmissionsPage({ searchParams }: { searchParams: SearchParams }) {
  const sp = await searchParams;
  const status = first(sp.status) ?? 'all';
  const order = first(sp.order) ?? '';
  const client = first(sp.client) ?? '';

  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  const [subs, ordersRes, clientsRes] = await Promise.all([
    loadSubmissions(supabase, ctx.companyId),
    supabase
      .from('job_orders')
      .select('id, reference, title, client_id')
      .eq('agency_id', ctx.companyId)
      .order('created_at', { ascending: false }),
    supabase.from('agency_clients').select('id, name').eq('agency_id', ctx.companyId).order('name'),
  ]);

  const orders = ordersRes.data ?? [];
  const clients = clientsRes.data ?? [];
  const clientOfOrder = new Map(orders.map((o) => [o.id, o.client_id]));

  // ?client= accepts the client's id or its name.
  const clientMatch = client
    ? clients.find((c) => c.id === client) ?? clients.find((c) => c.name.toLowerCase() === client.toLowerCase())
    : null;

  const scoped = subs.rows.filter((r) => {
    if (order && r.jobOrderId !== order) return false;
    if (client) {
      if (clientMatch) return clientOfOrder.get(r.jobOrderId) === clientMatch.id;
      return (r.client ?? '').toLowerCase() === client.toLowerCase();
    }
    return true;
  });
  const shown = status === 'all' ? scoped : scoped.filter((r) => r.status === status);

  const counts = new Map<string, number>();
  for (const r of scoped) counts.set(r.status, (counts.get(r.status) ?? 0) + 1);
  const chipOptions = [
    { value: 'all', label: 'All', count: scoped.length },
    ...SUBMISSION_STATUSES.map((s) => ({ value: s, label: submissionTone(s).label, count: counts.get(s) ?? 0 })),
  ];

  const filtered = !!(order || client);

  return (
    <div className="space-y-5 max-w-5xl">
      <PageHeader
        title="Submissions"
        subtitle="Candidates you put forward to clients, each with the candidate’s consent for that job order."
        action={
          <Link href={`${BASE}/candidates?status=accepted`} className="btn btn-ghost w-full sm:w-auto">
            Ready to submit
          </Link>
        }
      />
      <WorkTabs active="submissions" />

      <form method="get" className="card p-4 flex flex-wrap gap-3 items-end">
        {status !== 'all' && <input type="hidden" name="status" value={status} />}
        <div className="flex-1 min-w-[12rem]">
          <label className="label" htmlFor="f-order">
            Job order
          </label>
          <select id="f-order" name="order" className="input" defaultValue={order}>
            <option value="">All job orders</option>
            {orders.map((o) => (
              <option key={o.id} value={o.id}>
                {o.reference} · {o.title}
              </option>
            ))}
          </select>
        </div>
        <div className="flex-1 min-w-[12rem]">
          <label className="label" htmlFor="f-client">
            Client
          </label>
          <select id="f-client" name="client" className="input" defaultValue={clientMatch?.id ?? client}>
            <option value="">All clients</option>
            {clients.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
            {client && !clientMatch && <option value={client}>{client}</option>}
          </select>
        </div>
        <div className="flex gap-2 flex-wrap w-full sm:w-auto">
          <button className="btn btn-primary flex-1 sm:flex-none">Apply</button>
          {filtered && (
            <Link href={`${BASE}/submissions${qs({ status })}`} className="btn btn-ghost flex-1 sm:flex-none">
              Clear
            </Link>
          )}
        </div>
      </form>

      <FilterChips
        label="Filter by status"
        options={chipOptions}
        active={status}
        hrefFor={(v) => `${BASE}/submissions${qs({ status: v, order, client })}`}
      />

      {subs.error ? (
        <ErrorNote label="submissions" message={subs.error} />
      ) : subs.rows.length === 0 ? (
        <Notice
          title="No submissions yet"
          action={
            <Link href={`${BASE}/candidates`} className="btn btn-ghost">
              Go to candidates
            </Link>
          }
        >
          Submissions start from Candidates: once a candidate gives consent for a job order, use Submit to send
          exactly what they agreed to share to the client.
        </Notice>
      ) : shown.length === 0 ? (
        <Notice title="Nothing matches these filters">
          Try another status{filtered ? ', job order or client' : ''}.
        </Notice>
      ) : (
        <ul className="grid gap-3">
          {shown.map((r) => (
            <SubmissionCard key={r.id} row={r} />
          ))}
        </ul>
      )}
    </div>
  );
}
