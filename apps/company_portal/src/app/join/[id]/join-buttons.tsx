'use client';

import { useRouter } from 'next/navigation';
import { useState, useTransition } from 'react';
import { acceptTeamInvitation, declineTeamInvitation } from '../../dashboard/workspace-actions';

export default function JoinButtons({
  invitationId,
  companyName,
  back,
}: {
  invitationId: string;
  companyName: string;
  back: string;
}) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [declined, setDeclined] = useState(false);
  const [pending, start] = useTransition();

  if (declined) {
    return (
      <div className="card p-4 space-y-3" role="status">
        <p className="text-sm">You declined the invitation from {companyName}.</p>
        <button type="button" className="btn btn-ghost" onClick={() => router.push(back)}>
          Continue
        </button>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          className="btn btn-primary w-full sm:w-auto"
          disabled={pending}
          onClick={() => {
            setError(null);
            start(async () => {
              const res = await acceptTeamInvitation(invitationId);
              if (res && !res.ok) setError(res.error);
            });
          }}
        >
          {pending ? 'Working…' : `Join ${companyName}`}
        </button>
        <button
          type="button"
          className="btn btn-ghost w-full sm:w-auto"
          disabled={pending}
          onClick={() => {
            setError(null);
            start(async () => {
              const res = await declineTeamInvitation(invitationId);
              if (!res.ok) setError(res.error);
              else setDeclined(true);
            });
          }}
        >
          Decline
        </button>
      </div>
      {error && (
        <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
          {error}
        </p>
      )}
    </div>
  );
}
