'use client';

import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import type { JobInvitation } from '@/lib/talent';
import { withdrawInvitation } from '../../talent/actions';
import { Avatar, IdentityLine, InvitationChip } from '../../talent/ui';

function WithdrawButton({ invitationId, jobId }: { invitationId: string; jobId: string }) {
  const router = useRouter();
  const [confirming, setConfirming] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  if (!confirming)
    return (
      <button type="button" className="btn btn-ghost !h-8 !px-2.5 text-xs" onClick={() => setConfirming(true)}>
        Withdraw
      </button>
    );
  return (
    <span className="inline-flex flex-wrap items-center gap-2">
      <span className="text-xs">Withdraw this invitation?</span>
      <button
        type="button"
        className="btn btn-primary !h-8 !px-2.5 text-xs"
        style={{ background: 'var(--color-danger)' }}
        disabled={pending}
        onClick={() => {
          setError(null);
          start(async () => {
            const res = await withdrawInvitation({ invitationId, jobId });
            if (!res.ok) return setError(res.error);
            setConfirming(false);
            router.refresh();
          });
        }}
      >
        {pending ? 'Withdrawing…' : 'Yes, withdraw'}
      </button>
      <button type="button" className="btn btn-ghost !h-8 !px-2.5 text-xs" onClick={() => setConfirming(false)}>
        Keep
      </button>
      {error && (
        <span className="text-xs basis-full" role="alert" style={{ color: 'var(--color-danger)' }}>
          {error}
        </span>
      )}
    </span>
  );
}

/** Relative times are formatted on the server so the render stays pure. */
export type InvitationRow = JobInvitation & { sentAgo: string; answeredAgo: string };

export default function InvitationsPanel({
  jobId,
  invitations,
  error,
  canManage,
  canSearch,
}: {
  jobId: string;
  invitations: InvitationRow[];
  error?: string;
  canManage: boolean;
  canSearch: boolean;
}) {
  return (
    <section className="card p-5">
      <div className="flex items-center gap-3 flex-wrap mb-3">
        <h2 className="font-bold flex-1 min-w-0">Invitations ({invitations.length})</h2>
        {canSearch && (
          <Link href={`/dashboard/talent?job=${jobId}`} className="btn btn-ghost !h-9 !px-3 text-sm">
            Find candidates
          </Link>
        )}
      </div>
      {error ? (
        <p className="text-sm" style={{ color: 'var(--color-danger)' }}>
          Could not load invitations: <span className="muted">{error}</span>
        </p>
      ) : invitations.length === 0 ? (
        <p className="text-sm muted">
          You have not invited anyone to this job yet.
          {canSearch ? ' Use Find candidates to search for people who chose to be visible to employers.' : ''}
        </p>
      ) : (
        <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
          {invitations.map((inv) => {
            const c = inv.candidate;
            const href = c ? `/dashboard/talent/${c.workIdentityId}?job=${jobId}` : null;
            return (
              <li key={inv.id} className={`py-3 first:pt-0 last:pb-0 flex items-start gap-3 ${c ? '' : 'opacity-60'}`}>
                <Avatar name={inv.candidateName} url={c?.avatarUrl ?? null} size={36} />
                <div className="flex-1 min-w-0 space-y-1">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-semibold text-sm break-words">
                      {href ? (
                        <Link href={href} className="hover:underline">
                          {inv.candidateName}
                        </Link>
                      ) : (
                        inv.candidateName
                      )}
                    </span>
                    <InvitationChip status={inv.status} sentAt={inv.sentAt} />
                    {inv.status === 'pending' && inv.viewed && <span className="pill">Seen</span>}
                  </div>
                  {c && <IdentityLine card={c} />}
                  <p className="text-xs muted">
                    Invited {inv.sentAgo}
                    {inv.sentBy ? ` by ${inv.sentBy}` : ''}
                    {inv.respondedAt && inv.status !== 'pending' ? ` · answered ${inv.answeredAgo}` : ''}
                  </p>
                  {inv.declineReason && (
                    <p className="text-sm break-words">
                      <span className="muted">Their reason:</span> “{inv.declineReason}”
                    </p>
                  )}
                  <div className="flex flex-wrap gap-2 pt-0.5">
                    {inv.applicationId && (
                      <Link href={`/dashboard/candidates/${inv.applicationId}`} className="text-sm underline">
                        Open application
                      </Link>
                    )}
                    {canManage && inv.status === 'pending' && <WithdrawButton invitationId={inv.id} jobId={jobId} />}
                  </div>
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}
