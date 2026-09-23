'use client';

import { useRouter } from 'next/navigation';
import { useId, useState, useTransition } from 'react';
import { roleLabel } from '@/lib/agency';
import {
  APPROVAL_ENTITY_HELP,
  APPROVAL_ENTITY_LABEL,
  GRANT_SCOPES,
  GRANT_SCOPE_LABEL,
  type ApprovalEntity,
} from '@/lib/enterprise';
import { saveWorkflow, type WorkflowStepInput } from './actions';

export type WorkflowValue = {
  id: string;
  name: string;
  isActive: boolean;
  steps: WorkflowStepInput[];
};

const blankStep = (n: number, roles: string[]): WorkflowStepInput => ({
  name: n === 1 ? 'Department approval' : `Step ${n}`,
  // The first role the workspace actually has, so the select always matches.
  approverRole: roles.find((r) => r === 'hiring_manager') ?? roles.find((r) => r === 'admin') ?? roles[0] ?? 'owner',
  approverScope: 'department',
  requiredApprovals: 1,
});

/**
 * The chain an organization describes for itself: ordered steps, each with the
 * role that approves it, the scope that role acts in, and how many approvals
 * the step needs. Omelo hard-codes nobody's process.
 */
export default function WorkflowEditor({
  entityType,
  workflow,
  roles,
}: {
  entityType: ApprovalEntity;
  workflow: WorkflowValue | null;
  roles: string[];
}) {
  const uid = useId();
  const router = useRouter();
  const [name, setName] = useState(workflow?.name ?? `${APPROVAL_ENTITY_LABEL[entityType]} approval`);
  const [isActive, setIsActive] = useState(workflow?.isActive ?? true);
  const [steps, setSteps] = useState<WorkflowStepInput[]>(
    workflow?.steps.length ? workflow.steps : [blankStep(1, roles)]
  );
  const [result, setResult] = useState<{ text: string; ok: boolean } | null>(null);
  const [pending, start] = useTransition();

  const patch = (i: number, change: Partial<WorkflowStepInput>) =>
    setSteps((s) => s.map((step, n) => (n === i ? { ...step, ...change } : step)));

  const move = (i: number, by: number) =>
    setSteps((s) => {
      const to = i + by;
      if (to < 0 || to >= s.length) return s;
      const next = [...s];
      [next[i], next[to]] = [next[to], next[i]];
      return next;
    });

  return (
    <div className="space-y-4">
      <p className="text-sm muted leading-relaxed">{APPROVAL_ENTITY_HELP[entityType]}</p>

      <div className="grid gap-3 sm:grid-cols-2">
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}n`}>
            Name of this chain
          </label>
          <input
            id={`${uid}n`}
            className="input"
            maxLength={120}
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Job approval"
          />
        </div>
        <div className="min-w-0 flex items-end">
          <label className="flex items-center gap-2 text-sm pb-2.5">
            <input type="checkbox" checked={isActive} onChange={(e) => setIsActive(e.target.checked)} />
            Switched on
          </label>
        </div>
      </div>

      {isActive && entityType === 'job' && (
        <p className="text-sm" style={{ color: 'var(--color-warn)' }}>
          While this is switched on, a job cannot go live until this chain has approved it.
        </p>
      )}

      <ol className="space-y-3">
        {steps.map((s, i) => (
          <li key={i} className="card p-3 sm:p-4 space-y-3">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="pill">Step {i + 1}</span>
              <div className="ml-auto flex gap-1.5 flex-wrap">
                <button
                  type="button"
                  className="btn btn-ghost !h-8 !px-2.5 text-xs"
                  disabled={i === 0}
                  onClick={() => move(i, -1)}
                >
                  Move up
                </button>
                <button
                  type="button"
                  className="btn btn-ghost !h-8 !px-2.5 text-xs"
                  disabled={i === steps.length - 1}
                  onClick={() => move(i, 1)}
                >
                  Move down
                </button>
                <button
                  type="button"
                  className="btn btn-ghost !h-8 !px-2.5 text-xs"
                  style={{ color: 'var(--color-danger)' }}
                  disabled={steps.length === 1}
                  onClick={() => setSteps((all) => all.filter((_, n) => n !== i))}
                >
                  Remove
                </button>
              </div>
            </div>

            <div className="grid gap-3 sm:grid-cols-2">
              <div className="min-w-0">
                <label className="label" htmlFor={`${uid}s${i}n`}>
                  What this step is called
                </label>
                <input
                  id={`${uid}s${i}n`}
                  className="input !h-9 !py-0 text-sm"
                  maxLength={80}
                  value={s.name}
                  onChange={(e) => patch(i, { name: e.target.value })}
                />
              </div>
              <div className="min-w-0">
                <label className="label" htmlFor={`${uid}s${i}r`}>
                  Approved by
                </label>
                <select
                  id={`${uid}s${i}r`}
                  className="input !h-9 !py-0 text-sm"
                  value={s.approverRole}
                  onChange={(e) => patch(i, { approverRole: e.target.value })}
                >
                  {roles.map((r) => (
                    <option key={r} value={r}>
                      {roleLabel(r)}
                    </option>
                  ))}
                </select>
              </div>
              <div className="min-w-0">
                <label className="label" htmlFor={`${uid}s${i}c`}>
                  Acting for
                </label>
                <select
                  id={`${uid}s${i}c`}
                  className="input !h-9 !py-0 text-sm"
                  value={s.approverScope}
                  onChange={(e) => patch(i, { approverScope: e.target.value })}
                >
                  {GRANT_SCOPES.map((g) => (
                    <option key={g} value={g}>
                      {GRANT_SCOPE_LABEL[g]}
                    </option>
                  ))}
                </select>
              </div>
              <div className="min-w-0">
                <label className="label" htmlFor={`${uid}s${i}q`}>
                  Approvals needed
                </label>
                <select
                  id={`${uid}s${i}q`}
                  className="input !h-9 !py-0 text-sm"
                  value={String(s.requiredApprovals)}
                  onChange={(e) => patch(i, { requiredApprovals: Number(e.target.value) })}
                >
                  {[1, 2, 3, 4, 5].map((n) => (
                    <option key={n} value={n}>
                      {n}
                    </option>
                  ))}
                </select>
              </div>
            </div>
            <p className="text-xs muted break-words">
              {roleLabel(s.approverRole)}
              {s.approverScope === 'organization'
                ? ' anywhere in the organization'
                : ` for the ${GRANT_SCOPE_LABEL[s.approverScope as (typeof GRANT_SCOPES)[number]].toLowerCase()} the ${
                    APPROVAL_ENTITY_LABEL[entityType].toLowerCase()
                  } belongs to`}
              {s.requiredApprovals > 1 ? ` · ${s.requiredApprovals} of them must approve` : ''}
            </p>
          </li>
        ))}
      </ol>

      <div className="flex flex-wrap gap-2 items-center">
        <button
          type="button"
          className="btn btn-ghost !h-9 !px-3 text-sm"
          disabled={steps.length >= 20}
          onClick={() => setSteps((s) => [...s, blankStep(s.length + 1, roles)])}
        >
          Add a step
        </button>
        <button
          type="button"
          className="btn btn-primary"
          disabled={pending}
          onClick={() => {
            setResult(null);
            start(async () => {
              const res = await saveWorkflow({
                id: workflow?.id ?? null,
                entityType,
                name,
                isActive,
                steps,
              });
              if (!res.ok) return setResult({ text: res.error, ok: false });
              setResult({ text: res.message ?? 'Saved.', ok: true });
              router.refresh();
            });
          }}
        >
          {pending ? 'Saving…' : workflow ? 'Save chain' : 'Create chain'}
        </button>
        {result && (
          <p
            className="text-sm basis-full break-words"
            role={result.ok ? 'status' : 'alert'}
            style={{ color: result.ok ? 'var(--color-verified)' : 'var(--color-danger)' }}
          >
            {result.text}
          </p>
        )}
      </div>
    </div>
  );
}
