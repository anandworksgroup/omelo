import type { EmailOtpType } from '@supabase/supabase-js';
import { NextResponse, type NextRequest } from 'next/server';
import { createClient } from '@/lib/supabase/server';
import { reportError } from '@/lib/observability';

/** Same-site paths only: never redirect to another origin. */
function safeNext(raw: string | null, fallback: string) {
  if (!raw || !raw.startsWith('/') || raw.startsWith('//') || raw.startsWith('/\\')) return fallback;
  return raw;
}

/** Expected user-side outcomes (old, reused or other-browser links): not bugs. */
const EXPECTED = new Set(['pkce_code_verifier_not_found', 'otp_expired', 'flow_state_expired', 'flow_state_not_found', 'bad_code_verifier']);

function report(error: { code?: string; status?: number }, action: string) {
  if (error.code && EXPECTED.has(error.code)) return;
  reportError(error, { action, status: error.status, code: error.code });
}

/**
 * Auth email links land here (directly, or via /auth/reset).
 *
 * - `?code=` — PKCE: exchanged for a session using the code verifier cookie
 *   that was set when the link was requested (so it must be the same browser).
 * - `?token_hash=&type=` — email templates that use the token hash instead.
 *
 * On success the session cookies are set and the user is sent to `next`.
 * On failure they go to `next` with `?error=link_invalid`, where the page
 * explains what happened.
 */
export async function GET(request: NextRequest) {
  const url = request.nextUrl;
  const next = safeNext(url.searchParams.get('next'), '/dashboard');
  const code = url.searchParams.get('code');
  const tokenHash = url.searchParams.get('token_hash');
  const type = url.searchParams.get('type') as EmailOtpType | null;

  const done = (failed: boolean) => {
    const target = new URL(next, url.origin);
    if (failed) target.searchParams.set('error', 'link_invalid');
    return NextResponse.redirect(target);
  };

  const supabase = await createClient();

  if (code) {
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (error) {
      report(error, 'auth.callback.exchange');
      return done(true);
    }
    return done(false);
  }

  if (tokenHash && type) {
    const { error } = await supabase.auth.verifyOtp({ token_hash: tokenHash, type });
    if (error) {
      report(error, 'auth.callback.verifyOtp');
      return done(true);
    }
    return done(false);
  }

  return done(true);
}
