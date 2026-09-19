'use server';

import { revalidatePath } from 'next/cache';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { reportError } from '@/lib/observability';
import { COUNTRY_RE, CURRENCY_RE, friendlyDbError } from '@/lib/global';
import { UUID_RE } from '@/lib/talent';

/*
 * Legal entities are written straight to company_legal_entities; RLS lets
 * only owners and admins insert, update and delete, and the table's trigger
 * checks the time zone. These actions shape input and translate errors.
 */

export type EntityState = { error?: string; ok?: boolean; message?: string };

const EXPECTED = new Set(['42501', '22023', '23505', '23503', '23514']);
const PATH = '/dashboard/company/entities';

function validTimeZone(tz: string) {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

async function session() {
  const ctx = await getCompanyContext();
  if (!ctx) return null;
  if (!ctx.roles.some((r) => r === 'owner' || r === 'admin')) return 'forbidden' as const;
  return { ctx, supabase: await createClient() };
}

export async function saveEntity(_prev: EntityState, fd: FormData): Promise<EntityState> {
  const s = await session();
  if (!s) return { error: 'You are signed out or not part of a company.' };
  if (s === 'forbidden') return { error: 'Only owners and admins can change legal entities.' };

  const id = String(fd.get('id') ?? '').trim();
  const country = String(fd.get('country_code') ?? '').trim().toUpperCase();
  const legalName = String(fd.get('legal_name') ?? '').trim();
  const registration = String(fd.get('registration_number') ?? '').trim() || null;
  const currency = String(fd.get('currency') ?? '').trim().toUpperCase();
  const timezone = String(fd.get('timezone') ?? '').trim();
  const notes = String(fd.get('hiring_notes') ?? '').trim() || null;
  const isDefault = fd.get('is_default') === 'on';

  if (id && !UUID_RE.test(id)) return { error: 'Entity not found.' };
  if (!COUNTRY_RE.test(country)) return { error: 'Choose the country.' };
  if (legalName.length < 2 || legalName.length > 200) return { error: 'The legal name needs 2 to 200 characters.' };
  if (registration && registration.length > 80) return { error: 'Keep the registration number under 80 characters.' };
  if (!CURRENCY_RE.test(currency)) return { error: 'Choose the currency.' };
  if (!timezone || !validTimeZone(timezone)) return { error: 'Choose a time zone from the list.' };
  if (notes && notes.length > 2000) return { error: 'Keep the hiring notes under 2000 characters.' };

  const { ctx, supabase } = s;
  // One default per country (a unique index): clear the old one first.
  if (isDefault) {
    let q = supabase
      .from('company_legal_entities')
      .update({ is_default: false })
      .eq('company_id', ctx.companyId)
      .eq('country_code', country)
      .eq('is_default', true);
    if (id) q = q.neq('id', id);
    const { error } = await q;
    if (error) return { error: friendlyDbError(error) };
  }

  const row = {
    country_code: country,
    legal_name: legalName,
    registration_number: registration,
    currency,
    timezone,
    hiring_notes: notes,
    is_default: isDefault,
  };
  const { error } = id
    ? await supabase.from('company_legal_entities').update(row).eq('id', id).eq('company_id', ctx.companyId)
    : await supabase.from('company_legal_entities').insert({ ...row, company_id: ctx.companyId });
  if (error) {
    if (!EXPECTED.has(error.code ?? '')) reportError(error, { action: 'saveEntity' });
    return { error: friendlyDbError(error) };
  }
  revalidatePath(PATH);
  return { ok: true, message: id ? 'Entity saved.' : 'Entity added.' };
}

export async function deleteEntity(_prev: EntityState, fd: FormData): Promise<EntityState> {
  const s = await session();
  if (!s) return { error: 'You are signed out or not part of a company.' };
  if (s === 'forbidden') return { error: 'Only owners and admins can change legal entities.' };
  const id = String(fd.get('id') ?? '');
  if (!UUID_RE.test(id)) return { error: 'Entity not found.' };
  const { data, error } = await s.supabase
    .from('company_legal_entities')
    .delete()
    .eq('id', id)
    .eq('company_id', s.ctx.companyId)
    .select('id');
  if (error) {
    if (!EXPECTED.has(error.code ?? '')) reportError(error, { action: 'deleteEntity' });
    return { error: friendlyDbError(error) };
  }
  if (!data?.length) return { error: 'Nothing was removed. The entity may already be gone, or your role cannot remove it.' };
  revalidatePath(PATH);
  return { ok: true, message: 'Entity removed. Jobs that used it keep their country.' };
}
