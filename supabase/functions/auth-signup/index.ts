import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';

/**
 * auth-signup
 *
 * Creates an ALREADY-CONFIRMED user, so signing up needs no confirmation
 * email. The default project SMTP is heavily rate limited, which made
 * self-serve signup unusable in development.
 *
 * Why an Edge Function rather than the client:
 * creating a pre-confirmed user needs the service role. That key lives only
 * in this function's environment and never reaches a browser or an APK
 * (architecture/A4 §1.1). The client still signs in normally afterwards with
 * the publishable key, so the resulting session is an ordinary user session
 * with ordinary RLS.
 *
 * verify_jwt is off by design: the caller is by definition not yet
 * authenticated. The function does its own validation and rate limiting.
 *
 * Privacy: the client IP is never stored. The rate limit keys on a salted
 * SHA-256 of it (set IP_HASH_SALT in production).
 */

const ALLOWED_ROLES = new Set(['worker', 'employer']);

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

async function hashIp(ip: string): Promise<string> {
  const salt = Deno.env.get('IP_HASH_SALT') ?? 'omelo-dev-salt';
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`${salt}:${ip}`));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return json({ error: 'Send a JSON body.' }, 400);
  }

  const email = String(payload.email ?? '').trim().toLowerCase();
  const password = String(payload.password ?? '');
  const fullName = String(payload.full_name ?? '').trim().slice(0, 120);
  const role = String(payload.role ?? 'worker');

  // ---- validation -------------------------------------------------
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]{2,}$/.test(email) || email.length > 254) {
    return json({ error: 'Enter a valid email address.' }, 400);
  }
  if (password.length < 8) {
    return json({ error: 'Use at least 8 characters for your password.' }, 400);
  }
  if (password.length > 200) {
    return json({ error: 'That password is too long.' }, 400);
  }
  if (!ALLOWED_ROLES.has(role)) {
    return json({ error: 'Unknown account type.' }, 400);
  }

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  );

  // ---- per-IP rate limit ------------------------------------------
  // Without confirmation emails there is no natural brake on account
  // creation, so add one. 10 new accounts per IP per hour.
  const ip =
    req.headers.get('x-forwarded-for')?.split(',')[0].trim() ??
    req.headers.get('cf-connecting-ip') ??
    'unknown';
  const ipHash = await hashIp(ip);

  const { count } = await admin
    .from('audit_log')
    .select('id', { count: 'exact', head: true })
    .eq('action', 'auth.signup')
    .eq('ip_hash', ipHash)
    .gte('occurred_at', new Date(Date.now() - 3_600_000).toISOString());

  if ((count ?? 0) >= 10) {
    return json(
      { error: 'Too many accounts created from here. Try again later.' },
      429,
    );
  }

  // ---- create, pre-confirmed --------------------------------------
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true, // no confirmation email is ever sent
    user_metadata: { full_name: fullName, signup_role: role },
  });

  if (error) {
    const m = error.message.toLowerCase();
    if (m.includes('already') || m.includes('registered') || m.includes('exists')) {
      return json(
        { error: 'An account with that email already exists. Sign in instead.', code: 'already_exists' },
        409,
      );
    }
    return json({ error: 'Could not create the account. Try again.' }, 400);
  }

  // The signup trigger (omelo_handle_new_user) has already created the
  // person row, primary work identity and preferences.
  await admin.from('audit_log').insert({
    actor_type: 'system',
    actor_id: data.user?.id ?? null,
    action: 'auth.signup',
    subject_type: 'person',
    subject_id: data.user?.id ?? null,
    ip_hash: ipHash,
    metadata: { role, confirmed_without_email: true },
  });

  return json({ ok: true, user_id: data.user?.id });
});
