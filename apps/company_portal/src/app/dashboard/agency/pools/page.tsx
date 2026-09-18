import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { agencyCan } from '@/lib/agency';
import { timeAgo } from '@/lib/format';
import { CreatePoolForm } from '../../talent/pools/pool-forms';
import { ErrorNote, Notice, PageHeader, Why } from '../ui';

export const metadata: Metadata = { title: 'Talent pools · Omelo' };

/** Pool writes: owners/admins/recruiters create pools; sourcers can also add people (RLS). */
const POOL_ROLES = ['owner', 'admin', 'recruiter'];

export default async function AgencyPoolsPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const canCreate = ctx.roles.some((r) => POOL_ROLES.includes(r));
  const canAdd = agencyCan(ctx, 'search_talent');

  const { data, error } = await supabase
    .from('talent_pools')
    .select('id, name, created_at, talent_pool_members ( count )')
    .eq('company_id', ctx.companyId)
    .order('name');
  const pools = (data ?? []).map((p) => ({
    id: p.id,
    name: p.name,
    createdAt: p.created_at,
    members: (p.talent_pool_members as unknown as { count: number }[] | null)?.[0]?.count ?? 0,
  }));

  return (
    <div className="space-y-6 max-w-5xl">
      <PageHeader
        title="Talent pools"
        subtitle="Shortlists of promising people, shared with your agency."
        action={
          canAdd ? (
            <Link href="/dashboard/agency/talent" className="btn btn-ghost w-full sm:w-auto">
              Find candidates
            </Link>
          ) : undefined
        }
      />

      <div className="card p-4 text-sm leading-relaxed" style={{ borderLeft: '3px solid var(--color-brand-600)' }}>
        <strong>Saving someone doesn&apos;t let you submit them. Ask for their consent.</strong>{' '}
        <span className="muted">
          A pool is a private bookmark. It gives your agency no access to anyone&apos;s profile beyond what they already
          chose to show recruiters, and it does not let you put them forward for a job.
        </span>
      </div>

      {canCreate ? <CreatePoolForm basePath="/dashboard/agency/pools" /> : <Why>Owners, admins and recruiters create pools. Sourcers can add people to existing pools.</Why>}

      {error ? (
        <ErrorNote label="your pools" message={error.message} />
      ) : pools.length === 0 ? (
        <Notice title="No pools yet">
          {canCreate ? 'Create one above, or use “Save to pool” on a candidate in talent search.' : 'Pools your team creates appear here.'}
        </Notice>
      ) : (
        <ul className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {pools.map((p) => (
            <li key={p.id}>
              <Link href={`/dashboard/agency/pools/${p.id}`} className="card p-4 block hover:opacity-90">
                <p className="font-bold break-words">{p.name}</p>
                <p className="text-sm muted mt-1">
                  {p.members} {p.members === 1 ? 'person' : 'people'} · created {timeAgo(p.createdAt)}
                </p>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
