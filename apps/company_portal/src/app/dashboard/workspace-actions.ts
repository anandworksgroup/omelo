'use server';

import { revalidatePath } from 'next/cache';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { WORKSPACE_COOKIE, createClient, getMemberships } from '@/lib/supabase/server';
import { UUID_RE } from '@/lib/talent';

/*
 * Workspaces: a person can belong to several companies (an employer and an
 * agency, say). The cookie only remembers which one they are looking at;
 * membership is re-read from the database on every request and RLS decides
 * what each company may see.
 */

type Fail = { ok: false; error: string; code?: string };

const ONE_YEAR = 60 * 60 * 24 * 365;

async function rememberWorkspace(companyId: string) {
  (await cookies()).set(WORKSPACE_COOKIE, companyId, {
    path: '/',
    httpOnly: true,
    sameSite: 'lax',
    secure: process.env.NODE_ENV === 'production',
    maxAge: ONE_YEAR,
  });
}

/** Only same-site dashboard paths, never an open redirect. */
function safeNext(next: string | undefined, fallback: string) {
  return next && /^\/dashboard(\/[\w\-/]*)?$/.test(next) ? next : fallback;
}

export async function switchWorkspace(companyId: string, next?: string): Promise<Fail | void> {
  if (!UUID_RE.test(companyId)) return { ok: false, error: 'Choose one of your companies.' };
  const memberships = await getMemberships();
  const target = memberships.find((m) => m.companyId === companyId);
  if (!target) return { ok: false, error: 'You are not an active member of that company.' };
  await rememberWorkspace(companyId);
  revalidatePath('/', 'layout');
  redirect(safeNext(next, target.kind === 'agency' ? '/dashboard/agency' : '/dashboard'));
}

/** Form-friendly version for the switcher's no-JS fallback. */
export async function switchWorkspaceForm(formData: FormData): Promise<void> {
  const res = await switchWorkspace(String(formData.get('company') ?? ''));
  if (res && !res.ok) redirect('/dashboard');
}

/**
 * Create an agency (or an independent recruiter's one-person agency). Only
 * omelo_create_agency can make a company with kind 'agency'; the creator
 * becomes its owner. Searching and asking for consent stay closed until
 * Omelo verifies it.
 */
export async function createAgency(input: {
  name: string;
  independent: boolean;
  country?: string;
}): Promise<Fail | void> {
  const name = input.name.trim().replace(/\s+/g, ' ');
  if (name.length < 2 || name.length > 120)
    return { ok: false, error: 'Give the agency a name between 2 and 120 characters.' };
  const country = (input.country ?? '').trim().toUpperCase();
  if (country && !/^[A-Z]{2}$/.test(country)) return { ok: false, error: 'Choose a country.' };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('omelo_create_agency', {
    p_name: name,
    p_independent: input.independent,
    p_country: country || undefined,
  });
  if (error) return { ok: false, error: error.message, code: error.code };
  await rememberWorkspace(String(data));
  revalidatePath('/', 'layout');
  redirect('/dashboard/agency?welcome=1');
}

/** Accept a team invitation, then work in that company. */
export async function acceptTeamInvitation(invitationId: string): Promise<Fail | void> {
  if (!UUID_RE.test(invitationId)) return { ok: false, error: 'Invitation not found.' };
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('omelo_accept_team_invitation', { p_invitation: invitationId });
  if (error) return { ok: false, error: error.message, code: error.code };
  await rememberWorkspace(String(data));
  revalidatePath('/', 'layout');
  redirect('/dashboard?joined=1');
}

export async function declineTeamInvitation(invitationId: string): Promise<Fail | { ok: true }> {
  if (!UUID_RE.test(invitationId)) return { ok: false, error: 'Invitation not found.' };
  const supabase = await createClient();
  const { error } = await supabase.rpc('omelo_decline_team_invitation', { p_invitation: invitationId });
  if (error) return { ok: false, error: error.message, code: error.code };
  revalidatePath('/', 'layout');
  return { ok: true };
}
