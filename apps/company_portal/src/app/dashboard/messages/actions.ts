'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { isUuid } from '@/lib/messaging';
import type { ActionState } from '../actions';

/*
 * Conversations are created only by omelo_start_conversation (get-or-create,
 * one per application, hiring roles only). The single column an employer may
 * change directly is company_archived; a trigger rejects anything else.
 * Errors from the database are human-readable and returned as-is.
 */

export async function startConversation(_prev: ActionState, fd: FormData): Promise<ActionState> {
  const applicationId = String(fd.get('application_id') ?? '');
  if (!isUuid(applicationId)) return { error: 'Missing application.' };
  if (!(await getCompanyContext())) return { error: 'You are signed out or not part of a company.' };

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('omelo_start_conversation', {
    p_application_id: applicationId,
  });
  if (error) return { error: error.message };
  if (!data) return { error: 'The conversation could not be opened. Try again.' };

  revalidatePath('/dashboard/messages');
  redirect(`/dashboard/messages/${data}`);
}

export async function setConversationArchived(_prev: ActionState, fd: FormData): Promise<ActionState> {
  const id = String(fd.get('conversation_id') ?? '');
  if (!isUuid(id)) return { error: 'Missing conversation.' };
  const archived = fd.get('archived') === 'true';

  const ctx = await getCompanyContext();
  if (!ctx) return { error: 'You are signed out or not part of a company.' };

  const supabase = await createClient();
  const { data, error } = await supabase
    .from('conversations')
    .update({ company_archived: archived })
    .eq('id', id)
    .eq('company_id', ctx.companyId)
    .select('id');
  if (error) return { error: error.message };
  if (!data?.length) return { error: 'You do not have permission to change this conversation.' };

  revalidatePath('/dashboard/messages');
  revalidatePath(`/dashboard/messages/${id}`);
  return { ok: true, message: archived ? 'Archived.' : 'Moved back to the inbox.' };
}
