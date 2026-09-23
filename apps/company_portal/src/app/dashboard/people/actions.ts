'use server';

import { revalidatePath } from 'next/cache';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { reportError } from '@/lib/observability';
import { UUID_RE } from '@/lib/talent';
import { GRANT_SCOPES, SCOPE_MODES, enterpriseError } from '@/lib/enterprise';
import type { Database } from '@/lib/supabase/database.types';

/*
 * Release 8 — who reaches which part of the organization.
 *
 *   company_members.scope_mode   'organization' (everything, as before) or 'scoped'
 *   company_role_grants          role + scope for a scoped member
 *
 * Owners and admins write both (RLS). A grant's scope must belong to this
 * organization and the person must already be an active member — the database
 * trigger checks that and raises its own sentence, which is shown as it is.
 */

export type PeopleState = { error?: string; ok?: boolean; message?: string };

type Role = Database['public']['Enums']['company_role'];

const PATH = '/dashboard/people';
const EXPECTED = new Set(['42501', '22023', '23505', '23503', '23514']);
const NOT_ADMIN = 'Only owners and admins can change roles and their scope.';

function fail(e: { code?: string; message: string }, action: string): PeopleState {
  if (!EXPECTED.has(e.code ?? '')) reportError(e, { action });
  return { error: enterpriseError(e).text };
}

async function session() {
  const ctx = await getCompanyContext();
  if (!ctx) return null;
  return { ctx, supabase: await createClient() };
}

const text = (fd: FormData, key: string) => String(fd.get(key) ?? '').trim();

/** Whole organization, or only what they are granted. Applies to every role row. */
export async function setScopeMode(_prev: PeopleState, fd: FormData): Promise<PeopleState> {
  const s = await session();
  if (!s) return { error: 'You are signed out or not part of a company.' };
  const personId = text(fd, 'person_id');
  const mode = text(fd, 'scope_mode');
  if (!UUID_RE.test(personId)) return { error: 'That person is not on your team.' };
  if (!(SCOPE_MODES as readonly string[]).includes(mode)) return { error: 'Choose how far their role reaches.' };

  const { data, error } = await s.supabase
    .from('company_members')
    .update({ scope_mode: mode })
    .eq('company_id', s.ctx.companyId)
    .eq('person_id', personId)
    .select('id');
  if (error) return fail(error, 'setScopeMode');
  if (!data?.length) return { error: NOT_ADMIN };
  revalidatePath(PATH);
  return {
    ok: true,
    message:
      mode === 'scoped'
        ? 'Saved. They now reach only what is granted below.'
        : 'Saved. They work across the whole organization.',
  };
}

export async function addRoleGrant(_prev: PeopleState, fd: FormData): Promise<PeopleState> {
  const s = await session();
  if (!s) return { error: 'You are signed out or not part of a company.' };
  const personId = text(fd, 'person_id');
  const role = text(fd, 'role');
  const scopeType = text(fd, 'scope_type');
  const scopeId = text(fd, 'scope_id');
  if (!UUID_RE.test(personId)) return { error: 'That person is not on your team.' };
  if (!role) return { error: 'Choose the role.' };
  if (!(GRANT_SCOPES as readonly string[]).includes(scopeType)) return { error: 'Choose what the role covers.' };
  if (scopeType !== 'organization' && !UUID_RE.test(scopeId))
    return { error: 'Choose which part of the organization the role covers.' };

  const { error } = await s.supabase.from('company_role_grants').insert({
    company_id: s.ctx.companyId,
    person_id: personId,
    role: role as Role,
    scope_type: scopeType,
    scope_id: scopeType === 'organization' ? null : scopeId,
  });
  if (error) {
    if (error.code === '23505') return { error: 'They already have that role for that part of the organization.' };
    return fail(error, 'addRoleGrant');
  }
  revalidatePath(PATH);
  return { ok: true, message: 'Access granted.' };
}

export async function removeRoleGrant(_prev: PeopleState, fd: FormData): Promise<PeopleState> {
  const s = await session();
  if (!s) return { error: 'You are signed out or not part of a company.' };
  const id = text(fd, 'id');
  if (!UUID_RE.test(id)) return { error: 'That grant is already gone.' };
  const { data, error } = await s.supabase
    .from('company_role_grants')
    .delete()
    .eq('id', id)
    .eq('company_id', s.ctx.companyId)
    .select('id');
  if (error) return fail(error, 'removeRoleGrant');
  if (!data?.length) return { error: NOT_ADMIN };
  revalidatePath(PATH);
  return { ok: true, message: 'Access removed.' };
}
