import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { formatPay, WORK_TYPE_LABEL } from '@/lib/format';
import { calendarDate } from '@/lib/hiring';
import {
  LINK_STATUS,
  RELATIONSHIP,
  orderTone,
  parseClientJobOrders,
  parseRelationships,
  type AgencyRelationship,
  type ClientJobOrder,
} from '@/lib/agency';
import { ErrorNote, Notice } from '../talent/ui';
import { AgencyName, TonePill } from './agency-badge';
import { ConnectJob, EndRelationship, RespondToLink, type JobChoice } from './agency-controls';

export const metadata: Metadata = { title: 'Agencies · Omelo' };

/** Mirrors the roles the database checks; used only to explain, never to decide. */
const ANSWER_ROLES = ['owner', 'admin'];
const CONNECT_ROLES = ['owner', 'admin', 'recruiter', 'hiring_manager'];
/** Jobs that can no longer take candidates are not offered for connecting. */
const HIDDEN_JOB_STATUSES = ['closed', 'expired', 'rejected'];

const tone = (table: Record<string, { label: string; color: string }>, key: string) =>
  table[key] ?? { label: key.replace(/_/g, ' '), color: 'var(--muted)' };

export default async function AgenciesPage() {
  const ctx = (await getCompanyContext())!;

  if (ctx.kind === 'agency') {
    return (
      <div className="space-y-6 max-w-4xl">
        <h1 className="text-xl sm:text-2xl font-bold">Agencies</h1>
        <Notice
          title="This page is for employers"
          action={
            <Link href="/dashboard/agency/clients" className="btn btn-primary w-full sm:w-auto">
              Your clients
            </Link>
          }
        >
          Employers use it to confirm the agencies that recruit for them. Your own client companies are under
          Clients.
        </Notice>
      </div>
    );
  }

  const supabase = await createClient();
  const [relRes, orderRes, jobRes] = await Promise.all([
    supabase.rpc('omelo_my_agency_relationships'),
    supabase.rpc('omelo_client_job_orders'),
    supabase
      .from('jobs')
      .select('id, title, status')
      .eq('company_id', ctx.companyId)
      .order('created_at', { ascending: false }),
  ]);

  const relationships = relRes.error ? [] : parseRelationships(relRes.data);
  const orders = orderRes.error ? [] : parseClientJobOrders(orderRes.data);
  const jobs: JobChoice[] = (jobRes.data ?? []).filter((j) => !HIDDEN_JOB_STATUSES.includes(j.status));

  const pending = relationships.filter((r) => r.linkStatus === 'pending');
  const confirmed = relationships.filter((r) => r.linkStatus === 'confirmed');

  const canAnswerRole = ctx.roles.some((r) => ANSWER_ROLES.includes(r));
  const canConnectRole = ctx.roles.some((r) => CONNECT_ROLES.includes(r));
  const endHint = canAnswerRole ? null : 'Only owners and admins can end a relationship.';
  const connectHint = canConnectRole
    ? null
    : 'Only owners, admins, recruiters and hiring managers can connect a job.';

  // Group orders by agency so each relationship shows its own.
  const ordersByAgency = new Map<string, ClientJobOrder[]>();
  for (const o of orders) {
    const list = ordersByAgency.get(o.agency.id) ?? [];
    list.push(o);
    ordersByAgency.set(o.agency.id, list);
  }
  const knownAgencies = new Set(confirmed.map((r) => r.agency.id));
  const orphanOrders = orders.filter((o) => !knownAgencies.has(o.agency.id));

  const nothing = !relRes.error && !orderRes.error && relationships.length === 0 && orders.length === 0;

  return (
    <div className="space-y-8 max-w-4xl">
      <div>
        <h1 className="text-xl sm:text-2xl font-bold">Agencies</h1>
        <p className="muted text-sm mt-1 leading-relaxed">
          Recruitment agencies and independent recruiters who find candidates for you. A recruiter can only put
          someone forward with that person&apos;s consent, for one job, for a limited time. The candidate is never
          the agency&apos;s to keep.
        </p>
      </div>

      {relRes.error && <ErrorNote label="your agencies" message={relRes.error.message} />}
      {orderRes.error && <ErrorNote label="job orders" message={orderRes.error.message} />}
      {jobRes.error && <ErrorNote label="your jobs" message={jobRes.error.message} />}

      {nothing && (
        <Notice title="No agencies yet">
          When an agency or independent recruiter adds your company as a client on Omelo, they ask to link with
          you. The request appears here, and your owners and admins are notified. Once you confirm, the agency can
          connect its job orders to your jobs, and the candidates it submits arrive in your pipeline with their
          consent.
        </Notice>
      )}

      {/* ------------------------------------------------ Pending links */}
      {pending.length > 0 && (
        <section className="space-y-3" aria-labelledby="pending-title">
          <h2 id="pending-title" className="font-bold text-lg">
            Waiting for your answer
          </h2>
          <ul className="space-y-3">
            {pending.map((r) => (
              <li
                key={r.clientId}
                className="card p-4 sm:p-5 space-y-3"
                style={{ borderTop: '3px solid var(--color-warn)' }}
              >
                <RelationshipHead r={r} />
                <p className="text-sm leading-relaxed break-words">
                  <strong>{r.agency.name}</strong> wants to recruit for you. If you confirm, {r.agency.name} can
                  then connect its job orders for you to your jobs; candidates they submit arrive in your pipeline
                  with the candidate&apos;s consent. You can end this at any time.
                </p>
                {!r.agency.verified && (
                  <p className="text-sm" style={{ color: 'var(--color-warn)' }}>
                    This agency is not verified by Omelo yet.
                  </p>
                )}
                {r.canAnswer ? (
                  <RespondToLink clientId={r.clientId} agencyName={r.agency.name} />
                ) : (
                  <p className="text-sm muted">Waiting for an owner or admin of your company to answer.</p>
                )}
              </li>
            ))}
          </ul>
        </section>
      )}

      {/* ---------------------------------------------- Confirmed links */}
      {confirmed.length > 0 && (
        <section className="space-y-3" aria-labelledby="confirmed-title">
          <h2 id="confirmed-title" className="font-bold text-lg">
            Agencies working for you
          </h2>
          <ul className="space-y-4">
            {confirmed.map((r) => {
              const own = ordersByAgency.get(r.agency.id) ?? [];
              return (
                <li key={r.clientId} className="card p-4 sm:p-5 space-y-4">
                  <RelationshipHead r={r} />
                  <p className="text-sm muted">
                    {r.jobOrders} open job order{r.jobOrders === 1 ? '' : 's'} · {r.submissions} candidate
                    {r.submissions === 1 ? '' : 's'} submitted
                    {r.submissions > 0 && (
                      <>
                        {' · '}
                        <Link href="/dashboard/candidates?view=agency" className="underline">
                          See submissions
                        </Link>
                      </>
                    )}
                  </p>

                  {own.length > 0 ? (
                    <ul className="space-y-3">
                      {own.map((o) => (
                        <JobOrderCard key={o.id} o={o} jobs={jobs} hint={connectHint} />
                      ))}
                    </ul>
                  ) : (
                    <p className="text-sm muted surface rounded-lg p-3">
                      No job orders from {r.agency.name} yet. When they open one for you, it appears here and you
                      can connect it to one of your jobs.
                    </p>
                  )}

                  <div className="border-t hairline pt-4 flex flex-wrap gap-2">
                    <EndRelationship clientId={r.clientId} agencyName={r.agency.name} hint={endHint} />
                  </div>
                </li>
              );
            })}
          </ul>
        </section>
      )}

      {/* Orders whose relationship row the viewer cannot see (should be rare). */}
      {orphanOrders.length > 0 && (
        <section className="space-y-3" aria-labelledby="orders-title">
          <h2 id="orders-title" className="font-bold text-lg">
            Other job orders
          </h2>
          <ul className="space-y-3">
            {orphanOrders.map((o) => (
              <JobOrderCard key={o.id} o={o} jobs={jobs} hint={connectHint} showAgency />
            ))}
          </ul>
        </section>
      )}

      <section className="card p-4 sm:p-5 space-y-2">
        <h2 className="font-bold">How agencies work with you</h2>
        <ul className="text-sm muted space-y-1.5 leading-relaxed list-disc pl-5">
          <li>An agency adds your company as a client and asks to link. Your owners or admins confirm it here.</li>
          <li>
            The agency opens job orders for you. Connect each one to a job, and submitted candidates land in that
            job&apos;s pipeline like any applicant.
          </li>
          <li>
            You see only what the candidate agreed to share with the agency. If they withdraw consent, you are told.
          </li>
          <li>Interviews, offers and hiring work exactly as for your other candidates.</li>
        </ul>
      </section>
    </div>
  );
}

function RelationshipHead({ r }: { r: AgencyRelationship }) {
  return (
    <div className="flex items-start gap-3 flex-wrap">
      <div className="flex-1 min-w-0">
        <p className="text-base break-words">
          <AgencyName agency={r.agency} />
        </p>
      </div>
      <div className="flex gap-1.5 flex-wrap">
        <TonePill tone={tone(LINK_STATUS, r.linkStatus)} />
        {r.linkStatus === 'confirmed' && <TonePill tone={tone(RELATIONSHIP, r.relationshipStatus)} />}
      </div>
    </div>
  );
}

function JobOrderCard({
  o,
  jobs,
  hint,
  showAgency,
}: {
  o: ClientJobOrder;
  jobs: JobChoice[];
  hint: string | null;
  showAgency?: boolean;
}) {
  const facts = [
    `${o.openings} opening${o.openings === 1 ? '' : 's'}`,
    o.location,
    o.workType ? (WORK_TYPE_LABEL[o.workType] ?? o.workType) : null,
    o.pay.min != null || o.pay.max != null
      ? formatPay({ min: o.pay.min, max: o.pay.max, period: o.pay.period, currency: o.pay.currency })
      : null,
    o.startDate ? `Starts ${calendarDate(o.startDate)}` : null,
  ].filter(Boolean);
  return (
    <li className="surface rounded-lg p-3 sm:p-4 space-y-3 min-w-0">
      <div className="flex items-start gap-2 flex-wrap">
        <div className="flex-1 min-w-0">
          <p className="font-semibold break-words">{o.title}</p>
          <p className="text-xs muted break-words">
            {o.reference ? `Ref. ${o.reference}` : 'Job order'}
            {showAgency ? (
              <>
                {' · '}
                <AgencyName agency={o.agency} strong={false} />
              </>
            ) : null}
          </p>
        </div>
        <TonePill tone={orderTone(o.status)} />
      </div>
      <p className="text-sm muted break-words">{facts.join(' · ')}</p>
      <p className="text-sm">
        {o.submissions} candidate{o.submissions === 1 ? '' : 's'} submitted
      </p>
      <div className="border-t hairline pt-3">
        <ConnectJob
          jobOrderId={o.id}
          current={o.clientJobId ? { id: o.clientJobId, title: o.clientJobTitle } : null}
          jobs={jobs}
          hint={hint}
        />
      </div>
    </li>
  );
}
