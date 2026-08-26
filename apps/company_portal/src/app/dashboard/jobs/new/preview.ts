'use server';

import { createClient } from '@/lib/supabase/server';
import { payMonthly } from '@/lib/format';

export type PoolPreview = {
  workers: number;
  discoverableWorkers: number;
  similarJobs: number;
  payLow: number | null;
  payHigh: number | null;
  payPeriod: string | null;
  currency: string;
  note: string | null;
};

/**
 * Live feedback while requirements are being edited (A2 §5.2 / EC-4).
 *
 * Two signals:
 *  - how many workers currently match, so a requirement's cost is visible
 *  - what comparable live jobs pay, so the range is anchored in real data
 *
 * Both are computed from actual rows. When there is not enough data we say
 * so rather than inventing a number — pay is the field employers would
 * catch us being wrong about fastest.
 */
export async function previewPool(input: {
  professionId?: string;
  locationId?: string;
  minExperienceMonths?: number | null;
  acceptsNoExperience?: boolean;
}): Promise<PoolPreview> {
  const supabase = await createClient();
  const empty: PoolPreview = {
    workers: 0,
    discoverableWorkers: 0,
    similarJobs: 0,
    payLow: null,
    payHigh: null,
    payPeriod: null,
    currency: 'INR',
    note: null,
  };

  if (!input.professionId) return empty;

  // Workers who list this profession on any active work identity.
  let workerQuery = supabase
    .from('person_professions')
    .select('work_identity_id, work_identities!inner(status, discoverability)', {
      count: 'exact',
      head: false,
    })
    .eq('profession_id', input.professionId)
    .eq('work_identities.status', 'active');

  if (!input.acceptsNoExperience && input.minExperienceMonths) {
    workerQuery = workerQuery.gte('months_experience', input.minExperienceMonths);
  }

  const { data: workerRows } = await workerQuery;
  const workers = workerRows?.length ?? 0;
  const discoverable = (workerRows ?? []).filter((r) => {
    const wi = r.work_identities as unknown as { discoverability: string };
    return wi?.discoverability !== 'private';
  }).length;

  // Comparable live postings for the same profession.
  const { data: similar } = await supabase
    .from('jobs')
    .select('pay_min, pay_max, pay_period, pay_currency')
    .eq('profession_id', input.professionId)
    .eq('status', 'published')
    .not('pay_min', 'is', null);

  const monthly = (similar ?? [])
    .map((j) => payMonthly(Number(j.pay_min), j.pay_period))
    .filter((n): n is number => n != null)
    .sort((a, b) => a - b);

  const MIN_SAMPLE = 3;
  let payLow: number | null = null;
  let payHigh: number | null = null;
  let note: string | null = null;

  if (monthly.length >= MIN_SAMPLE) {
    payLow = Math.round(monthly[Math.floor(monthly.length * 0.25)] / 500) * 500;
    payHigh = Math.round(monthly[Math.floor(monthly.length * 0.75)] / 500) * 500;
  } else if (monthly.length > 0) {
    note = `Only ${monthly.length} comparable job${monthly.length === 1 ? '' : 's'} on Omelo — too few to show a reliable range.`;
  }

  return {
    workers,
    discoverableWorkers: discoverable,
    similarJobs: similar?.length ?? 0,
    payLow,
    payHigh,
    payPeriod: 'month',
    currency: similar?.[0]?.pay_currency?.trim() ?? 'INR',
    note,
  };
}
