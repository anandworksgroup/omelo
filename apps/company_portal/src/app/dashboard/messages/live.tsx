'use client';

import { useRouter } from 'next/navigation';
import { useEffect } from 'react';
import { createClient } from '@/lib/supabase/client';
import { UNREAD_CHANGED_EVENT, messageStamp } from '@/lib/messaging';
import { useIsClient } from '@/lib/use-is-client';

/**
 * Keeps the server-rendered inbox current: new messages, read receipts and
 * archive changes trigger a refresh. A poll covers a blocked socket.
 */
export function InboxLive({ companyId }: { companyId: string }) {
  const router = useRouter();

  useEffect(() => {
    const supabase = createClient();
    let timer: ReturnType<typeof setTimeout> | null = null;
    const refresh = () => {
      if (timer) clearTimeout(timer);
      timer = setTimeout(() => router.refresh(), 400);
    };
    const channel = supabase
      .channel(`inbox-${companyId}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages' }, refresh)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'messages' }, refresh)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'conversations', filter: `company_id=eq.${companyId}` },
        refresh
      )
      .subscribe();
    const poll = setInterval(refresh, 30_000);
    window.addEventListener(UNREAD_CHANGED_EVENT, refresh);
    return () => {
      if (timer) clearTimeout(timer);
      clearInterval(poll);
      window.removeEventListener(UNREAD_CHANGED_EVENT, refresh);
      void supabase.removeChannel(channel);
    };
  }, [companyId, router]);

  return null;
}

/** Last-activity time in the viewer's timezone; blank until hydration. */
export function InboxTime({ iso }: { iso: string }) {
  const isClient = useIsClient();
  return <time dateTime={iso}>{isClient ? messageStamp(iso) : ''}</time>;
}
