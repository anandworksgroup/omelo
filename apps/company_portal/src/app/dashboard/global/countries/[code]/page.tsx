import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { COUNTRY_RE, TOPIC_LABEL, parseCountryGuide, regionLabel } from '@/lib/global';
import { loadGlobalOptions } from '@/lib/global-data';
import { UUID_RE } from '@/lib/talent';
import CurrencyConverter from '../../converter';
import NotLegalAdvice from '../disclaimer';

export const metadata: Metadata = { title: 'Country guide · Omelo' };

const dateText = (d: string | null) =>
  d
    ? new Date(d.slice(0, 10) + 'T00:00:00Z').toLocaleDateString('en-GB', {
        day: 'numeric',
        month: 'short',
        year: 'numeric',
        timeZone: 'UTC',
      })
    : null;

/** Official link: opens in a new tab, without giving the target a window.opener. */
function Source({ url, source, reviewedAt }: { url: string | null; source: string | null; reviewedAt: string | null }) {
  return (
    <p className="text-xs muted break-words">
      {url ? (
        <a
          href={url}
          target="_blank"
          rel="noopener noreferrer"
          className="underline"
          style={{ color: 'var(--color-brand-600)' }}
        >
          {source ?? url} ↗
        </a>
      ) : (
        source
      )}
      {reviewedAt ? ` · reviewed ${dateText(reviewedAt)}` : ''}
    </p>
  );
}

export default async function CountryGuidePage({
  params,
  searchParams,
}: {
  params: Promise<{ code: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { code: raw } = await params;
  const code = raw.toUpperCase();
  if (!COUNTRY_RE.test(code)) notFound();
  const sp = await searchParams;
  const profession = typeof sp.profession === 'string' && UUID_RE.test(sp.profession) ? sp.profession : null;

  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const [guideRes, profRes, global] = await Promise.all([
    supabase.rpc('omelo_country_guide', { p_country: code, p_profession: profession ?? undefined }),
    supabase.from('professions').select('id, name').eq('status', 'active').order('name'),
    loadGlobalOptions(supabase, ctx.companyId),
  ]);
  const back = (
    <Link href="/dashboard/global/countries" className="text-sm underline muted">
      ← All countries
    </Link>
  );
  if (guideRes.error)
    return (
      <div className="space-y-4 max-w-3xl">
        {back}
        <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
          Could not load the guide: <span className="muted">{guideRes.error.message}</span>
        </p>
      </div>
    );
  const guide = parseCountryGuide(guideRes.data);
  if (!guide) notFound();

  const facts: [string, string | null][] = [
    ['Region', regionLabel(guide.region)],
    ['Currency', guide.currency ? `${guide.currency}${guide.currencyName ? ` · ${guide.currencyName}` : ''}` : null],
    ['Main time zone', guide.timezone?.replace(/_/g, ' ') ?? null],
    ['Language code', guide.language],
    ['Calling code', guide.callingCode],
  ];
  const entities = global.entities.filter((e) => e.country_code === code);
  const profName = profession ? (profRes.data ?? []).find((p) => p.id === profession)?.name : null;

  return (
    <div className="space-y-6 max-w-5xl">
      {back}
      <div>
        <div className="flex items-center gap-3 flex-wrap">
          <h1 className="text-xl sm:text-2xl font-bold break-words">{guide.name}</h1>
          <span className="pill">{guide.country}</span>
          {guide.supported && (
            <span className="pill" style={{ color: 'var(--color-verified)' }}>
              Omelo available
            </span>
          )}
        </div>
        <p className="text-sm muted mt-1">Hiring in {guide.name}: official sources and the basics.</p>
      </div>

      <NotLegalAdvice text={guide.disclaimer} />

      <div className="grid gap-6 lg:grid-cols-3 items-start">
        <div className="space-y-6 lg:col-span-2 min-w-0">
          <section className="card p-5 space-y-4">
            <h2 className="font-bold">Official information</h2>
            {guide.information.length === 0 ? (
              <p className="text-sm muted">
                No official sources are linked for {guide.name} yet. Check the government&apos;s immigration and labour
                websites directly.
              </p>
            ) : (
              <ul className="space-y-4">
                {guide.information.map((i, n) => (
                  <li key={`${i.topic}-${n}`} className="space-y-1 min-w-0">
                    <p className="text-xs font-semibold uppercase tracking-wide muted">{TOPIC_LABEL[i.topic] ?? i.topic}</p>
                    <p className="font-semibold break-words">
                      {i.url ? (
                        <a href={i.url} target="_blank" rel="noopener noreferrer" className="hover:underline">
                          {i.title} ↗
                        </a>
                      ) : (
                        i.title
                      )}
                    </p>
                    {i.summary && <p className="text-sm leading-relaxed break-words">{i.summary}</p>}
                    <Source url={i.url} source={i.source} reviewedAt={i.reviewedAt} />
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section className="card p-5 space-y-4">
            <div className="flex items-end gap-3 flex-wrap">
              <h2 className="font-bold flex-1 min-w-0">Licences by profession</h2>
              <form className="flex gap-2 flex-wrap items-end w-full sm:w-auto" method="get">
                <label className="sr-only" htmlFor="profession">
                  Profession
                </label>
                <select id="profession" name="profession" className="input sm:w-56" defaultValue={profession ?? ''}>
                  <option value="">All professions</option>
                  {(profRes.data ?? []).map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.name}
                    </option>
                  ))}
                </select>
                <button className="btn btn-ghost w-full sm:w-auto">Show</button>
              </form>
            </div>
            {guide.licences.length === 0 ? (
              <p className="text-sm muted">
                No licence requirements recorded{profName ? ` for ${profName}` : ''} in {guide.name}. That does not
                mean none apply.
              </p>
            ) : (
              <ul className="space-y-4">
                {guide.licences.map((l, n) => (
                  <li key={`${l.name}-${n}`} className="space-y-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="font-semibold break-words">{l.name}</span>
                      {l.level && (
                        <span
                          className="pill"
                          style={l.level === 'required' ? { color: 'var(--color-warn)' } : undefined}
                        >
                          {l.level === 'required' ? 'Required' : 'Recommended'}
                        </span>
                      )}
                    </div>
                    {l.profession && <p className="text-xs muted">{l.profession}</p>}
                    {l.description && <p className="text-sm leading-relaxed break-words">{l.description}</p>}
                    <Source url={l.url} source={l.source} reviewedAt={l.reviewedAt} />
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>

        <div className="space-y-6 min-w-0">
          <section className="card p-5">
            <h2 className="font-bold mb-3">Basics</h2>
            <dl className="text-sm grid grid-cols-[auto_1fr] gap-x-3 gap-y-1.5">
              {facts
                .filter(([, v]) => v)
                .map(([k, v]) => (
                  <div key={k} className="contents">
                    <dt className="muted">{k}</dt>
                    <dd className="break-words">{v}</dd>
                  </div>
                ))}
            </dl>
          </section>
          <section className="card p-5 space-y-2">
            <h2 className="font-bold">Your entities here</h2>
            {entities.length === 0 ? (
              <p className="text-sm muted">You have no legal entity in {guide.name}.</p>
            ) : (
              <ul className="text-sm space-y-1">
                {entities.map((e) => (
                  <li key={e.id} className="break-words">
                    {e.legal_name} · {e.currency}
                    {e.is_default ? ' · default' : ''}
                  </li>
                ))}
              </ul>
            )}
            <Link href="/dashboard/company/entities" className="text-sm underline">
              Legal entities
            </Link>
          </section>
        </div>
      </div>

      <CurrencyConverter
        currencies={global.currencies}
        defaultFrom={global.defaultCurrency}
        defaultTo={guide.currency && guide.currency !== global.defaultCurrency ? guide.currency : 'USD'}
      />
    </div>
  );
}
