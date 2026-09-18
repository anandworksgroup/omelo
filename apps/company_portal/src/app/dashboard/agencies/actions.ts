'use server';

import { revalidatePath } from 'next/cache';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { UUID_RE } from '@/lib/talent';

/*
 * The employer (client) side of agency relationships. Every rule — who may
 * answer a link, end it, or connect a job — is checked by the SECURITY
 * DEFINER functions; these actions only validate ids and pass the database's
 * message through verbatim (42501 = not allowed, 22023 = a rule was broken).
 */

export type AgencyActionResult = { ok: true } | { ok: false; error: string };

const SIGNED_OUT = 'You are signed out or not part of a company.';

async function client() {
  const ctx = await getCompanyContext();
  if (!ctx) return null;
  return await createClient();
}

function refresh() {
  revalidatePath('/dashboard/agencies');
  revalidatePath('/dashboard/candidates', 'layout');
}

export async function respondToLink(clientId: string, accept: boolean): Promise<AgencyActionResult> {
  const supabase = await client();
  if (!supabase) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(clientId)) return { ok: false, error: 'That request no longer exists.' };
  const { error } = await supabase.rpc('omelo_respond_client_link', { p_client: clientId, p_accept: accept === true });
  if (error) return { ok: false, error: error.message };
  refresh();
  return { ok: true };
}

export async function endLink(clientId: string): Promise<AgencyActionResult> {
  const supabase = await client();
  if (!supabase) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(clientId)) return { ok: false, error: 'That relationship no longer exists.' };
  const { error } = await supabase.rpc('omelo_end_client_link', { p_client: clientId });
  if (error) return { ok: false, error: error.message };
  refresh();
  return { ok: true };
}

export async function connectJob(jobOrderId: string, jobId: string): Promise<AgencyActionResult> {
  const supabase = await client();
  if (!supabase) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(jobOrderId)) return { ok: false, error: 'That job order no longer exists.' };
  if (!UUID_RE.test(jobId)) return { ok: false, error: 'Choose one of your jobs.' };
  const { error } = await supabase.rpc('omelo_link_job_order', { p_job_order: jobOrderId, p_job: jobId });
  if (error) return { ok: false, error: error.message };
  refresh();
  return { ok: true };
}
