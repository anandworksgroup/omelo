'use client';

import { useState, useTransition } from 'react';
import { setCapability } from './capability-actions';

/**
 * The optional modules an organization has turned on.
 *
 * Core hiring is not here and never will be: a page, jobs, candidates,
 * interviews, hiring, posts and a team come with every organization. These are
 * the parts a company hiring only for itself has no use for, so its workspace
 * does not carry them around until it says otherwise.
 *
 * Turning one on opens the workflow. It does not hand over any client's data:
 * a client relationship still has to be confirmed by that client, and a worker
 * still has to consent before anyone may represent them.
 */
export const CAPABILITIES = [
  {
    key: 'client_recruitment',
    title: 'Client recruitment',
    body:
      'Keep client relationships, take job orders, source and submit candidates for them, and track placements. Your own hiring carries on exactly as it is.',
  },
  {
    key: 'workforce',
    title: 'Workforce and shifts',
    body:
      'Requirements, rosters, attendance, timesheets, earnings and pay for the people working through you.',
  },
  {
    key: 'rpo',
    title: 'RPO engagements',
    body:
      'Run hiring inside a client’s own process, or let a provider run yours, within a scope that client confirms.',
  },
  {
    key: 'billing',
    title: 'Client billing',
    body:
      'Bill rates and client billing records, kept apart from what the worker is paid.',
  },
] as const;

export default function Capabilities({
  companyId,
  enabled,
  canEdit,
  inUse,
}: {
  companyId: string;
  enabled: Record<string, boolean>;
  canEdit: boolean;
  /** Modules with records behind them already — those stay on. */
  inUse: Record<string, boolean>;
}) {
  const [state, setState] = useState(enabled);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  function toggle(key: string, next: boolean) {
    setError(null);
    setState((s) => ({ ...s, [key]: next }));
    start(async () => {
      const res = await setCapability(companyId, key, next);
      if (res && !res.ok) {
        setState((s) => ({ ...s, [key]: !next }));
        setError(res.error);
      }
    });
  }

  return (
    <section className="card p-5 space-y-4">
      <div>
        <h2>What this organization does</h2>
        <p className="text-sm muted mt-1 leading-relaxed">
          Every organization on Omelo publishes jobs, manages candidates, interviews and
          hires. These are the extras. Turn one on whenever you need it — you never have to
          create a second organization for it.
        </p>
      </div>

      <ul className="space-y-2">
        {CAPABILITIES.map((c) => {
          const on = state[c.key] ?? false;
          const locked = inUse[c.key] && on;
          return (
            <li key={c.key} className="panel p-3 flex items-start gap-3">
              <input
                type="checkbox"
                id={`cap-${c.key}`}
                checked={on}
                disabled={!canEdit || pending || locked}
                onChange={(e) => toggle(c.key, e.target.checked)}
                className="mt-0.5"
              />
              <label htmlFor={`cap-${c.key}`} className="min-w-0 flex-1 cursor-pointer">
                <span className="font-semibold text-sm flex items-center gap-2 flex-wrap">
                  {c.title}
                  {on && <span className="pill pill-success">On</span>}
                </span>
                <span className="text-sm muted block mt-0.5">{c.body}</span>
                {locked && (
                  <span className="hint block">
                    In use — there are records here already, so this stays on.
                  </span>
                )}
              </label>
            </li>
          );
        })}
      </ul>

      {error && <p className="error-text">{error}</p>}
      {!canEdit && (
        <p className="hint !mt-0">Only an owner or admin can change these.</p>
      )}
    </section>
  );
}
