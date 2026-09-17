'use client';

import NotificationRow from './notification-row';
import { useNotifications } from './use-notifications';

/** Full notification list for /dashboard/notifications. */
export default function NotificationList({ personId }: { personId: string }) {
  const feed = useNotifications(personId, 200);
  const unread = feed.items.filter((n) => !n.read_at).length;

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3 flex-wrap">
        <p className="text-sm muted flex-1">
          {feed.loaded ? (unread > 0 ? `${unread} unread` : 'All read') : ' '}
        </p>
        {unread > 0 && (
          <button type="button" className="btn btn-ghost" onClick={() => void feed.markAllRead()}>
            Mark all read
          </button>
        )}
      </div>

      {feed.error && (
        <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
          {feed.error}
        </p>
      )}

      <div className="card p-1.5">
        {!feed.loaded ? (
          <p className="text-sm muted p-4">Loading…</p>
        ) : feed.items.length === 0 ? (
          <p className="text-sm muted p-4">
            No notifications yet. Candidate replies, interview updates and offer responses show up here.
          </p>
        ) : (
          <ul className="divide-y divide-[var(--line)]">
            {feed.items.map((n) => (
              <NotificationRow
                key={n.id}
                n={n}
                onRead={(id) => void feed.markRead(id)}
                onRemove={(id) => void feed.remove(id)}
              />
            ))}
          </ul>
        )}
      </div>
      {feed.loaded && feed.items.length >= 200 && (
        <p className="text-xs muted">Showing the 200 most recent notifications.</p>
      )}
    </div>
  );
}
