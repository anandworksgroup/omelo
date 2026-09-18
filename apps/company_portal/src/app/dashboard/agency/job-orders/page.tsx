import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { JOB_ORDER_STATUS, JOB_ORDER_STATUSES, PRIORITIES, PRIORITY, agencyCan, onlyRoles } from '@/lib/agency';
import { formatPay, timeAgo } from '@/lib/format';
import { UUID_RE } from '@/lib/talent';
import { ErrorNote, FilterChips, Notice, OrderStatusPill, PageHeader, PriorityPill, Why, qs } from '../ui';

export const metadata: Metadata = { title: 'Job orders · Omelo' };

const ACTIVE = ['draft', 'open', 'on_hold'];

export default async function JobOrdersPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const pick = (k: string) => (typeof sp[k] === 'string' ? (sp[k] as string) : null);
  const status = pick('status');
  const statusFilter = status && (status === 'active' || (JOB_ORDER_STATUSES as readonly string[]).includes(status)) ? status : 'active';
  const priority = pick('priority');
  const priorityFilter = priority && (PRIORITIES as readonly string[]).includes(priority) ? priority : 'all';
  const client = pick('client');
  const clientFilter = client && UUID_RE.test(client) ? client : null;

  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const [ordersRes, clientsRes, consentsRes, subsRes] = await Promise.all([
    supabase
      .from('job_orders')
      .select(
        'id, reference, title, client_id, status, priority, openings, location_text, pay_min, pay_max, pay_period, pay_currency, closing_date, client_job_id, updated_at, agency_clients ( name )'
      )
      .eq('agency_id', ctx.companyId)
      .order('updated_at', { ascending: false }),
    supabase.from('agency_clients').select('id, name').eq('agency_id', ctx.companyId).order('name'),
    supabase.from('candidate_consents').select('job_order_id, status').eq('agency_id', ctx.companyId),
    supabase.from('candidate_submissions').select('job_order_id, status').eq('agency_id', ctx.companyId),
  ]);

  const all = ordersRes.data ?? [];
  const count = (rows: { job_order_id: string; status: string }[] | null, id: string, statuses?: string[]) =>
    (rows ?? []).filter((r) => r.job_order_id === id && (!statuses || statuses.includes(r.status))).length;

  const byStatus = (s: string) => (s === 'active' ? all.filter((o) => ACTIVE.includes(o.status)) : all.filter((o) => o.status === s));
  const rows = byStatus(statusFilter)
    .filter((o) => priorityFilter === 'all' || o.priority === priorityFilter)
    .filter((o) => !clientFilter || o.client_id === clientFilter);

  const href = (over: Record<string, string | null>) =>
    `/dashboard/agency/job-orders${qs({
      status: statusFilter === 'active' ? null : statusFilter,
      priority: priorityFilter,
      client: clientFilter,
      ...over,
    })}`;
  const canCreate = agencyCan(ctx, 'create_job_order');

  return (
    <div className="space-y-6 max-w-5xl">
      <PageHeader
        title="Job orders"
        subtitle="Roles you are recruiting for, one per client request."
        action={
          canCreate ? (
            <Link href="/dashboard/agency/job-orders/new" className="btn btn-primary w-full sm:w-auto">
              New job order
            </Link>
          ) : undefined
        }
      />
      {!canCreate && <Why>{onlyRoles('create_job_order', 'create job orders')}</Why>}

      <div className="space-y-2">
        <FilterChips
          label="Filter by status"
          active={statusFilter}
          hrefFor={(v) => href({ status: v === 'active' ? null : v })}
          options={[
            { value: 'active', label: 'Active', count: byStatus('active').length },
            ...JOB_ORDER_STATUSES.map((s) => ({ value: s, label: JOB_ORDER_STATUS[s].label, count: byStatus(s).length })),
          ]}
        />
        <FilterChips
          label="Filter by priority"
          active={priorityFilter}
          hrefFor={(v) => href({ priority: v })}
          options={[{ value: 'all', label: 'Any priority' }, ...PRIORITIES.map((p) => ({ value: p, label: PRIORITY[p].label }))]}
        />
        {(clientsRes.data ?? []).length > 1 && (
          <form className="flex flex-wrap gap-2 items-end" action="/dashboard/agency/job-orders">
            {statusFilter !== 'active' && <input type="hidden" name="status" value={statusFilter} />}
            {priorityFilter !== 'all' && <input type="hidden" name="priority" value={priorityFilter} />}
            <div className="flex-1 min-w-[12rem] sm:max-w-xs">
              <label className="label" htmlFor="jo-client">
                Client
              </label>
              <select id="jo-client" name="client" className="input" defaultValue={clientFilter ?? ''}>
                <option value="">All clients</option>
                {(clientsRes.data ?? []).map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                  </option>
                ))}
              </select>
            </div>
            <button className="btn btn-ghost w-full sm:w-auto">Filter</button>
          </form>
        )}
      </div>

      {ordersRes.error ? (
        <ErrorNote label="job orders" message={ordersRes.error.message} />
      ) : rows.length === 0 ? (
        <Notice title={all.length ? 'No job orders match' : 'No job orders yet'}>
          {all.length
            ? 'Try other filters.'
            : 'Create a job order for each role a client asks you to fill. Then search for candidates and ask for their consent.'}
        </Notice>
      ) : (
        <ul className="space-y-3">
          {rows.map((o) => {
            const asked = count(consentsRes.data, o.id);
            const accepted = count(consentsRes.data, o.id, ['accepted', 'active']);
            const submitted = count(subsRes.data, o.id);
            const hired = count(subsRes.data, o.id, ['hired']);
            return (
              <li key={o.id}>
                <Link href={`/dashboard/agency/job-orders/${o.id}`} className="card p-4 block hover:opacity-90 space-y-2">
                  <div className="flex items-start gap-2 flex-wrap">
                    <div className="flex-1 min-w-[12rem]">
                      <p className="font-bold break-words">{o.title}</p>
                      <p className="text-sm muted break-words">
                        {o.reference} · {(o.agency_clients as unknown as { name: string } | null)?.name ?? 'Client'}
                        {o.location_text ? ` · ${o.location_text}` : ''}
                      </p>
                    </div>
                    <PriorityPill priority={o.priority} />
                    <OrderStatusPill status={o.status} />
                  </div>
                  <p className="text-xs muted break-words">
                    {o.openings} opening{o.openings === 1 ? '' : 's'} ·{' '}
                    {formatPay({ min: o.pay_min, max: o.pay_max, period: o.pay_period, currency: o.pay_currency })} ·{' '}
                    {o.client_job_id ? 'connected to the client’s job' : 'client tracks off-platform'} · updated{' '}
                    {timeAgo(o.updated_at)}
                  </p>
                  <p className="text-xs break-words">
                    <span className="font-semibold">{asked}</span> asked · <span className="font-semibold">{accepted}</span>{' '}
                    consented · <span className="font-semibold">{submitted}</span> submitted ·{' '}
                    <span className="font-semibold">{hired}</span> hired
                  </p>
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
