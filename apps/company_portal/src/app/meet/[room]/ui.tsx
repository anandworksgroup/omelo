'use client';

import { useEffect, useRef } from 'react';

/* ------------------------------------------------------------------ */
/* Icons (inline, currentColor)                                        */
/* ------------------------------------------------------------------ */

type IconName =
  | 'mic'
  | 'mic-off'
  | 'cam'
  | 'cam-off'
  | 'screen'
  | 'chat'
  | 'more'
  | 'leave'
  | 'panel'
  | 'close'
  | 'lock'
  | 'users'
  | 'flag'
  | 'external';

const PATHS: Record<IconName, React.ReactNode> = {
  mic: (
    <>
      <rect x="9" y="3" width="6" height="11" rx="3" />
      <path d="M5 11a7 7 0 0 0 14 0M12 18v3" />
    </>
  ),
  'mic-off': (
    <>
      <path d="M15 10V6a3 3 0 0 0-5.7-1.3M9 9v2a3 3 0 0 0 5.1 2.1M5 11a7 7 0 0 0 11.5 5.4M19 11a7 7 0 0 1-.6 2.8M12 18v3M3 3l18 18" />
    </>
  ),
  cam: (
    <>
      <rect x="3" y="6" width="13" height="12" rx="2" />
      <path d="m16 10 5-3v10l-5-3" />
    </>
  ),
  'cam-off': (
    <>
      <path d="M16 16v1a1 1 0 0 1-1 1H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h1m4 0h5a1 1 0 0 1 1 1v3l5-3v10M3 3l18 18" />
    </>
  ),
  screen: (
    <>
      <rect x="3" y="4" width="18" height="12" rx="2" />
      <path d="M8 20h8M12 16v4M9 10l3-3 3 3M12 7v6" />
    </>
  ),
  chat: <path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.4A8 8 0 1 1 21 12Z" />,
  more: (
    <>
      <circle cx="12" cy="5" r="1.2" />
      <circle cx="12" cy="12" r="1.2" />
      <circle cx="12" cy="19" r="1.2" />
    </>
  ),
  leave: <path d="M3 15.5c5.5-5 12.5-5 18 0l-2.5 2.5-3.5-1.5v-3a11 11 0 0 0-6 0v3L5.5 18 3 15.5Z" />,
  panel: (
    <>
      <rect x="3" y="4" width="18" height="16" rx="2" />
      <path d="M14 4v16" />
    </>
  ),
  close: <path d="M6 6l12 12M18 6 6 18" />,
  lock: (
    <>
      <rect x="5" y="11" width="14" height="10" rx="2" />
      <path d="M8 11V8a4 4 0 0 1 8 0v3" />
    </>
  ),
  users: (
    <>
      <circle cx="9" cy="8" r="3.5" />
      <path d="M2.5 20a6.5 6.5 0 0 1 13 0M16 4.5a3.5 3.5 0 0 1 0 7M18 14a6.5 6.5 0 0 1 3.5 6" />
    </>
  ),
  flag: <path d="M5 21V4m0 0h11l-2 4 2 4H5" />,
  external: <path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5" />,
};

export function Icon({ name, className = 'h-5 w-5' }: { name: IconName; className?: string }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden
    >
      {PATHS[name]}
    </svg>
  );
}

/* ------------------------------------------------------------------ */
/* Bottom-bar button                                                   */
/* ------------------------------------------------------------------ */

export function BarButton({
  icon,
  label,
  onClick,
  active = true,
  danger = false,
  disabled = false,
  badge,
  showLabel = false,
  pressed,
}: {
  icon: IconName;
  label: string;
  onClick?: () => void;
  active?: boolean;
  danger?: boolean;
  disabled?: boolean;
  badge?: number;
  showLabel?: boolean;
  pressed?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-label={label}
      aria-pressed={pressed}
      title={label}
      className={`relative inline-flex items-center justify-center gap-2 h-11 rounded-full text-sm font-semibold transition-colors disabled:opacity-40 disabled:cursor-not-allowed ${
        showLabel ? 'px-4' : 'w-11'
      }`}
      style={{
        background: danger ? 'var(--color-danger)' : active ? 'rgba(255,255,255,.12)' : '#f4f4f5',
        color: danger ? '#fff' : active ? '#fff' : '#18181b',
      }}
    >
      <Icon name={icon} />
      {showLabel && <span className="hidden sm:inline">{label}</span>}
      {badge ? (
        <span
          className="absolute -top-1 -right-1 min-w-5 h-5 px-1 rounded-full text-[11px] leading-5 text-center"
          style={{ background: 'var(--color-accent-500)', color: '#1b1b1b' }}
        >
          {badge > 9 ? '9+' : badge}
        </span>
      ) : null}
    </button>
  );
}

/* ------------------------------------------------------------------ */
/* Modal                                                               */
/* ------------------------------------------------------------------ */

export function Modal({
  title,
  onClose,
  children,
}: {
  title: string;
  onClose: () => void;
  children: React.ReactNode;
}) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const prev = document.activeElement as HTMLElement | null;
    ref.current?.querySelector<HTMLElement>('input, textarea, select, button')?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('keydown', onKey);
      prev?.focus?.();
    };
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 z-50 grid place-items-center p-4"
      style={{ background: 'rgba(0,0,0,.55)' }}
      onMouseDown={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div
        ref={ref}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        className="card w-full max-w-md p-5 space-y-4 shadow-xl"
        style={{ color: 'var(--fg)' }}
      >
        <div className="flex items-center gap-3">
          <h2 className="font-bold flex-1">{title}</h2>
          <button type="button" onClick={onClose} aria-label="Close" className="muted hover:opacity-70">
            <Icon name="close" />
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}

export function Restricted() {
  return (
    <p className="text-sm muted surface rounded-lg p-3 flex items-center gap-2">
      <Icon name="lock" className="h-4 w-4 shrink-0" />
      Only the hiring team can see this.
    </p>
  );
}
