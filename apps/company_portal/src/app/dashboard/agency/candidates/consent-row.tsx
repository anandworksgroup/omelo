import Link from 'next/link';
import { daysLeft, onlyRoles, submitBlocker, type ConsentRow } from '@/lib/agency';
import { timeAgo } from '@/lib/format';
import { Avatar, IdentityLine } from '../../talent/ui';
import { SubmitCandidate, WithdrawRequest } from '../consent-ui';
import { ConsentPill, ScopeChips, SubmissionPill } from '../ui';

export type OrderFacts = { status: string; clientJobId: string | null; assignedToMe: boolean };

/**
 * Everything that must hold before "Submit" can work, in the order the
 * database checks it. Returns the first reason it would refuse, or null.
 */
export function whyCannotSubmit(
  row: ConsentRow,
  opts: { canSubmit: boolean; isAdmin: boolean; order: OrderFacts | undefined; nowMs: number }
): string | null {
  if (!opts.canSubmit) return onlyRoles('submit', 'submit candidates');
  const consent = submitBlocker(row, opts.nowMs);
  if (consent) return consent;
  if (opts.order && opts.order.status !== 'open') return 'The job order is not open, so nobody can be submitted to it.';
  if (opts.order && !opts.isAdmin && !opts.order.assignedToMe)
    return 'Only recruiters assigned to this job order (or admins) can submit to it.';
  return null;
}

export default function ConsentRowItem({
  row,
  nowMs,
  canSubmit,
  canWithdraw,
  canViewDetails,
  isAdmin,
  order,
  showOrder = true,
}: {
  row: ConsentRow;
  nowMs: number;
  canSubmit: boolean;
  canWithdraw: boolean;
  canViewDetails: boolean;
  isAdmin: boolean;
  order: OrderFacts | undefined;
  showOrder?: boolean;
}) {
  const inForce =
    row.status === 'active' || (row.status === 'accepted' && (!row.expiresAt || new Date(row.expiresAt).getTime() > nowMs));
  const left = inForce ? daysLeft(row.expiresAt, nowMs) : null;
  const blocker = row.submission ? null : whyCannotSubmit(row, { canSubmit, isAdmin, order, nowMs });
  const profileHref = `/dashboard/agency/candidates/${row.consentId}`;

  return (
    <li className="card p-4 space-y-3 min-w-0">
      <div className="flex items-start gap-3">
        <Avatar name={row.name} url={row.card?.avatarUrl ?? null} size={40} />
        <div className="flex-1 min-w-0 space-y-0.5">
          <p className="font-bold break-words">
            {inForce ? (
              <Link href={profileHref} className="hover:underline">
                {row.name}
              </Link>
            ) : (
              row.name
            )}
          </p>
          {row.card && <IdentityLine card={row.card} />}
          {showOrder && (
            <p className="text-sm break-words">
              <Link href={`/dashboard/agency/job-orders/${row.jobOrderId}`} className="underline">
                {row.position ?? 'Job order'}
              </Link>{' '}
              <span className="muted">
                · {row.jobOrder} · {row.client}
              </span>
            </p>
          )}
          <p className="text-xs muted break-words">
            Asked {timeAgo(row.requestedAt)}
            {row.recruiter ? ` by ${row.recruiter}` : ''}
            {row.respondedAt ? ` · answered ${timeAgo(row.respondedAt)}` : ''}
            {left != null ? ` · consent ends in ${left} day${left === 1 ? '' : 's'}` : ''}
          </p>
        </div>
        <div className="shrink-0">
          <ConsentPill status={row.status} />
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2 text-xs">
        <span className="muted">Shares:</span>
        <ScopeChips scope={row.scope} />
      </div>

      {row.declineReason && (
        <p className="text-sm break-words">
          <span className="muted">Their reason:</span> “{row.declineReason}”
        </p>
      )}

      <div className="flex flex-wrap items-start gap-2 border-t hairline pt-3">
        {row.submission ? (
          <>
            <Link href={`/dashboard/agency/submissions/${row.submission.id}`} className="btn btn-ghost !h-9 !px-3 text-sm">
              View submission
            </Link>
            <SubmissionPill status={row.submission.status} />
          </>
        ) : (
          (row.status === 'accepted' || row.status === 'requested') && (
            <SubmitCandidate
              consentId={row.consentId}
              candidateName={row.name}
              client={row.client ?? 'the client'}
              clientOnOmelo={!!order?.clientJobId}
              scope={row.scope}
              blocker={blocker}
            />
          )
        )}
        {inForce && (
          <Link href={profileHref} className="btn btn-ghost !h-9 !px-3 text-sm">
            {canViewDetails ? 'Open consented profile' : 'Open profile (skills only)'}
          </Link>
        )}
        {row.status === 'requested' && canWithdraw && <WithdrawRequest consentId={row.consentId} />}
      </div>
    </li>
  );
}
