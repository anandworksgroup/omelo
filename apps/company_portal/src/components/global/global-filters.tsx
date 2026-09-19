'use client';

import { useId } from 'react';
import { ELIGIBILITY_FILTERS, ELIGIBILITY_FILTER_LABEL } from '@/lib/global';

export type GlobalFilterValues = {
  eligibility: (typeof ELIGIBILITY_FILTERS)[number];
  relocation: '' | 'yes' | 'no';
  language: string;
  currentCountry: string;
  workAuth: string;
};

export const EMPTY_GLOBAL_FILTERS: GlobalFilterValues = {
  eligibility: 'any',
  relocation: '',
  language: '',
  currentCountry: '',
  workAuth: '',
};

/** The p_filters keys the talent search RPCs read (empty values left out). */
export function globalFilterKeys(v: GlobalFilterValues) {
  return {
    eligibility: v.eligibility !== 'any' ? v.eligibility : undefined,
    open_to_relocation: v.relocation === '' ? undefined : v.relocation === 'yes',
    language: v.language || undefined,
    current_country: v.currentCountry || undefined,
    work_auth_country: v.workAuth || undefined,
  };
}

export function activeGlobalFilters(v: GlobalFilterValues) {
  return [v.eligibility !== 'any', v.relocation, v.language, v.currentCountry, v.workAuth].filter(Boolean).length;
}

type Option = { id: string; label: string };

/** Eligibility, relocation, language, current country and work-authorization filters. */
export default function GlobalFilterFields({
  value,
  onChange,
  countries,
  languages,
}: {
  value: GlobalFilterValues;
  onChange: (v: GlobalFilterValues) => void;
  countries: Option[];
  languages: Option[];
}) {
  const uid = useId();
  const set = <K extends keyof GlobalFilterValues>(k: K, v: GlobalFilterValues[K]) => onChange({ ...value, [k]: v });
  return (
    <>
      <div className="min-w-0">
        <label className="label" htmlFor={`${uid}elig`}>
          Eligibility for the job
        </label>
        <select
          id={`${uid}elig`}
          className="input"
          value={value.eligibility}
          onChange={(e) => set('eligibility', e.target.value as GlobalFilterValues['eligibility'])}
        >
          {ELIGIBILITY_FILTERS.map((f) => (
            <option key={f} value={f}>
              {ELIGIBILITY_FILTER_LABEL[f]}
            </option>
          ))}
        </select>
      </div>
      <div className="min-w-0">
        <label className="label" htmlFor={`${uid}reloc`}>
          Open to relocation
        </label>
        <select
          id={`${uid}reloc`}
          className="input"
          value={value.relocation}
          onChange={(e) => set('relocation', e.target.value as GlobalFilterValues['relocation'])}
        >
          <option value="">Either</option>
          <option value="yes">Yes</option>
          <option value="no">No</option>
        </select>
      </div>
      <div className="min-w-0">
        <label className="label" htmlFor={`${uid}lang`}>
          Speaks
        </label>
        <select id={`${uid}lang`} className="input" value={value.language} onChange={(e) => set('language', e.target.value)}>
          <option value="">Any language</option>
          {languages.map((l) => (
            <option key={l.id} value={l.id}>
              {l.label}
            </option>
          ))}
        </select>
      </div>
      <div className="min-w-0">
        <label className="label" htmlFor={`${uid}cur`}>
          Lives in
        </label>
        <select
          id={`${uid}cur`}
          className="input"
          value={value.currentCountry}
          onChange={(e) => set('currentCountry', e.target.value)}
        >
          <option value="">Any country</option>
          {countries.map((c) => (
            <option key={c.id} value={c.id}>
              {c.label}
            </option>
          ))}
        </select>
      </div>
      <div className="min-w-0">
        <label className="label" htmlFor={`${uid}auth`}>
          Allowed to work in
        </label>
        <select id={`${uid}auth`} className="input" value={value.workAuth} onChange={(e) => set('workAuth', e.target.value)}>
          <option value="">Any country</option>
          {countries.map((c) => (
            <option key={c.id} value={c.id}>
              {c.label}
            </option>
          ))}
        </select>
      </div>
    </>
  );
}
