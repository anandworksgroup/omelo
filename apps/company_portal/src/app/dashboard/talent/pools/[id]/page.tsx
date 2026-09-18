import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { timeAgo } from '@/lib/format';
import { TALENT_ROLES, UUID_RE, parsePoolMembers } from '@/lib/talent';
import { Avatar, CardHeader, ErrorNote, Notice, SkillChips } from '../../ui';
import { MemberControls, PoolSettings } from '../pool-forms';

export const metadata: Metadata = { title: 'Talent pool · Omelo' };

export default async function PoolPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID_RE.test(id)) notFound();
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const canEdit = TALENT_ROLES.includes(ctx.role);

  const { data: pool } = await supabase
    .from('talent_pools')
    .select('id, name, created_at')
    .eq('id', id)
    .eq('company_id', ctx.companyId)
    .maybeSingle();
  if (!pool) notFound();

  const { data, error } = await supabase.rpc('omelo_pool_members', { p_pool: id });
  const members = parsePoolMembers(data);
  const visible = members.filter((m) => m.visible).length;

  return (
    <div className="space-y-6 max-w-4xl">
      <Link href="/dashboard/talent/pools" className="text-sm underline muted">
        ← Talent pools
      </Link>

      <div className="flex items-start gap-3 flex-wrap">
        <div className="flex-1 min-w-0">
          <h1 className="text-xl sm:text-2xl font-bold break-words">{pool.name}</h1>
          <p className="text-sm muted mt-1">
            {members.length} {members.length === 1 ? 'person' : 'people'}
            {members.length !== visible ? ` · ${members.length - visible} no longer visible` : ''} · created{' '}
            {timeAgo(pool.created_at)}
          </p>
        </div>
        {canEdit && <PoolSettings poolId={pool.id} name={pool.name} />}
      </div>

      {error ? (
        <ErrorNote label="this pool" message={error.message} />
      ) : members.length === 0 ? (
        <Notice
          title="Nobody saved here yet"
          action={
            canEdit ? (
              <Link href="/dashboard/talent" className="btn btn-primary">
                Find candidates
              </Link>
            ) : undefined
          }
        >
          Use “Save to pool” on a candidate in talent search or on their profile.
        </Notice>
      ) : (
        <ul className="space-y-3">
          {members.map((m) => (
            <li
              key={m.personId}
              className={`card p-4 space-y-3 ${m.visible ? '' : 'opacity-60'}`}
              style={m.visible ? undefined : { background: 'var(--surface)' }}
            >
              {m.visible && m.candidate ? (
                <>
                  <CardHeader
                    card={m.candidate}
                    href={`/dashboard/talent/${m.candidate.workIdentityId}`}
                    showScore={false}
                  />
                  <SkillChips card={m.candidate} />
                </>
              ) : (
                <div className="flex items-center gap-3">
                  <Avatar name="?" url={null} />
                  <div className="min-w-0">
                    <p className="font-semibold break-words">{m.candidateName}</p>
                    <p className="text-xs muted">
                      They changed who can see this profile. You can keep your note or remove them.
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

              <div className="flex items-center gap-2 flex-wrap border-t hairline pt-3">
                {m.visible && m.candidate && (
                  <Link
                    href={`/dashboard/talent/${m.candidate.workIdentityId}`}
                    className="btn btn-ghost !h-9 !px-3 text-sm"
                  >
                    Open profile
                  </Link>
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
    </div>
  );
}
