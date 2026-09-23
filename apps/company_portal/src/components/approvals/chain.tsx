/**
 * The approval chain, drawn. No hooks, so a server component and a client
 * component can both render it.
 *
 * Every tick comes from the database (approval_decisions counted per step);
 * nothing here assumes a step is done.
 */
import { roleLabel } from '@/lib/agency';
import {
  APPROVAL_STATUS_COLOR,
  APPROVAL_STATUS_LABEL,
  stepState,
  type ApprovalRequest,
  type ApprovalStepState,
} from '@/lib/enterprise';

const MARK: Record<ReturnType<typeof stepState>, { glyph: string; color: string; note: string }> = {
  approved: { glyph: '✓', color: 'var(--color-verified)', note: 'approved' },
  current: { glyph: '•', color: 'var(--color-warn)', note: 'waiting now' },
  waiting: { glyph: '○', color: 'var(--muted)', note: 'later' },
  stopped: { glyph: '✕', color: 'var(--color-danger)', note: 'not approved' },
};

export function ApprovalStatusPill({ status }: { status: string }) {
  const color = APPROVAL_STATUS_COLOR[status] ?? 'var(--muted)';
  return (
    <span className="pill whitespace-nowrap" style={{ color, borderColor: color }}>
      {APPROVAL_STATUS_LABEL[status] ?? status}
    </span>
  );
}

export function StepLine({ step, request }: { step: ApprovalStepState; request: ApprovalRequest }) {
  const state = stepState(step, request);
  const m = MARK[state];
  return (
    <li className="flex items-start gap-2.5">
      <span aria-hidden className="font-bold shrink-0 w-4 text-center leading-6" style={{ color: m.color }}>
        {m.glyph}
      </span>
      <div className="min-w-0 text-sm">
        <p className="font-semibold break-words">
          {step.position}. {step.name}
          <span className="sr-only"> — {m.note}</span>
        </p>
        <p className="text-xs muted break-words">
          {roleLabel(step.role)} ·{' '}
          {step.required > 1
            ? `${step.approvals} of ${step.required} approvals`
            : step.approvals >= 1
              ? 'approved'
              : 'one approval needed'}
        </p>
      </div>
    </li>
  );
}

/** Ordered steps with a tick on the ones that are done. */
export function ApprovalChain({ request }: { request: ApprovalRequest }) {
  if (request.steps.length === 0) return <p className="text-sm muted">This chain has no steps any more.</p>;
  return (
    <ol className="space-y-2">
      {request.steps.map((s) => (
        <StepLine key={s.position} step={s} request={request} />
      ))}
    </ol>
  );
}

/** Every decision made on a request, newest last, with the words people wrote. */
export function ApprovalDecisions({
  request,
  when,
}: {
  request: ApprovalRequest;
  when: (iso: string) => React.ReactNode;
}) {
  if (request.decisions.length === 0) return null;
  return (
    <div className="space-y-1.5">
      <p className="label !mb-0">What has been decided</p>
      <ul className="space-y-1.5">
        {request.decisions.map((d, i) => {
          const step = request.steps.find((s) => s.position === d.position);
          const good = d.decision === 'approved';
          return (
            <li key={`${d.position}-${i}`} className="text-sm break-words">
              <span
                className="font-semibold"
                style={{ color: good ? 'var(--color-verified)' : 'var(--color-danger)' }}
              >
                {good ? 'Approved' : 'Not approved'}
              </span>
              <span className="muted">
                {' '}
                · {step?.name ?? `step ${d.position}`}
                {d.at ? ' · ' : ''}
              </span>
              {d.at ? when(d.at) : null}
              {d.note && <p className="text-sm break-words">“{d.note}”</p>}
            </li>
          );
        })}
      </ul>
    </div>
  );
}
