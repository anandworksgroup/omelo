import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { agencyCan, parseConsents, parseDashboard } from '@/lib/agency';
import { timeAgo } from '@/lib/format';
import { ConsentPill, ErrorNote, NotVerifiedAgency, OrderStatusPill, PageHeader, PriorityPill, Section, Tile } from './ui';

export const metadata: Metadata = { title: 'Agency dashboard · Omelo' };

export default async function AgencyDashboardPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  const [dashRes, consentsRes, ordersRes, clientsRes] = await Promise.all([
    supabase.rpc('omelo_agency_dashboard', { p_agency: ctx.companyId }),
    supabase.rpc('omelo_agency_candidates', { p_agency: ctx.companyId }),
    supabase
      .from('job_orders')
      .select('id, reference, title, status, priority, openings, agency_clients ( name )')
      .eq('agency_id', ctx.companyId)
      .in('status', ['open', 'on_hold'])
      .order('updated_at', { ascending: false })
      .limit(6),
    supabase.from('agency_clients').select('id', { count: 'exact', head: true }).eq('agency_id', ctx.companyId),
  ]);

  const d = parseDashboard(dashRes.data ?? null);
  const consents = parseConsents(consentsRes.data ?? null);
  const readyToSubmit = consents.filter((c) => c.status === 'accepted' && !c.submission);
  const waiting = consents.filter((c) => c.status === 'requested');
  const orders = ordersRes.data ?? [];
  const clientCount = clientsRes.count ?? 0;
  const acceptRate = d.consentRequests ? Math.round((d.consentsAccepted / d.consentRequests) * 100) : null;
  const canCreate = agencyCan(ctx, 'create_job_order');

  return (
    <div className="space-y-6">
      <PageHeader
        title={ctx.companyName}
        subtitle={
          <>
            {ctx.isIndependent ? 'Independent recruiter' : 'Recruitment agency'} · last {d.days} days
          </>
        }
        action={
          canCreate ? (
            <Link href="/dashboard/agency/job-orders/new" className="btn btn-primary w-full sm:w-auto">
              New job order
            </Link>
          ) : undefined
        }
      />

      {sp.welcome === '1' && (
        <div className="card p-4 sm:p-5" role="status" style={{ borderTop: '3px solid var(--color-brand-600)' }}>
          <p className="font-semibold">Your agency is ready</p>
          <ol className="text-sm muted mt-2 space-y-1 list-decimal pl-5">
            <li>
              <Link href="/dashboard/agency/clients" className="underline">
                Add your clients
              </Link>{' '}
              and ask the ones already on Omelo to link with you.
            </li>
            <li>Create a job order for each role you are recruiting for.</li>
            <li>
              <Link href="/dashboard/team" className="underline">
                Invite your team
              </Link>{' '}
              — recruiters, sourcers and coordinators.
            </li>
            <li>Once Omelo verifies you, search for candidates and ask for their consent.</li>
          </ol>
        </div>
      )}

      {!ctx.isVerified && <NotVerifiedAgency />}

      {dashRes.error ? (
        <ErrorNote label="your dashboard" message={dashRes.error.message} />
      ) : (
        <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-5 gap-3">
          <Tile label="Active job orders" value={d.activeJobOrders} hint={`${d.openings} openings`} href="/dashboard/agency/job-orders" />
          <Tile label="Candidates sourced" value={d.candidatesSourced} hint="asked or saved" href="/dashboard/agency/pools" />
          <Tile
            label="Consent requests"
            value={d.consentRequests}
            hint={acceptRate != null ? `${d.consentsAccepted} accepted (${acceptRate}%)` : `${d.consentsAccepted} accepted`}
            href="/dashboard/agency/candidates"
          />
          <Tile label="Submissions" value={d.submissions} href="/dashboard/agency/submissions" />
          <Tile label="Interviews" value={d.interviews} href="/dashboard/agency/interviews" />
          <Tile label="Offers" value={d.offers} href="/dashboard/agency/offers" />
          <Tile label="Placements" value={d.placements} href="/dashboard/agency/placements" />
          <Tile label="Clients" value={clientCount} href="/dashboard/agency/clients" />
        </div>
      )}

      <div className="grid gap-6 lg:grid-cols-2 items-start">
        <Section
          title="Ready to submit"
          aside={
            <Link href="/dashboard/agency/candidates?status=accepted" className="text-sm underline muted">
              All
            </Link>
          }
        >
          {consentsRes.error ? (
            <ErrorNote label="candidates" message={consentsRes.error.message} />
          ) : readyToSubmit.length === 0 ? (
            <p className="text-sm muted">
              Nobody is waiting to be submitted. When a candidate accepts your request, they appear here.
              {waiting.length > 0 ? ` ${waiting.length} request${waiting.length === 1 ? ' is' : 's are'} still waiting for a reply.` : ''}
            </p>
          ) : (
            <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
              {readyToSubmit.slice(0, 6).map((c) => (
                <li key={c.consentId} className="py-2.5 flex items-center gap-3 flex-wrap">
                  <div className="flex-1 min-w-[10rem]">
                    <Link href={`/dashboard/agency/candidates/${c.consentId}`} className="font-semibold text-sm hover:underline break-words">
                      {c.name}
                    </Link>
                    <p className="text-xs muted break-words">
                      {c.position} · {c.client} · accepted {timeAgo(c.respondedAt)}
                    </p>
                  </div>
                  <ConsentPill status={c.status} />
                </li>
              ))}
            </ul>
          )}
        </Section>

        <Section
          title="Open job orders"
          aside={
            <Link href="/dashboard/agency/job-orders" className="text-sm underline muted">
              All
            </Link>
          }
        >
          {ordersRes.error ? (
            <ErrorNote label="job orders" message={ordersRes.error.message} />
          ) : orders.length === 0 ? (
            <p className="text-sm muted">
              No open job orders.{' '}
              {canCreate ? (
                <Link href="/dashboard/agency/job-orders/new" className="underline">
                  Create one
                </Link>
              ) : (
                'Recruiters, admins and owners create them.'
              )}
            </p>
          ) : (
            <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
              {orders.map((o) => (
                <li key={o.id} className="py-2.5 flex items-center gap-2 flex-wrap">
                  <div className="flex-1 min-w-[10rem]">
                    <Link href={`/dashboard/agency/job-orders/${o.id}`} className="font-semibold text-sm hover:underline break-words">
                      {o.title}
                    </Link>
                    <p className="text-xs muted break-words">
                      {o.reference} · {(o.agency_clients as unknown as { name: string } | null)?.name ?? 'Client'} ·{' '}
                      {o.openings} opening{o.openings === 1 ? '' : 's'}
                    </p>
                  </div>
                  <PriorityPill priority={o.priority} />
                  <OrderStatusPill status={o.status} />
                </li>
              ))}
            </ul>
          )}
        </Section>
      </div>
    </div>
  );
}
