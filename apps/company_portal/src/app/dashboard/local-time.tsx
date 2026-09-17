'use client';

import { useSyncExternalStore } from 'react';

const subscribe = () => () => {};

/**
 * Renders a timestamp in the VIEWER's timezone.
 *
 * Server components run in the server's timezone, which is wrong for an
 * interview time. The server pass renders UTC (labelled), and the client
 * re-renders in local time straight after hydration.
 */
export default function LocalTime({
  iso,
  withTime = true,
  className,
}: {
  iso: string | null;
  withTime?: boolean;
  className?: string;
}) {
  const isClient = useSyncExternalStore(
    subscribe,
    () => true,
    () => false
  );
  if (!iso) return <span className={className}>—</span>;

  const opts: Intl.DateTimeFormatOptions = {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    ...(withTime ? { hour: 'numeric', minute: '2-digit', timeZoneName: 'short' } : {}),
    ...(isClient ? {} : { timeZone: 'UTC' }),
  };

  return (
    <time dateTime={iso} className={className}>
      {new Date(iso).toLocaleString('en-IN', opts)}
    </time>
  );
}
