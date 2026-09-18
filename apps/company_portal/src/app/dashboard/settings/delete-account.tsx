'use client';

import { useState, useTransition } from 'react';
import LocalTime from '../local-time';
import { cancelAccountDeletion, requestAccountDeletion } from './actions';

const danger = { background: 'var(--color-danger)', color: '#fff' } as const;

export default function DeleteAccount({ scheduledFor }: { scheduledFor: string | null }) {
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState('');
  const [confirm, setConfirm] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  if (scheduledFor) {
    return (
      <div>
        <p className="text-sm leading-relaxed">
          Your account is scheduled for deletion on{' '}
          <LocalTime iso={scheduledFor} withTime={false} className="font-semibold" />. Until then you can keep
          using Omelo and cancel at any time.
        </p>
        <button
          type="button"
          className="btn btn-primary mt-4"
          disabled={pending}
          onClick={() => {
            setError(null);
            start(async () => {
              const res = await cancelAccountDeletion();
              if (res.error) setError(res.error);
            });
          }}
        >
          {pending ? 'Cancelling…' : 'Cancel deletion'}
        </button>
        {error && (
          <p className="text-sm mt-3" role="alert" style={{ color: 'var(--color-danger)' }}>
            {error}
          </p>
        )}
      </div>
    );
  }

  return (
    <div>
      <div className="text-sm leading-relaxed space-y-2">
        <p>
          Deleting your account starts a <strong>14-day grace period</strong>. You can cancel any time before it
          ends — just sign in and choose Cancel deletion.
        </p>
        <p>
          After 14 days your sign-in, profile and personal data are permanently deleted. Work your team still needs
          — jobs you posted, interviews you ran — stays with the company, no longer linked to you.
        </p>
        <p>
          Companies where you are the <strong>only member</strong> are closed and their jobs are taken down. If you
          are the only owner of a team with other members, make someone else an owner first.
        </p>
      </div>

      {!open ? (
        <button type="button" className="btn btn-ghost mt-4" onClick={() => setOpen(true)}>
          Delete my account…
        </button>
      ) : (
        <form
          className="mt-4 space-y-4"
          onSubmit={(e) => {
            e.preventDefault();
            setError(null);
            start(async () => {
              const res = await requestAccountDeletion(reason, confirm);
              if (res.error) setError(res.error);
            });
          }}
        >
          <div>
            <label className="label" htmlFor="delete-reason">
              Why are you leaving? <span className="muted font-normal">(optional)</span>
            </label>
            <textarea
              id="delete-reason"
              className="input"
              rows={3}
              maxLength={1000}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
            />
          </div>
          <div>
            <label className="label" htmlFor="delete-confirm">
              Type <span className="font-mono">DELETE</span> to confirm
            </label>
            <input
              id="delete-confirm"
              className="input font-mono"
              style={{ maxWidth: 220 }}
              autoComplete="off"
              spellCheck={false}
              value={confirm}
              onChange={(e) => setConfirm(e.target.value)}
            />
          </div>

          {error && (
            <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
              {error}
            </p>
          )}

          <div className="flex gap-3 flex-wrap">
            <button className="btn" style={danger} disabled={pending || confirm.trim() !== 'DELETE'}>
              {pending ? 'Scheduling…' : 'Delete my account in 14 days'}
            </button>
            <button
              type="button"
              className="btn btn-ghost"
              disabled={pending}
              onClick={() => {
                setOpen(false);
                setConfirm('');
                setError(null);
              }}
            >
              Keep my account
            </button>
          </div>
        </form>
      )}
    </div>
  );
}
