'use client';

import { useRouter } from 'next/navigation';
import { useId, useState, useTransition } from 'react';
import { JOB_ORDER_STATUS, JOB_ORDER_STATUSES } from '@/lib/agency';
import { assignRecruiter, setJobOrderStatus } from '../../actions';

function ErrorLine({ text }: { text: string | null }) {
  if (!text) return null;
  return (
    <p className="text-sm basis-full break-words" role="alert" style={{ color: 'var(--color-danger)' }}>
      {text}
    </p>
  );
}

export function StatusChanger({ orderId, status }: { orderId: string; status: string }) {
  const uid = useId();
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  return (
    <div className="flex flex-wrap items-center gap-2">
      <label className="text-sm muted" htmlFor={`${uid}s`}>
        Status
      </label>
      <select
        id={`${uid}s`}
        className="input !h-9 !py-0 text-sm !w-auto"
        value={status}
        disabled={pending}
        onChange={(e) => {
          const next = e.target.value;
          setError(null);
          start(async () => {
            const res = await setJobOrderStatus(orderId, next);
            if (!res.ok) setError(res.error);
            router.refresh();
          });
        }}
      >
        {JOB_ORDER_STATUSES.map((s) => (
          <option key={s} value={s}>
            {JOB_ORDER_STATUS[s].label}
          </option>
        ))}
      </select>
      <ErrorLine text={error} />
    </div>
  );
}

export type Assigned = { personId: string; label: string; role: 'lead' | 'support' };

/**
 * Recruiters on the order. Admins and the lead recruiter can assign; only
 * owners, admins, recruiters and sourcers can be assigned (the DB checks).
 */
export function Recruiters({
  orderId,
  assigned,
  candidates,
  canManage,
}: {
  orderId: string;
  assigned: Assigned[];
  candidates: { personId: string; label: string }[];
  canManage: boolean;
}) {
  const uid = useId();
  const router = useRouter();
  const [person, setPerson] = useState('');
  const [role, setRole] = useState<'lead' | 'support'>('support');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const free = candidates.filter((c) => !assigned.some((a) => a.personId === c.personId));

  const run = (input: { personId: string; assign: boolean; role: 'lead' | 'support' }) => {
    setError(null);
    start(async () => {
      const res = await assignRecruiter({ orderId, ...input });
      if (!res.ok) return setError(res.error);
      setPerson('');
      router.refresh();
    });
  };

  return (
    <div className="space-y-3">
      {assigned.length === 0 ? (
        <p className="text-sm muted">Nobody is assigned.</p>
      ) : (
        <ul className="space-y-2">
          {assigned.map((a) => (
            <li key={a.personId} className="flex items-center gap-2 flex-wrap">
              <span className="flex-1 min-w-0 text-sm break-words">
                {a.label} <span className="pill ml-1 text-[0.7rem]">{a.role === 'lead' ? 'Lead' : 'Support'}</span>
              </span>
              {canManage && (
                <span className="flex gap-1.5">
                  <button
                    type="button"
                    className="btn btn-ghost !h-8 !px-2.5 text-xs"
                    disabled={pending}
                    onClick={() => run({ personId: a.personId, assign: true, role: a.role === 'lead' ? 'support' : 'lead' })}
                  >
                    {a.role === 'lead' ? 'Make support' : 'Make lead'}
                  </button>
                  <button
                    type="button"
                    className="btn btn-ghost !h-8 !px-2.5 text-xs"
                    disabled={pending}
                    onClick={() => run({ personId: a.personId, assign: false, role: a.role })}
                  >
                    Remove
                  </button>
                </span>
              )}
            </li>
          ))}
        </ul>
      )}
      {canManage && free.length > 0 && (
        <form
          className="flex flex-wrap gap-2 items-end"
          onSubmit={(e) => {
            e.preventDefault();
            if (person) run({ personId: person, assign: true, role });
          }}
        >
          <div className="flex-1 min-w-[10rem]">
            <label className="label" htmlFor={`${uid}p`}>
              Assign
            </label>
            <select id={`${uid}p`} className="input" value={person} onChange={(e) => setPerson(e.target.value)}>
              <option value="">Choose a teammate…</option>
              {free.map((c) => (
                <option key={c.personId} value={c.personId}>
                  {c.label}
                </option>
              ))}
            </select>
          </div>
          <div className="w-28">
            <label className="label" htmlFor={`${uid}r`}>
              As
            </label>
            <select
              id={`${uid}r`}
              className="input"
              value={role}
              onChange={(e) => setRole(e.target.value === 'lead' ? 'lead' : 'support')}
            >
              <option value="support">Support</option>
              <option value="lead">Lead</option>
            </select>
          </div>
          <button className="btn btn-ghost w-full sm:w-auto" disabled={pending || !person}>
            Assign
          </button>
        </form>
      )}
      <ErrorLine text={error} />
    </div>
  );
}
