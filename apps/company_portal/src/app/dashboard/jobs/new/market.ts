'use server';

import { createClient } from '@/lib/supabase/server';
import { parseMarketInsights, type MarketInsights } from '@/lib/intelligence';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * "Market for this role" on the job form: open jobs, pay range and skills in
 * demand for the chosen profession (and country), from omelo_market_insights.
 * Returns null when there is nothing to show; the form then shows nothing.
 */
export async function marketForRole(input: {
  professionId: string;
  country?: string | null;
  currency?: string | null;
}): Promise<{ data: MarketInsights | null; error: string | null }> {
  if (!UUID_RE.test(input.professionId)) return { data: null, error: null };
  const country = input.country && /^[A-Z]{2}$/.test(input.country) ? input.country : undefined;
  const currency = input.currency && /^[A-Z]{3}$/.test(input.currency) ? input.currency : undefined;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('omelo_market_insights', {
    p_profession: input.professionId,
    ...(country ? { p_country: country } : {}),
    ...(currency ? { p_currency: currency } : {}),
  });
  if (error) return { data: null, error: error.message };
  return { data: parseMarketInsights(data), error: null };
}
