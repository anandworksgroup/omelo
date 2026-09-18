'use client';

import Link from 'next/link';
import { useEffect, useRef, useState, useTransition } from 'react';
import { switchWorkspace } from './workspace-actions';

export type WorkspaceOption = {
  companyId: string;
  companyName: string;
  kind: 'employer' | 'agency';
  isIndependent: boolean;
  isVerified: boolean;
  role: string;
};

function kindLabel(w: Pick<WorkspaceOption, 'kind' | 'isIndependent'>) {
  if (w.kind === 'agency') return w.isIndependent ? 'Independent recruiter' : 'Agency';
  return 'Employer';
}

function Verified({ ok }: { ok: boolean }) {
  return ok ? (
    <span style={{ color: 'var(--color-verified)' }}>verified</span>
  ) : (
    <span style={{ color: 'var(--color-warn)' }}>unverified</span>
  );
}

/**
 * The company (workspace) you are working in. With one membership it is a
 * plain label; with several it opens a menu. Switching is remembered in a
 * cookie; access is still decided by the database on every request.
 */
export default function WorkspaceSwitcher({
  current,
  options,
}: {
  current: WorkspaceOption;
  options: WorkspaceOption[];
}) {
  const [open, setOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const close = (e: MouseEvent | KeyboardEvent) => {
      if (e instanceof KeyboardEvent ? e.key === 'Escape' : !ref.current?.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', close);
    document.addEventListener('keydown', close);
    return () => {
      document.removeEventListener('mousedown', close);
      document.removeEventListener('keydown', close);
    };
  }, [open]);

  return (
    <div className="relative min-w-0" ref={ref}>
      <button
        type="button"
        className="pill max-w-[52vw] sm:max-w-xs inline-flex items-center gap-1.5 min-w-0"
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
        title="Switch company"
      >
        <span className="truncate min-w-0 font-semibold">{current.companyName}</span>
        <span className="hidden sm:inline shrink-0 muted">· {kindLabel(current)}</span>
        <span className="shrink-0 hidden sm:inline">
          · <Verified ok={current.isVerified} />
        </span>
        <span aria-hidden className="shrink-0 muted">
          ▾
        </span>
      </button>

      {open && (
        <div
          role="menu"
          className="card absolute left-0 mt-2 z-50 w-[min(20rem,calc(100vw-2rem))] p-1.5 shadow-lg"
          style={{ background: 'var(--bg)' }}
        >
          <p className="px-2.5 pt-1.5 pb-1 text-xs font-semibold muted uppercase tracking-wide">Your workspaces</p>
          <ul>
            {options.map((w) => {
              const isCurrent = w.companyId === current.companyId;
              return (
                <li key={w.companyId}>
                  <button
                    type="button"
                    role="menuitemradio"
                    aria-checked={isCurrent}
                    disabled={pending || isCurrent}
                    className="w-full text-left rounded-lg px-2.5 py-2 hover:bg-[var(--surface)] disabled:cursor-default"
                    style={isCurrent ? { background: 'var(--surface)' } : undefined}
                    onClick={() => {
                      setError(null);
                      start(async () => {
                        const res = await switchWorkspace(w.companyId);
                        if (res && !res.ok) setError(res.error);
                      });
                    }}
                  >
                    <span className="flex items-center gap-2">
                      <span className="font-semibold text-sm break-words min-w-0 flex-1">{w.companyName}</span>
                      {isCurrent && (
                        <span aria-hidden style={{ color: 'var(--color-brand-600)' }}>
                          ✓
                        </span>
                      )}
                    </span>
                    <span className="block text-xs muted">
                      {kindLabel(w)} · {w.role.replace(/_/g, ' ')} · <Verified ok={w.isVerified} />
                    </span>
                  </button>
                </li>
              );
            })}
          </ul>
          {error && (
            <p className="text-sm px-2.5 py-1" role="alert" style={{ color: 'var(--color-danger)' }}>
              {error}
            </p>
          )}
          <div className="border-t hairline mt-1.5 pt-1.5">
            <Link
              href="/onboarding/agency"
              className="block rounded-lg px-2.5 py-2 text-sm hover:bg-[var(--surface)]"
              onClick={() => setOpen(false)}
            >
              + Create an agency
            </Link>
          </div>
          {pending && <p className="text-xs muted px-2.5 pb-1">Switching…</p>}
        </div>
      )}
    </div>
  );
}
