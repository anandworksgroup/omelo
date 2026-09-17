'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useRef, useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import {
  MESSAGE_COLUMNS,
  MESSAGE_MAX,
  announceUnreadChanged,
  messageStamp,
  type ThreadMessage,
} from '@/lib/messaging';
import { useIsClient } from '@/lib/use-is-client';

const POLL_MS = 20_000;
const HISTORY = 200;

/**
 * A job conversation. Messages arrive over Realtime (INSERT for new ones,
 * UPDATE for read receipts), with a poll as a fallback. Sending goes through
 * omelo_send_message, whose errors are shown to the employer verbatim.
 */
export default function Thread({
  conversationId,
  myId,
  candidateName,
  initial,
  truncated,
  closedReason,
}: {
  conversationId: string;
  myId: string;
  candidateName: string;
  initial: ThreadMessage[];
  truncated: boolean;
  closedReason: string | null;
}) {
  const router = useRouter();
  const isClient = useIsClient();
  const [messages, setMessages] = useState<ThreadMessage[]>(initial);
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const scroller = useRef<HTMLDivElement>(null);
  const nearBottom = useRef(true);
  const input = useRef<HTMLTextAreaElement>(null);

  const merge = useCallback((incoming: ThreadMessage[]) => {
    if (incoming.length === 0) return;
    setMessages((cur) => {
      const byId = new Map(cur.map((m) => [m.id, m]));
      for (const m of incoming) byId.set(m.id, m);
      return [...byId.values()].sort((a, b) => a.id - b.id).slice(-HISTORY * 2);
    });
  }, []);

  /** Marks the candidate's messages read while this thread is actually on screen. */
  const markRead = useCallback(async () => {
    if (document.visibilityState !== 'visible') return;
    // The candidate's read_at is not shown here, so no local state to update;
    // the UPDATE events and the next poll bring the rows in step.
    const { error: e } = await createClient().rpc('omelo_mark_conversation_read', {
      p_conversation_id: conversationId,
    });
    // Always announce: the RPC also clears this conversation's notifications.
    if (!e) announceUnreadChanged();
  }, [conversationId]);

  useEffect(() => {
    const supabase = createClient();
    let alive = true;

    const load = async () => {
      const { data, error: e } = await supabase
        .from('messages')
        .select(MESSAGE_COLUMNS)
        .eq('conversation_id', conversationId)
        .order('id', { ascending: false })
        .limit(HISTORY);
      if (!alive) return;
      if (e) {
        setLoadError(e.message);
        return;
      }
      setLoadError(null);
      const rows = data ?? [];
      merge(rows);
      if (rows.some((m) => m.sender_type === 'candidate' && !m.read_at)) void markRead();
    };

    void markRead();
    const channel = supabase
      .channel(`thread-${conversationId}`)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'messages', filter: `conversation_id=eq.${conversationId}` },
        (payload) => {
          if (!alive) return;
          const m = payload.new as ThreadMessage;
          merge([m]);
          if (m.sender_type === 'candidate') void markRead();
        }
      )
      .on(
        'postgres_changes',
        { event: 'UPDATE', schema: 'public', table: 'messages', filter: `conversation_id=eq.${conversationId}` },
        (payload) => {
          if (alive) merge([payload.new as ThreadMessage]);
        }
      )
      .subscribe((status) => {
        // Catch up on anything sent while the socket was connecting or down.
        if (status === 'SUBSCRIBED' && alive) void load();
      });
    const poll = setInterval(() => void load(), POLL_MS);
    const onVisible = () => {
      if (document.visibilityState === 'visible') void load();
    };
    document.addEventListener('visibilitychange', onVisible);

    return () => {
      alive = false;
      clearInterval(poll);
      document.removeEventListener('visibilitychange', onVisible);
      void supabase.removeChannel(channel);
    };
  }, [conversationId, merge, markRead]);

  // Follow the conversation when already at the bottom, or when you sent it.
  const lastId = messages.at(-1)?.id ?? 0;
  const lastMine = messages.at(-1)?.sender_person_id === myId;
  useEffect(() => {
    const el = scroller.current;
    if (el && (nearBottom.current || lastMine)) el.scrollTop = el.scrollHeight;
  }, [lastId, lastMine]);

  const onScroll = () => {
    const el = scroller.current;
    if (el) nearBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < 80;
  };

  const length = draft.trim().length;
  const tooLong = draft.length > MESSAGE_MAX;
  const canSend = !closedReason && !sending && length > 0 && !tooLong;

  const send = async () => {
    if (!canSend) return;
    setSending(true);
    setError(null);
    const supabase = createClient();
    const { data: newId, error: e } = await supabase.rpc('omelo_send_message', {
      p_conversation_id: conversationId,
      p_body: draft.trim(),
    });
    if (e) {
      setError(e.message);
      setSending(false);
      return;
    }
    setDraft('');
    setSending(false);
    if (newId != null) {
      const { data } = await supabase.from('messages').select(MESSAGE_COLUMNS).eq('id', newId).maybeSingle();
      if (data) merge([data]);
    }
    // Sending un-archives the conversation; keep the header in step.
    router.refresh();
    input.current?.focus();
  };

  return (
    <section className="card flex flex-col" aria-label={`Conversation with ${candidateName}`}>
      <div
        ref={scroller}
        onScroll={onScroll}
        className="h-[55vh] min-h-[18rem] overflow-y-auto px-3 sm:px-5 py-4 space-y-3"
        aria-live="polite"
        aria-relevant="additions"
      >
        {truncated && <p className="text-xs muted text-center">Showing the most recent {HISTORY} messages.</p>}
        {messages.length === 0 ? (
          <p className="text-sm muted text-center py-10">
            No messages yet. Say hello to {candidateName} — they will get a notification and an email.
          </p>
        ) : (
          messages.map((m) => {
            const company = m.sender_type !== 'candidate';
            const mine = m.sender_person_id === myId;
            return (
              <div key={m.id} className={`flex ${company ? 'justify-end' : 'justify-start'}`}>
                <div className={`max-w-[85%] sm:max-w-[75%] flex flex-col ${company ? 'items-end' : 'items-start'}`}>
                  {company && !mine && <span className="text-xs muted mb-0.5">Teammate</span>}
                  <div
                    className="rounded-2xl px-3.5 py-2 text-sm whitespace-pre-wrap break-words"
                    style={
                      mine
                        ? { background: 'var(--color-brand-600)', color: '#fff', borderBottomRightRadius: 6 }
                        : company
                          ? {
                              background: 'var(--color-brand-100)',
                              color: 'var(--color-brand-900)',
                              borderBottomRightRadius: 6,
                            }
                          : {
                              background: 'var(--surface)',
                              border: '1px solid var(--line)',
                              borderBottomLeftRadius: 6,
                            }
                    }
                  >
                    {m.body ?? <span className="italic opacity-70">Unsupported message</span>}
                  </div>
                  <span className="text-[0.7rem] muted mt-0.5">
                    {isClient ? <time dateTime={m.sent_at}>{messageStamp(m.sent_at)}</time> : null}
                    {company && (
                      <>
                        {isClient ? ' · ' : ''}
                        {m.read_at ? (
                          <span style={{ color: 'var(--color-verified)' }}>Seen</span>
                        ) : (
                          'Sent'
                        )}
                      </>
                    )}
                  </span>
                </div>
              </div>
            );
          })
        )}
      </div>

      {loadError && (
        <p className="text-xs px-4 pb-2" style={{ color: 'var(--color-warn)' }}>
          Could not refresh messages: {loadError}
        </p>
      )}

      <div className="border-t hairline p-3 sm:p-4">
        {closedReason ? (
          <p className="text-sm muted" role="status">
            {closedReason}
          </p>
        ) : (
          <form
            onSubmit={(e) => {
              e.preventDefault();
              void send();
            }}
            className="space-y-2"
          >
            <label htmlFor="message-body" className="sr-only">
              Message {candidateName}
            </label>
            <textarea
              id="message-body"
              ref={input}
              className="input resize-y min-h-[3rem] max-h-60"
              rows={2}
              placeholder={`Message ${candidateName}…`}
              value={draft}
              onChange={(e) => {
                setDraft(e.target.value);
                if (error) setError(null);
              }}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) {
                  e.preventDefault();
                  void send();
                }
              }}
              aria-invalid={tooLong || undefined}
              aria-describedby="message-hint"
            />
            {error && (
              <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
                {error}
              </p>
            )}
            <div className="flex items-center gap-3">
              <p id="message-hint" className="text-xs muted flex-1">
                Enter to send · Shift+Enter for a new line
              </p>
              <span
                className="text-xs tabular-nums"
                style={{ color: tooLong ? 'var(--color-danger)' : 'var(--muted)' }}
                aria-live="polite"
              >
                {draft.length}/{MESSAGE_MAX}
              </span>
              <button type="submit" className="btn btn-primary" disabled={!canSend}>
                {sending ? 'Sending…' : 'Send'}
              </button>
            </div>
          </form>
        )}
      </div>
    </section>
  );
}
