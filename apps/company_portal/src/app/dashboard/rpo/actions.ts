'use server';

import { revalidatePath } from 'next/cache';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { reportError } from '@/lib/observability';
import { UUID_RE } from '@/lib/talent';
import {
  RPO_PERMISSIONS,
  RPO_RECRUITER_ROLES,
  RPO_SCOPES,
  enterpriseError,
} from '@/lib/enterprise';

/*
 * Release 8 — RPO engagements.
 *
 * Every write is a SECURITY DEFINER function: the provider sets the engagement
 * up and assigns its own recruiters, the client decides the scope and confirms
 * it, and either side can pause or end it. Nothing here widens that — these
 * actions shape the input and pass the database's sentence back.
 */

export type RpoResult = { ok: true; message?: string; id?: string } | { ok: false; error: string };

const EXPECTED = new Set(['42501', '22023', '23505', '23503', '23514']);
const SIGNED_OUT = 'You are signed out or not part of a company.';
const PATH = '/dashboard/rpo';

function fail(e: { code?: string; message: string }, action: string): RpoResult {
  if (!EXPECTED.has(e.code ?? '')) reportError(e, { action });
  return { ok: false, error: enterpriseError(e).text };
}

function refresh(engagementId?: string) {
  revalidatePath(PATH);
  if (engagementId) revalidatePath(`${PATH}/${engagementId}`);
}

/** The id returned by an RPC that hands back the whole row as jsonb. */
function idOf(data: unknown): string | undefined {
  if (data && typeof data === 'object' && !Array.isArray(data)) {
    const v = (data as Record<string, unknown>).id;
    if (typeof v === 'string') return v;
  }
  return undefined;
}

/* ------------------------------------------------------------------ */
/* Finding a client organization                                       */
/* ------------------------------------------------------------------ */

export type CompanyHit = { id: string; name: string; kind: string; organizationType: string };

/** Companies are public on Omelo; this only searches what anyone can already see. */
export async function searchCompanies(query: string): Promise<CompanyHit[]> {
  const ctx = await getCompanyContext();
  if (!ctx) return [];
  const q = query.trim();
  if (q.length < 2) return [];
  const supabase = await createClient();
  const { data, error } = await supabase
    .from('companies')
    .select('id, display_name, company_kind, organization_type')
    .is('deleted_at', null)
    .neq('id', ctx.companyId)
    .ilike('display_name', `%${q.replace(/[%_]/g, '')}%`)
    .order('display_name')
    .limit(15);
  if (error) {
    reportError(error, { action: 'searchCompanies' });
    return [];
  }
  return (data ?? []).map((c) => ({
    id: c.id,
    name: c.display_name,
    kind: c.company_kind,
    organizationType: c.organization_type,
  }));
}

/* ------------------------------------------------------------------ */
/* Setting one up                                                      */
/* ------------------------------------------------------------------ */

export type EngagementInput = {
  clientCompanyId: string;
  title: string;
  reference: string;
  permissions: string[];
  startDate: string;
  endDate: string;
  notes: string;
};

export async function createEngagement(input: EngagementInput): Promise<RpoResult> {
  const ctx = await getCompanyContext();
  if (!ctx) return { ok: false, error: SIGNED_OUT };
  if (!ctx.roles.some((r) => r === 'owner' || r === 'admin'))
    return { ok: false, error: 'Only an owner or admin of the provider sets up an engagement.' };
  if (!UUID_RE.test(input.clientCompanyId)) return { ok: false, error: 'Choose the client organization.' };
  if (input.clientCompanyId === ctx.companyId)
    return { ok: false, error: 'An organization cannot be its own RPO client.' };

  const title = input.title.trim();
  if (title.length < 2 || title.length > 160) return { ok: false, error: 'The title needs 2 to 160 characters.' };
  const reference = input.reference.trim();
  if (reference.length > 60) return { ok: false, error: 'Keep the reference under 60 characters.' };
  const notes = input.notes.trim();
  if (notes.length > 2000) return { ok: false, error: 'Keep the notes under 2000 characters.' };

  const permissions = input.permissions.filter((p) => (RPO_PERMISSIONS as readonly string[]).includes(p));
  if (permissions.length === 0) return { ok: false, error: 'Choose at least one thing the provider may do.' };
  if (input.startDate && input.endDate && input.endDate < input.startDate)
    return { ok: false, error: 'The end date cannot be before the start date.' };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('omelo_create_rpo_engagement', {
    p: {
      provider_id: ctx.companyId,
      client_company_id: input.clientCompanyId,
      title,
      reference: reference || null,
      permissions,
      start_date: input.startDate || null,
      end_date: input.endDate || null,
      notes: notes || null,
    },
  });
  if (error) return fail(error, 'createEngagement');
  refresh();
  return {
    ok: true,
    id: idOf(data),
    message: 'Draft created. Set what it covers, then send it to the client to confirm.',
  };
}

/* ------------------------------------------------------------------ */
/* Scope, recruiters, status                                           */
/* ------------------------------------------------------------------ */

export async function setEngagementScope(
  engagementId: string,
  scopeType: string,
  scopeId: string | null,
  add: boolean
): Promise<RpoResult> {
  const ctx = await getCompanyContext();
  if (!ctx) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(engagementId)) return { ok: false, error: 'That engagement no longer exists.' };
  if (!(RPO_SCOPES as readonly string[]).includes(scopeType))
    return { ok: false, error: 'Choose what the engagement covers.' };
  if (scopeType !== 'organization' && !(scopeId && UUID_RE.test(scopeId)))
    return { ok: false, error: 'Choose which part of the organization it covers.' };

  const supabase = await createClient();
  const { error } = await supabase.rpc('omelo_set_rpo_scope', {
    p_engagement: engagementId,
    p_scope_type: scopeType,
    p_scope_id: scopeType === 'organization' ? undefined : (scopeId ?? undefined),
    p_add: add,
  });
  if (error) return fail(error, 'setEngagementScope');
  refresh(engagementId);
  return { ok: true, message: add ? 'Added to what this engagement covers.' : 'Removed.' };
}

export async function assignRecruiter(
  engagementId: string,
  personId: string,
  role: string,
  active: boolean
): Promise<RpoResult> {
  const ctx = await getCompanyContext();
  if (!ctx) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(engagementId)) return { ok: false, error: 'That engagement no longer exists.' };
  if (!UUID_RE.test(personId)) return { ok: false, error: 'Choose someone from your team.' };
  if (!(RPO_RECRUITER_ROLES as readonly string[]).includes(role))
    return { ok: false, error: 'Choose what they do on this engagement.' };

  const supabase = await createClient();
  const { error } = await supabase.rpc('omelo_assign_rpo_recruiter', {
    p_engagement: engagementId,
    p_person: personId,
    p_role: role,
    p_active: active,
  });
  if (error) return fail(error, 'assignRecruiter');
  refresh(engagementId);
  return { ok: true, message: active ? 'Assigned.' : 'Taken off this engagement.' };
}

export async function proposeEngagement(engagementId: string): Promise<RpoResult> {
  const ctx = await getCompanyContext();
  if (!ctx) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(engagementId)) return { ok: false, error: 'That engagement no longer exists.' };
  const supabase = await createClient();
  const { error } = await supabase.rpc('omelo_propose_rpo_engagement', { p_engagement: engagementId });
  if (error) return fail(error, 'proposeEngagement');
  refresh(engagementId);
  return { ok: true, message: 'Sent. The client’s owners and admins have been told.' };
}

export async function respondEngagement(
  engagementId: string,
  accept: boolean,
  note: string
): Promise<RpoResult> {
  const ctx = await getCompanyContext();
  if (!ctx) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(engagementId)) return { ok: false, error: 'That engagement no longer exists.' };
  const trimmed = note.trim();
  if (trimmed.length > 2000) return { ok: false, error: 'Keep the note under 2000 characters.' };
  const supabase = await createClient();
  const { error } = await supabase.rpc('omelo_respond_rpo_engagement', {
    p_engagement: engagementId,
    p_accept: accept,
    p_note: trimmed || undefined,
  });
  if (error) return fail(error, 'respondEngagement');
  refresh(engagementId);
  return {
    ok: true,
    message: accept
      ? 'Confirmed. Their assigned recruiters can now work on what this covers.'
      : 'Declined. Nothing of yours was shared.',
  };
}

export async function setEngagementStatus(
  engagementId: string,
  status: string,
  note: string
): Promise<RpoResult> {
  const ctx = await getCompanyContext();
  if (!ctx) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(engagementId)) return { ok: false, error: 'That engagement no longer exists.' };
  if (!['paused', 'active', 'completed', 'terminated'].includes(status))
    return { ok: false, error: 'That is not a status an engagement can have.' };
  const trimmed = note.trim();
  if (trimmed.length > 2000) return { ok: false, error: 'Keep the note under 2000 characters.' };

  const supabase = await createClient();
  const { error } = await supabase.rpc('omelo_set_rpo_status', {
    p_engagement: engagementId,
    p_status: status,
    p_note: trimmed || undefined,
  });
  if (error) return fail(error, 'setEngagementStatus');
  refresh(engagementId);
  const said: Record<string, string> = {
    paused: 'Paused. Their recruiters cannot reach anything until it is resumed.',
    active: 'Resumed.',
    completed: 'Marked as completed.',
    terminated: 'Ended. Their access stopped immediately.',
  };
  return { ok: true, message: said[status] };
}
