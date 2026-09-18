import type { createClient } from '@/lib/supabase/server';
import { loadSubmissions } from '../submissions/lib';

type Supabase = Awaited<ReturnType<typeof createClient>>;

export type PlacementItem = {
  id: string;
  submissionId: string;
  jobOrderId: string;
  title: string | null;
  status: string;
  startDate: string | null;
  guaranteeEndsOn: string | null;
  feeAmount: number | null;
  feeCurrency: string | null;
  notes: string | null;
  createdAt: string;
  candidate: string;
  candidateLabel: string | null;
  position: string | null;
  jobOrder: string | null;
  client: string | null;
  onOmelo: boolean;
};

/** Placements (RLS: agency members) joined in JS with the submission list. */
export async function loadPlacements(
  supabase: Supabase,
  agencyId: string
): Promise<{ items: PlacementItem[]; error: string | null }> {
  const [pl, subs] = await Promise.all([
    supabase
      .from('placements')
      .select(
        'id, submission_id, job_order_id, title, status, start_date, guarantee_ends_on, fee_amount, fee_currency, notes, created_at'
      )
      .eq('agency_id', agencyId)
      .order('created_at', { ascending: false }),
    loadSubmissions(supabase, agencyId),
  ]);
  if (pl.error) return { items: [], error: pl.error.message };
  const bySub = new Map(subs.rows.map((r) => [r.id, r]));
  return {
    error: subs.error,
    items: (pl.data ?? []).map((p) => {
      const s = bySub.get(p.submission_id);
      return {
        id: p.id,
        submissionId: p.submission_id,
        jobOrderId: p.job_order_id,
        title: p.title,
        status: p.status,
        startDate: p.start_date,
        guaranteeEndsOn: p.guarantee_ends_on,
        feeAmount: p.fee_amount == null ? null : Number(p.fee_amount),
        feeCurrency: p.fee_currency,
        notes: p.notes,
        createdAt: p.created_at,
        candidate: s?.candidate.name ?? 'Candidate',
        candidateLabel: s?.candidate.label ?? null,
        position: s?.position ?? p.title,
        jobOrder: s?.jobOrder ?? null,
        client: s?.client ?? null,
        onOmelo: s?.onOmelo ?? false,
      };
    }),
  };
}
