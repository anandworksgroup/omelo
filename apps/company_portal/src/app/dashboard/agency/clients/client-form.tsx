'use client';

import { useRouter } from 'next/navigation';
import { useId, useState, useTransition } from 'react';
import { RELATIONSHIP, RELATIONSHIP_STATUSES } from '@/lib/agency';
import { createAgencyClient, deleteAgencyClient, updateAgencyClient, type ClientInput } from '../actions';

export type ClientInitial = {
  id: string;
  name: string;
  relationshipStatus: string;
  ownerId: string | null;
  industry: string | null;
  website: string | null;
  locations: string[];
  departments: string[];
  notes: string | null;
};

const splitList = (s: string) =>
  s
    .split(/[\n,]/)
    .map((x) => x.trim())
    .filter(Boolean);

/** Create or edit an agency client. Link fields are not here: linking goes through the client's confirmation. */
export default function ClientForm({
  initial,
  people,
  onDone,
}: {
  initial?: ClientInitial;
  people: { personId: string; label: string }[];
  onDone?: () => void;
}) {
  const uid = useId();
  const router = useRouter();
  const [name, setName] = useState(initial?.name ?? '');
  const [status, setStatus] = useState(initial?.relationshipStatus ?? 'prospect');
  const [ownerId, setOwnerId] = useState(initial?.ownerId ?? '');
  const [industry, setIndustry] = useState(initial?.industry ?? '');
  const [website, setWebsite] = useState(initial?.website ?? '');
  const [locations, setLocations] = useState((initial?.locations ?? []).join(', '));
  const [departments, setDepartments] = useState((initial?.departments ?? []).join(', '));
  const [notes, setNotes] = useState(initial?.notes ?? '');
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [pending, start] = useTransition();

  function submit() {
    setError(null);
    setSaved(false);
    const input: ClientInput = {
      name,
      relationshipStatus: status,
      ownerId: ownerId || null,
      industry,
      website,
      locations: splitList(locations),
      departments: splitList(departments),
      notes,
    };
    start(async () => {
      if (initial) {
        const res = await updateAgencyClient(initial.id, input);
        if (!res.ok) return setError(res.error);
        setSaved(true);
        router.refresh();
        onDone?.();
      } else {
        const res = await createAgencyClient(input);
        if (!res.ok) return setError(res.error);
        router.push(`/dashboard/agency/clients/${res.id}`);
      }
    });
  }

  return (
    <form
      className="space-y-4"
      onSubmit={(e) => {
        e.preventDefault();
        submit();
      }}
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <div className="sm:col-span-2">
          <label className="label" htmlFor={`${uid}name`}>
            Client name *
          </label>
          <input
            id={`${uid}name`}
            className="input"
            required
            minLength={2}
            maxLength={120}
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Zippy Logistics"
          />
        </div>
        <div>
          <label className="label" htmlFor={`${uid}status`}>
            Relationship
          </label>
          <select id={`${uid}status`} className="input" value={status} onChange={(e) => setStatus(e.target.value)}>
            {RELATIONSHIP_STATUSES.map((s) => (
              <option key={s} value={s}>
                {RELATIONSHIP[s].label}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="label" htmlFor={`${uid}owner`}>
            Account owner
          </label>
          <select id={`${uid}owner`} className="input" value={ownerId} onChange={(e) => setOwnerId(e.target.value)}>
            <option value="">Nobody yet</option>
            {people.map((p) => (
              <option key={p.personId} value={p.personId}>
                {p.label}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="label" htmlFor={`${uid}industry`}>
            Industry
          </label>
          <input
            id={`${uid}industry`}
            className="input"
            maxLength={120}
            value={industry}
            onChange={(e) => setIndustry(e.target.value)}
            placeholder="Warehousing"
          />
        </div>
        <div>
          <label className="label" htmlFor={`${uid}web`}>
            Website
          </label>
          <input
            id={`${uid}web`}
            className="input"
            maxLength={300}
            value={website}
            onChange={(e) => setWebsite(e.target.value)}
            placeholder="https://…"
          />
        </div>
        <div>
          <label className="label" htmlFor={`${uid}loc`}>
            Locations
          </label>
          <textarea
            id={`${uid}loc`}
            className="input"
            rows={2}
            value={locations}
            onChange={(e) => setLocations(e.target.value)}
            placeholder="Bengaluru, Hosur"
          />
          <p className="hint">Separate with commas or new lines.</p>
        </div>
        <div>
          <label className="label" htmlFor={`${uid}dep`}>
            Departments
          </label>
          <textarea
            id={`${uid}dep`}
            className="input"
            rows={2}
            value={departments}
            onChange={(e) => setDepartments(e.target.value)}
            placeholder="Operations, Last-mile delivery"
          />
        </div>
        <div className="sm:col-span-2">
          <label className="label" htmlFor={`${uid}notes`}>
            Notes <span className="muted font-normal">(only your agency sees these)</span>
          </label>
          <textarea
            id={`${uid}notes`}
            className="input"
            rows={3}
            maxLength={4000}
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
          />
        </div>
      </div>

      {error && (
        <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
          {error}
        </p>
      )}
      {saved && (
        <p className="text-sm" role="status" style={{ color: 'var(--color-verified)' }}>
          Saved.
        </p>
      )}
      <div className="flex flex-wrap gap-2">
        <button className="btn btn-primary w-full sm:w-auto" disabled={pending || name.trim().length < 2}>
          {pending ? 'Saving…' : initial ? 'Save changes' : 'Add client'}
        </button>
        {onDone && (
          <button type="button" className="btn btn-ghost w-full sm:w-auto" onClick={onDone}>
            Cancel
          </button>
        )}
      </div>
    </form>
  );
}

export function NewClientToggle({ people }: { people: { personId: string; label: string }[] }) {
  const [open, setOpen] = useState(false);
  if (!open)
    return (
      <button type="button" className="btn btn-primary w-full sm:w-auto" onClick={() => setOpen(true)}>
        Add a client
      </button>
    );
  return (
    <div className="card p-4 sm:p-5 w-full">
      <h2 className="font-bold mb-3">New client</h2>
      <ClientForm people={people} onDone={() => setOpen(false)} />
    </div>
  );
}

export function EditClientToggle({
  initial,
  people,
}: {
  initial: ClientInitial;
  people: { personId: string; label: string }[];
}) {
  const [open, setOpen] = useState(false);
  if (!open)
    return (
      <button type="button" className="btn btn-ghost w-full sm:w-auto" onClick={() => setOpen(true)}>
        Edit client
      </button>
    );
  return (
    <div className="card p-4 sm:p-5 w-full basis-full">
      <h2 className="font-bold mb-3">Edit client</h2>
      <ClientForm initial={initial} people={people} onDone={() => setOpen(false)} />
    </div>
  );
}

export function DeleteClient({ clientId, name }: { clientId: string; name: string }) {
  const router = useRouter();
  const [confirm, setConfirm] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  return (
    <div className="space-y-2">
      {confirm ? (
        <div className="flex flex-wrap gap-2 items-center">
          <span className="text-sm">
            Delete {name}, its contacts and job orders? Consents and submissions for those orders go too.
          </span>
          <button
            type="button"
            className="btn btn-primary !h-9 !px-3 text-sm"
            style={{ background: 'var(--color-danger)' }}
            disabled={pending}
            onClick={() => {
              setError(null);
              start(async () => {
                const res = await deleteAgencyClient(clientId);
                if (!res.ok) return setError(res.error);
                router.push('/dashboard/agency/clients');
              });
            }}
          >
            {pending ? 'Deleting…' : 'Delete'}
          </button>
          <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setConfirm(false)}>
            Keep
          </button>
        </div>
      ) : (
        <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setConfirm(true)}>
          Delete client
        </button>
      )}
      {error && (
        <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
          {error}
        </p>
      )}
    </div>
  );
}
