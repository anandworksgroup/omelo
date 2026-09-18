'use client';

import { useId, useState, useTransition } from 'react';
import { createAgency } from '../../dashboard/workspace-actions';

/**
 * Create a recruitment agency, or a one-person agency for an independent
 * recruiter. The database creates it (omelo_create_agency) and makes you
 * its owner; searching for candidates waits for Omelo's verification.
 */
export default function AgencyForm({
  countries,
  defaultCountry,
}: {
  countries: { country_code: string; name: string }[];
  defaultCountry: string;
}) {
  const uid = useId();
  const [name, setName] = useState('');
  const [independent, setIndependent] = useState(false);
  const [country, setCountry] = useState(defaultCountry);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  return (
    <form
      className="space-y-5"
      onSubmit={(e) => {
        e.preventDefault();
        setError(null);
        start(async () => {
          const res = await createAgency({ name, independent, country });
          if (res && !res.ok) setError(res.error);
        });
      }}
    >
      <fieldset className="space-y-2">
        <legend className="label">What are you setting up?</legend>
        <label className="card p-3 flex items-start gap-3 cursor-pointer">
          <input
            type="radio"
            name={`${uid}kind`}
            checked={!independent}
            onChange={() => setIndependent(false)}
            className="mt-1"
          />
          <span className="min-w-0">
            <span className="font-semibold text-sm block">A recruitment agency</span>
            <span className="text-sm muted">A team of recruiters, sourcers and coordinators working for clients.</span>
          </span>
        </label>
        <label className="card p-3 flex items-start gap-3 cursor-pointer">
          <input
            type="radio"
            name={`${uid}kind`}
            checked={independent}
            onChange={() => setIndependent(true)}
            className="mt-1"
          />
          <span className="min-w-0">
            <span className="font-semibold text-sm block">I am an independent recruiter</span>
            <span className="text-sm muted">
              Just you. Workers see that they are dealing with an independent recruiter.
            </span>
          </span>
        </label>
      </fieldset>

      <div>
        <label className="label" htmlFor={`${uid}name`}>
          {independent ? 'Your trading name' : 'Agency name'} *
        </label>
        <input
          id={`${uid}name`}
          className="input"
          required
          minLength={2}
          maxLength={120}
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder={independent ? 'Priya Nair Recruiting' : 'Northstar Staffing'}
        />
        <p className="hint">Workers see this name on every request to represent them.</p>
      </div>

      <div>
        <label className="label" htmlFor={`${uid}country`}>
          Country
        </label>
        <select id={`${uid}country`} className="input" value={country} onChange={(e) => setCountry(e.target.value)}>
          {countries.map((c) => (
            <option key={c.country_code} value={c.country_code}>
              {c.name}
            </option>
          ))}
        </select>
      </div>

      <div className="rounded-xl p-4 surface text-sm leading-relaxed space-y-2">
        <p>
          <strong>Before you can search for candidates, Omelo verifies your agency</strong> and turns on talent
          search for it. Until then you can add clients, create job orders and invite your team.
        </p>
        <p className="muted">
          Workers stay in control: you can only put someone forward for a job after they have said yes to that
          specific job, for a limited time, and only with the information they agreed to share.
        </p>
      </div>

      {error && (
        <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
          {error}
        </p>
      )}

      <button className="btn btn-primary w-full sm:w-auto" disabled={pending || name.trim().length < 2}>
        {pending ? 'Creating…' : independent ? 'Create my recruiter workspace' : 'Create agency'}
      </button>
    </form>
  );
}
