'use client';

import { useActionState } from 'react';
import { createCompany, type ActionState } from '../dashboard/actions';

const SIZE_BANDS = [
  '1-10',
  '11-50',
  '51-200',
  '201-500',
  '501-1000',
  '1001-5000',
  '5001-10000',
  '10000+',
];

export default function CompanyForm({
  countries,
  areas,
}: {
  countries: { country_code: string; name: string }[];
  areas: { id: string; label: string }[];
}) {
  const [state, action, pending] = useActionState<ActionState, FormData>(
    createCompany,
    {}
  );

  return (
    <form action={action} className="space-y-5">
      <div>
        <label className="label" htmlFor="display_name">
          Company name *
        </label>
        <input
          id="display_name"
          name="display_name"
          required
          className="input"
          placeholder="Zippy Logistics"
        />
        <p className="hint">The name workers will see on every job.</p>
      </div>

      <div className="grid sm:grid-cols-2 gap-4">
        <div>
          <label className="label" htmlFor="country_code">
            Country
          </label>
          <select id="country_code" name="country_code" className="input" defaultValue="IN">
            {countries.map((c) => (
              <option key={c.country_code} value={c.country_code}>
                {c.name}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="label" htmlFor="size_band">
            Company size
          </label>
          <select id="size_band" name="size_band" className="input" defaultValue="11-50">
            {SIZE_BANDS.map((s) => (
              <option key={s} value={s}>
                {s} people
              </option>
            ))}
          </select>
        </div>
      </div>

      <div>
        <label className="label" htmlFor="hq_location_id">
          Main location *
        </label>
        <select id="hq_location_id" name="hq_location_id" className="input" required>
          <option value="">Choose an area…</option>
          {areas.map((a) => (
            <option key={a.id} value={a.id}>
              {a.label}
            </option>
          ))}
        </select>
        <p className="hint">
          Workers find jobs by distance from where they live, so this decides
          who sees you. Individual jobs can be somewhere else.
        </p>
      </div>

      <div className="grid sm:grid-cols-2 gap-4">
        <div>
          <label className="label" htmlFor="legal_name">
            Registered name
          </label>
          <input
            id="legal_name"
            name="legal_name"
            className="input"
            placeholder="Zippy Logistics Pvt Ltd"
          />
        </div>
        <div>
          <label className="label" htmlFor="website">
            Website
          </label>
          <input
            id="website"
            name="website"
            className="input"
            placeholder="https://…"
          />
        </div>
      </div>

      <div>
        <label className="label" htmlFor="about">
          About the company
        </label>
        <textarea
          id="about"
          name="about"
          rows={4}
          className="input"
          placeholder="What you do, how many people work there, what it's like."
        />
      </div>

      {state.error && (
        <p className="text-sm" style={{ color: 'var(--color-danger)' }}>
          {state.error}
        </p>
      )}

      <div className="rounded-xl p-4 surface text-sm leading-relaxed">
        <strong>You start on the free plan:</strong> 3 active jobs, 2 seats.
        Talent search stays off until your company is verified — we never let
        an unverified account browse worker profiles.
      </div>

      <button className="btn btn-primary" disabled={pending}>
        {pending ? 'Creating…' : 'Create company'}
      </button>
    </form>
  );
}
