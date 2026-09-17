'use client';

import { useCallback, useEffect, useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import type { Participant } from './types';

const POLL_MS = 10_000;

/**
 * Who is invited, waiting, in the room or gone — plus the room's own status.
 * Realtime postgres_changes on interview_participants / interview_rooms, with
 * a 10 s poll as a fallback when the socket is blocked or drops.
 */
export function useRoster(interviewId: string) {
  const [participants, setParticipants] = useState<Participant[]>([]);
  const [roomStatus, setRoomStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    const supabase = createClient();
    const [p, r] = await Promise.all([
      supabase
        .from('interview_participants')
        .select('person_id, display_name, role, status, requested_at, admitted_at, joined_at, left_at')
        .eq('interview_id', interviewId)
        .order('invited_at'),
      supabase.from('interview_rooms').select('status').eq('interview_id', interviewId).maybeSingle(),
    ]);
    if (p.error) setError(p.error.message);
    else {
      setError(null);
      setParticipants(p.data ?? []);
    }
    if (r.data) setRoomStatus(r.data.status);
  }, [interviewId]);

  useEffect(() => {
    const supabase = createClient();
    let alive = true;
    const run = () => {
      if (alive) void refresh();
    };
    run();
    const channel = supabase
      .channel(`meet-roster-${interviewId}`)
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'interview_participants', filter: `interview_id=eq.${interviewId}` },
        run
      )
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'interview_rooms', filter: `interview_id=eq.${interviewId}` },
        run
      )
      .subscribe();
    const poll = setInterval(run, POLL_MS);
    return () => {
      alive = false;
      clearInterval(poll);
      void supabase.removeChannel(channel);
    };
  }, [interviewId, refresh]);

  return { participants, roomStatus, error, refresh };
}

export type ChatMessage = {
  id: number;
  sender_id: string;
  sender_name: string | null;
  body: string;
  sent_at: string;
};

/** In-room chat (meet_messages), delivered over Realtime. */
export function useChat(interviewId: string, myId: string, open: boolean) {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [lastSeenId, setLastSeenId] = useState(0);

  const merge = useCallback((incoming: ChatMessage[]) => {
    setMessages((cur) => {
      const byId = new Map(cur.map((m) => [m.id, m]));
      for (const m of incoming) byId.set(m.id, m);
      return [...byId.values()].sort((a, b) => a.id - b.id).slice(-300);
    });
  }, []);

  useEffect(() => {
    const supabase = createClient();
    let alive = true;
    const load = () =>
      supabase
        .from('meet_messages')
        .select('id, sender_id, sender_name, body, sent_at')
        .eq('interview_id', interviewId)
        .order('id', { ascending: false })
        .limit(200)
        .then(({ data, error: e }) => {
          if (!alive) return;
          if (e) setError(e.message);
          else merge(data ?? []);
        });
    void load();
    const channel = supabase
      .channel(`meet-chat-${interviewId}`)
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'meet_messages', filter: `interview_id=eq.${interviewId}` },
        (payload) => {
          if (alive) merge([payload.new as ChatMessage]);
        }
      )
      .subscribe();
    const poll = setInterval(() => void load(), 15_000);
    return () => {
      alive = false;
      clearInterval(poll);
      void supabase.removeChannel(channel);
    };
  }, [interviewId, merge]);

  const send = useCallback(
    async (body: string) => {
      const text = body.trim();
      if (!text) return false;
      if (text.length > 2000) {
        setError('Messages can be up to 2000 characters.');
        return false;
      }
      const supabase = createClient();
      const { data, error: e } = await supabase
        .from('meet_messages')
        .insert({ interview_id: interviewId, sender_id: myId, body: text })
        .select('id, sender_id, sender_name, body, sent_at')
        .single();
      if (e) {
        setError(
          /too quickly/i.test(e.message)
            ? 'You are sending messages too quickly. Wait a moment.'
            : /row-level security/i.test(e.message)
              ? 'You can chat once you are in the room.'
              : e.message
        );
        return false;
      }
      setError(null);
      if (data) merge([data]);
      return true;
    },
    [interviewId, myId, merge]
  );

  const newest = messages.at(-1)?.id ?? 0;
  const unread = open ? 0 : messages.filter((m) => m.id > lastSeenId && m.sender_id !== myId).length;
  const markSeen = useCallback(() => setLastSeenId(newest), [newest]);

  return { messages, error, send, unread, markSeen };
}
