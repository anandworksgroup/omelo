'use server';

import { revalidatePath } from 'next/cache';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { reportError } from '@/lib/observability';
import { UUID_RE } from '@/lib/talent';
import { ORGANIZATION_TYPES, TEAM_PURPOSES, enterpriseError } from '@/lib/enterprise';

/*
 * Release 8 — the structure inside an organization.
 *
 * Everything here is a plain table write; RLS decides who may do it (business
 * units: owner and admin; departments and locations: owner, admin, recruiter;
 * teams and their members: owner, admin, HR). These actions shape the input,
 * keep the company id on the row, and turn a refusal into one sentence.
 */

export type OrgState = { error?: string; ok?: boolean; message?: string };

const PATH = '/dashboard/organization';
/** Codes the database raises on purpose; anything else is worth reporting. */
const EXPECTED = new Set(['42501', '22023', '23505', '23503', '23514', '22001']);

function fail(e: { code?: string; message: string }, action: string): OrgState {
  if (!EXPECTED.has(e.code ?? '')) reportError(e, { action });
  return { error: enterpriseError(e).text };
}

async function session() {
  const ctx = await getCompanyContext();
  if (!ctx) return null;
  return { ctx, supabase: await createClient() };
}

const text = (fd: FormData, key: string) => String(fd.get(key) ?? '').trim();
const uuidOrNull = (fd: FormData, key: string) => {
  const v = text(fd, key);
  return v && UUID_RE.test(v) ? v : null;
};

/* ------------------------------------------------------------------ */
/* What kind of organization                                           */
/* ------------------------------------------------------------------ */

export async function setOrganizationType(_prev: OrgState, fd: FormData): Promise<OrgState> {
  const s = await session();
  if (!s) return { error: 'You are signed out or not part of a company.' };
  const type = text(fd, 'organization_type');
  if (!(ORGANIZATION_TYPES as readonly string[]).includes(type))
    return { error: 'Choose one of the organization types.' };
  if (!s.ctx.roles.some((r) => r === 'owner' || r === 'admin'))
    return { error: 'Only an owner or admin changes what kind of organization this is.' };

  const { data, error } = await s.supabase
    .from('companies')
    .update({ organization_type: type })
    .eq('id', s.ctx.companyId)
    .select('id, organization_type, company_kind');
  if (error) return fail(error, 'setOrganizationType');
  if (!data?.length) return { error: 'Only an owner or admin changes what kind of organization this is.' };

  // company_kind follows organization_type, and the whole menu follows kind.
  revalidatePath('/', 'layout');
  return {
    ok: true,
    message:
      data[0].company_kind === 'agency'
        ? 'Saved. This workspace now uses the agency menu.'
        : 'Saved. This workspace uses the employer menu.',
  };
}

/* ------------------------------------------------------------------ */
/* Business units                                                      */
/* ------------------------------------------------------------------ */

export async function saveBusinessUnit(_prev: OrgState, fd: FormData): Promise<OrgState> {
  const s = await session();
  if (!s) return { error: 'You are signed out or not part of a company.' };
  const id = uuidOrNull(fd, 'id');
  const name = text(fd, 'name');
  const code = text(fd, 'code') || null;
  const parentId = uuidOrNull(fd, 'parent_id');
  if (name.length < 2 || name.length > 120) return { error: 'A business unit name needs 2 to 120 characters.' };
  if (code && code.length > 40) return { error: 'Keep the code under 40 characters.' };
  if (id && parentId === id) return { error: 'A business unit cannot sit inside itself.' };

  const row = { name, code, parent_id: parentId };
  const { data, error } = id
    ? await s.supabase
        .from('business_units')
        .update(row)
        .eq('id', id)
        .eq('company_id', s.ctx.companyId)
        .select('id')
    : await s.supabase
        .from('business_units')
        .insert({ ...row, company_id: s.ctx.companyId })
        .select('id');
  if (error) {
    if (error.code === '23505') return { error: 'You already have a business unit with that name.' };
    return fail(error, 'saveBusinessUnit');
  }
  if (!data?.length) return { error: 'Only an owner or admin can change business units.' };
  revalidatePath(PATH);
  return { ok: true, message: id ? 'Business unit saved.' : 'Business unit added.' };
}

export async function setBusinessUnitActive(_prev: OrgState, fd: FormData): Promise<OrgState> {
  const s = await session();
  if (!s) return { error: 'You are signed out or not part of a company.' };
  const id = uuidOrNull(fd, 'id');
  if (!id) return { error: 'Business unit not found.' };
  const active = text(fd, 'is_active') === 'true';
  const { data, error } = await s.supabase
    .from('business_units')
    .update({ is_active: active })
    .eq('id', id)
    .eq('company_id', s.ctx.companyId)
    .select('id');
  if (error) return fail(error, 'setBusinessUnitActive');
  if (!data?.length) return { error: 'Only an owner or admin can change business units.' };
  revalidatePath(PATH);
  return { ok: true, message: active ? 'Business unit reopened.' : 'Business unit archived.' };
}

/* ------------------------------------------------------------------ */
/* Departments                                                         */
/* ------------------------------------------------------------------ */

export async function saveDepartment(_prev: OrgState, fd: FormData): Promise<OrgState> {
  const s = await session();
  if (!s) return { error: 'You are signed out or not part of a company.' };
  const id = uuidOrNull(fd, 'id');
  const name = text(fd, 'name');
  const businessUnitId = uuidOrNull(fd, 'business_unit_id');
  if (name.length < 2 || name.length > 120) return { error: 'A department name needs 2 to 120 characters.' };

  const row = { name, business_unit_id: businessUnitId };
  const { data, error } = id
    ? await s.supabase.from('departments').update(row).eq('id', id).eq('company_id', s.ctx.companyId).select('id')
    : await s.supabase
        .from('departments')
        .insert({ ...row, company_id: s.ctx.companyId })
        .select('id');
  if (error) {
    if (error.code === '23505') return { error: 'You already have a department with that name.' };
    return fail(error, 'saveDepartment');
  }
  if (!data?.length) return { error: 'Only an owner, admin or recruiter can change departments.' };
  revalidatePath(PATH);
  return { ok: true, message: id ? 'Department saved.' : 'Department added.' };
}

export async function deleteDepartment(_prev: OrgState, fd: FormData): Promise<OrgState> {
  const s = await session();
  if (!s) return { error: 'You are signed out or not part of a company.' };
  const id = uuidOrNull(fd, 'id');
  if (!id) return { error: 'Department not found.' };
  const { data, error } = await s.supabase
    .from('departments')
    .delete()
    .eq('id', id)
    .eq('company_id', s.ctx.companyId)
    .select('id');
  if (error) {
    if (error.code === '23503')
      return { error: 'Jobs or people still point at this department. Move them first, or keep it.' };
    return fail(error, 'deleteDepartment');
  }
  if (!data?.length) return { error: 'Nothing was removed. It may already be gone, or your role cannot remove it.' };
  revalidatePath(PATH);
  return { ok: true, message: 'Department removed.' };
}

/* ------------------------------------------------------------------ */
/* Locations                                                           */
/* ------------------------------------------------------------------ */

export async function saveLocation(_prev: OrgState, fd: FormData): Promise<OrgState> {
  const s = await session();
  if (!s) return { error: 'You are signed out or not part of a company.' };
  const id = uuidOrNull(fd, 'id');
  const name = text(fd, 'name');
  const address = text(fd, 'address') || null;
  if (name.length < 2 || name.length > 120) return { error: 'A location name needs 2 to 120 characters.' };
  if (address && address.length > 300) return { error: 'Keep the address under 300 characters.' };

  const { data, error } = id
    ? await s.supabase
        .from('company_locations')
        .update({ name, address })
        .eq('id', id)
        .eq('company_id', s.ctx.companyId)
        .select('id')
    : await s.supabase
        .from('company_locations')
        .insert({ name, address, company_id: s.ctx.companyId })
        .select('id');
  if (error) return fail(error, 'saveLocation');
  if (!data?.length) return { error: 'Only an owner, admin or recruiter can change locations.' };
  revalidatePath(PATH);
  return { ok: true, message: id ? 'Location saved.' : 'Location added.' };
}

export async function deleteLocation(_prev: OrgState, fd: FormData): Promise<OrgState> {
  const s = await session();
  if (!s) return { error: 'You are signed out or not part of a company.' };
  const id = uuidOrNull(fd, 'id');
  if (!id) return { error: 'Location not found.' };
  const { data, error } = await s.supabase
    .from('company_locations')
    .delete()
    .eq('id', id)
    .eq('company_id', s.ctx.companyId)
    .select('id');
  if (error) {
    if (error.code === '23503') return { error: 'Jobs still use this location. Move them first, or keep it.' };
    return fail(error, 'deleteLocation');
  }
  if (!data?.length) return { error: 'Nothing was removed. It may already be gone, or your role cannot remove it.' };
  revalidatePath(PATH);
  return { ok: true, message: 'Location removed.' };
}

/* ------------------------------------------------------------------ */
/* Teams                                                               */
/* ------------------------------------------------------------------ */

export async function saveTeam(_prev: OrgState, fd: FormData): Promise<OrgState> {
  const s = await session();
  if (!s) return { error: 'You are signed out or not part of a company.' };
  const id = uuidOrNull(fd, 'id');
  const name = text(fd, 'name');
  const purpose = text(fd, 'purpose') || 'general';
  if (name.length < 2 || name.length > 120) return { error: 'A team name needs 2 to 120 characters.' };
  if (!(TEAM_PURPOSES as readonly string[]).includes(purpose)) return { error: 'Choose what the team is for.' };

  const row = {
    name,
    purpose,
    business_unit_id: uuidOrNull(fd, 'business_unit_id'),
    department_id: uuidOrNull(fd, 'department_id'),
    lead_person_id: uuidOrNull(fd, 'lead_person_id'),
  };
  const { data, error } = id
    ? await s.supabase.from('teams').update(row).eq('id', id).eq('company_id', s.ctx.companyId).select('id')
    : await s.supabase
        .from('teams')
        .insert({ ...row, company_id: s.ctx.companyId })
        .select('id');
  if (error) {
    if (error.code === '23505') return { error: 'You already have a team with that name.' };
    return fail(error, 'saveTeam');
  }
  if (!data?.length) return { error: 'Only an owner, admin or HR can change teams.' };
  revalidatePath(PATH);
  return { ok: true, message: id ? 'Team saved.' : 'Team added.' };
}

export async function setTeamActive(_prev: OrgState, fd: FormData): Promise<OrgState> {
  const s = await session();
  if (!s) return { error: 'You are signed out or not part of a company.' };
  const id = uuidOrNull(fd, 'id');
  if (!id) return { error: 'Team not found.' };
  const active = text(fd, 'is_active') === 'true';
  const { data, error } = await s.supabase
    .from('teams')
    .update({ is_active: active })
    .eq('id', id)
    .eq('company_id', s.ctx.companyId)
    .select('id');
  if (error) return fail(error, 'setTeamActive');
  if (!data?.length) return { error: 'Only an owner, admin or HR can change teams.' };
  revalidatePath(PATH);
  return { ok: true, message: active ? 'Team reopened.' : 'Team archived.' };
}

/** Add or remove one person on a team. The team must belong to this company. */
export async function setTeamMember(_prev: OrgState, fd: FormData): Promise<OrgState> {
  const s = await session();
  if (!s) return { error: 'You are signed out or not part of a company.' };
  const teamId = uuidOrNull(fd, 'team_id');
  const personId = uuidOrNull(fd, 'person_id');
  const add = text(fd, 'add') === 'true';
  if (!teamId) return { error: 'Team not found.' };
  if (!personId) return { error: 'Choose someone from your team.' };

  const { data: team } = await s.supabase
    .from('teams')
    .select('id')
    .eq('id', teamId)
    .eq('company_id', s.ctx.companyId)
    .maybeSingle();
  if (!team) return { error: 'Team not found.' };

  if (add) {
    const { data: member } = await s.supabase
      .from('company_members')
      .select('id')
      .eq('company_id', s.ctx.companyId)
      .eq('person_id', personId)
      .eq('is_active', true)
      .limit(1);
    if (!member?.length) return { error: 'Only active members of this organization can join a team.' };
    const { error } = await s.supabase.from('team_members').insert({ team_id: teamId, person_id: personId });
    if (error) {
      if (error.code === '23505') return { error: 'They are already on this team.' };
      return fail(error, 'setTeamMember.add');
    }
  } else {
    const { data, error } = await s.supabase
      .from('team_members')
      .delete()
      .eq('team_id', teamId)
      .eq('person_id', personId)
      .select('team_id');
    if (error) return fail(error, 'setTeamMember.remove');
    if (!data?.length) return { error: 'Nothing changed. Only an owner, admin or HR can change team members.' };
  }
  revalidatePath(PATH);
  return { ok: true, message: add ? 'Added to the team.' : 'Removed from the team.' };
}
