'use server';

import { revalidatePath } from 'next/cache';
import { createClient, getCompanyContext } from '@/lib/supabase/server';

export type RoundInput = {
  id?: string;
  name: string;
  kind: string;
  meeting_mode: string;
  duration_minutes: number;
};

const KINDS = ['screening', 'technical', 'practical', 'hiring_manager', 'culture', 'final', 'general'];
const MODES = ['omelo_meet', 'phone', 'in_person'];
const MAX_ROUNDS = 10;

/**
 * Saves a job's planned interview process (job_interview_rounds).
 *
 * The hiring team writes the table directly under RLS. Positions are unique
 * per job and limited to 1..20, so a reorder first parks existing rows on
 * 11..20 and then writes the final 1..10 — never colliding mid-way.
 */
export async function saveInterviewRounds(
  jobId: string,
  rounds: RoundInput[]
): Promise<{ error?: string; ok?: boolean }> {
  const ctx = await getCompanyContext();
  if (!ctx) return { error: 'You are signed out or not part of a company.' };
  if (rounds.length > MAX_ROUNDS) return { error: `At most ${MAX_ROUNDS} rounds.` };

  for (const [i, r] of rounds.entries()) {
    const name = r.name.trim();
    if (name.length < 2 || name.length > 80) return { error: `Round ${i + 1}: give it a name (2–80 characters).` };
    if (!KINDS.includes(r.kind)) return { error: `Round ${i + 1}: choose a kind.` };
    if (!MODES.includes(r.meeting_mode)) return { error: `Round ${i + 1}: choose a format.` };
    if (!(r.duration_minutes >= 5 && r.duration_minutes <= 480))
      return { error: `Round ${i + 1}: duration must be 5–480 minutes.` };
  }

  const supabase = await createClient();
  const { data: existing, error: readError } = await supabase
    .from('job_interview_rounds')
    .select('id')
    .eq('job_id', jobId);
  if (readError) return { error: readError.message };

  const keep = new Set(rounds.map((r) => r.id).filter(Boolean) as string[]);
  const remove = (existing ?? []).map((r) => r.id).filter((id) => !keep.has(id));
  if (remove.length) {
    const { error } = await supabase.from('job_interview_rounds').delete().in('id', remove);
    if (error) return { error: error.message };
  }

  // Park kept rows out of the way.
  const kept = rounds.filter((r) => r.id && (existing ?? []).some((e) => e.id === r.id));
  for (const [i, r] of kept.entries()) {
    const { error } = await supabase
      .from('job_interview_rounds')
      .update({ position: 11 + i })
      .eq('id', r.id!);
    if (error) return { error: error.message };
  }

  for (const [i, r] of rounds.entries()) {
    const row = {
      position: i + 1,
      name: r.name.trim(),
      kind: r.kind,
      meeting_mode: r.meeting_mode,
      duration_minutes: Math.round(r.duration_minutes),
    };
    const isKept = r.id && kept.some((k) => k.id === r.id);
    const { error } = isKept
      ? await supabase.from('job_interview_rounds').update(row).eq('id', r.id!)
      : await supabase.from('job_interview_rounds').insert({ ...row, job_id: jobId });
    if (error) return { error: error.message };
  }

  revalidatePath(`/dashboard/jobs/${jobId}`);
  revalidatePath('/dashboard/candidates', 'layout');
  return { ok: true };
}
