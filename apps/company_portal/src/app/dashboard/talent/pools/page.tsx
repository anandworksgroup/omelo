import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { timeAgo } from '@/lib/format';
import { TALENT_ROLES } from '@/lib/talent';
import { ErrorNote, Notice, TalentHeader } from '../ui';
import { CreatePoolForm } from './pool-forms';

export const metadata: Metadata = { title: 'Talent pools · Omelo' };

export default async function PoolsPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const canEdit = TALENT_ROLES.includes(ctx.role);

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
    <div className="space-y-6">
      <TalentHeader active="pools" />
      <p className="text-sm muted max-w-2xl">
        Save promising people to shared lists, with a note for your team. Pools only ever hold people who are
        visible to your company; if someone hides their profile they stay listed but greyed out.
      </p>

      {canEdit && <CreatePoolForm />}

      {error ? (
        <ErrorNote label="your pools" message={error.message} />
      ) : pools.length === 0 ? (
        <Notice
          title="No pools yet"
          action={
            canEdit ? (
              <Link href="/dashboard/talent" className="btn btn-ghost">
                Find candidates
              </Link>
            ) : undefined
          }
        >
          {canEdit
            ? 'Create one above, or use “Save to pool” on any candidate in talent search.'
            : 'Owners, admins and recruiters can create pools. They will appear here for your whole team.'}
        </Notice>
      ) : (
        <ul className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {pools.map((p) => (
            <li key={p.id}>
              <Link href={`/dashboard/talent/pools/${p.id}`} className="card p-4 block hover:opacity-90">
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
