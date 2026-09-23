'use server';

import { revalidatePath } from 'next/cache';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { reportError } from '@/lib/observability';
import { UUID_RE } from '@/lib/talent';
import { APPROVAL_ENTITIES, GRANT_SCOPES, enterpriseError } from '@/lib/enterprise';

/*
 * Release 8 — approvals.
 *
 * Every write goes through a SECURITY DEFINER function that enforces the rules
 * (only a role whose scope covers the entity may decide a step, nobody approves
 * their own request, one open request per entity). These actions shape the
 * input and pass the database's own sentence back to the person.
 */

export type ApprovalResult = { ok: true; message?: string } | { ok: false; error: string };

const EXPECTED = new Set(['42501', '22023', '23505', '23503', '23514']);

function fail(e: { code?: string; message: string }, action: string): ApprovalResult {
  if (!EXPECTED.has(e.code ?? '')) reportError(e, { action });
  return { ok: false, error: enterpriseError(e).text };
}

function refreshApprovalPaths(entityType?: string, entityId?: string) {
  revalidatePath('/dashboard/approvals');
  if (entityType === 'job' && entityId) revalidatePath(`/dashboard/jobs/${entityId}`);
  if (entityType === 'workforce_requirement' && entityId)
    revalidatePath(`/dashboard/workforce/requirements/${entityId}`);
  if (entityType === 'offer') revalidatePath('/dashboard/offers');
}

const SIGNED_OUT = 'You are signed out or not part of a company.';

/* ------------------------------------------------------------------ */
/* Deciding                                                            */
/* ------------------------------------------------------------------ */

export async function decideApproval(requestId: string, approve: boolean, note: string): Promise<ApprovalResult> {
  const ctx = await getCompanyContext();
  if (!ctx) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(requestId)) return { ok: false, error: 'That request no longer exists.' };
  const trimmed = note.trim();
  if (trimmed.length > 1000) return { ok: false, error: 'Keep the note under 1000 characters.' };
  if (!approve && !trimmed)
    return { ok: false, error: 'Say why you are declining, so the person who asked knows what to change.' };

  const supabase = await createClient();
  const { error } = await supabase.rpc('omelo_decide_approval', {
    p_request: requestId,
    p_approve: approve,
    p_note: trimmed || undefined,
  });
  if (error) return fail(error, 'decideApproval');
  refreshApprovalPaths();
  return { ok: true, message: approve ? 'Approved.' : 'Sent back as not approved.' };
}

export async function submitForApproval(
  entityType: string,
  entityId: string,
  note: string
): Promise<ApprovalResult> {
  const ctx = await getCompanyContext();
  if (!ctx) return { ok: false, error: SIGNED_OUT };
  if (!(APPROVAL_ENTITIES as readonly string[]).includes(entityType))
    return { ok: false, error: 'That is not something Omelo approves.' };
  if (!UUID_RE.test(entityId)) return { ok: false, error: 'That no longer exists.' };
  const trimmed = note.trim();
  if (trimmed.length > 1000) return { ok: false, error: 'Keep the note under 1000 characters.' };

  const supabase = await createClient();
  const { error } = await supabase.rpc('omelo_submit_for_approval', {
    p_entity_type: entityType,
    p_entity_id: entityId,
    p_note: trimmed || undefined,
  });
  if (error) return fail(error, 'submitForApproval');
  refreshApprovalPaths(entityType, entityId);
  return { ok: true, message: 'Sent for approval. The first approver has been told.' };
}

export async function cancelApproval(
  requestId: string,
  note: string,
  entityType?: string,
  entityId?: string
): Promise<ApprovalResult> {
  const ctx = await getCompanyContext();
  if (!ctx) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(requestId)) return { ok: false, error: 'That request no longer exists.' };
  const trimmed = note.trim();
  if (trimmed.length > 1000) return { ok: false, error: 'Keep the note under 1000 characters.' };

  const supabase = await createClient();
  const { error } = await supabase.rpc('omelo_cancel_approval', {
    p_request: requestId,
    p_note: trimmed || undefined,
  });
  if (error) return fail(error, 'cancelApproval');
  refreshApprovalPaths(entityType, entityId);
  return { ok: true, message: 'Withdrawn.' };
}

/* ------------------------------------------------------------------ */
/* The chain itself                                                    */
/* ------------------------------------------------------------------ */

export type WorkflowStepInput = {
  name: string;
  approverRole: string;
  approverScope: string;
  requiredApprovals: number;
};

export type WorkflowInput = {
  id?: string | null;
  entityType: string;
  name: string;
  isActive: boolean;
  steps: WorkflowStepInput[];
};

export async function saveWorkflow(input: WorkflowInput): Promise<ApprovalResult> {
  const ctx = await getCompanyContext();
  if (!ctx) return { ok: false, error: SIGNED_OUT };
  if (!ctx.roles.some((r) => r === 'owner' || r === 'admin'))
    return { ok: false, error: 'Only an owner or admin sets approval workflows.' };
  if (!(APPROVAL_ENTITIES as readonly string[]).includes(input.entityType))
    return { ok: false, error: 'That is not something Omelo approves.' };
  if (input.id && !UUID_RE.test(input.id)) return { ok: false, error: 'That workflow no longer exists.' };

  const name = input.name.trim();
  if (name.length < 2 || name.length > 120) return { ok: false, error: 'The workflow name needs 2 to 120 characters.' };
  if (input.steps.length === 0) return { ok: false, error: 'An approval workflow needs at least one step.' };
  if (input.steps.length > 20) return { ok: false, error: 'Keep the chain to 20 steps or fewer.' };

  const steps = input.steps.map((s, i) => {
    const stepName = s.name.trim() || `Step ${i + 1}`;
    return {
      name: stepName.slice(0, 80),
      approver_role: s.approverRole,
      approver_scope: s.approverScope,
      required_approvals: Math.min(5, Math.max(1, Math.round(s.requiredApprovals || 1))),
    };
  });
  for (const s of steps) {
    if (!s.approver_role) return { ok: false, error: 'Every step needs a role that approves it.' };
    if (!(GRANT_SCOPES as readonly string[]).includes(s.approver_scope))
      return { ok: false, error: 'Every step needs a scope the approver acts in.' };
    if (s.name.trim().length < 2) return { ok: false, error: 'Every step name needs at least 2 characters.' };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc('omelo_save_approval_workflow', {
    p: {
      company_id: ctx.companyId,
      id: input.id || undefined,
      entity_type: input.entityType,
      name,
      is_active: input.isActive,
      steps,
    },
  });
  if (error) {
    if (error.code === '23505')
      return {
        ok: false,
        error: 'Another chain is already the active one for that. Turn that one off first, or rename this one.',
      };
    return fail(error, 'saveWorkflow');
  }
  revalidatePath('/dashboard/approvals');
  revalidatePath('/dashboard/jobs');
  return { ok: true, message: input.isActive ? 'Saved and switched on.' : 'Saved. It is switched off.' };
}
