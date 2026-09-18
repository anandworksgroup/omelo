'use server';

import { revalidatePath } from 'next/cache';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { UUID_RE } from '@/lib/talent';
import type { Database } from '@/lib/supabase/database.types';

/*
 * Team management for employers and agencies. People join only by accepting
 * an invitation (omelo_invite_team_member → omelo_accept_team_invitation);
 * owners and admins change roles, deactivate and remove members directly.
 * The database enforces who may do what (only owners manage owners; sourcer
 * and coordinator exist only in agencies) and its message is shown as is.
 */

type Fail = { ok: false; error: string; code?: string };
type Ok = { ok: true; message?: string };
type Role = Database['public']['Enums']['company_role'];

const SIGNED_OUT = 'You are signed out or not part of a company.';
const NOT_ADMIN = 'Only owners and admins can manage the team.';

export async function inviteTeamMember(email: string, role: string): Promise<Ok | Fail> {
  const ctx = await getCompanyContext();
  if (!ctx) return { ok: false, error: SIGNED_OUT };
  const e = email.trim().toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e) || e.length > 254) return { ok: false, error: 'Enter a valid email address.' };
  const supabase = await createClient();
  const { error } = await supabase.rpc('omelo_invite_team_member', { p_company: ctx.companyId, p_email: e, p_role: role });
  if (error) return { ok: false, error: error.message, code: error.code };
  revalidatePath('/dashboard/team');
  return {
    ok: true,
    message: `Invitation sent to ${e}. If they already use Omelo they get a notification; otherwise send them the link to sign up with this address — the invitation waits for 14 days.`,
  };
}

export async function cancelTeamInvitation(invitationId: string): Promise<Ok | Fail> {
  const ctx = await getCompanyContext();
  if (!ctx) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(invitationId)) return { ok: false, error: 'Invitation not found.' };
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('company_invitations')
    .delete()
    .eq('id', invitationId)
    .eq('company_id', ctx.companyId)
    .select('id');
  if (error) return { ok: false, error: error.message, code: error.code };
  if (!data?.length) return { ok: false, error: NOT_ADMIN, code: '42501' };
  revalidatePath('/dashboard/team');
  return { ok: true };
}

export async function updateTeamMember(
  memberId: string,
  changes: { role?: string; isActive?: boolean }
): Promise<Ok | Fail> {
  const ctx = await getCompanyContext();
  if (!ctx) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(memberId)) return { ok: false, error: 'Member not found.' };
  const patch: { role?: Role; is_active?: boolean } = {};
  if (changes.role) patch.role = changes.role as Role;
  if (changes.isActive !== undefined) patch.is_active = changes.isActive;
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('company_members')
    .update(patch)
    .eq('id', memberId)
    .eq('company_id', ctx.companyId)
    .select('id');
  if (error) {
    if (error.code === '23505') return { ok: false, error: 'This person already has that role.' };
    return { ok: false, error: error.message, code: error.code };
  }
  if (!data?.length) return { ok: false, error: NOT_ADMIN, code: '42501' };
  revalidatePath('/dashboard/team');
  return { ok: true };
}

export async function removeTeamMember(memberId: string): Promise<Ok | Fail> {
  const ctx = await getCompanyContext();
  if (!ctx) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(memberId)) return { ok: false, error: 'Member not found.' };
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('company_members')
    .delete()
    .eq('id', memberId)
    .eq('company_id', ctx.companyId)
    .select('id');
  if (error) return { ok: false, error: error.message, code: error.code };
  if (!data?.length) return { ok: false, error: NOT_ADMIN, code: '42501' };
  revalidatePath('/dashboard/team');
  return { ok: true };
}
