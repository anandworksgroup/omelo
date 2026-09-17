'use server';

import { revalidatePath } from 'next/cache';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import type { ActionState } from '../actions';
import type {
  ApplicationState,
  InterviewStatus,
  InterviewType,
  PayPeriod,
} from '@/lib/hiring';

/*
 * Every hiring-loop mutation goes through a SECURITY DEFINER RPC. Direct
 * table updates are blocked by triggers, so there is deliberately no
 * `.from('applications').update(...)` anywhere in the portal.
 *
 * Errors are returned verbatim: the RPCs raise human-readable messages
 * ("An offer is already open; withdraw it first") meant for the employer.
 */

const str = (fd: FormData, key: string) => String(fd.get(key) ?? '').trim();

function refresh() {
  // Pipeline counts, the review page, interviews, offers and the overview
  // all read the same rows.
  revalidatePath('/dashboard', 'layout');
}

async function client() {
  const ctx = await getCompanyContext();
  if (!ctx) return { error: 'You are signed out or not part of a company.' } as const;
  return { ctx, supabase: await createClient() } as const;
}

/* ------------------------------------------------------------------ */
/* Scoring                                                             */
/* ------------------------------------------------------------------ */

export async function rankApplicants(_prev: ActionState, fd: FormData): Promise<ActionState> {
  const c = await client();
  if ('error' in c) return { error: c.error };
  const jobId = str(fd, 'job_id');
  if (!jobId) return { error: 'Missing job.' };

  const { data, error } = await c.supabase.rpc('omelo_rank_applicants', { p_job_id: jobId });
  if (error) return { error: error.message };
  refresh();
  return { ok: true, message: `Re-scored ${data?.length ?? 0} applicant${data?.length === 1 ? '' : 's'}.` };
}

/* ------------------------------------------------------------------ */
/* Pipeline moves                                                      */
/* ------------------------------------------------------------------ */

const MOVABLE: ApplicationState[] = ['viewed', 'shortlisted', 'screening', 'assessment', 'interview'];

export async function moveApplication(_prev: ActionState, fd: FormData): Promise<ActionState> {
  const c = await client();
  if ('error' in c) return { error: c.error };
  const state = str(fd, 'state') as ApplicationState;
  if (!MOVABLE.includes(state)) return { error: 'That move is not available here.' };

  const { error } = await c.supabase.rpc('omelo_move_application', {
    p_application_id: str(fd, 'application_id'),
    p_state: state,
  });
  if (error) return { error: error.message };
  refresh();
  return { ok: true };
}

export async function rejectApplication(_prev: ActionState, fd: FormData): Promise<ActionState> {
  const c = await client();
  if ('error' in c) return { error: c.error };

  const preset = str(fd, 'reason_preset');
  const reason = preset === 'other' ? str(fd, 'reason_other') : preset;
  if (reason.length < 3)
    return { error: 'Choose a reason, or write one (at least 3 characters). The candidate will see it.' };

  const { error } = await c.supabase.rpc('omelo_reject_application', {
    p_application_id: str(fd, 'application_id'),
    p_reason: reason,
  });
  if (error) return { error: error.message };
  refresh();
  return { ok: true };
}

/* ------------------------------------------------------------------ */
/* Interviews                                                          */
/* ------------------------------------------------------------------ */

export async function scheduleInterview(_prev: ActionState, fd: FormData): Promise<ActionState> {
  const c = await client();
  if ('error' in c) return { error: c.error };

  // The client converts the datetime-local value to an absolute instant, so
  // the server's own timezone never leaks into the scheduled time.
  const at = str(fd, 'scheduled_at_iso');
  if (!at || Number.isNaN(Date.parse(at))) return { error: 'Choose a date and time.' };

  const { error } = await c.supabase.rpc('omelo_schedule_interview', {
    p_application_id: str(fd, 'application_id'),
    p_type: (str(fd, 'type') || 'in_person') as InterviewType,
    p_scheduled_at: at,
    p_duration_minutes: Number(str(fd, 'duration_minutes')) || 30,
    p_timezone: str(fd, 'timezone') || undefined,
    p_meeting_url: str(fd, 'meeting_url') || undefined,
    p_location_text: str(fd, 'location_text') || undefined,
    p_instructions: str(fd, 'instructions') || undefined,
  });
  if (error) return { error: error.message };
  refresh();
  return { ok: true, message: 'Interview scheduled. The candidate has been asked to confirm.' };
}

export async function rescheduleInterview(_prev: ActionState, fd: FormData): Promise<ActionState> {
  const c = await client();
  if ('error' in c) return { error: c.error };
  const at = str(fd, 'scheduled_at_iso');
  if (!at || Number.isNaN(Date.parse(at))) return { error: 'Choose a new date and time.' };

  const { error } = await c.supabase.rpc('omelo_reschedule_interview', {
    p_interview_id: str(fd, 'interview_id'),
    p_scheduled_at: at,
    p_reason: str(fd, 'reason') || undefined,
  });
  if (error) return { error: error.message };
  refresh();
  return { ok: true, message: 'Rescheduled. The candidate has been asked to confirm the new time.' };
}

export async function cancelInterview(_prev: ActionState, fd: FormData): Promise<ActionState> {
  const c = await client();
  if ('error' in c) return { error: c.error };
  const reason = str(fd, 'reason');
  if (reason.length < 3) return { error: 'Give a short reason. The candidate will see it.' };

  const { error } = await c.supabase.rpc('omelo_cancel_interview', {
    p_interview_id: str(fd, 'interview_id'),
    p_reason: reason,
  });
  if (error) return { error: error.message };
  refresh();
  return { ok: true };
}

const OUTCOMES: InterviewStatus[] = ['completed', 'no_show_candidate', 'no_show_employer'];

export async function completeInterview(_prev: ActionState, fd: FormData): Promise<ActionState> {
  const c = await client();
  if ('error' in c) return { error: c.error };
  const outcome = (str(fd, 'outcome') || 'completed') as InterviewStatus;
  if (!OUTCOMES.includes(outcome)) return { error: 'Choose an outcome.' };
  const rating = Number(str(fd, 'rating'));

  const { error } = await c.supabase.rpc('omelo_complete_interview', {
    p_interview_id: str(fd, 'interview_id'),
    p_outcome: outcome,
    p_rating: rating >= 1 && rating <= 5 ? rating : undefined,
    p_recommendation: str(fd, 'recommendation') || undefined,
    p_notes: str(fd, 'notes') || undefined,
  });
  if (error) return { error: error.message };
  refresh();
  return { ok: true };
}

/* ------------------------------------------------------------------ */
/* Offers                                                              */
/* ------------------------------------------------------------------ */

export async function sendOffer(_prev: ActionState, fd: FormData): Promise<ActionState> {
  const c = await client();
  if ('error' in c) return { error: c.error };

  const pay = Number(str(fd, 'pay_amount'));
  if (!pay || pay <= 0) return { error: 'Enter the pay for this offer.' };
  const start = str(fd, 'start_date');
  if (!start) return { error: 'Choose a start date.' };

  const days = Number(str(fd, 'expires_days'));
  const expires =
    days > 0 ? new Date(Date.now() + days * 86_400_000).toISOString() : undefined;

  const { error } = await c.supabase.rpc('omelo_send_offer', {
    p_application_id: str(fd, 'application_id'),
    p_pay_amount: pay,
    p_pay_period: (str(fd, 'pay_period') || 'month') as PayPeriod,
    p_start_date: start,
    p_title: str(fd, 'title') || undefined,
    p_expires_at: expires,
    p_conditions: str(fd, 'conditions') || undefined,
    // Omitted: the RPC copies the job's benefits onto the offer.
  });
  if (error) return { error: error.message };
  refresh();
  return { ok: true, message: 'Offer sent.' };
}

export async function withdrawOffer(_prev: ActionState, fd: FormData): Promise<ActionState> {
  const c = await client();
  if ('error' in c) return { error: c.error };
  const reason = str(fd, 'reason');
  if (reason.length < 3) return { error: 'Give a short reason. The candidate will see it.' };

  const { error } = await c.supabase.rpc('omelo_withdraw_offer', {
    p_offer_id: str(fd, 'offer_id'),
    p_reason: reason,
  });
  if (error) return { error: error.message };
  refresh();
  return { ok: true };
}

/* ------------------------------------------------------------------ */
/* Private notes                                                       */
/* ------------------------------------------------------------------ */

export async function addNote(_prev: ActionState, fd: FormData): Promise<ActionState> {
  const c = await client();
  if ('error' in c) return { error: c.error };
  const body = str(fd, 'body');
  if (!body) return { error: 'Write something first.' };

  // author_id is stamped server-side by the database.
  const { error } = await c.supabase.from('application_notes').insert({
    application_id: str(fd, 'application_id'),
    company_id: c.ctx.companyId,
    body,
  });
  if (error) return { error: error.message };
  refresh();
  return { ok: true };
}
