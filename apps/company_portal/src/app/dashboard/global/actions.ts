'use server';

import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { reportError } from '@/lib/observability';
import { CURRENCY_RE, parseConversion, type Conversion } from '@/lib/global';

export type ConvertResult = { ok: true; data: Conversion } | { ok: false; error: string };

/** Indicative conversion through omelo_convert_currency (rate, time and source travel with it). */
export async function convertCurrency(amount: number, from: string, to: string): Promise<ConvertResult> {
  const ctx = await getCompanyContext();
  if (!ctx) return { ok: false, error: 'You are signed out or not part of a company.' };
  const f = from.trim().toUpperCase();
  const t = to.trim().toUpperCase();
  if (!CURRENCY_RE.test(f) || !CURRENCY_RE.test(t)) return { ok: false, error: 'Choose both currencies.' };
  if (!Number.isFinite(amount) || amount < 0 || amount > 1e12) return { ok: false, error: 'Enter an amount.' };
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('omelo_convert_currency', { p_amount: amount, p_from: f, p_to: t });
  if (error) {
    if (error.code !== '22023') reportError(error, { action: 'convertCurrency' });
    return { ok: false, error: error.message };
  }
  const parsed = parseConversion(data);
  return parsed ? { ok: true, data: parsed } : { ok: false, error: 'No result.' };
}
