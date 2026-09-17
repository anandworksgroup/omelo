'use client';

import { useCallback, useEffect, useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import { announceUnreadChanged } from '@/lib/messaging';

export type NotificationItem = {
  id: number;
  type: string;
  title: string;
  body: string | null;
  deeplink: string | null;
  entity_type: string | null;
  entity_id: string | null;
  read_at: string | null;
  created_at: string;
};

const COLUMNS = 'id, type, title, body, deeplink, entity_type, entity_id, read_at, created_at';

/**
 * The signed-in person's notifications, newest first, kept live over
 * Realtime. Rows are only ever marked read or deleted here: RLS and a
 * trigger forbid any other change.
 *
 * `enabled` lets the header bell load only once its panel is first opened.
 */
export function useNotifications(personId: string, limit: number, enabled = true) {
  const [items, setItems] = useState<NotificationItem[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const supabase = createClient();
    const { data, error: e } = await supabase
      .from('notifications')
      .select(COLUMNS)
      .eq('person_id', personId)
      .order('created_at', { ascending: false })
      .order('id', { ascending: false })
      .limit(limit);
    if (e) setError(e.message);
    else {
      setError(null);
      setItems(data ?? []);
    }
    setLoaded(true);
  }, [personId, limit]);

  useEffect(() => {
    if (!enabled) return;
    const supabase = createClient();
    let alive = true;
    const run = () => {
      if (alive) void load();
    };
    run();
    const channel = supabase
      .channel(`notifications-feed-${personId}-${limit}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'notifications', filter: `person_id=eq.${personId}` },
        run
      )
      .subscribe();
    const poll = setInterval(run, 60_000);
    return () => {
      alive = false;
      clearInterval(poll);
      void supabase.removeChannel(channel);
    };
  }, [enabled, personId, limit, load]);

  const markRead = useCallback(
    async (id: number) => {
      const at = new Date().toISOString();
      setItems((cur) => cur.map((n) => (n.id === id && !n.read_at ? { ...n, read_at: at } : n)));
      const { error: e } = await createClient()
        .from('notifications')
        .update({ read_at: at })
        .eq('id', id)
        .is('read_at', null);
      if (e) {
        setError(e.message);
        void load();
      }
      announceUnreadChanged();
    },
    [load]
  );

  const markAllRead = useCallback(async () => {
    const at = new Date().toISOString();
    setItems((cur) => cur.map((n) => (n.read_at ? n : { ...n, read_at: at })));
    const { error: e } = await createClient()
      .from('notifications')
      .update({ read_at: at })
      .eq('person_id', personId)
      .is('read_at', null);
    if (e) {
      setError(e.message);
      void load();
    }
    announceUnreadChanged();
  }, [personId, load]);

  const remove = useCallback(
    async (id: number) => {
      setItems((cur) => cur.filter((n) => n.id !== id));
      const { error: e } = await createClient().from('notifications').delete().eq('id', id);
      if (e) {
        setError(e.message);
        void load();
      }
      announceUnreadChanged();
    },
    [load]
  );

  return { items, loaded, error, reload: load, markRead, markAllRead, remove };
}
