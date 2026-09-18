'use client';

import { useRouter } from 'next/navigation';
import { useId, useState, useTransition } from 'react';
import { NOTE_MAX } from '@/lib/talent';
import { createPool, deletePool, removePoolMember, renamePool, updatePoolNote } from '../actions';

function ErrorLine({ message }: { message: string | null }) {
  if (!message) return null;
  return (
    <p className="text-sm basis-full" role="alert" style={{ color: 'var(--color-danger)' }}>
      {message}
    </p>
  );
}

/** `basePath` lets the agency's pool pages reuse these forms. */
export function CreatePoolForm({ basePath = '/dashboard/talent/pools' }: { basePath?: string } = {}) {
  const uid = useId();
  const router = useRouter();
  const [name, setName] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  return (
    <form
      className="card p-4 flex flex-wrap gap-2 items-end"
      onSubmit={(e) => {
        e.preventDefault();
        setError(null);
        start(async () => {
          const res = await createPool(name);
          if (!res.ok) return setError(res.error);
          setName('');
          router.push(`${basePath}/${res.pool.id}`);
        });
      }}
    >
      <div className="flex-1 min-w-[12rem]">
        <label className="label" htmlFor={`${uid}name`}>
          New pool
        </label>
        <input
          id={`${uid}name`}
          className="input"
          value={name}
          maxLength={80}
          placeholder="e.g. Drivers for the new depot"
          onChange={(e) => setName(e.target.value)}
        />
      </div>
      <button className="btn btn-primary w-full sm:w-auto" disabled={pending || name.trim().length < 2}>
        {pending ? 'Creating…' : 'Create pool'}
      </button>
      <ErrorLine message={error} />
    </form>
  );
}

export function PoolSettings({
  poolId,
  name: initial,
  basePath = '/dashboard/talent/pools',
}: {
  poolId: string;
  name: string;
  basePath?: string;
}) {
  const uid = useId();
  const router = useRouter();
  const [mode, setMode] = useState<'idle' | 'rename' | 'delete'>('idle');
  const [name, setName] = useState(initial);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  if (mode === 'rename')
    return (
      <form
        className="flex flex-wrap gap-2 items-end w-full"
        onSubmit={(e) => {
          e.preventDefault();
          setError(null);
          start(async () => {
            const res = await renamePool(poolId, name);
            if (!res.ok) return setError(res.error);
            setMode('idle');
            router.refresh();
          });
        }}
      >
        <div className="flex-1 min-w-[12rem]">
          <label className="label" htmlFor={`${uid}rename`}>
            Pool name
          </label>
          <input
            id={`${uid}rename`}
            className="input"
            value={name}
            maxLength={80}
            autoFocus
            onChange={(e) => setName(e.target.value)}
          />
        </div>
        <button className="btn btn-primary" disabled={pending}>
          {pending ? 'Saving…' : 'Save'}
        </button>
        <button type="button" className="btn btn-ghost" onClick={() => setMode('idle')}>
          Cancel
        </button>
        <ErrorLine message={error} />
      </form>
    );

  if (mode === 'delete')
    return (
      <div className="flex flex-wrap gap-2 items-center w-full card surface p-3">
        <p className="text-sm flex-1 min-w-[12rem]">
          Delete “{initial}”? The saved candidates and notes in it are removed. This cannot be undone.
        </p>
        <button
          type="button"
          className="btn btn-primary"
          style={{ background: 'var(--color-danger)' }}
          disabled={pending}
          onClick={() => {
            setError(null);
            start(async () => {
              const res = await deletePool(poolId);
              if (!res.ok) return setError(res.error);
              router.push(basePath);
            });
          }}
        >
          {pending ? 'Deleting…' : 'Delete pool'}
        </button>
        <button type="button" className="btn btn-ghost" onClick={() => setMode('idle')}>
          Cancel
        </button>
        <ErrorLine message={error} />
      </div>
    );

  return (
    <div className="flex gap-2 flex-wrap">
      <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setMode('rename')}>
        Rename
      </button>
      <button
        type="button"
        className="btn btn-ghost !h-9 !px-3 text-sm"
        style={{ color: 'var(--color-danger)' }}
        onClick={() => setMode('delete')}
      >
        Delete
      </button>
    </div>
  );
}

export function MemberControls({
  poolId,
  personId,
  note: initialNote,
  canEditNote,
}: {
  poolId: string;
  personId: string;
  note: string | null;
  canEditNote: boolean;
}) {
  const uid = useId();
  const router = useRouter();
  const [mode, setMode] = useState<'idle' | 'note' | 'remove'>('idle');
  const [note, setNote] = useState(initialNote ?? '');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  return (
    <div className="space-y-2">
      {mode === 'note' ? (
        <form
          className="space-y-2"
          onSubmit={(e) => {
            e.preventDefault();
            setError(null);
            start(async () => {
              const res = await updatePoolNote({ poolId, personId, note });
              if (!res.ok) return setError(res.error);
              setMode('idle');
              router.refresh();
            });
          }}
        >
          <label className="label" htmlFor={`${uid}note`}>
            Note for your team
          </label>
          <textarea
            id={`${uid}note`}
            className="input"
            rows={3}
            maxLength={NOTE_MAX}
            value={note}
            autoFocus
            onChange={(e) => setNote(e.target.value)}
          />
          <div className="flex gap-2 flex-wrap">
            <button className="btn btn-primary !h-9 !px-3 text-sm" disabled={pending}>
              {pending ? 'Saving…' : 'Save note'}
            </button>
            <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setMode('idle')}>
              Cancel
            </button>
          </div>
        </form>
      ) : mode === 'remove' ? (
        <div className="flex flex-wrap gap-2 items-center">
          <span className="text-sm">Remove from this pool?</span>
          <button
            type="button"
            className="btn btn-primary !h-9 !px-3 text-sm"
            style={{ background: 'var(--color-danger)' }}
            disabled={pending}
            onClick={() => {
              setError(null);
              start(async () => {
                const res = await removePoolMember({ poolId, personId });
                if (!res.ok) return setError(res.error);
                router.refresh();
              });
            }}
          >
            {pending ? 'Removing…' : 'Remove'}
          </button>
          <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setMode('idle')}>
            Cancel
          </button>
        </div>
      ) : (
        <div className="flex gap-2 flex-wrap">
          {canEditNote && (
            <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setMode('note')}>
              {initialNote ? 'Edit note' : 'Add note'}
            </button>
          )}
          <button
            type="button"
            className="btn btn-ghost !h-9 !px-3 text-sm"
            style={{ color: 'var(--color-danger)' }}
            onClick={() => setMode('remove')}
          >
            Remove
          </button>
        </div>
      )}
      <ErrorLine message={error} />
    </div>
  );
}
