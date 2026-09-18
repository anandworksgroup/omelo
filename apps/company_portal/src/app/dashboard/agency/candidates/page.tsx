import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { CONSENT_STATUS, agencyCan, parseConsents, type ConsentStatus } from '@/lib/agency';
import { requestNow } from '@/lib/hiring';
import { UUID_RE } from '@/lib/talent';
import { ErrorNote, FilterChips, Notice, PageHeader, qs } from '../ui';
import ConsentRowItem, { type OrderFacts } from './consent-row';

export const metadata: Metadata = { title: 'Candidates · Omelo' };

const ORDER: ConsentStatus[] = ['accepted', 'requested', 'active', 'declined', 'expired', 'revoked', 'withdrawn'];

export default async function AgencyCandidatesPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const status = typeof sp.status === 'string' && (ORDER as string[]).includes(sp.status) ? sp.status : 'all';
  const orderFilter = typeof sp.order === 'string' && UUID_RE.test(sp.order) ? sp.order : null;
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const [consentsRes, ordersRes, mineRes] = await Promise.all([
    supabase.rpc('omelo_agency_candidates', { p_agency: ctx.companyId, p_job_order: orderFilter ?? undefined }),
    supabase
      .from('job_orders')
      .select('id, reference, title, status, client_job_id')
      .eq('agency_id', ctx.companyId)
      .order('updated_at', { ascending: false }),
    user
      ? supabase.from('job_order_recruiters').select('job_order_id').eq('person_id', user.id)
      : Promise.resolve({ data: [] as { job_order_id: string }[] }),
  ]);

  const all = parseConsents(consentsRes.data ?? null);
  const mine = new Set((mineRes.data ?? []).map((r) => r.job_order_id));
  const facts = new Map<string, OrderFacts>(
    (ordersRes.data ?? []).map((o) => [o.id, { status: o.status, clientJobId: o.client_job_id, assignedToMe: mine.has(o.id) }])
  );
  const rows = (status === 'all' ? all : all.filter((c) => c.status === status)).sort(
    (a, b) => ORDER.indexOf(a.status as ConsentStatus) - ORDER.indexOf(b.status as ConsentStatus)
  );
  const nowMs = requestNow();
  const activeOrder = orderFilter ? (ordersRes.data ?? []).find((o) => o.id === orderFilter) : null;

  return (
    <div className="space-y-6 max-w-4xl">
      <PageHeader
        title="Candidates"
        subtitle={
          activeOrder ? (
            <>
              Consent requests for <strong>{activeOrder.title}</strong> ({activeOrder.reference}) ·{' '}
              <Link href={`/dashboard/agency/candidates${qs({ status })}`} className="underline">
                all job orders
              </Link>
            </>
          ) : (
            'Everyone you asked to represent. You can submit a candidate only while their consent is in force.'
          )
        }
      />

      <FilterChips
        label="Filter by consent"
        active={status}
        hrefFor={(v) => `/dashboard/agency/candidates${qs({ status: v, order: orderFilter })}`}
        options={[
          { value: 'all', label: 'All', count: all.length },
          ...ORDER.map((s) => ({ value: s, label: CONSENT_STATUS[s].label, count: all.filter((c) => c.status === s).length })),
        ]}
      />

      {(ordersRes.data ?? []).length > 1 && (
        <form className="flex flex-wrap gap-2 items-end" action="/dashboard/agency/candidates">
          {status !== 'all' && <input type="hidden" name="status" value={status} />}
          <div className="flex-1 min-w-[12rem] sm:max-w-sm">
            <label className="label" htmlFor="cand-order">
              Job order
            </label>
            <select id="cand-order" name="order" className="input" defaultValue={orderFilter ?? ''}>
              <option value="">All job orders</option>
              {(ordersRes.data ?? []).map((o) => (
                <option key={o.id} value={o.id}>
                  {o.reference} · {o.title}
                </option>
              ))}
            </select>
          </div>
          <button className="btn btn-ghost w-full sm:w-auto">Filter</button>
        </form>
      )}

      {consentsRes.error ? (
        <ErrorNote label="candidates" message={consentsRes.error.message} />
      ) : rows.length === 0 ? (
        <Notice
          title={all.length ? 'Nobody with this status' : 'No consent requests yet'}
          action={
            !all.length && agencyCan(ctx, 'search_talent') ? (
              <Link href="/dashboard/agency/talent" className="btn btn-primary">
                Find candidates
              </Link>
            ) : undefined
          }
        >
          {all.length
            ? 'Try another filter.'
            : 'Search for candidates on a job order and ask for their consent. People who accept appear here, ready to submit.'}
        </Notice>
      ) : (
        <ul className="space-y-3">
          {rows.map((c) => (
            <ConsentRowItem
              key={c.consentId}
              row={c}
              nowMs={nowMs}
              canSubmit={agencyCan(ctx, 'submit')}
              canWithdraw={agencyCan(ctx, 'request_consent')}
              canViewDetails={agencyCan(ctx, 'view_candidate_details')}
              isAdmin={agencyCan(ctx, 'manage_agency')}
              order={facts.get(c.jobOrderId)}
            />
          ))}
        </ul>
      )}

      <p className="hint">
        Requests nobody answers expire after 7 days. Consent lasts for the period the candidate agreed to, and they can
        withdraw it at any time before the client starts considering them.
      </p>
    </div>
  );
}
