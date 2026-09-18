'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';
import { isPlatformAdmin } from '@/lib/admin';
import { UUID_RE } from '@/lib/talent';
import type { Database } from '@/lib/supabase/database.types';

/*
 * Platform-admin tools. The RPCs authorise for themselves (trust_safety or
 * superadmin for verification, superadmin for entitlements) and every call
 * is written to audit_log by the database. The isPlatformAdmin() check here
 * only stops obvious misuse early; the server message is shown verbatim.
 */

type Result = { ok: true; message: string } | { ok: false; error: string };
type Method = Database['public']['Enums']['verification_method'];

export async function setCompanyVerification(input: {
  companyId: string;
  verified: boolean;
  method: Method;
}): Promise<Result> {
  if (!(await isPlatformAdmin())) return { ok: false, error: 'Platform administrators only.' };
  if (!UUID_RE.test(input.companyId)) return { ok: false, error: 'That is not a company id.' };
  const supabase = await createClient();
  const { error } = await supabase.rpc('omelo_admin_set_company_verification', {
    p_company: input.companyId,
    p_verified: input.verified,
    p_method: input.method,
  });
  if (error) return { ok: false, error: error.message };
  revalidatePath('/admin/companies');
  return { ok: true, message: input.verified ? 'Company verified.' : 'Verification removed.' };
}

export async function setCompanyEntitlements(input: {
  companyId: string;
  plan: string;
  talentSearch: boolean;
  searchQuotaMonthly: number;
  outreachQuotaDaily: number;
  validUntil: string | null;
}): Promise<Result> {
  if (!(await isPlatformAdmin())) return { ok: false, error: 'Platform administrators only.' };
  if (!UUID_RE.test(input.companyId)) return { ok: false, error: 'That is not a company id.' };
  const plan = input.plan.trim();
  if (!/^[a-z0-9][a-z0-9_-]{0,39}$/i.test(plan)) return { ok: false, error: 'Plan: letters, digits, - or _ (up to 40).' };
  const sq = Math.floor(Number(input.searchQuotaMonthly));
  const oq = Math.floor(Number(input.outreachQuotaDaily));
  if (!Number.isFinite(sq) || !Number.isFinite(oq) || sq < 0 || oq < 0)
    return { ok: false, error: 'Quotas must be whole numbers, 0 or more (0 = unlimited).' };
  if (input.validUntil && !/^\d{4}-\d{2}-\d{2}$/.test(input.validUntil))
    return { ok: false, error: 'Valid until must be a date.' };

  const supabase = await createClient();
  const { error } = await supabase.rpc('omelo_admin_set_entitlements', {
    p_company: input.companyId,
    p_plan: plan,
    p_talent_search: input.talentSearch,
    p_search_quota_monthly: sq,
    p_outreach_quota_daily: oq,
    p_valid_until: input.validUntil ?? undefined,
  });
  if (error) return { ok: false, error: error.message };
  revalidatePath('/admin/companies');
  return { ok: true, message: 'Plan saved.' };
}
