'use client';

import { usePathname } from 'next/navigation';
import { useState, useTransition } from 'react';
import { switchWorkspace } from '../workspace-actions';

/** Shown when an agency link is opened from an employer workspace. */
export default function SwitchPrompt({ agencies, current }: { agencies: { id: string; name: string }[]; current: string }) {
  const path = usePathname();
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  return (
    <div className="card p-6 sm:p-8 max-w-xl space-y-4">
      <div>
        <h1 className="text-xl font-bold">This page belongs to your agency</h1>
        <p className="text-sm muted mt-1">
          You are working in {current}. Switch to your agency workspace to open it.
        </p>
      </div>
      <div className="flex flex-wrap gap-2">
        {agencies.map((a) => (
          <button
            key={a.id}
            type="button"
            className="btn btn-primary w-full sm:w-auto"
            disabled={pending}
            onClick={() =>
              start(async () => {
                setError(null);
                const res = await switchWorkspace(a.id, path);
                if (res && !res.ok) setError(res.error);
              })
            }
          >
            Switch to {a.name}
          </button>
        ))}
      </div>
      {error && (
        <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
          {error}
        </p>
      )}
    </div>
  );
}
