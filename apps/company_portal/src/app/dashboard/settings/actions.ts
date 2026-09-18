'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { reportError } from '@/lib/observability';

export type AccountResult<T = Record<string, unknown>> = { error?: string; data?: T };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type RpcError = { message: string; code?: string };

/**
 * The account RPCs raise human-readable messages (wrong code, expired, too
 * many requests, sole owner…) as 22023 / 54000 (or P0001), so those are shown
 * as-is. Anything else is unexpected: report it and show a generic message.
 */
function fail(error: RpcError, action: string): AccountResult<never> {
  if (!error.code || ['P0001', '22023', '54000'].includes(error.code)) return { error: error.message };
  if (error.code === '42501') return { error: 'You are signed out. Sign in and try again.' };
  reportError(error, { action, code: error.code });
  return { error: 'Something went wrong. Try again in a moment.' };
}

function asObject(v: unknown): Record<string, unknown> {
  return v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {};
}

/* Verification ------------------------------------------------------ */

export async function requestEmailVerification(): Promise<
  AccountResult<{ sent_to?: string; expires_at?: string; already_verified?: boolean }>
> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('omelo_request_email_verification');
  if (error) return fail(error, 'requestEmailVerification');
  const d = asObject(data);
  if (d.already_verified) revalidatePath('/dashboard/settings');
  return {
    data: {
      sent_to: typeof d.sent_to === 'string' ? d.sent_to : undefined,
      expires_at: typeof d.expires_at === 'string' ? d.expires_at : undefined,
      already_verified: d.already_verified === true,
    },
  };
}

export async function requestPhoneVerification(
  phone: string
): Promise<AccountResult<{ sent_to?: string; expires_at?: string; already_verified?: boolean }>> {
  const p = phone.replace(/[\s()-]/g, '');
  if (!/^\+[0-9]{8,15}$/.test(p)) return { error: 'Enter your phone number with the country code, e.g. +91 98765 43210.' };
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('omelo_request_phone_verification', { p_phone: p });
  if (error) return fail(error, 'requestPhoneVerification');
  const d = asObject(data);
  return {
    data: {
      sent_to: typeof d.sent_to === 'string' ? d.sent_to : undefined,
      expires_at: typeof d.expires_at === 'string' ? d.expires_at : undefined,
      already_verified: d.already_verified === true,
    },
  };
}

export async function confirmVerification(channel: 'email' | 'phone', code: string): Promise<AccountResult> {
  if (channel !== 'email' && channel !== 'phone') return { error: 'Unknown verification.' };
  const c = code.replace(/\D/g, '');
  if (c.length !== 6) return { error: 'Enter the 6-digit code.' };
  const supabase = await createClient();
  const { error } = await supabase.rpc('omelo_confirm_verification', { p_channel: channel, p_code: c });
  if (error) return fail(error, 'confirmVerification');
  revalidatePath('/dashboard/settings');
  return { data: { verified: true } };
}

/* Sessions ---------------------------------------------------------- */

export async function revokeSession(sessionId: string): Promise<AccountResult> {
  if (!UUID.test(sessionId)) return { error: 'Unknown session.' };
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('omelo_revoke_session', { p_session_id: sessionId });
  if (error) return fail(error, 'revokeSession');
  revalidatePath('/dashboard/settings');
  if (!data) return { error: 'That session has already ended.' };
  return { data: {} };
}

export async function revokeOtherSessions(): Promise<AccountResult<{ count: number }>> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('omelo_revoke_other_sessions');
  if (error) return fail(error, 'revokeOtherSessions');
  revalidatePath('/dashboard/settings');
  return { data: { count: Number(data ?? 0) } };
}

/* Deletion ---------------------------------------------------------- */

export async function requestAccountDeletion(
  reason: string,
  confirmation: string
): Promise<AccountResult<{ scheduled_for?: string }>> {
  if (confirmation.trim() !== 'DELETE') return { error: 'Type DELETE to confirm.' };
  const supabase = await createClient();
  const r = reason.trim().slice(0, 1000);
  const { data, error } = await supabase.rpc('omelo_request_account_deletion', r ? { p_reason: r } : {});
  if (error) return fail(error, 'requestAccountDeletion');
  revalidatePath('/dashboard', 'layout');
  const d = asObject(data);
  return { data: { scheduled_for: typeof d.scheduled_for === 'string' ? d.scheduled_for : undefined } };
}

export async function cancelAccountDeletion(): Promise<AccountResult> {
  const supabase = await createClient();
  const { error } = await supabase.rpc('omelo_cancel_account_deletion');
  if (error) return fail(error, 'cancelAccountDeletion');
  revalidatePath('/dashboard', 'layout');
  return { data: {} };
}

/** Form-action variant for the dashboard-wide banner (no client JS needed). */
export async function cancelAccountDeletionForm(): Promise<void> {
  await cancelAccountDeletion();
}
