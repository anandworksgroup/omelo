/*
 * Shared by the inbox, the thread and the notification bell.
 *
 * All message writes go through SECURITY DEFINER RPCs (omelo_send_message,
 * omelo_start_conversation, omelo_mark_conversation_read). Direct inserts
 * into `messages` are blocked by RLS, so nothing here builds one.
 */

export const MESSAGE_MAX = 4000;

/** Application states in which the employer can no longer write. */
export const MESSAGING_CLOSED_STATES = ['withdrawn', 'declined_by_candidate'];

export type ThreadMessage = {
  id: number;
  conversation_id: string;
  sender_person_id: string | null;
  sender_type: string;
  kind: string;
  body: string | null;
  read_at: string | null;
  sent_at: string;
};

export const MESSAGE_COLUMNS =
  'id, conversation_id, sender_person_id, sender_type, kind, body, read_at, sent_at';

/** Fired after this tab marks messages or notifications read, so badges refresh at once. */
export const UNREAD_CHANGED_EVENT = 'omelo:unread-changed';

export function announceUnreadChanged() {
  if (typeof window !== 'undefined') window.dispatchEvent(new Event(UNREAD_CHANGED_EVENT));
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const isUuid = (v: string) => UUID.test(v);

/**
 * Where a notification should take an employer, or null when it has no
 * destination in this portal.
 *
 * Only same-origin paths the portal owns are followed. Worker-app links
 * (e.g. /applications/…) on an account that is also a job seeker are not.
 */
export function portalDeeplink(deeplink: string | null): string | null {
  if (!deeplink) return null;
  if (!deeplink.startsWith('/') || deeplink.startsWith('//') || deeplink.includes('\\')) return null;
  if (/^\/dashboard(\/|$)/.test(deeplink) || /^\/meet\/[^/]+$/.test(deeplink)) return deeplink;
  return null;
}

/** "3:04 pm" today, "Mon 3:04 pm" this week, "17 Sep, 3:04 pm" otherwise. Viewer's timezone. */
export function messageStamp(iso: string): string {
  const d = new Date(iso);
  const now = new Date();
  const time = d.toLocaleTimeString('en-IN', { hour: 'numeric', minute: '2-digit' });
  if (d.toDateString() === now.toDateString()) return time;
  const days = (now.getTime() - d.getTime()) / 86_400_000;
  if (days < 6) return `${d.toLocaleDateString('en-IN', { weekday: 'short' })} ${time}`;
  const date = d.toLocaleDateString('en-IN', {
    day: 'numeric',
    month: 'short',
    ...(d.getFullYear() === now.getFullYear() ? {} : { year: 'numeric' }),
  });
  return `${date}, ${time}`;
}

/** "just now", "5 min ago", "2 h ago", then a date. */
export function shortAgo(iso: string): string {
  const s = (Date.now() - new Date(iso).getTime()) / 1000;
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.floor(s / 60)} min ago`;
  if (s < 86_400) return `${Math.floor(s / 3600)} h ago`;
  if (s < 7 * 86_400) return `${Math.floor(s / 86_400)} d ago`;
  return new Date(iso).toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
}
