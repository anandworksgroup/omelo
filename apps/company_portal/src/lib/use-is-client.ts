'use client';

import { useSyncExternalStore } from 'react';

const subscribe = () => () => {};

/**
 * False during the server render and hydration, true afterwards.
 * Use it to render viewer-local values (timezones, relative times) without a
 * hydration mismatch.
 */
export function useIsClient() {
  return useSyncExternalStore(
    subscribe,
    () => true,
    () => false
  );
}
