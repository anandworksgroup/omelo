'use client';

import { useSyncExternalStore } from 'react';

/*
 * One shared one-second clock for countdowns and join windows.
 *
 * Server render gets 0 so time-dependent UI renders nothing until hydration,
 * which avoids hydration mismatches between the server clock and the viewer's.
 */

let now = 0;
let timer: ReturnType<typeof setInterval> | null = null;
const listeners = new Set<() => void>();

function subscribe(listener: () => void) {
  listeners.add(listener);
  if (!timer) {
    now = Date.now();
    timer = setInterval(() => {
      now = Date.now();
      listeners.forEach((l) => l());
    }, 1000);
  }
  return () => {
    listeners.delete(listener);
    if (listeners.size === 0 && timer) {
      clearInterval(timer);
      timer = null;
    }
  };
}

function getSnapshot() {
  if (now === 0) now = Date.now();
  return now;
}

export function useNow() {
  return useSyncExternalStore(subscribe, getSnapshot, () => 0);
}
