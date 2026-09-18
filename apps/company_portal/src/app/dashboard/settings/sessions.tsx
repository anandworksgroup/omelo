'use client';

import { useState, useTransition } from 'react';
import { revokeOtherSessions, revokeSession } from './actions';

export type SessionRow = {
  id: string;
  device: string;
  lastActive: string;
  ipHint: string | null;
  isCurrent: boolean;
};

export default function Sessions({ sessions }: { sessions: SessionRow[] }) {
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [pending, start] = useTransition();

  const others = sessions.filter((s) => !s.isCurrent).length;

  function run(key: string, fn: () => Promise<{ error?: string }>, ok: string) {
    setError(null);
    setNotice(null);
    setBusy(key);
    start(async () => {
      const res = await fn();
      setBusy(null);
      if (res.error) setError(res.error);
      else setNotice(ok);
    });
  }

  if (!sessions.length) return <p className="text-sm muted">No active sessions found.</p>;

  return (
    <div>
      <ul>
        {sessions.map((s, i) => (
          <li
            key={s.id}
            className={`py-3 flex items-center justify-between gap-3 flex-wrap ${i ? 'border-t hairline' : ''}`}
          >
            <div className="min-w-0">
              <p className="font-semibold flex items-center gap-2 flex-wrap">
                {s.device}
                {s.isCurrent && (
                  <span className="pill" style={{ color: 'var(--color-brand-600)' }}>
                    This device
                  </span>
                )}
              </p>
              <p className="text-sm muted">
                {s.isCurrent ? 'Active now' : s.lastActive}
                {s.ipHint ? ` · ${s.ipHint}` : ''}
              </p>
            </div>
            {!s.isCurrent && (
              <button
                type="button"
                className="btn btn-ghost"
                disabled={pending}
                onClick={() => run(s.id, () => revokeSession(s.id), 'Signed out.')}
              >
                {busy === s.id ? 'Signing out…' : 'Sign out'}
              </button>
            )}
          </li>
        ))}
      </ul>

      {others > 0 && (
        <button
          type="button"
          className="btn btn-ghost mt-3"
          disabled={pending}
          onClick={() => run('all', revokeOtherSessions, 'Signed out of all other devices.')}
        >
          {busy === 'all' ? 'Signing out…' : 'Sign out of all other devices'}
        </button>
      )}

      {error && (
        <p className="text-sm mt-3" role="alert" style={{ color: 'var(--color-danger)' }}>
          {error}
        </p>
      )}
      {notice && (
        <p className="text-sm mt-3" role="status" style={{ color: 'var(--color-verified)' }}>
          {notice}
        </p>
      )}
    </div>
  );
}
