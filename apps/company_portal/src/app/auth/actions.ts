'use server';

import { revalidatePath } from 'next/cache';
import { headers } from 'next/headers';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { reportError } from '@/lib/observability';

export type AuthState = { error?: string; notice?: string };

export async function signIn(
  _prev: AuthState,
  formData: FormData
): Promise<AuthState> {
  const email = String(formData.get('email') ?? '').trim();
  const password = String(formData.get('password') ?? '');
  // Only same-site paths: never redirect to another origin (open redirect).
  const rawNext = String(formData.get('next') ?? '/dashboard');
  const next = rawNext.startsWith('/') && !rawNext.startsWith('//') && !rawNext.startsWith('/\\') ? rawNext : '/dashboard';

  if (!email || !password) return { error: 'Enter your email and password.' };

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) {
    // Plain language. "Invalid login credentials" tells a user nothing.
    if (error.message.toLowerCase().includes('invalid'))
      return { error: 'That email and password do not match an account.' };
    if (error.message.toLowerCase().includes('confirm'))
      return {
        error:
          'This account has not confirmed its email address yet. Check your inbox.',
      };
    return { error: error.message };
  }

  revalidatePath('/', 'layout');
  redirect(next);
}

export async function signUp(
  _prev: AuthState,
  formData: FormData
): Promise<AuthState> {
  const email = String(formData.get('email') ?? '').trim();
  const password = String(formData.get('password') ?? '');
  const fullName = String(formData.get('full_name') ?? '').trim();

  if (!email || !password) return { error: 'Enter your email and password.' };
  if (password.length < 8)
    return { error: 'Use at least 8 characters for your password.' };

  // Create through the auth-signup Edge Function, which makes an
  // already-confirmed user. No confirmation email is sent, so the default
  // SMTP rate limit never applies and the account works immediately.
  const res = await fetch(
    `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/auth-signup`,
    {
      method: 'POST',
      headers: {
        apikey: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
        Authorization: `Bearer ${process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        email,
        password,
        full_name: fullName,
        role: 'employer',
      }),
    }
  );

  const body = (await res.json().catch(() => ({}))) as {
    error?: string;
    code?: string;
  };

  if (!res.ok) {
    if (body.code === 'already_exists') {
      return { error: 'An account with that email already exists. Sign in below.' };
    }
    return { error: body.error ?? 'Could not create your account.' };
  }

  // Straight in — no verification step.
  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) return { error: error.message };

  revalidatePath('/', 'layout');
  redirect('/dashboard');
}

export async function signOut() {
  const supabase = await createClient();
  const { error } = await supabase.auth.signOut();
  if (error) reportError(error, { action: 'signOut' });
  revalidatePath('/', 'layout');
  redirect('/sign-in');
}

/** The origin the user is on, for auth email links (never user input). */
async function siteOrigin(): Promise<string> {
  const h = await headers();
  const origin = h.get('origin');
  if (origin) return origin;
  const host = h.get('x-forwarded-host') ?? h.get('host');
  const proto = h.get('x-forwarded-proto') ?? (host?.startsWith('localhost') ? 'http' : 'https');
  return `${proto}://${host}`;
}

const RESET_NOTICE =
  'If an account exists for that email, a link to reset your password is on its way. It can take a few minutes to arrive — check your spam folder too.';

/**
 * Sends a password reset link. The response is the same whether or not the
 * email belongs to an account, so this cannot be used to discover accounts.
 */
export async function requestPasswordReset(
  _prev: AuthState,
  formData: FormData
): Promise<AuthState> {
  const email = String(formData.get('email') ?? '').trim();
  if (!email || !email.includes('@')) return { error: 'Enter the email you sign in with.' };

  const supabase = await createClient();
  // PKCE: the code verifier is stored in this browser's cookies, so the link
  // must be opened in the same browser. /auth/reset exchanges the code.
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${await siteOrigin()}/auth/reset`,
  });
  // Never surface the error: it could reveal whether the account exists.
  if (error) reportError(error, { action: 'requestPasswordReset', status: error.status });

  return { notice: RESET_NOTICE };
}

/**
 * Sets a new password for the signed-in user. Used by the reset flow (after
 * the recovery link signs them in) and by Settings -> Change password.
 */
export async function updatePassword(
  _prev: AuthState,
  formData: FormData
): Promise<AuthState> {
  const password = String(formData.get('password') ?? '');
  const confirm = String(formData.get('confirm') ?? '');
  const mode = String(formData.get('mode') ?? 'settings');

  if (password.length < 8) return { error: 'Use at least 8 characters for your password.' };
  if (password !== confirm) return { error: 'The two passwords do not match.' };

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user)
    return {
      error:
        mode === 'reset'
          ? 'This reset link has expired. Request a new one.'
          : 'You are signed out. Sign in and try again.',
    };

  const { error } = await supabase.auth.updateUser({ password });
  if (error) {
    const msg = error.message.toLowerCase();
    if (msg.includes('different from the old'))
      return { error: 'Choose a password different from your current one.' };
    if (msg.includes('weak') || msg.includes('pwned') || msg.includes('known'))
      return { error: 'That password is too easy to guess. Try a longer or less common one.' };
    if (msg.includes('reauthent'))
      return { error: 'For security, sign out and back in, then change your password.' };
    reportError(error, { action: 'updatePassword', mode, status: error.status });
    return { error: 'Your password could not be changed. Try again in a moment.' };
  }

  if (mode === 'reset') {
    revalidatePath('/', 'layout');
    redirect('/dashboard');
  }
  return { notice: 'Password changed.' };
}
