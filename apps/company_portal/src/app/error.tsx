'use client'; // Error boundaries must be Client Components

import Link from 'next/link';
import { useEffect } from 'react';
import { reportError } from '@/lib/observability';

export default function RouteError({
  error,
  retry,
  reset,
}: {
  error: Error & { digest?: string };
  retry?: () => void;
  reset?: () => void;
}) {
  useEffect(() => {
    reportError(error, { boundary: 'error' });
  }, [error]);

  return (
    <main className="min-h-[60vh] flex items-center justify-center px-5 py-16">
      <div className="card p-6 sm:p-8 max-w-md w-full text-center">
        <h1 className="text-xl font-bold">Something went wrong</h1>
        <p className="muted mt-2 text-sm leading-relaxed">
          This page hit an unexpected problem. Try again, and if it keeps happening, reload the page or come back
          in a few minutes.
        </p>
        {error.digest && <p className="text-xs muted mt-3">Reference: {error.digest}</p>}
        <div className="mt-6 flex gap-3 justify-center flex-wrap">
          <button type="button" className="btn btn-primary" onClick={() => (retry ?? reset)?.()}>
            Try again
          </button>
          <Link href="/dashboard" className="btn btn-ghost">
            Go to dashboard
          </Link>
        </div>
      </div>
    </main>
  );
}
