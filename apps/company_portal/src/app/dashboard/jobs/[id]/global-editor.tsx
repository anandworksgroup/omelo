'use client';

import { useActionState, useState } from 'react';
import { updateJobGlobal, type ActionState } from '../../actions';
import GlobalHiringFields, { type EntityOption } from '@/components/global/global-hiring-fields';
import { readGlobalHiring, validateGlobalHiring, type CountryOption, type GlobalHiring } from '@/lib/global';

/** Edit form for a job's "Global hiring" fields, opened from the job page. */
export default function GlobalHiringEditor({
  jobId,
  workplace,
  initial,
  countries,
  entities,
}: {
  jobId: string;
  workplace: string;
  initial: GlobalHiring;
  countries: CountryOption[];
  entities: EntityOption[];
}) {
  const [open, setOpen] = useState(false);
  const [state, action, pending] = useActionState<ActionState, FormData>(updateJobGlobal, {});
  const [clientError, setClientError] = useState<string | null>(null);

  if (!open)
    return (
      <div className="flex items-center gap-3 flex-wrap">
        <button type="button" className="btn btn-ghost w-full sm:w-auto" onClick={() => setOpen(true)}>
          Edit global hiring
        </button>
        {state.ok && (
          <span className="text-sm" role="status" style={{ color: 'var(--color-verified)' }}>
            {state.message}
          </span>
        )}
      </div>
    );

  return (
    <form
      action={action}
      className="space-y-4 border-t hairline pt-4"
      onSubmit={(e) => {
        const err = validateGlobalHiring(readGlobalHiring(new FormData(e.currentTarget)), workplace, entities);
        setClientError(err);
        if (err) e.preventDefault();
      }}
    >
      <input type="hidden" name="job_id" value={jobId} />
      <GlobalHiringFields countries={countries} entities={entities} workplace={workplace} initial={initial} />
      {(clientError || state.error) && (
        <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
          {clientError ?? state.error}
        </p>
      )}
      {state.ok && !pending && (
        <p className="text-sm" role="status" style={{ color: 'var(--color-verified)' }}>
          {state.message}
        </p>
      )}
      <div className="flex gap-2 flex-wrap">
        <button className="btn btn-primary w-full sm:w-auto" disabled={pending}>
          {pending ? 'Saving…' : 'Save'}
        </button>
        <button type="button" className="btn btn-ghost w-full sm:w-auto" onClick={() => setOpen(false)}>
          Close
        </button>
      </div>
    </form>
  );
}
