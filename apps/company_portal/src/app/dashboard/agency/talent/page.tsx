import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { agencyCan, onlyRoles } from '@/lib/agency';
import { UUID_RE } from '@/lib/talent';
import { ErrorNote, NotVerifiedAgency, Notice, PageHeader } from '../ui';
import { ORDER_SUMMARY_SELECT, agencySummary, myDisplayName, toOrderSummary } from '../order-summary';
import AgencyTalentSearch, { type OrderOption } from './agency-search';

export const metadata: Metadata = { title: 'Talent search · Omelo' };

export default async function AgencyTalentPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const wanted = typeof sp.order === 'string' && UUID_RE.test(sp.order) ? sp.order : null;
  const ctx = (await getCompanyContext())!;
  const header = (
    <PageHeader
      title="Talent search"
      subtitle="Find people for a job order. Only workers who let recruiters see their profile appear."
    />
  );

  if (!agencyCan(ctx, 'search_talent'))
    return (
      <div className="space-y-6">
        {header}
        <Notice title="Search is for owners, admins, recruiters and sourcers">
          {onlyRoles('search_talent', 'search for candidates')} Ask an owner or admin if you need it.
        </Notice>
      </div>
    );

  const supabase = await createClient();
  const [ordersRes, poolsRes, profRes, skillsRes, countriesRes, me] = await Promise.all([
    supabase
      .from('job_orders')
      .select(`${ORDER_SUMMARY_SELECT}, profession_id`)
      .eq('agency_id', ctx.companyId)
      .in('status', ['draft', 'open', 'on_hold'])
      .order('updated_at', { ascending: false }),
    supabase.from('talent_pools').select('id, name').eq('company_id', ctx.companyId).order('name'),
    supabase.from('professions').select('id, name').eq('status', 'active').order('name'),
    supabase.from('skills').select('id, name').eq('status', 'active').order('name'),
    supabase.from('country_policies').select('country_code, name').eq('supported', true).order('name'),
    myDisplayName(supabase),
  ]);

  const orders: OrderOption[] = (ordersRes.data ?? []).map((o) => ({
    ...toOrderSummary(o),
    status: o.status,
    professionId: o.profession_id,
  }));

  let body: React.ReactNode;
  if (ordersRes.error) body = <ErrorNote label="your job orders" message={ordersRes.error.message} />;
  else if (orders.length === 0)
    body = (
      <Notice
        title="Create a job order first"
        action={
          agencyCan(ctx, 'create_job_order') ? (
            <Link href="/dashboard/agency/job-orders/new" className="btn btn-primary">
              New job order
            </Link>
          ) : undefined
        }
      >
        Search ranks people against an open job order, and consent is always asked for a specific order.
      </Notice>
    );
  else {
    const initial = orders.find((o) => o.id === wanted)?.id ?? orders[0].id;
    body = (
      <AgencyTalentSearch
        key={initial}
        orders={orders}
        initialOrderId={initial}
        pools={poolsRes.data ?? []}
        professions={(profRes.data ?? []).map((p) => ({ id: p.id, label: p.name }))}
        skills={(skillsRes.data ?? []).map((s) => ({ id: s.id, label: s.name }))}
        countries={(countriesRes.data ?? []).map((c) => ({ id: c.country_code, label: c.name }))}
        agency={agencySummary(ctx)}
        recruiterName={me}
        canRequest={agencyCan(ctx, 'request_consent')}
        canSave={agencyCan(ctx, 'search_talent')}
      />
    );
  }

  return (
    <div className="space-y-6">
      {header}
      {!ctx.isVerified && <NotVerifiedAgency />}
      {wanted && orders.length > 0 && !orders.some((o) => o.id === wanted) && (
        <p className="text-sm" style={{ color: 'var(--color-warn)' }}>
          That job order is filled, closed or cancelled, so it cannot be searched for. Showing your latest open order.
        </p>
      )}
      {body}
    </div>
  );
}
