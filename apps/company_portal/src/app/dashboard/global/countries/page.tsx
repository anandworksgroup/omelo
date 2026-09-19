import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { regionLabel } from '@/lib/global';
import { loadGlobalOptions } from '@/lib/global-data';
import CurrencyConverter from '../converter';
import NotLegalAdvice from './disclaimer';

export const metadata: Metadata = { title: 'Country guides · Omelo' };

type Country = {
  country_code: string;
  name: string;
  default_currency: string;
  world_region: string | null;
  supported: boolean;
};

export default async function CountriesPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const [{ data, error }, infoRes, global] = await Promise.all([
    supabase
      .from('country_policies')
      .select('country_code, name, default_currency, world_region, supported')
      .order('name'),
    supabase.from('country_employment_info').select('country_code'),
    loadGlobalOptions(supabase, ctx.companyId),
  ]);
  const withInfo = new Set((infoRes.data ?? []).map((r) => r.country_code.trim()));
  const byRegion = new Map<string, Country[]>();
  for (const c of (data ?? []) as Country[]) {
    const r = regionLabel(c.world_region);
    byRegion.set(r, [...(byRegion.get(r) ?? []), c]);
  }
  const regions = [...byRegion.keys()].sort();

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl sm:text-2xl font-bold">Hiring across countries</h1>
        <p className="text-sm muted mt-1 max-w-2xl leading-relaxed">
          Country guides with links to the official sources on work permits, licences and hiring, plus an indicative
          currency converter.
        </p>
      </div>

      <NotLegalAdvice />

      <CurrencyConverter
        currencies={global.currencies}
        defaultFrom={global.defaultCurrency}
        defaultTo={global.defaultCurrency === 'EUR' ? 'USD' : 'EUR'}
      />

      {error ? (
        <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
          Could not load countries: <span className="muted">{error.message}</span>
        </p>
      ) : (
        regions.map((r) => (
          <section key={r} className="space-y-2">
            <h2 className="font-bold">{r}</h2>
            <ul className="grid gap-3 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3">
              {byRegion.get(r)!.map((c) => {
                const code = c.country_code.trim();
                return (
                  <li key={code} className="min-w-0">
                    <Link
                      href={`/dashboard/global/countries/${code}`}
                      className="card p-3 flex items-center gap-3 hover:underline min-w-0"
                    >
                      <span className="pill shrink-0">{code}</span>
                      <span className="flex-1 min-w-0 truncate font-medium">{c.name}</span>
                      <span className="text-xs muted shrink-0">{c.default_currency}</span>
                    </Link>
                    <p className="text-xs muted mt-1 px-1">
                      {withInfo.has(code) ? 'Official sources linked' : 'Basics only so far'}
                      {c.supported ? ' · Omelo available' : ''}
                    </p>
                  </li>
                );
              })}
            </ul>
          </section>
        ))
      )}
    </div>
  );
}
