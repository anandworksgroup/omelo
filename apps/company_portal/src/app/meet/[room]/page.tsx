import type { Metadata } from 'next';
import { notFound, redirect } from 'next/navigation';
import { getUser } from '@/lib/supabase/server';
import { ROOM_NAME_RE } from '@/lib/meet';
import MeetRoom from './meet-room';

export const metadata: Metadata = {
  title: 'Omelo Meet',
  robots: { index: false, follow: false },
};

/**
 * Omelo Meet room. Full screen, outside the dashboard chrome.
 *
 * Signing in is required (proxy.ts sends signed-out visitors to sign-in with
 * a return path). Whether this person may enter is decided only by the
 * database via the meet-token Edge Function — the room name grants nothing.
 */
export default async function MeetPage({ params }: { params: Promise<{ room: string }> }) {
  const { room } = await params;
  if (!ROOM_NAME_RE.test(room)) notFound();

  const user = await getUser();
  if (!user) redirect(`/sign-in?next=${encodeURIComponent(`/meet/${room}`)}`);

  return <MeetRoom key={room} roomName={room} />;
}
