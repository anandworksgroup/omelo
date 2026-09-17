'use client';

import Link from 'next/link';
import { useEffect, useId, useRef, useState } from 'react';
import { useUnreadNotifications } from '@/lib/realtime/unread';
import NotificationRow from './notification-row';
import { useNotifications } from './use-notifications';

function BellIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9" />
      <path d="M10.3 21a1.94 1.94 0 0 0 3.4 0" />
    </svg>
  );
}

export function CountBadge({ count, label }: { count: number; label: string }) {
  if (count <= 0) return null;
  return (
    <span
      className="inline-flex items-center justify-center min-w-[1.15rem] h-[1.15rem] px-1 rounded-full text-[0.68rem] font-bold leading-none text-white"
      style={{ background: 'var(--color-danger)' }}
      aria-label={`${count} ${label}`}
    >
      {count > 99 ? '99+' : count}
    </span>
  );
}

/** Header bell: live unread count and a panel of recent notifications. */
export default function NotificationBell({ personId }: { personId: string }) {
  const unread = useUnreadNotifications(personId);
  const [open, setOpen] = useState(false);
  const [everOpened, setEverOpened] = useState(false);
  const feed = useNotifications(personId, 15, everOpened);
  const wrap = useRef<HTMLDivElement>(null);
  const panelId = useId();

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      if (wrap.current && !wrap.current.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    document.addEventListener('mousedown', onDown);
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('mousedown', onDown);
      document.removeEventListener('keydown', onKey);
    };
  }, [open]);

  const toggle = () => {
    setEverOpened(true);
    setOpen((o) => !o);
  };

  return (
    <div className="relative" ref={wrap}>
      <button
        type="button"
        onClick={toggle}
        className="relative inline-flex items-center justify-center h-10 w-10 rounded-lg hover:bg-[var(--surface)]"
        aria-label={unread > 0 ? `Notifications, ${unread} unread` : 'Notifications'}
        aria-expanded={open}
        aria-controls={panelId}
      >
        <BellIcon />
        {unread > 0 && (
          <span className="absolute top-0.5 right-0.5">
            <CountBadge count={unread} label="unread" />
          </span>
        )}
      </button>

      {open && (
        <div
          id={panelId}
          role="dialog"
          aria-label="Notifications"
          className="card shadow-lg absolute right-0 top-12 z-50 w-[min(24rem,calc(100vw-2rem))] max-h-[70vh] flex flex-col"
        >
          <div className="flex items-center gap-2 px-4 py-3 border-b hairline">
            <p className="font-bold flex-1">Notifications</p>
            {(unread > 0 || feed.items.some((n) => !n.read_at)) && (
              <button type="button" className="text-sm underline muted" onClick={() => void feed.markAllRead()}>
                Mark all read
              </button>
            )}
          </div>
          <div className="overflow-y-auto p-1.5 flex-1">
            {feed.error ? (
              <p className="text-sm p-3" role="alert" style={{ color: 'var(--color-danger)' }}>
                Could not load notifications: <span className="muted">{feed.error}</span>
              </p>
            ) : !feed.loaded ? (
              <p className="text-sm muted p-3">Loading…</p>
            ) : feed.items.length === 0 ? (
              <p className="text-sm muted p-3">You are all caught up.</p>
            ) : (
              <ul>
                {feed.items.map((n) => (
                  <NotificationRow
                    key={n.id}
                    n={n}
                    compact
                    onRead={(id) => void feed.markRead(id)}
                    onNavigate={() => setOpen(false)}
                  />
                ))}
              </ul>
            )}
          </div>
          <Link
            href="/dashboard/notifications"
            onClick={() => setOpen(false)}
            className="block text-center text-sm font-semibold px-4 py-3 border-t hairline hover:bg-[var(--surface)]"
          >
            See all notifications
          </Link>
        </div>
      )}
    </div>
  );
}
