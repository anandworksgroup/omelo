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

  const supabase = await createClient();
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: { data: { full_name: fullName } },
  });

  if (error) {
    if (error.message.toLowerCase().includes('rate limit'))
      return {
        error:
          'Too many sign-up emails from this project right now. Wait a few minutes, or ask an admin to turn off email confirmation for development.',
      };
    return { error: error.message };
  }

  // Email confirmation is on by default, so there may be no session yet.
  if (!data.session) {
    return {
      notice:
        'Account created. Check your email to confirm the address, then sign in.',
    };
  }

  revalidatePath('/', 'layout');
  redirect('/dashboard');
}

export async function signOut() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  revalidatePath('/', 'layout');
  redirect('/sign-in');
}
