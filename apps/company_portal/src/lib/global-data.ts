import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/lib/supabase/database.types';
import type { CountryOption } from '@/lib/global';
import type { EntityOption } from '@/components/global/global-hiring-fields';

/**
 * Reference lists the global-hiring UI needs: every country Omelo knows, the
 * company's legal entities (members can read them), active currencies and
 * the company's home currency (the pay default — never assumed to be INR).
 */
export async function loadGlobalOptions(supabase: SupabaseClient<Database>, companyId: string) {
  const [countriesRes, entitiesRes, currenciesRes, companyRes] = await Promise.all([
    supabase.from('country_policies').select('country_code, name, default_currency, default_timezone').order('name'),
    supabase
      .from('company_legal_entities')
      .select('id, legal_name, country_code, currency, is_default')
      .eq('company_id', companyId)
      .order('country_code')
      .order('legal_name'),
    supabase.from('currencies').select('code, name').eq('active', true).order('code'),
    supabase.from('companies').select('country_code').eq('id', companyId).maybeSingle(),
  ]);

  const countries: CountryOption[] = (countriesRes.data ?? []).map((c) => ({
    code: c.country_code.trim(),
    name: c.name,
    currency: c.default_currency?.trim() ?? null,
    timezone: c.default_timezone,
  }));
  const entities: EntityOption[] = (entitiesRes.data ?? []).map((e) => ({
    id: e.id,
    legal_name: e.legal_name,
    country_code: e.country_code.trim(),
    currency: e.currency.trim(),
    is_default: e.is_default,
  }));
  const currencies = (currenciesRes.data ?? []).map((c) => ({ code: c.code.trim(), name: c.name }));
  const home = companyRes.data?.country_code?.trim() ?? null;
  const homeEntity = entities.find((e) => e.country_code === home && e.is_default);
  const defaultCurrency =
    homeEntity?.currency ?? countries.find((c) => c.code === home)?.currency ?? currencies[0]?.code ?? 'USD';

  return {
    countries,
    entities,
    currencies,
    homeCountry: home,
    defaultCurrency,
    error: countriesRes.error?.message ?? entitiesRes.error?.message ?? currenciesRes.error?.message ?? null,
  };
}
