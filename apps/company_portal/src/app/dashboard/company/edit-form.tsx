'use client';

import { useActionState } from 'react';
import { updateCompany, type ActionState } from '../actions';

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

type Company = {
  display_name: string;
  legal_name: string | null;
  website: string | null;
  about: string | null;
  size_band: string | null;
  founded_year: number | null;
};

export default function CompanyEditForm({
  company,
  canEdit,
}: {
  company: Company;
  canEdit: boolean;
}) {
  const [state, action, pending] = useActionState<ActionState, FormData>(
    updateCompany,
    {}
  );

  return (
    <form action={action} className="card p-5 space-y-5">
      <fieldset disabled={!canEdit} className="space-y-5">
        <div>
          <label className="label">Company name</label>
          <input
            name="display_name"
            defaultValue={company.display_name}
            className="input"
            required
          />
        </div>

        <div className="grid sm:grid-cols-2 gap-4">
          <div>
            <label className="label">Registered name</label>
            <input
              name="legal_name"
              defaultValue={company.legal_name ?? ''}
              className="input"
            />
          </div>
          <div>
            <label className="label">Website</label>
            <input
              name="website"
              defaultValue={company.website ?? ''}
              className="input"
              placeholder="https://…"
            />
          </div>
        </div>

        <div className="grid sm:grid-cols-2 gap-4">
          <div>
            <label className="label">Size</label>
            <select
              name="size_band"
              defaultValue={company.size_band ?? '11-50'}
              className="input"
            >
              {SIZE_BANDS.map((s) => (
                <option key={s} value={s}>
                  {s} people
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="label">Founded</label>
            <input
              name="founded_year"
              type="number"
              min={1800}
              max={2100}
              defaultValue={company.founded_year ?? ''}
              className="input"
            />
          </div>
        </div>

        <div>
          <label className="label">About</label>
          <textarea
            name="about"
            rows={5}
            defaultValue={company.about ?? ''}
            className="input"
            placeholder="What you do, how many people work there, what it's like to work with you."
          />
          <p className="hint">
            Workers read this before applying. Plain language beats marketing.
          </p>
        </div>
      </fieldset>

      {state.error && (
        <p className="text-sm" style={{ color: 'var(--color-danger)' }}>
          {state.error}
        </p>
      )}
      {state.ok && (
        <p className="text-sm" style={{ color: 'var(--color-verified)' }}>
          Saved.
        </p>
      )}

      {canEdit ? (
        <button className="btn btn-primary" disabled={pending}>
          {pending ? 'Saving…' : 'Save changes'}
        </button>
      ) : (
        <p className="text-sm muted">
          Only an owner or admin can edit the company profile.
        </p>
      )}
    </form>
  );
}
