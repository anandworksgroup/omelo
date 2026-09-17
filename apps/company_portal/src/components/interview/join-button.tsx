'use client';

import Link from 'next/link';
import { countdown, joinWindow } from '@/lib/meet';
import { useNow } from '@/lib/use-now';

/**
 * [Join interview] for an Omelo Meet round. Enabled from the room's
 * opens_at until closes_at; before that it counts down. The database checks
 * the window again on join, so this is only guidance.
 */
export default function JoinButton({
  roomName,
  opensAt,
  closesAt,
  roomStatus,
  compact = false,
}: {
  roomName: string;
  opensAt: string;
  closesAt: string;
  roomStatus: string;
  compact?: boolean;
}) {
  const now = useNow();
  const size = compact ? '!h-9 !px-3 text-sm' : '';

  if (roomStatus === 'ended' || roomStatus === 'expired' || roomStatus === 'cancelled') return null;
  if (now === 0) {
    return (
      <span className={`btn btn-ghost ${size} opacity-60`} aria-disabled>
        Join interview
      </span>
    );
  }

  const w = joinWindow(opensAt, closesAt, now);
  if (w.kind === 'closed') return null;
  if (w.kind === 'before') {
    return (
      <span className={`btn btn-ghost ${size} cursor-default`} aria-disabled title="The room opens 15 minutes before the start">
        Opens in {countdown(w.ms)}
      </span>
    );
  }
  return (
    <Link href={`/meet/${roomName}`} className={`btn btn-primary ${size}`}>
      {roomStatus === 'live' ? '● Join interview (live)' : 'Join interview'}
    </Link>
  );
}
