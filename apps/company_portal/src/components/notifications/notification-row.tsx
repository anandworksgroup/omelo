'use client';

import { useRouter } from 'next/navigation';
import { portalDeeplink, shortAgo } from '@/lib/messaging';
import { useIsClient } from '@/lib/use-is-client';
import type { NotificationItem } from './use-notifications';

const TYPE_LABEL: Record<string, string> = {
  message_received: 'Message',
  interview_scheduled: 'Interview',
  application_update: 'Application',
  offer_received: 'Offer',
};

export function typeLabel(type: string) {
  return TYPE_LABEL[type] ?? type.replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase());
}

/** One notification. Clicking marks it read and follows its link, if it has one here. */
export default function NotificationRow({
  n,
  onRead,
  onRemove,
  onNavigate,
  compact = false,
}: {
  n: NotificationItem;
  onRead: (id: number) => void;
  onRemove?: (id: number) => void;
  onNavigate?: () => void;
  compact?: boolean;
}) {
  const router = useRouter();
  const isClient = useIsClient();
  const href = portalDeeplink(n.deeplink);
  const unread = !n.read_at;

  const open = () => {
    if (unread) onRead(n.id);
    if (href) {
      onNavigate?.();
      router.push(href);
    }
  };

  return (
    <li className="flex items-stretch gap-1">
      <button
        type="button"
        onClick={open}
        className={`flex-1 min-w-0 text-left flex gap-3 rounded-lg px-3 py-2.5 hover:bg-[var(--surface)] ${
          href || unread ? 'cursor-pointer' : 'cursor-default'
        }`}
        aria-label={`${unread ? 'Unread: ' : ''}${n.title}`}
      >
        <span
          aria-hidden
          className="mt-1.5 h-2 w-2 rounded-full shrink-0"
          style={{ background: unread ? 'var(--color-brand-600)' : 'transparent' }}
        />
        <span className="min-w-0 flex-1">
          <span className={`block text-sm break-words ${unread ? 'font-semibold' : ''}`}>{n.title}</span>
          {n.body && (
            <span className={`block text-sm muted break-words ${compact ? 'line-clamp-2' : ''}`}>
              {n.body}
            </span>
          )}
          <span className="block text-xs muted mt-0.5">
            {typeLabel(n.type)}
            {isClient ? ` · ${shortAgo(n.created_at)}` : ''}
          </span>
        </span>
      </button>
      {onRemove && (
        <button
          type="button"
          onClick={() => onRemove(n.id)}
          className="text-xs muted underline px-2 shrink-0"
          aria-label={`Delete notification: ${n.title}`}
        >
          Delete
        </button>
      )}
    </li>
  );
}
