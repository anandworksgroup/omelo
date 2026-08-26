'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';

export type AuthState = { error?: string; notice?: string };

export async function signIn(
  _prev: AuthState,
  formData: FormData
): Promise<AuthState> {
  const email = String(formData.get('email') ?? '').trim();
  const password = String(formData.get('password') ?? '');
  const next = String(formData.get('next') ?? '/dashboard');

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
  await supabase.auth.signOut();
  revalidatePath('/', 'layout');
  redirect('/sign-in');
}
