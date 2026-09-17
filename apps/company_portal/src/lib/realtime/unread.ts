'use client';

import { useSyncExternalStore } from 'react';
import { createClient } from '@/lib/supabase/client';
import { UNREAD_CHANGED_EVENT } from '@/lib/messaging';

/*
 * Live unread counts for the header: candidate messages for the company, and
 * the signed-in person's notifications.
 *
 * One shared store per key, however many components read it (the nav is
 * rendered twice for desktop and mobile), so there is one Realtime channel,
 * not one per badge. Realtime triggers a recount; a slow poll covers a
 * blocked or dropped socket.
 */

type Store = {
  value: number;
  listeners: Set<() => void>;
  stop: (() => void) | null;
};

const stores = new Map<string, Store>();
const POLL_MS = 60_000;

function makeHook(
  prefix: string,
  count: (id: string) => Promise<number | null>,
  channel: (id: string, recount: () => void) => () => void
) {
  function getStore(id: string): Store {
    const key = `${prefix}:${id}`;
    let s = stores.get(key);
    if (!s) {
      s = { value: 0, listeners: new Set(), stop: null };
      stores.set(key, s);
    }
    return s;
  }

  function start(id: string, s: Store) {
    let alive = true;
    let timer: ReturnType<typeof setTimeout> | null = null;
    const recount = () => {
      // Coalesce bursts (e.g. mark-all-read updates many rows at once).
      if (timer) clearTimeout(timer);
      timer = setTimeout(async () => {
        timer = null;
        const n = await count(id);
        if (!alive || n == null || n === s.value) return;
        s.value = n;
        s.listeners.forEach((l) => l());
      }, 250);
    };
    recount();
    const unsubscribe = channel(id, recount);
    const poll = setInterval(recount, POLL_MS);
    const onLocal = () => recount();
    const onVisible = () => {
      if (document.visibilityState === 'visible') recount();
    };
    window.addEventListener(UNREAD_CHANGED_EVENT, onLocal);
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      alive = false;
      if (timer) clearTimeout(timer);
      clearInterval(poll);
      unsubscribe();
      window.removeEventListener(UNREAD_CHANGED_EVENT, onLocal);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }

  return function useUnread(id: string) {
    const s = getStore(id);
    return useSyncExternalStore(
      (listener) => {
        s.listeners.add(listener);
        if (!s.stop) s.stop = start(id, s);
        return () => {
          s.listeners.delete(listener);
          if (s.listeners.size === 0 && s.stop) {
            s.stop();
            s.stop = null;
          }
        };
      },
      () => s.value,
      () => 0
    );
  };
}

/** Messages from candidates, not yet read by anyone on the hiring team. */
export const useUnreadMessages = makeHook(
  'messages',
  async (companyId) => {
    const supabase = createClient();
    const { count, error } = await supabase
      .from('messages')
      .select('id, conversations!inner ( company_id )', { count: 'exact', head: true })
      .eq('conversations.company_id', companyId)
      .eq('sender_type', 'candidate')
      .is('read_at', null);
    return error ? null : (count ?? 0);
  },
  (companyId, recount) => {
    const supabase = createClient();
    // RLS scopes postgres_changes to rows this user can read.
    const ch = supabase
      .channel(`unread-messages-${companyId}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' }, recount)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'messages' }, recount)
      .subscribe();
    return () => void supabase.removeChannel(ch);
  }
);

/** The signed-in person's unread notifications. */
export const useUnreadNotifications = makeHook(
  'notifications',
  async (personId) => {
    const supabase = createClient();
    const { count, error } = await supabase
      .from('notifications')
      .select('id', { count: 'exact', head: true })
      .eq('person_id', personId)
      .is('read_at', null);
    return error ? null : (count ?? 0);
  },
  (personId, recount) => {
    const supabase = createClient();
    const filter = `person_id=eq.${personId}`;
    const ch = supabase
      .channel(`unread-notifications-${personId}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'notifications', filter }, recount)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'notifications', filter }, recount)
      .on('postgres_changes', { event: 'DELETE', schema: 'public', table: 'notifications' }, recount)
      .subscribe();
    return () => void supabase.removeChannel(ch);
  }
);
