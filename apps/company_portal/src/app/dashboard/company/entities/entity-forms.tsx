'use client';

import { useActionState, useId, useState } from 'react';
import type { CountryOption } from '@/lib/global';
import { deleteEntity, saveEntity, type EntityState } from './actions';

export type Entity = {
  id: string;
  country_code: string;
  legal_name: string;
  registration_number: string | null;
  currency: string;
  timezone: string;
  hiring_notes: string | null;
  is_default: boolean;
};

type Options = {
  countries: CountryOption[];
  currencies: { code: string; name: string }[];
  timeZones: string[];
};

function Status({ state }: { state: EntityState }) {
  if (state.error)
    return (
      <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
        {state.error}
      </p>
    );
  if (state.ok)
    return (
      <p className="text-sm" role="status" style={{ color: 'var(--color-verified)' }}>
        {state.message}
      </p>
    );
  return null;
}

/** Add (no `entity`) or edit one legal entity. Collapsed to a button until opened. */
export function EntityForm({ entity, options, label }: { entity?: Entity; options: Options; label: string }) {
  const uid = useId();
  const [open, setOpen] = useState(false);
  const [state, action, pending] = useActionState<EntityState, FormData>(async (prev, fd) => {
    const res = await saveEntity(prev, fd);
    if (res.ok) setOpen(false);
    return res;
  }, {});
  const [country, setCountry] = useState(entity?.country_code ?? '');
  const [currency, setCurrency] = useState(entity?.currency ?? '');
  const [timezone, setTimezone] = useState(entity?.timezone ?? '');

  if (!open)
    return (
      <div className="flex items-center gap-3 flex-wrap">
        <button type="button" className={`btn ${entity ? 'btn-ghost !h-9 !px-3 text-sm' : 'btn-primary'} w-full sm:w-auto`} onClick={() => setOpen(true)}>
          {label}
        </button>
        {state.ok && <Status state={state} />}
      </div>
    );

  const zones = timezone && !options.timeZones.includes(timezone) ? [timezone, ...options.timeZones] : options.timeZones;

  return (
    <form action={action} className="space-y-4 border-t hairline pt-4 w-full">
      {entity && <input type="hidden" name="id" value={entity.id} />}
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}country`}>
            Country *
          </label>
          <select
            id={`${uid}country`}
            name="country_code"
            className="input"
            required
            value={country}
            onChange={(e) => {
              const c = options.countries.find((x) => x.code === e.target.value);
              setCountry(e.target.value);
              // Suggest the country's currency and time zone; both stay editable.
              if (c?.currency) setCurrency(c.currency);
              if (c?.timezone) setTimezone(c.timezone);
            }}
          >
            <option value="">Choose…</option>
            {options.countries.map((c) => (
              <option key={c.code} value={c.code}>
                {c.name}
              </option>
            ))}
          </select>
        </div>
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}name`}>
            Legal name *
          </label>
          <input
            id={`${uid}name`}
            name="legal_name"
            className="input"
            required
            minLength={2}
            maxLength={200}
            defaultValue={entity?.legal_name ?? ''}
            placeholder="Acme Services GmbH"
          />
        </div>
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}reg`}>
            Registration number
          </label>
          <input
            id={`${uid}reg`}
            name="registration_number"
            className="input"
            maxLength={80}
            defaultValue={entity?.registration_number ?? ''}
          />
        </div>
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}cur`}>
            Currency *
          </label>
          <select
            id={`${uid}cur`}
            name="currency"
            className="input"
            required
            value={currency}
            onChange={(e) => setCurrency(e.target.value)}
          >
            <option value="">Choose…</option>
            {options.currencies.map((c) => (
              <option key={c.code} value={c.code}>
                {c.code} · {c.name}
              </option>
            ))}
          </select>
        </div>
        <div className="min-w-0 sm:col-span-2">
          <label className="label" htmlFor={`${uid}tz`}>
            Time zone *
          </label>
          <select
            id={`${uid}tz`}
            name="timezone"
            className="input"
            required
            value={timezone}
            onChange={(e) => setTimezone(e.target.value)}
          >
            <option value="">Choose…</option>
            {zones.map((z) => (
              <option key={z} value={z}>
                {z.replace(/_/g, ' ')}
              </option>
            ))}
          </select>
        </div>
        <div className="min-w-0 sm:col-span-2">
          <label className="label" htmlFor={`${uid}notes`}>
            Hiring notes
          </label>
          <textarea
            id={`${uid}notes`}
            name="hiring_notes"
            className="input"
            rows={3}
            maxLength={2000}
            defaultValue={entity?.hiring_notes ?? ''}
            placeholder="Internal notes for your team, e.g. which roles this entity hires for."
          />
        </div>
        <label className="flex items-center gap-2 text-sm sm:col-span-2">
          <input type="checkbox" name="is_default" defaultChecked={entity?.is_default ?? false} />
          Default entity for this country
        </label>
      </div>
      <Status state={state} />
      <div className="flex gap-2 flex-wrap">
        <button className="btn btn-primary w-full sm:w-auto" disabled={pending}>
          {pending ? 'Saving…' : entity ? 'Save' : 'Add entity'}
        </button>
        <button type="button" className="btn btn-ghost w-full sm:w-auto" onClick={() => setOpen(false)}>
          Cancel
        </button>
      </div>
    </form>
  );
}

/** Two-step remove: the first click asks, the second removes. */
export function DeleteEntity({ id, name }: { id: string; name: string }) {
  const [confirming, setConfirming] = useState(false);
  const [state, action, pending] = useActionState<EntityState, FormData>(deleteEntity, {});
  if (!confirming)
    return (
      <div className="flex items-center gap-2 flex-wrap">
        <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setConfirming(true)}>
          Remove
        </button>
        <Status state={state} />
      </div>
    );
  return (
    <form action={action} className="flex items-center gap-2 flex-wrap">
      <input type="hidden" name="id" value={id} />
      <span className="text-sm">Remove {name}? Jobs using it keep their country.</span>
      <button className="btn btn-ghost !h-9 !px-3 text-sm" style={{ color: 'var(--color-danger)' }} disabled={pending}>
        {pending ? 'Removing…' : 'Yes, remove'}
      </button>
      <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setConfirming(false)}>
        Keep
      </button>
      <Status state={state} />
    </form>
  );
}
