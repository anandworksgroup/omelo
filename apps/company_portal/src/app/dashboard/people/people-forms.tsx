'use client';

import { useActionState, useId, useMemo, useState } from 'react';
import { roleLabel } from '@/lib/agency';
import {
  GRANT_SCOPES,
  GRANT_SCOPE_LABEL,
  SCOPE_MODES,
  SCOPE_MODE_HELP,
  SCOPE_MODE_LABEL,
  grantSentence,
  type GrantScope,
  type ScopeMode,
} from '@/lib/enterprise';
import { addRoleGrant, removeRoleGrant, setScopeMode, type PeopleState } from './actions';

export type ScopeOptions = Record<Exclude<GrantScope, 'organization'>, { id: string; name: string }[]>;

function Status({ state }: { state: PeopleState }) {
  if (state.error)
    return (
      <p className="text-sm basis-full break-words" role="alert" style={{ color: 'var(--color-danger)' }}>
        {state.error}
      </p>
    );
  if (state.ok)
    return (
      <p className="text-sm basis-full break-words" role="status" style={{ color: 'var(--color-verified)' }}>
        {state.message}
      </p>
    );
  return null;
}

/** Whole organization, or only what is granted. Saves as soon as it changes. */
export function ScopeModeToggle({ personId, mode }: { personId: string; mode: ScopeMode }) {
  const uid = useId();
  const [state, action, pending] = useActionState<PeopleState, FormData>(setScopeMode, {});
  const [value, setValue] = useState<ScopeMode>(mode);

  return (
    <form action={action} className="flex flex-wrap items-end gap-2">
      <input type="hidden" name="person_id" value={personId} />
      <div className="min-w-[13rem]">
        <label className="label" htmlFor={`${uid}m`}>
          Their role reaches
        </label>
        <select
          id={`${uid}m`}
          name="scope_mode"
          className="input !h-9 !py-0 text-sm"
          value={value}
          disabled={pending}
          onChange={(e) => setValue(e.target.value as ScopeMode)}
        >
          {SCOPE_MODES.map((m) => (
            <option key={m} value={m}>
              {SCOPE_MODE_LABEL[m]}
            </option>
          ))}
        </select>
      </div>
      <button className="btn btn-ghost !h-9 !px-3 text-sm" disabled={pending || value === mode}>
        {pending ? 'Saving…' : 'Save'}
      </button>
      <p className="basis-full text-xs muted">{SCOPE_MODE_HELP[value]}</p>
      <Status state={state} />
    </form>
  );
}

/**
 * One grant: a role plus the part of the organization it covers. The sentence
 * under the form is the same one the list shows afterwards, so nobody has to
 * guess what they are about to give away.
 */
export function GrantForm({
  personId,
  roles,
  options,
}: {
  personId: string;
  roles: string[];
  options: ScopeOptions;
}) {
  const uid = useId();
  const [open, setOpen] = useState(false);
  const [role, setRole] = useState(roles[0] ?? 'recruiter');
  const [scopeType, setScopeType] = useState<GrantScope>('department');
  const [scopeId, setScopeId] = useState('');
  const [state, action, pending] = useActionState<PeopleState, FormData>(async (prev, fd) => {
    const res = await addRoleGrant(prev, fd);
    if (res.ok) {
      setOpen(false);
      setScopeId('');
    }
    return res;
  }, {});

  const list = useMemo(
    () => (scopeType === 'organization' ? [] : (options[scopeType] ?? [])),
    [options, scopeType]
  );
  const chosen = list.find((o) => o.id === scopeId)?.name ?? null;

  if (!open)
    return (
      <div className="flex items-center gap-3 flex-wrap">
        <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setOpen(true)}>
          Give access to a part of the organization
        </button>
        {state.ok && <Status state={state} />}
      </div>
    );

  return (
    <form action={action} className="space-y-3 border-t hairline pt-3">
      <input type="hidden" name="person_id" value={personId} />
      <div className="grid gap-3 sm:grid-cols-3">
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}r`}>
            Role
          </label>
          <select
            id={`${uid}r`}
            name="role"
            className="input !h-9 !py-0 text-sm"
            value={role}
            onChange={(e) => setRole(e.target.value)}
          >
            {roles.map((r) => (
              <option key={r} value={r}>
                {roleLabel(r)}
              </option>
            ))}
          </select>
        </div>
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}t`}>
            Covers
          </label>
          <select
            id={`${uid}t`}
            name="scope_type"
            className="input !h-9 !py-0 text-sm"
            value={scopeType}
            onChange={(e) => {
              setScopeType(e.target.value as GrantScope);
              setScopeId('');
            }}
          >
            {GRANT_SCOPES.map((s) => (
              <option key={s} value={s}>
                {GRANT_SCOPE_LABEL[s]}
              </option>
            ))}
          </select>
        </div>
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}i`}>
            Which one
          </label>
          <select
            id={`${uid}i`}
            name="scope_id"
            className="input !h-9 !py-0 text-sm"
            value={scopeId}
            disabled={scopeType === 'organization'}
            onChange={(e) => setScopeId(e.target.value)}
          >
            <option value="">{scopeType === 'organization' ? 'Not needed' : 'Choose…'}</option>
            {list.map((o) => (
              <option key={o.id} value={o.id}>
                {o.name}
              </option>
            ))}
          </select>
          {scopeType !== 'organization' && list.length === 0 && (
            <p className="hint">
              Nothing of that kind exists yet. Add it on the Organization page first.
            </p>
          )}
        </div>
      </div>
      <p className="text-sm font-semibold break-words">{grantSentence(role, scopeType, chosen)}</p>
      <Status state={state} />
      <div className="flex gap-2 flex-wrap">
        <button
          className="btn btn-primary !h-9 !px-3 text-sm"
          disabled={pending || (scopeType !== 'organization' && !scopeId)}
        >
          {pending ? 'Saving…' : 'Give this access'}
        </button>
        <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setOpen(false)}>
          Cancel
        </button>
      </div>
    </form>
  );
}

export function RemoveGrant({ id }: { id: string }) {
  const [state, action, pending] = useActionState<PeopleState, FormData>(removeRoleGrant, {});
  return (
    <form action={action} className="inline-flex items-center gap-2 flex-wrap">
      <input type="hidden" name="id" value={id} />
      <button className="btn btn-ghost !h-8 !px-2.5 text-xs" disabled={pending}>
        {pending ? 'Removing…' : 'Remove'}
      </button>
      {state.error && <Status state={state} />}
    </form>
  );
}
