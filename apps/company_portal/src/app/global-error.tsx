'use client'; // Error boundaries must be Client Components

import { useEffect } from 'react';
import { reportError } from '@/lib/observability';

/*
 * Replaces the root layout when it fails, so globals.css is not available:
 * everything here is inline and follows the OS colour scheme.
 */
export default function GlobalError({
  error,
  retry,
  reset,
}: {
  error: Error & { digest?: string };
  retry?: () => void;
  reset?: () => void;
}) {
  useEffect(() => {
    reportError(error, { boundary: 'global-error' });
  }, [error]);

  return (
    <html lang="en">
      <body
        style={{
          margin: 0,
          minHeight: '100vh',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '1.25rem',
          fontFamily: 'ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif',
          background: 'Canvas',
          color: 'CanvasText',
          colorScheme: 'light dark',
        }}
      >
        <title>Something went wrong · Omelo</title>
        <main style={{ maxWidth: 420, textAlign: 'center' }}>
          <p style={{ fontWeight: 900, fontSize: '1.25rem', color: '#1b5e4a', margin: 0 }}>Omelo</p>
          <h1 style={{ fontSize: '1.25rem', margin: '1.5rem 0 0.5rem' }}>Something went wrong</h1>
          <p style={{ opacity: 0.75, lineHeight: 1.5, fontSize: '0.95rem', margin: 0 }}>
            The portal could not load. Try again, or reload the page in a moment.
          </p>
          {error.digest && (
            <p style={{ opacity: 0.6, fontSize: '0.75rem', marginTop: '0.75rem' }}>Reference: {error.digest}</p>
          )}
          <button
            type="button"
            onClick={() => (retry ?? reset)?.()}
            style={{
              marginTop: '1.5rem',
              height: 44,
              padding: '0 1.1rem',
              borderRadius: 10,
              border: 0,
              background: '#1b5e4a',
              color: '#fff',
              fontWeight: 600,
              fontSize: '0.95rem',
              cursor: 'pointer',
            }}
          >
            Try again
          </button>
        </main>
      </body>
    </html>
  );
}
