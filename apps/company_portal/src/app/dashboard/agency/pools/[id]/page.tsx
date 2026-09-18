import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { agencyCan, onlyRoles, parseConsents } from '@/lib/agency';
import { timeAgo } from '@/lib/format';
import { UUID_RE, parsePoolMembers } from '@/lib/talent';
import { MemberControls, PoolSettings } from '../../../talent/pools/pool-forms';
import { Avatar, CardHeader, SkillChips } from '../../../talent/ui';
import { ORDER_SUMMARY_SELECT, agencySummary, myDisplayName, toOrderSummary } from '../../order-summary';
import { ErrorNote, Notice, PageHeader, Why } from '../../ui';
import PoolConsent, { type PoolOrder } from './pool-consent';

export const metadata: Metadata = { title: 'Talent pool · Omelo' };

const POOL_ROLES = ['owner', 'admin', 'recruiter'];

export default async function AgencyPoolPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID_RE.test(id)) notFound();
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  const { data: pool } = await supabase
    .from('talent_pools')
    .select('id, name, created_at')
    .eq('id', id)
    .eq('company_id', ctx.companyId)
    .maybeSingle();
  if (!pool) notFound();

  const canRequest = agencyCan(ctx, 'request_consent');
  const [membersRes, ordersRes, consentsRes, me] = await Promise.all([
    supabase.rpc('omelo_pool_members', { p_pool: id }),
    supabase
      .from('job_orders')
      .select(ORDER_SUMMARY_SELECT)
      .eq('agency_id', ctx.companyId)
      .in('status', ['open', 'on_hold'])
      .order('updated_at', { ascending: false }),
    supabase.rpc('omelo_agency_candidates', { p_agency: ctx.companyId }),
    myDisplayName(supabase),
  ]);

  const members = parsePoolMembers(membersRes.data ?? null);
  const orders: PoolOrder[] = (ordersRes.data ?? []).map((o) => ({ ...toOrderSummary(o), status: o.status }));
  // Latest consent per (identity, order) so the button shows the real state.
  const consentBy = new Map<string, Record<string, { id: string; status: string }>>();
  for (const c of parseConsents(consentsRes.data ?? null)) {
    const idt = c.card?.workIdentityId;
    if (!idt) continue;
    const m = consentBy.get(idt) ?? {};
    if (!m[c.jobOrderId]) m[c.jobOrderId] = { id: c.consentId, status: c.status };
    consentBy.set(idt, m);
  }
  const canEdit = ctx.roles.some((r) => POOL_ROLES.includes(r));
  const blockedReason = !canRequest
    ? onlyRoles('request_consent', 'ask for consent')
    : !ctx.isVerified
      ? 'Asking for consent opens once Omelo verifies your agency.'
      : null;
  const agency = agencySummary(ctx);

  return (
    <div className="space-y-6 max-w-4xl">
      <PageHeader
        back={{ href: '/dashboard/agency/pools', label: 'Talent pools' }}
        title={pool.name}
        subtitle={`${members.length} ${members.length === 1 ? 'person' : 'people'} · created ${timeAgo(pool.created_at)}`}
        action={canEdit ? <PoolSettings poolId={pool.id} name={pool.name} basePath="/dashboard/agency/pools" /> : undefined}
      />

      <p className="card p-4 text-sm" style={{ borderLeft: '3px solid var(--color-brand-600)' }}>
        <strong>Saving someone doesn&apos;t let you submit them. Ask for their consent.</strong>{' '}
        <span className="muted">Pick a job order below; they decide what to share and for how long.</span>
      </p>

      {membersRes.error ? (
        <ErrorNote label="this pool" message={membersRes.error.message} />
      ) : members.length === 0 ? (
        <Notice title="Nobody saved here yet">Use “Save to pool” on a candidate in talent search.</Notice>
      ) : (
        <ul className="space-y-3">
          {members.map((m) => (
            <li
              key={m.personId}
              className={`card p-4 space-y-3 min-w-0 ${m.visible ? '' : 'opacity-60'}`}
              style={m.visible ? undefined : { background: 'var(--surface)' }}
            >
              {m.visible && m.candidate ? (
                <>
                  <CardHeader card={m.candidate} showScore={false} />
                  <SkillChips card={m.candidate} />
                </>
              ) : (
                <div className="flex items-center gap-3">
                  <Avatar name="?" url={null} />
                  <div className="min-w-0">
                    <p className="font-semibold break-words">{m.candidateName}</p>
                    <p className="text-xs muted">
                      Not visible to your role, or they changed who can see their profile. You can keep your note or
                      remove them.
                    </p>
                  </div>
                </div>
              )}

              {m.note && (
                <p className="text-sm surface rounded-lg p-3 whitespace-pre-line break-words">
                  <span className="label !mb-1">Team note</span>
                  {m.note}
                </p>
              )}

              <div className="flex items-start gap-2 flex-wrap border-t hairline pt-3">
                {m.visible && m.candidate && (
                  <PoolConsent
                    candidate={{ identityId: m.candidate.workIdentityId, name: m.candidate.name, label: m.candidate.label }}
                    orders={orders}
                    existing={consentBy.get(m.candidate.workIdentityId) ?? {}}
                    agency={agency}
                    recruiterName={me}
                    blockedReason={blockedReason}
                  />
                )}
                {canEdit && (
                  <MemberControls poolId={pool.id} personId={m.personId} note={m.note} canEditNote={m.visible} />
                )}
                {m.addedAt && <span className="text-xs muted ml-auto">Saved {timeAgo(m.addedAt)}</span>}
              </div>
            </li>
          ))}
        </ul>
      )}
      {!canEdit && <Why>Owners, admins and recruiters can edit notes and remove people from pools.</Why>}
    </div>
  );
}
