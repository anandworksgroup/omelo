import Link from 'next/link';
import {
  APPROVAL_STATUS_LABEL,
  publishBlockedReason,
  type ApprovalStatus,
} from '@/lib/enterprise';
import { ApprovalChain, ApprovalDecisions, ApprovalStatusPill } from '@/components/approvals/chain';
import { SubmitForApproval, WithdrawApproval } from '@/components/approvals/controls';
import LocalTime from '../../local-time';

/**
 * The approval panel on a job.
 *
 * It appears only when this organization actually approves jobs. Everything
 * shown comes from omelo_approval_status; the trigger on `jobs` is what really
 * stops a job going live, and this says the same thing beforehand.
 */
export default function ApprovalPanel({
  jobId,
  status,
  canSubmit,
  isPublished = false,
}: {
  jobId: string;
  status: ApprovalStatus | null;
  canSubmit: boolean;
  /** A job that is already live is not waiting on anything. */
  isPublished?: boolean;
}) {
  if (!status?.required) return null;
  const request = status.request;
  const open = request?.status === 'pending';
  const reason = publishBlockedReason(status);
  const blocked = isPublished && !open ? null : reason;

  return (
    <section className="card p-5 space-y-4">
      <div className="flex items-start gap-3 flex-wrap">
        <h2 className="font-bold flex-1 min-w-0">Approval</h2>
        {request && <ApprovalStatusPill status={request.status} />}
      </div>

      <p className="text-sm muted leading-relaxed">
        This organization approves a job before it goes live. The chain below is set on{' '}
        <Link href="/dashboard/approvals?tab=workflow" className="underline">
          Approvals
        </Link>
        .
      </p>

      {request ? (
        <>
          <p className="text-sm">
            {APPROVAL_STATUS_LABEL[request.status] ?? request.status}
            {request.requestedAt ? (
              <>
                {' '}
                · asked <LocalTime iso={request.requestedAt} withTime={false} />
              </>
            ) : null}
            {request.decidedAt ? (
              <>
                {' '}
                · decided <LocalTime iso={request.decidedAt} withTime={false} />
              </>
            ) : null}
          </p>
          <ApprovalChain request={request} />
          <ApprovalDecisions request={request} when={(iso) => <LocalTime iso={iso} withTime={false} />} />
        </>
      ) : (
        <p className="text-sm muted">This job has not been sent for approval yet.</p>
      )}

      {blocked && (
        <p className="text-sm" style={{ color: 'var(--color-warn)' }}>
          {blocked}
        </p>
      )}

      {canSubmit && (open || blocked) && (
        <div className="border-t hairline pt-4 flex flex-wrap gap-3 items-center">
          {open && request ? (
            <WithdrawApproval requestId={request.id} entityType="job" entityId={jobId} />
          ) : (
            <SubmitForApproval
              entityType="job"
              entityId={jobId}
              label={request ? 'Submit for approval again' : 'Submit for approval'}
            />
          )}
        </div>
      )}
      {!canSubmit && (
        <p className="text-xs muted">
          Owners, admins, recruiters, hiring managers and HR whose scope covers this job can submit it.
        </p>
      )}
    </section>
  );
}
