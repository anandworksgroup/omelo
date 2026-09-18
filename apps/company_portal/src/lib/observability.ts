/**
 * Minimal error reporting with an optional provider.
 *
 * When NEXT_PUBLIC_SENTRY_DSN is set, errors are POSTed to Sentry's envelope
 * endpoint (no SDK: nothing added to the bundle, no build plugin, no config
 * files). Without it, errors go to the console only.
 *
 * Works in the browser (error boundaries) and on the server (server actions,
 * route handlers). Never throws: reporting must not turn one failure into two.
 */

type Context = Record<string, unknown>;

type Dsn = { endpoint: string; publicKey: string; raw: string };

function parseDsn(raw: string | undefined): Dsn | null {
  if (!raw) return null;
  try {
    const url = new URL(raw);
    const projectId = url.pathname.replace(/^\/+|\/+$/g, '');
    if (!url.username || !projectId) return null;
    return {
      endpoint: `${url.protocol}//${url.host}/api/${projectId}/envelope/`,
      publicKey: url.username,
      raw,
    };
  } catch {
    return null;
  }
}

function eventId(): string {
  const c = globalThis.crypto;
  if (c?.randomUUID) return c.randomUUID().replace(/-/g, '');
  return Array.from({ length: 32 }, () => Math.floor(Math.random() * 16).toString(16)).join('');
}

function normalise(error: unknown): { type: string; message: string; stack?: string; digest?: string } {
  if (error instanceof Error) {
    return {
      type: error.name || 'Error',
      message: error.message,
      stack: error.stack,
      digest: (error as Error & { digest?: string }).digest,
    };
  }
  if (error && typeof error === 'object' && 'message' in error) {
    const e = error as { message: unknown; code?: unknown };
    return { type: typeof e.code === 'string' ? `Error ${e.code}` : 'Error', message: String(e.message) };
  }
  return { type: 'Error', message: String(error) };
}

/**
 * Report an error. `context` is free-form (where it happened, ids) and must
 * not contain personal data such as emails, phone numbers or message text.
 */
export function reportError(error: unknown, context: Context = {}): void {
  const e = normalise(error);
  // Always visible in server logs / devtools.
  console.error(`[omelo] ${e.type}: ${e.message}`, context, error);

  const dsn = parseDsn(process.env.NEXT_PUBLIC_SENTRY_DSN);
  if (!dsn) return;

  try {
    const id = eventId();
    const isServer = typeof window === 'undefined';
    const event = {
      event_id: id,
      timestamp: Date.now() / 1000,
      platform: 'javascript',
      level: 'error',
      environment: process.env.NODE_ENV,
      server_name: isServer ? 'company_portal' : undefined,
      tags: { runtime: isServer ? 'server' : 'browser', app: 'company_portal' },
      exception: { values: [{ type: e.type, value: e.message }] },
      extra: { ...context, stack: e.stack, digest: e.digest },
      request: isServer ? undefined : { url: window.location.href.split('?')[0] },
    };
    const body =
      JSON.stringify({ event_id: id, sent_at: new Date().toISOString(), dsn: dsn.raw }) +
      '\n' +
      JSON.stringify({ type: 'event' }) +
      '\n' +
      JSON.stringify(event);

    void fetch(`${dsn.endpoint}?sentry_key=${dsn.publicKey}&sentry_version=7`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-sentry-envelope' },
      body,
      keepalive: true,
    }).catch(() => {});
  } catch {
    // Reporting is best-effort.
  }
}
