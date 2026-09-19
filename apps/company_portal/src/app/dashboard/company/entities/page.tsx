import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { countryName } from '@/lib/global';
import { loadGlobalOptions } from '@/lib/global-data';
import { timeZones } from '../../workforce/requirements/form-data';
import { DeleteEntity, EntityForm, type Entity } from './entity-forms';

export const metadata: Metadata = { title: 'Legal entities · Omelo' };

/**
 * The legal entities a company hires through, one or more per country.
 * Owners and admins edit them (RLS enforces this); everyone else reads.
 */
export default async function EntitiesPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const [{ data, error }, global] = await Promise.all([
    supabase
      .from('company_legal_entities')
      .select('id, country_code, legal_name, registration_number, currency, timezone, hiring_notes, is_default')
      .eq('company_id', ctx.companyId)
      .order('country_code')
      .order('legal_name'),
    loadGlobalOptions(supabase, ctx.companyId),
  ]);
  const canEdit = ctx.roles.some((r) => r === 'owner' || r === 'admin');
  const entities: Entity[] = (data ?? []).map((e) => ({
    ...e,
    country_code: e.country_code.trim(),
    currency: e.currency.trim(),
  }));
  const options = { countries: global.countries, currencies: global.currencies, timeZones: timeZones() };
  const nameOf = (code: string) => global.countries.find((c) => c.code === code)?.name ?? countryName(code) ?? code;

  return (
    <div className="space-y-6 max-w-3xl">
      <div>
        <Link href="/dashboard/company" className="text-sm underline muted">
          ← Company
        </Link>
        <h1 className="text-xl sm:text-2xl font-bold mt-3">Legal entities</h1>
        <p className="muted text-sm mt-1 leading-relaxed">
          The registered companies you hire through in each country. A job can name the entity that employs the
          person; its country, currency and time zone become the job&apos;s defaults.
        </p>
      </div>

      {!canEdit && (
        <p className="text-sm muted">Only owners and admins can add or change legal entities. You can view them.</p>
      )}

      {canEdit && (
        <div className="card p-5">
          <EntityForm options={options} label="Add a legal entity" />
        </div>
      )}

      {error ? (
        <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
          Could not load legal entities: <span className="muted">{error.message}</span>
        </p>
      ) : entities.length === 0 ? (
        <div className="card p-8 text-center text-sm muted">
          No legal entities yet. Jobs still work without one; add entities when you hire in more than one country.
        </div>
      ) : (
        <ul className="space-y-3">
          {entities.map((e) => (
            <li key={e.id} className="card p-5 space-y-3 min-w-0">
              <div className="flex items-start gap-3 flex-wrap">
                <div className="flex-1 min-w-0">
                  <p className="font-bold break-words">{e.legal_name}</p>
                  <p className="text-sm muted break-words">
                    {nameOf(e.country_code)} · {e.currency} · {e.timezone.replace(/_/g, ' ')}
                    {e.registration_number ? ` · Reg. ${e.registration_number}` : ''}
                  </p>
                </div>
                {e.is_default && <span className="pill">Default for {e.country_code}</span>}
              </div>
              {e.hiring_notes && <p className="text-sm whitespace-pre-line break-words">{e.hiring_notes}</p>}
              {canEdit && (
                <div className="flex flex-wrap gap-2 items-start border-t hairline pt-3">
                  <EntityForm entity={e} options={options} label="Edit" />
                  <DeleteEntity id={e.id} name={e.legal_name} />
                </div>
              )}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
