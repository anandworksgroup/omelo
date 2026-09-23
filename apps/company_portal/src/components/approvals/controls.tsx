'use client';

import { useRouter } from 'next/navigation';
import { useId, useState, useTransition } from 'react';
import {
  cancelApproval,
  decideApproval,
  submitForApproval,
  type ApprovalResult,
} from '@/app/dashboard/approvals/actions';

function Line({ text, ok }: { text: string | null; ok?: boolean }) {
  if (!text) return null;
  return (
    <p
      className="text-sm basis-full break-words"
      role={ok ? 'status' : 'alert'}
      style={{ color: ok ? 'var(--color-verified)' : 'var(--color-danger)' }}
    >
      {text}
    </p>
  );
}

/** Approve or decline one step. A decline always carries a reason. */
export function DecideControls({ requestId }: { requestId: string }) {
  const uid = useId();
  const router = useRouter();
  const [note, setNote] = useState('');
  const [result, setResult] = useState<{ text: string; ok: boolean } | null>(null);
  const [pending, start] = useTransition();

  function run(approve: boolean) {
    setResult(null);
    start(async () => {
      const res: ApprovalResult = await decideApproval(requestId, approve, note);
      if (!res.ok) return setResult({ text: res.error, ok: false });
      setNote('');
      setResult({ text: res.message ?? 'Done.', ok: true });
      router.refresh();
    });
  }

  return (
    <div className="space-y-2 w-full">
      <label className="label !mb-1" htmlFor={`${uid}n`}>
        Note <span className="muted font-normal">· required when you decline</span>
      </label>
      <textarea
        id={`${uid}n`}
        className="input"
        rows={2}
        maxLength={1000}
        value={note}
        onChange={(e) => setNote(e.target.value)}
        placeholder="What the person who asked should know."
      />
      <div className="flex gap-2 flex-wrap">
        <button type="button" className="btn btn-primary !h-9 !px-3 text-sm" disabled={pending} onClick={() => run(true)}>
          {pending ? 'Saving…' : 'Approve'}
        </button>
        <button
          type="button"
          className="btn btn-ghost !h-9 !px-3 text-sm"
          style={{ color: 'var(--color-danger)' }}
          disabled={pending}
          onClick={() => run(false)}
        >
          Decline
        </button>
        <Line text={result?.text ?? null} ok={result?.ok} />
      </div>
    </div>
  );
}

/** Send a job, requirement or offer into the chain. */
export function SubmitForApproval({
  entityType,
  entityId,
  label = 'Submit for approval',
}: {
  entityType: string;
  entityId: string;
  label?: string;
}) {
  const uid = useId();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [note, setNote] = useState('');
  const [result, setResult] = useState<{ text: string; ok: boolean } | null>(null);
  const [pending, start] = useTransition();

  if (!open)
    return (
      <div className="flex items-center gap-3 flex-wrap">
        <button type="button" className="btn btn-primary" onClick={() => setOpen(true)}>
          {label}
        </button>
        {result?.ok && <Line text={result.text} ok />}
      </div>
    );

  return (
    <div className="space-y-2 w-full">
      <label className="label !mb-1" htmlFor={`${uid}n`}>
        Anything the approvers should know?
      </label>
      <textarea
        id={`${uid}n`}
        className="input"
        rows={2}
        maxLength={1000}
        value={note}
        onChange={(e) => setNote(e.target.value)}
        placeholder="Optional."
      />
      <div className="flex gap-2 flex-wrap">
        <button
          type="button"
          className="btn btn-primary"
          disabled={pending}
          onClick={() => {
            setResult(null);
            start(async () => {
              const res = await submitForApproval(entityType, entityId, note);
              if (!res.ok) return setResult({ text: res.error, ok: false });
              setOpen(false);
              setNote('');
              setResult({ text: res.message ?? 'Sent.', ok: true });
              router.refresh();
            });
          }}
        >
          {pending ? 'Sending…' : 'Send for approval'}
        </button>
        <button type="button" className="btn btn-ghost" onClick={() => setOpen(false)}>
          Cancel
        </button>
        <Line text={result?.text ?? null} ok={result?.ok} />
      </div>
    </div>
  );
}

/** Withdraw an open request: the person who asked, or an owner or admin. */
export function WithdrawApproval({
  requestId,
  entityType,
  entityId,
}: {
  requestId: string;
  entityType?: string;
  entityId?: string;
}) {
  const router = useRouter();
  const [confirming, setConfirming] = useState(false);
  const [result, setResult] = useState<{ text: string; ok: boolean } | null>(null);
  const [pending, start] = useTransition();

  if (!confirming)
    return (
      <div className="flex items-center gap-2 flex-wrap">
        <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setConfirming(true)}>
          Withdraw
        </button>
        <Line text={result?.text ?? null} ok={result?.ok} />
      </div>
    );

  return (
    <div className="flex items-center gap-2 flex-wrap">
      <span className="text-sm">Withdraw this request?</span>
      <button
        type="button"
        className="btn btn-ghost !h-9 !px-3 text-sm"
        style={{ color: 'var(--color-danger)' }}
        disabled={pending}
        onClick={() => {
          setResult(null);
          start(async () => {
            const res = await cancelApproval(requestId, '', entityType, entityId);
            setConfirming(false);
            if (!res.ok) return setResult({ text: res.error, ok: false });
            setResult({ text: res.message ?? 'Withdrawn.', ok: true });
            router.refresh();
          });
        }}
      >
        {pending ? 'Withdrawing…' : 'Yes, withdraw'}
      </button>
      <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setConfirming(false)}>
        Keep it
      </button>
      <Line text={result?.text ?? null} ok={result?.ok} />
    </div>
  );
}
