'use client';

import { useActionState, useId, useState } from 'react';
import {
  ORGANIZATION_TYPES,
  ORGANIZATION_TYPE_HELP,
  ORGANIZATION_TYPE_LABEL,
  TEAM_PURPOSES,
  TEAM_PURPOSE_LABEL,
  type OrganizationType,
} from '@/lib/enterprise';
import {
  deleteDepartment,
  deleteLocation,
  saveBusinessUnit,
  saveDepartment,
  saveLocation,
  saveTeam,
  setBusinessUnitActive,
  setOrganizationType,
  setTeamActive,
  setTeamMember,
  type OrgState,
} from './actions';

export type Named = { id: string; name: string };
export type Person = { personId: string; label: string };

export function Status({ state }: { state: OrgState }) {
  if (state.error)
    return (
      <p className="text-sm break-words" role="alert" style={{ color: 'var(--color-danger)' }}>
        {state.error}
      </p>
    );
  if (state.ok)
    return (
      <p className="text-sm break-words" role="status" style={{ color: 'var(--color-verified)' }}>
        {state.message}
      </p>
    );
  return null;
}

/** A button that posts one hidden-field form and reports what happened. */
function QuickAction({
  action,
  fields,
  label,
  busyLabel,
  danger,
}: {
  action: (prev: OrgState, fd: FormData) => Promise<OrgState>;
  fields: Record<string, string>;
  label: string;
  busyLabel: string;
  danger?: boolean;
}) {
  const [state, run, pending] = useActionState<OrgState, FormData>(action, {});
  return (
    <form action={run} className="inline-flex items-center gap-2 flex-wrap">
      {Object.entries(fields).map(([k, v]) => (
        <input key={k} type="hidden" name={k} value={v} />
      ))}
      <button
        className="btn btn-ghost !h-9 !px-3 text-sm"
        disabled={pending}
        style={danger ? { color: 'var(--color-danger)' } : undefined}
      >
        {pending ? busyLabel : label}
      </button>
      {state.error && <Status state={state} />}
    </form>
  );
}

/* ------------------------------------------------------------------ */
/* What kind of organization                                           */
/* ------------------------------------------------------------------ */

export function OrgTypeForm({ current }: { current: OrganizationType }) {
  const uid = useId();
  const [state, action, pending] = useActionState<OrgState, FormData>(setOrganizationType, {});
  const [type, setType] = useState<OrganizationType>(current);

  return (
    <form action={action} className="space-y-3">
      <div>
        <label className="label" htmlFor={`${uid}type`}>
          This organization is a…
        </label>
        <select
          id={`${uid}type`}
          name="organization_type"
          className="input sm:max-w-sm"
          value={type}
          onChange={(e) => setType(e.target.value as OrganizationType)}
        >
          {ORGANIZATION_TYPES.map((t) => (
            <option key={t} value={t}>
              {ORGANIZATION_TYPE_LABEL[t]}
            </option>
          ))}
        </select>
        <p className="hint">{ORGANIZATION_TYPE_HELP[type]}</p>
      </div>
      {type !== current && (
        <p className="text-sm" style={{ color: 'var(--color-warn)' }}>
          {type === 'employer'
            ? 'Saving this switches the workspace to the employer menu.'
            : 'Saving this switches the workspace to the agency menu. Your jobs and people stay where they are.'}
        </p>
      )}
      <div className="flex items-center gap-3 flex-wrap">
        <button className="btn btn-primary" disabled={pending || type === current}>
          {pending ? 'Saving…' : 'Save'}
        </button>
        <Status state={state} />
      </div>
    </form>
  );
}

/* ------------------------------------------------------------------ */
/* Business units                                                      */
/* ------------------------------------------------------------------ */

export function UnitForm({
  unit,
  units,
  label,
}: {
  unit?: { id: string; name: string; code: string | null; parentId: string | null };
  units: Named[];
  label: string;
}) {
  const uid = useId();
  const [open, setOpen] = useState(false);
  const [state, action, pending] = useActionState<OrgState, FormData>(async (prev, fd) => {
    const res = await saveBusinessUnit(prev, fd);
    if (res.ok) setOpen(false);
    return res;
  }, {});

  if (!open)
    return (
      <div className="flex items-center gap-3 flex-wrap">
        <button
          type="button"
          className={`btn ${unit ? 'btn-ghost !h-9 !px-3 text-sm' : 'btn-primary'}`}
          onClick={() => setOpen(true)}
        >
          {label}
        </button>
        {state.ok && <Status state={state} />}
      </div>
    );

  const parents = units.filter((u) => u.id !== unit?.id);

  return (
    <form action={action} className="space-y-3 w-full border-t hairline pt-3">
      {unit && <input type="hidden" name="id" value={unit.id} />}
      <div className="grid gap-3 sm:grid-cols-3">
        <div className="min-w-0 sm:col-span-2">
          <label className="label" htmlFor={`${uid}n`}>
            Name *
          </label>
          <input
            id={`${uid}n`}
            name="name"
            className="input"
            required
            minLength={2}
            maxLength={120}
            defaultValue={unit?.name ?? ''}
            placeholder="Retail division"
          />
        </div>
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}c`}>
            Code
          </label>
          <input id={`${uid}c`} name="code" className="input" maxLength={40} defaultValue={unit?.code ?? ''} placeholder="RET" />
        </div>
        <div className="min-w-0 sm:col-span-3">
          <label className="label" htmlFor={`${uid}p`}>
            Sits inside
          </label>
          <select id={`${uid}p`} name="parent_id" className="input" defaultValue={unit?.parentId ?? ''}>
            <option value="">Top level</option>
            {parents.map((u) => (
              <option key={u.id} value={u.id}>
                {u.name}
              </option>
            ))}
          </select>
          <p className="hint">A grant on a unit also reaches the units inside it.</p>
        </div>
      </div>
      <Status state={state} />
      <div className="flex gap-2 flex-wrap">
        <button className="btn btn-primary" disabled={pending}>
          {pending ? 'Saving…' : unit ? 'Save' : 'Add business unit'}
        </button>
        <button type="button" className="btn btn-ghost" onClick={() => setOpen(false)}>
          Cancel
        </button>
      </div>
    </form>
  );
}

export function UnitActive({ id, isActive }: { id: string; isActive: boolean }) {
  return (
    <QuickAction
      action={setBusinessUnitActive}
      fields={{ id, is_active: String(!isActive) }}
      label={isActive ? 'Archive' : 'Reopen'}
      busyLabel="Saving…"
    />
  );
}

/* ------------------------------------------------------------------ */
/* Departments                                                         */
/* ------------------------------------------------------------------ */

export function DepartmentForm({
  department,
  units,
  label,
}: {
  department?: { id: string; name: string; businessUnitId: string | null };
  units: Named[];
  label: string;
}) {
  const uid = useId();
  const [open, setOpen] = useState(false);
  const [state, action, pending] = useActionState<OrgState, FormData>(async (prev, fd) => {
    const res = await saveDepartment(prev, fd);
    if (res.ok) setOpen(false);
    return res;
  }, {});

  if (!open)
    return (
      <div className="flex items-center gap-3 flex-wrap">
        <button
          type="button"
          className={`btn ${department ? 'btn-ghost !h-9 !px-3 text-sm' : 'btn-primary'}`}
          onClick={() => setOpen(true)}
        >
          {label}
        </button>
        {state.ok && <Status state={state} />}
      </div>
    );

  return (
    <form action={action} className="space-y-3 w-full border-t hairline pt-3">
      {department && <input type="hidden" name="id" value={department.id} />}
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}n`}>
            Name *
          </label>
          <input
            id={`${uid}n`}
            name="name"
            className="input"
            required
            minLength={2}
            maxLength={120}
            defaultValue={department?.name ?? ''}
            placeholder="Engineering"
          />
        </div>
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}b`}>
            Business unit
          </label>
          <select id={`${uid}b`} name="business_unit_id" className="input" defaultValue={department?.businessUnitId ?? ''}>
            <option value="">Not in a business unit</option>
            {units.map((u) => (
              <option key={u.id} value={u.id}>
                {u.name}
              </option>
            ))}
          </select>
        </div>
      </div>
      <Status state={state} />
      <div className="flex gap-2 flex-wrap">
        <button className="btn btn-primary" disabled={pending}>
          {pending ? 'Saving…' : department ? 'Save' : 'Add department'}
        </button>
        <button type="button" className="btn btn-ghost" onClick={() => setOpen(false)}>
          Cancel
        </button>
      </div>
    </form>
  );
}

/* ------------------------------------------------------------------ */
/* Locations                                                           */
/* ------------------------------------------------------------------ */

export function LocationForm({
  location,
  label,
}: {
  location?: { id: string; name: string | null; address: string | null };
  label: string;
}) {
  const uid = useId();
  const [open, setOpen] = useState(false);
  const [state, action, pending] = useActionState<OrgState, FormData>(async (prev, fd) => {
    const res = await saveLocation(prev, fd);
    if (res.ok) setOpen(false);
    return res;
  }, {});

  if (!open)
    return (
      <div className="flex items-center gap-3 flex-wrap">
        <button
          type="button"
          className={`btn ${location ? 'btn-ghost !h-9 !px-3 text-sm' : 'btn-primary'}`}
          onClick={() => setOpen(true)}
        >
          {label}
        </button>
        {state.ok && <Status state={state} />}
      </div>
    );

  return (
    <form action={action} className="space-y-3 w-full border-t hairline pt-3">
      {location && <input type="hidden" name="id" value={location.id} />}
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}n`}>
            Name *
          </label>
          <input
            id={`${uid}n`}
            name="name"
            className="input"
            required
            minLength={2}
            maxLength={120}
            defaultValue={location?.name ?? ''}
            placeholder="Pune office"
          />
        </div>
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}a`}>
            Address
          </label>
          <input
            id={`${uid}a`}
            name="address"
            className="input"
            maxLength={300}
            defaultValue={location?.address ?? ''}
            placeholder="Street, city"
          />
        </div>
      </div>
      <p className="hint">
        A job&apos;s map position comes from the location it is attached to. Adding one here does not move any job.
      </p>
      <Status state={state} />
      <div className="flex gap-2 flex-wrap">
        <button className="btn btn-primary" disabled={pending}>
          {pending ? 'Saving…' : location ? 'Save' : 'Add location'}
        </button>
        <button type="button" className="btn btn-ghost" onClick={() => setOpen(false)}>
          Cancel
        </button>
      </div>
    </form>
  );
}

/* ------------------------------------------------------------------ */
/* Teams                                                               */
/* ------------------------------------------------------------------ */

export function TeamForm({
  team,
  units,
  departments,
  people,
  label,
}: {
  team?: {
    id: string;
    name: string;
    purpose: string | null;
    businessUnitId: string | null;
    departmentId: string | null;
    leadPersonId: string | null;
  };
  units: Named[];
  departments: Named[];
  people: Person[];
  label: string;
}) {
  const uid = useId();
  const [open, setOpen] = useState(false);
  const [state, action, pending] = useActionState<OrgState, FormData>(async (prev, fd) => {
    const res = await saveTeam(prev, fd);
    if (res.ok) setOpen(false);
    return res;
  }, {});

  if (!open)
    return (
      <div className="flex items-center gap-3 flex-wrap">
        <button
          type="button"
          className={`btn ${team ? 'btn-ghost !h-9 !px-3 text-sm' : 'btn-primary'}`}
          onClick={() => setOpen(true)}
        >
          {label}
        </button>
        {state.ok && <Status state={state} />}
      </div>
    );

  return (
    <form action={action} className="space-y-3 w-full border-t hairline pt-3">
      {team && <input type="hidden" name="id" value={team.id} />}
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}n`}>
            Name *
          </label>
          <input
            id={`${uid}n`}
            name="name"
            className="input"
            required
            minLength={2}
            maxLength={120}
            defaultValue={team?.name ?? ''}
            placeholder="Night shift hiring"
          />
        </div>
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}p`}>
            What it is for
          </label>
          <select id={`${uid}p`} name="purpose" className="input" defaultValue={team?.purpose ?? 'general'}>
            {TEAM_PURPOSES.map((p) => (
              <option key={p} value={p}>
                {TEAM_PURPOSE_LABEL[p]}
              </option>
            ))}
          </select>
        </div>
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}b`}>
            Business unit
          </label>
          <select id={`${uid}b`} name="business_unit_id" className="input" defaultValue={team?.businessUnitId ?? ''}>
            <option value="">None</option>
            {units.map((u) => (
              <option key={u.id} value={u.id}>
                {u.name}
              </option>
            ))}
          </select>
        </div>
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}d`}>
            Department
          </label>
          <select id={`${uid}d`} name="department_id" className="input" defaultValue={team?.departmentId ?? ''}>
            <option value="">None</option>
            {departments.map((d) => (
              <option key={d.id} value={d.id}>
                {d.name}
              </option>
            ))}
          </select>
        </div>
        <div className="min-w-0 sm:col-span-2">
          <label className="label" htmlFor={`${uid}l`}>
            Lead
          </label>
          <select id={`${uid}l`} name="lead_person_id" className="input" defaultValue={team?.leadPersonId ?? ''}>
            <option value="">No lead</option>
            {people.map((p) => (
              <option key={p.personId} value={p.personId}>
                {p.label}
              </option>
            ))}
          </select>
        </div>
      </div>
      <Status state={state} />
      <div className="flex gap-2 flex-wrap">
        <button className="btn btn-primary" disabled={pending}>
          {pending ? 'Saving…' : team ? 'Save' : 'Add team'}
        </button>
        <button type="button" className="btn btn-ghost" onClick={() => setOpen(false)}>
          Cancel
        </button>
      </div>
    </form>
  );
}

export function TeamActive({ id, isActive }: { id: string; isActive: boolean }) {
  return (
    <QuickAction
      action={setTeamActive}
      fields={{ id, is_active: String(!isActive) }}
      label={isActive ? 'Archive' : 'Reopen'}
      busyLabel="Saving…"
    />
  );
}

export function AddTeamMember({ teamId, people }: { teamId: string; people: Person[] }) {
  const uid = useId();
  const [state, action, pending] = useActionState<OrgState, FormData>(setTeamMember, {});
  if (people.length === 0) return <p className="text-xs muted">Everyone in the organization is already on this team.</p>;
  return (
    <form action={action} className="flex flex-wrap items-end gap-2">
      <input type="hidden" name="team_id" value={teamId} />
      <input type="hidden" name="add" value="true" />
      <div className="min-w-[12rem] flex-1">
        <label className="sr-only" htmlFor={`${uid}p`}>
          Person
        </label>
        <select id={`${uid}p`} name="person_id" className="input !h-9 !py-0 text-sm" defaultValue="">
          <option value="">Add someone…</option>
          {people.map((p) => (
            <option key={p.personId} value={p.personId}>
              {p.label}
            </option>
          ))}
        </select>
      </div>
      <button className="btn btn-ghost !h-9 !px-3 text-sm" disabled={pending}>
        {pending ? 'Adding…' : 'Add'}
      </button>
      <Status state={state} />
    </form>
  );
}

export function RemoveTeamMember({ teamId, personId }: { teamId: string; personId: string }) {
  return (
    <QuickAction
      action={setTeamMember}
      fields={{ team_id: teamId, person_id: personId, add: 'false' }}
      label="Remove"
      busyLabel="Removing…"
    />
  );
}

/* ------------------------------------------------------------------ */
/* Two-step removals                                                   */
/* ------------------------------------------------------------------ */

function ConfirmDelete({
  action,
  id,
  question,
}: {
  action: (prev: OrgState, fd: FormData) => Promise<OrgState>;
  id: string;
  question: string;
}) {
  const [confirming, setConfirming] = useState(false);
  const [state, run, pending] = useActionState<OrgState, FormData>(action, {});
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
    <form action={run} className="flex items-center gap-2 flex-wrap">
      <input type="hidden" name="id" value={id} />
      <span className="text-sm break-words">{question}</span>
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

export function DeleteDepartment({ id, name }: { id: string; name: string }) {
  return <ConfirmDelete action={deleteDepartment} id={id} question={`Remove ${name}?`} />;
}

export function DeleteLocation({ id, name }: { id: string; name: string }) {
  return <ConfirmDelete action={deleteLocation} id={id} question={`Remove ${name}?`} />;
}
