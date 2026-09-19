'use server';

import { revalidatePath } from 'next/cache';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { reportError } from '@/lib/observability';
import {
  INVITE_MAX,
  NOTE_MAX,
  PAGE_SIZE,
  RADII,
  UUID_RE,
  parseSearch,
  type Pool,
  type SearchResult,
} from '@/lib/talent';

/*
 * Talent search, invitations and pools. Every rule (consent, verification,
 * plan, quotas, anti-spam) lives in the database; these actions only shape
 * input and pass the database's human-readable message straight through.
 */

type Fail = { ok: false; error: string; code?: string };
type Ok<T = object> = { ok: true } & T;

const SIGNED_OUT = 'You are signed out or not part of a company.';

async function client() {
  const ctx = await getCompanyContext();
  if (!ctx) return { error: SIGNED_OUT } as const;
  return { ctx, supabase: await createClient() } as const;
}

const fail = (e: { message: string; code?: string }): Fail => ({ ok: false, error: e.message, code: e.code });

/* ------------------------------------------------------------------ */
/* Search                                                              */
/* ------------------------------------------------------------------ */

export async function searchTalent(input: {
  jobId: string;
  query: string;
  radiusKm: number;
  offset: number;
  /** R6 filters: eligibility, open_to_relocation, language, current_country, work_auth_country. */
  filters?: Record<string, string | boolean | undefined>;
}): Promise<Ok<{ data: SearchResult }> | Fail> {
  const c = await client();
  if ('error' in c) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(input.jobId)) return { ok: false, error: 'Choose one of your published jobs.' };
  const query = input.query.trim();
  if (query.length > 80) return { ok: false, error: 'Keep the search under 80 characters.' };
  const radius = (RADII as readonly number[]).includes(input.radiusKm) ? input.radiusKm : 50;
  // Only the keys this search understands, empty values dropped.
  const ALLOWED = ['eligibility', 'open_to_relocation', 'language', 'current_country', 'work_auth_country'];
  const filters: Record<string, string | boolean> = {};
  for (const [k, v] of Object.entries(input.filters ?? {})) {
    if (!ALLOWED.includes(k) || v === undefined || v === '') continue;
    filters[k] = v;
  }

  const { data, error } = await c.supabase.rpc('omelo_search_talent', {
    p_job_id: input.jobId,
    p_query: query || undefined,
    p_radius_km: radius,
    p_limit: PAGE_SIZE,
    p_offset: Math.max(0, Math.floor(input.offset) || 0),
    p_filters: filters,
  });
  if (error) {
    if (error.code !== '42501' && error.code !== '22023') reportError(error, { action: 'searchTalent' });
    return fail(error);
  }
  return { ok: true, data: parseSearch(data) };
}

/* ------------------------------------------------------------------ */
/* Invitations                                                         */
/* ------------------------------------------------------------------ */

export async function inviteToApply(input: {
  jobId: string;
  identityId: string;
  message: string;
}): Promise<Ok<{ invitationId: string }> | Fail> {
  const c = await client();
  if ('error' in c) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(input.jobId) || !UUID_RE.test(input.identityId))
    return { ok: false, error: 'Choose a job and a candidate.' };
  const message = input.message.trim();
  if (message.length > INVITE_MAX) return { ok: false, error: `Keep the message under ${INVITE_MAX} characters.` };

  const { data, error } = await c.supabase.rpc('omelo_invite_to_apply', {
    p_job_id: input.jobId,
    p_identity: input.identityId,
    p_message: message || undefined,
  });
  if (error) return fail(error);
  revalidatePath(`/dashboard/jobs/${input.jobId}`);
  return { ok: true, invitationId: String(data) };
}

export async function withdrawInvitation(input: {
  invitationId: string;
  jobId?: string;
}): Promise<Ok | Fail> {
  const c = await client();
  if ('error' in c) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(input.invitationId)) return { ok: false, error: 'Invitation not found.' };
  const { error } = await c.supabase.rpc('omelo_withdraw_invitation', { p_invitation: input.invitationId });
  if (error) return fail(error);
  if (input.jobId) revalidatePath(`/dashboard/jobs/${input.jobId}`);
  return { ok: true };
}

/* ------------------------------------------------------------------ */
/* Pools                                                               */
/* ------------------------------------------------------------------ */

function poolName(raw: string): string | Fail {
  const name = raw.trim().replace(/\s+/g, ' ');
  if (name.length < 2 || name.length > 80) return { ok: false, error: 'Give the pool a name (2–80 characters).' };
  return name;
}

export async function createPool(rawName: string): Promise<Ok<{ pool: Pool }> | Fail> {
  const c = await client();
  if ('error' in c) return { ok: false, error: SIGNED_OUT };
  const name = poolName(rawName);
  if (typeof name !== 'string') return name;
  const {
    data: { user },
  } = await c.supabase.auth.getUser();
  const { data, error } = await c.supabase
    .from('talent_pools')
    .insert({ company_id: c.ctx.companyId, name, created_by: user?.id ?? null })
    .select('id, name')
    .single();
  if (error) {
    if (error.code === '23505') return { ok: false, error: `You already have a pool called “${name}”.` };
    return fail(error);
  }
  revalidatePath('/dashboard/talent', 'layout');
  return { ok: true, pool: data };
}

export async function renamePool(poolId: string, rawName: string): Promise<Ok | Fail> {
  const c = await client();
  if ('error' in c) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(poolId)) return { ok: false, error: 'Pool not found.' };
  const name = poolName(rawName);
  if (typeof name !== 'string') return name;
  const { data, error } = await c.supabase
    .from('talent_pools')
    .update({ name })
    .eq('id', poolId)
    .eq('company_id', c.ctx.companyId)
    .select('id');
  if (error) {
    if (error.code === '23505') return { ok: false, error: `You already have a pool called “${name}”.` };
    return fail(error);
  }
  if (!data?.length) return { ok: false, error: 'Only owners, admins and recruiters can rename pools.' };
  revalidatePath('/dashboard/talent', 'layout');
  return { ok: true };
}

export async function deletePool(poolId: string): Promise<Ok | Fail> {
  const c = await client();
  if ('error' in c) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(poolId)) return { ok: false, error: 'Pool not found.' };
  const { data, error } = await c.supabase
    .from('talent_pools')
    .delete()
    .eq('id', poolId)
    .eq('company_id', c.ctx.companyId)
    .select('id');
  if (error) return fail(error);
  if (!data?.length) return { ok: false, error: 'Only owners, admins and recruiters can delete pools.' };
  revalidatePath('/dashboard/talent', 'layout');
  return { ok: true };
}

/**
 * Save a candidate to a pool (optionally creating the pool first).
 *
 * talent_pool_members needs person_id, which the talent card does not carry.
 * The identity row is readable to the company exactly when the candidate is
 * visible to it (RLS work_identities_via_consent / via_application), so that
 * read doubles as a consent check; the insert trigger checks again.
 */
export async function addToPool(input: {
  poolId?: string;
  newPoolName?: string;
  identityId: string;
  note: string;
}): Promise<Ok<{ pool: Pool; created: boolean }> | Fail> {
  const c = await client();
  if ('error' in c) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(input.identityId)) return { ok: false, error: 'Candidate not found.' };
  const note = input.note.trim();
  if (note.length > NOTE_MAX) return { ok: false, error: `Keep the note under ${NOTE_MAX} characters.` };

  const { data: wi, error: wiError } = await c.supabase
    .from('work_identities')
    .select('person_id')
    .eq('id', input.identityId)
    .maybeSingle();
  if (wiError) return fail(wiError);
  if (!wi) return { ok: false, error: 'This person is no longer visible to your company.' };

  let pool: Pool;
  let created = false;
  if (input.poolId) {
    if (!UUID_RE.test(input.poolId)) return { ok: false, error: 'Choose a pool.' };
    const { data, error } = await c.supabase
      .from('talent_pools')
      .select('id, name')
      .eq('id', input.poolId)
      .eq('company_id', c.ctx.companyId)
      .maybeSingle();
    if (error) return fail(error);
    if (!data) return { ok: false, error: 'Pool not found.' };
    pool = data;
  } else {
    const res = await createPool(input.newPoolName ?? '');
    if (!res.ok) return res;
    pool = res.pool;
    created = true;
  }

  const { error } = await c.supabase.from('talent_pool_members').insert({
    pool_id: pool.id,
    person_id: wi.person_id,
    work_identity_id: input.identityId,
    note: note || null,
  });
  if (error) {
    if (error.code === '23505') return { ok: false, error: `Already saved in “${pool.name}”.` };
    return fail(error);
  }
  revalidatePath('/dashboard/talent', 'layout');
  return { ok: true, pool, created };
}

export async function removePoolMember(input: { poolId: string; personId: string }): Promise<Ok | Fail> {
  const c = await client();
  if ('error' in c) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(input.poolId) || !UUID_RE.test(input.personId)) return { ok: false, error: 'Member not found.' };
  const { data, error } = await c.supabase
    .from('talent_pool_members')
    .delete()
    .eq('pool_id', input.poolId)
    .eq('person_id', input.personId)
    .select('pool_id');
  if (error) return fail(error);
  if (!data?.length) return { ok: false, error: 'Only owners, admins and recruiters can remove members.' };
  revalidatePath(`/dashboard/talent/pools/${input.poolId}`);
  return { ok: true };
}

export async function updatePoolNote(input: {
  poolId: string;
  personId: string;
  note: string;
}): Promise<Ok | Fail> {
  const c = await client();
  if ('error' in c) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(input.poolId) || !UUID_RE.test(input.personId)) return { ok: false, error: 'Member not found.' };
  const note = input.note.trim();
  if (note.length > NOTE_MAX) return { ok: false, error: `Keep the note under ${NOTE_MAX} characters.` };
  const { data, error } = await c.supabase
    .from('talent_pool_members')
    .update({ note: note || null })
    .eq('pool_id', input.poolId)
    .eq('person_id', input.personId)
    .select('pool_id');
  if (error) return fail(error);
  if (!data?.length) return { ok: false, error: 'Only owners, admins and recruiters can edit notes.' };
  revalidatePath(`/dashboard/talent/pools/${input.poolId}`);
  return { ok: true };
}
