'use client';

import { useActionState, useState } from 'react';
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

/**
 * What the organization does for a living.
 *
 * This is a description, not a permission. Every organization gets the same
 * core: a public page, jobs, candidates, interviews, hiring, posts and a team.
 * The choice here only decides which optional modules start switched on, and
 * any of them can be turned on later from Settings without creating a second
 * organization.
 */
const TYPES = [
  {
    value: 'employer',
    label: 'We hire for ourselves',
    hint: 'A company filling its own roles.',
  },
  {
    value: 'recruitment_agency',
    label: 'We recruit for clients',
    hint: 'A recruitment firm placing candidates with other organizations.',
  },
  {
    value: 'staffing_agency',
    label: 'We staff and run shifts for clients',
    hint: 'A staffing firm that also manages rosters, timesheets and pay.',
  },
  {
    value: 'rpo_provider',
    label: 'We run hiring inside our clients',
    hint: 'An RPO provider working within a client’s own hiring process.',
  },
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
  const [type, setType] = useState('employer');
  const recruitsForClients = type !== 'employer';

  return (
    <form action={action} className="space-y-6">
      <fieldset className="space-y-2">
        <legend className="label">What does your organization do?</legend>
        <p className="hint mb-2 mt-0">
          This sets your starting point, not your limits. Every organization on Omelo can
          publish jobs, manage candidates, interview and hire.
        </p>
        {TYPES.map((t) => (
          <label
            key={t.value}
            className={`card card-interactive p-3 flex items-start gap-3 cursor-pointer${
              type === t.value ? ' is-chosen' : ''
            }`}
          >
            <input
              type="radio"
              name="organization_type"
              value={t.value}
              checked={type === t.value}
              onChange={() => setType(t.value)}
              className="mt-0.5"
            />
            <span className="min-w-0">
              <span className="font-semibold text-sm block">{t.label}</span>
              <span className="text-sm muted">{t.hint}</span>
            </span>
          </label>
        ))}
      </fieldset>

      {recruitsForClients && (
        <label className="flex items-start gap-3 text-sm">
          <input type="checkbox" name="independent" className="mt-0.5" />
          <span>
            <span className="font-semibold block">I work on my own</span>
            <span className="muted">
              Workers will see that they are dealing with an independent recruiter rather
              than a team.
            </span>
          </span>
        </label>
      )}

      <div>
        <label className="label" htmlFor="display_name">
          Organization name *
        </label>
        <input
          id="display_name"
          name="display_name"
          required
          className="input"
          placeholder="Zippy Logistics"
        />
        <p className="hint">The name workers will see on every job and on your page.</p>
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
            Size
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
          Workers find jobs by distance from where they live, so this decides who sees you.
          Individual jobs can be somewhere else.
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
          <input id="website" name="website" className="input" placeholder="https://…" />
        </div>
      </div>

      <div>
        <label className="label" htmlFor="about">
          About
        </label>
        <textarea
          id="about"
          name="about"
          rows={4}
          className="input"
          placeholder="What you do, how many people work there, what it's like."
        />
      </div>

      {state.error && <p className="error-text">{state.error}</p>}

      <div className="panel p-4 text-sm leading-relaxed">
        <strong>You start on the free plan:</strong> 3 active jobs, 2 seats. Talent search
        stays off until Omelo verifies your organization — we never let an unverified
        account browse worker profiles, whatever business it is in.
      </div>

      <button className="btn btn-primary" disabled={pending}>
        {pending ? 'Creating…' : 'Create organization'}
      </button>
    </form>
  );
}
