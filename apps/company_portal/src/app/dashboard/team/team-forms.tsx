'use client';

import { useRouter } from 'next/navigation';
import { useId, useState, useTransition } from 'react';
import { roleLabel } from '@/lib/agency';
import { cancelTeamInvitation, inviteTeamMember, removeTeamMember, updateTeamMember } from './actions';

function Line({ text, ok }: { text: string | null; ok?: boolean }) {
  if (!text) return null;
  return (
    <p
      className="text-sm basis-full break-words"
      role={ok ? 'status' : 'alert'}
      style={{ color: ok ? 'var(--color-verified)' : 'var(--color-danger)' }}
    >
      {text}
    </p>
  );
}

export function InviteForm({ roles, defaultRole }: { roles: string[]; defaultRole: string }) {
  const uid = useId();
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [role, setRole] = useState(defaultRole);
  const [result, setResult] = useState<{ text: string; ok: boolean } | null>(null);
  const [pending, start] = useTransition();

  return (
    <form
      className="card p-4 sm:p-5 flex flex-wrap gap-3 items-end"
      onSubmit={(e) => {
        e.preventDefault();
        setResult(null);
        start(async () => {
          const res = await inviteTeamMember(email, role);
          if (!res.ok) return setResult({ text: res.error, ok: false });
          setEmail('');
          setResult({ text: res.message ?? 'Invitation sent.', ok: true });
          router.refresh();
        });
      }}
    >
      <div className="flex-1 min-w-[14rem]">
        <label className="label" htmlFor={`${uid}email`}>
          Email address
        </label>
        <input
          id={`${uid}email`}
          className="input"
          type="email"
          required
          maxLength={254}
          autoComplete="off"
          placeholder="colleague@example.com"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
        />
      </div>
      <div className="w-full sm:w-48">
        <label className="label" htmlFor={`${uid}role`}>
          Role
        </label>
        <select id={`${uid}role`} className="input" value={role} onChange={(e) => setRole(e.target.value)}>
          {roles.map((r) => (
            <option key={r} value={r}>
              {roleLabel(r)}
            </option>
          ))}
        </select>
      </div>
      <button className="btn btn-primary w-full sm:w-auto" disabled={pending || !email.trim()}>
        {pending ? 'Sending…' : 'Send invitation'}
      </button>
      <Line text={result?.text ?? null} ok={result?.ok} />
    </form>
  );
}

export function CancelInvitation({ id }: { id: string }) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  return (
    <div className="flex flex-col items-end gap-1">
      <button
        type="button"
        className="btn btn-ghost !h-9 !px-3 text-sm"
        disabled={pending}
        onClick={() => {
          setError(null);
          start(async () => {
            const res = await cancelTeamInvitation(id);
            if (!res.ok) setError(res.error);
            else router.refresh();
          });
        }}
      >
        {pending ? 'Cancelling…' : 'Cancel invitation'}
      </button>
      <Line text={error} />
    </div>
  );
}

export function MemberControls({
  memberId,
  role,
  isActive,
  roles,
  isYou,
}: {
  memberId: string;
  role: string;
  isActive: boolean;
  roles: string[];
  isYou: boolean;
}) {
  const uid = useId();
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [confirmRemove, setConfirmRemove] = useState(false);
  const [pending, start] = useTransition();

  function run(fn: () => Promise<{ ok: boolean; error?: string }>) {
    setError(null);
    start(async () => {
      const res = await fn();
      if (!res.ok) setError(res.error ?? 'Something went wrong.');
      else {
        setConfirmRemove(false);
        router.refresh();
      }
    });
  }

  const options = roles.includes(role) ? roles : [role, ...roles];

  return (
    <div className="flex flex-wrap items-center gap-2 w-full sm:w-auto sm:justify-end">
      <label className="sr-only" htmlFor={`${uid}role`}>
        Role
      </label>
      <select
        id={`${uid}role`}
        className="input !h-9 !py-0 text-sm !w-auto"
        value={role}
        disabled={pending}
        onChange={(e) => run(() => updateTeamMember(memberId, { role: e.target.value }))}
      >
        {options.map((r) => (
          <option key={r} value={r}>
            {roleLabel(r)}
          </option>
        ))}
      </select>
      <button
        type="button"
        className="btn btn-ghost !h-9 !px-3 text-sm"
        disabled={pending}
        onClick={() => run(() => updateTeamMember(memberId, { isActive: !isActive }))}
      >
        {isActive ? 'Deactivate' : 'Reactivate'}
      </button>
      {confirmRemove ? (
        <span className="inline-flex gap-2 items-center flex-wrap">
          <span className="text-sm">{isYou ? 'Remove yourself?' : 'Remove from the team?'}</span>
          <button
            type="button"
            className="btn btn-primary !h-9 !px-3 text-sm"
            style={{ background: 'var(--color-danger)' }}
            disabled={pending}
            onClick={() => run(() => removeTeamMember(memberId))}
          >
            Remove
          </button>
          <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setConfirmRemove(false)}>
            Keep
          </button>
        </span>
      ) : (
        <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setConfirmRemove(true)}>
          Remove
        </button>
      )}
      <Line text={error} />
    </div>
  );
}
