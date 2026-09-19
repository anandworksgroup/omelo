'use client';

import { useId, useMemo, useState } from 'react';
import {
  EMPTY_GLOBAL,
  REMOTE_SCOPES,
  REMOTE_SCOPE_LABEL,
  SPONSORSHIP,
  SPONSORSHIP_LABEL,
  SUPPORT_FLAGS,
  SUPPORT_LABEL,
  TZ_OPTIONS,
  utcOffsetLabel,
  validateGlobalHiring,
  type CountryOption,
  type GlobalHiring,
  type RemoteScope,
  type Sponsorship,
} from '@/lib/global';

export type EntityOption = {
  id: string;
  legal_name: string;
  country_code: string;
  currency: string;
  is_default: boolean;
};

/**
 * The "Global hiring" fields of a job: country, legal entity, visa
 * sponsorship and support, and — for remote jobs — where the worker may be.
 * Writes plain named inputs, so the surrounding <form> posts them and
 * readGlobalHiring() on the server reads them back. Live hints use the same
 * validateGlobalHiring() the form runs before submitting.
 */
export default function GlobalHiringFields({
  countries,
  entities,
  workplace,
  initial,
  onCurrencyHint,
}: {
  countries: CountryOption[];
  entities: EntityOption[];
  workplace: string;
  initial?: GlobalHiring;
  /** Called with a suggested pay currency when the country or entity changes. */
  onCurrencyHint?: (currency: string) => void;
}) {
  const uid = useId();
  const [g, setG] = useState<GlobalHiring>(initial ?? EMPTY_GLOBAL);
  const [countryFilter, setCountryFilter] = useState('');
  const set = <K extends keyof GlobalHiring>(k: K, v: GlobalHiring[K]) => setG((x) => ({ ...x, [k]: v }));
  const remote = workplace === 'remote';

  const countryByCode = useMemo(() => new Map(countries.map((c) => [c.code, c])), [countries]);
  const entityOptions = g.country_code ? entities.filter((e) => e.country_code === g.country_code) : entities;
  const problem = validateGlobalHiring(g, workplace, entities);
  const shownCountries = countries.filter(
    (c) =>
      g.remote_countries.includes(c.code) ||
      !countryFilter.trim() ||
      c.name.toLowerCase().includes(countryFilter.trim().toLowerCase()) ||
      c.code.toLowerCase() === countryFilter.trim().toLowerCase()
  );

  function chooseCountry(code: string) {
    const next = code || null;
    setG((x) => {
      const keepEntity = x.legal_entity_id && entities.find((e) => e.id === x.legal_entity_id)?.country_code === next;
      const def = next ? entities.find((e) => e.country_code === next && e.is_default) : undefined;
      return { ...x, country_code: next, legal_entity_id: keepEntity ? x.legal_entity_id : (def?.id ?? null) };
    });
    const def = next ? entities.find((e) => e.country_code === next && e.is_default) : undefined;
    const cur = def?.currency ?? (next ? countryByCode.get(next)?.currency : null);
    if (cur) onCurrencyHint?.(cur);
  }

  function chooseEntity(id: string) {
    const e = entities.find((x) => x.id === id);
    setG((x) => ({ ...x, legal_entity_id: e ? e.id : null, country_code: e ? e.country_code : x.country_code }));
    if (e) onCurrencyHint?.(e.currency);
  }

  const toggleCountry = (c: string) =>
    set('remote_countries', g.remote_countries.includes(c) ? g.remote_countries.filter((x) => x !== c) : [...g.remote_countries, c]);

  return (
    <div className="space-y-4">
      <div className="grid sm:grid-cols-2 gap-4">
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}country`}>
            Country of the job
          </label>
          <select
            id={`${uid}country`}
            name="country_code"
            className="input"
            value={g.country_code ?? ''}
            onChange={(e) => chooseCountry(e.target.value)}
          >
            <option value="">Not set</option>
            {countries.map((c) => (
              <option key={c.code} value={c.code}>
                {c.name}
              </option>
            ))}
          </select>
          <p className="hint">Where the work is done (or where the employer is, for remote work).</p>
        </div>
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}entity`}>
            Hiring legal entity <span className="muted font-normal">(optional)</span>
          </label>
          <select
            id={`${uid}entity`}
            name="legal_entity_id"
            className="input"
            value={g.legal_entity_id ?? ''}
            onChange={(e) => chooseEntity(e.target.value)}
            disabled={entities.length === 0}
          >
            <option value="">{entities.length === 0 ? 'No entities added yet' : 'None'}</option>
            {entityOptions.map((e) => (
              <option key={e.id} value={e.id}>
                {e.legal_name} · {e.country_code}
                {e.is_default ? ' (default)' : ''}
              </option>
            ))}
          </select>
          <p className="hint">Add entities under Company → Legal entities.</p>
        </div>
      </div>

      <fieldset className="min-w-0">
        <legend className="label">Visa sponsorship</legend>
        <div className="flex flex-wrap gap-2">
          {SPONSORSHIP.map((s) => (
            <label key={s} className="pill cursor-pointer">
              <input
                type="radio"
                name="sponsorship"
                value={s}
                checked={g.sponsorship === s}
                onChange={() => set('sponsorship', s as Sponsorship)}
                className="mr-1"
              />
              {s === 'no' ? 'No' : s === 'yes' ? 'Yes' : 'Case by case'}
            </label>
          ))}
        </div>
        <p className="hint">{SPONSORSHIP_LABEL[g.sponsorship]}.</p>
      </fieldset>

      {g.sponsorship !== 'no' && (
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}stype`}>
            Kind of sponsorship <span className="muted font-normal">(optional)</span>
          </label>
          <input
            id={`${uid}stype`}
            name="sponsorship_type"
            className="input"
            maxLength={80}
            value={g.sponsorship_type ?? ''}
            onChange={(e) => set('sponsorship_type', e.target.value || null)}
            placeholder="e.g. Skilled Worker visa, EU Blue Card"
          />
        </div>
      )}

      <fieldset className="min-w-0">
        <legend className="label">Support you offer</legend>
        <div className="flex flex-wrap gap-2">
          {SUPPORT_FLAGS.map((f) => (
            <label key={f} className="pill cursor-pointer">
              <input
                type="checkbox"
                name={f}
                checked={g[f]}
                onChange={(e) => set(f, e.target.checked)}
                className="mr-1"
              />
              {SUPPORT_LABEL[f]}
            </label>
          ))}
        </div>
      </fieldset>

      <label className="flex items-start gap-2.5 cursor-pointer">
        <input
          type="checkbox"
          name="accepts_non_residents"
          checked={g.accepts_non_residents}
          onChange={(e) => set('accepts_non_residents', e.target.checked)}
          className="mt-1"
        />
        <span className="text-sm font-medium">
          Accept applicants who live abroad
          <span className="block hint !mt-0 font-normal">
            People outside the job’s country can apply; eligibility is checked for each of them.
          </span>
        </span>
      </label>

      {remote && (
        <div className="surface rounded-xl p-4 space-y-4">
          <div className="min-w-0">
            <label className="label" htmlFor={`${uid}scope`}>
              Where can remote workers be?
            </label>
            <select
              id={`${uid}scope`}
              name="remote_scope"
              className="input"
              value={g.remote_scope ?? ''}
              onChange={(e) => set('remote_scope', (e.target.value || null) as RemoteScope | null)}
            >
              <option value="">Not specified</option>
              {REMOTE_SCOPES.map((s) => (
                <option key={s} value={s}>
                  {REMOTE_SCOPE_LABEL[s]}
                </option>
              ))}
            </select>
          </div>

          {g.remote_scope === 'countries' && (
            <fieldset className="min-w-0">
              <legend className="label">
                Countries{' '}
                {g.remote_countries.length > 0 && (
                  <span className="muted font-normal">· {g.remote_countries.length} chosen</span>
                )}
              </legend>
              <input
                className="input mb-2"
                type="search"
                aria-label="Filter countries"
                placeholder="Filter countries"
                value={countryFilter}
                onChange={(e) => setCountryFilter(e.target.value)}
              />
              <div className="max-h-48 overflow-y-auto rounded-lg border hairline p-2 grid gap-x-4 gap-y-2 grid-cols-1 sm:grid-cols-2">
                {shownCountries.map((c) => (
                  <label key={c.code} className="text-sm inline-flex items-center gap-1.5 min-w-0">
                    <input
                      type="checkbox"
                      name="remote_countries"
                      value={c.code}
                      checked={g.remote_countries.includes(c.code)}
                      onChange={() => toggleCountry(c.code)}
                    />
                    <span className="truncate">{c.name}</span>
                  </label>
                ))}
              </div>
            </fieldset>
          )}

          {g.remote_scope === 'timezone' && (
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div className="min-w-0">
                <label className="label" htmlFor={`${uid}tzmin`}>
                  From
                </label>
                <select
                  id={`${uid}tzmin`}
                  name="remote_tz_min_offset"
                  className="input"
                  value={g.remote_tz_min_offset ?? ''}
                  onChange={(e) => set('remote_tz_min_offset', e.target.value === '' ? null : Number(e.target.value))}
                >
                  <option value="">Choose…</option>
                  {TZ_OPTIONS.map((m) => (
                    <option key={m} value={m}>
                      {utcOffsetLabel(m)}
                    </option>
                  ))}
                </select>
              </div>
              <div className="min-w-0">
                <label className="label" htmlFor={`${uid}tzmax`}>
                  To
                </label>
                <select
                  id={`${uid}tzmax`}
                  name="remote_tz_max_offset"
                  className="input"
                  value={g.remote_tz_max_offset ?? ''}
                  onChange={(e) => set('remote_tz_max_offset', e.target.value === '' ? null : Number(e.target.value))}
                >
                  <option value="">Choose…</option>
                  {TZ_OPTIONS.map((m) => (
                    <option key={m} value={m}>
                      {utcOffsetLabel(m)}
                    </option>
                  ))}
                </select>
              </div>
              <p className="hint sm:col-span-2 !mt-0">
                Workers whose time zone falls in this range fit best. Daylight saving moves some zones by an hour.
              </p>
            </div>
          )}
        </div>
      )}

      {problem && (
        <p className="text-sm" role="status" style={{ color: 'var(--color-warn)' }}>
          {problem}
        </p>
      )}
    </div>
  );
}
