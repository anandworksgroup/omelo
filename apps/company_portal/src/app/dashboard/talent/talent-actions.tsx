'use client';

import Link from 'next/link';
import { useId, useState, useTransition } from 'react';
import {
  INVITE_MAX,
  NOTE_MAX,
  defaultInviteMessage,
  type Pool,
  type TalentCard,
} from '@/lib/talent';
import { addToPool, inviteToApply } from './actions';
import Dialog from './dialog';
import { InvitationChip } from './ui';

export type JobOption = { id: string; title: string; location: string | null };

function ErrorLine({ message }: { message: string | null }) {
  if (!message) return null;
  return (
    <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
      {message}
    </p>
  );
}

/* ------------------------------------------------------------------ */
/* Invite                                                              */
/* ------------------------------------------------------------------ */

function InviteDialog({
  open,
  onClose,
  card,
  jobs,
  defaultJobId,
  companyName,
  onInvited,
}: {
  open: boolean;
  onClose: () => void;
  card: TalentCard;
  jobs: JobOption[];
  defaultJobId: string | null;
  companyName: string;
  onInvited: (invitationId: string, jobId: string) => void;
}) {
  const uid = useId();
  const [jobId, setJobId] = useState(defaultJobId ?? jobs[0]?.id ?? '');
  const job = jobs.find((j) => j.id === jobId) ?? null;
  const firstName = card.name.split(' ')[0] ?? '';
  const [message, setMessage] = useState(() =>
    defaultInviteMessage({ firstName, jobTitle: job?.title ?? 'open', companyName })
  );
  const [touched, setTouched] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  function pickJob(id: string) {
    setJobId(id);
    const j = jobs.find((x) => x.id === id);
    // Keep the employer's own edits; only refresh the untouched default.
    if (!touched && j) setMessage(defaultInviteMessage({ firstName, jobTitle: j.title, companyName }));
  }

  function send() {
    setError(null);
    if (!job) return setError('Choose one of your published jobs.');
    start(async () => {
      const res = await inviteToApply({ jobId: job.id, identityId: card.workIdentityId, message });
      if (!res.ok) return setError(res.error);
      onInvited(res.invitationId, job.id);
      onClose();
    });
  }

  const left = INVITE_MAX - message.length;

  return (
    <Dialog
      open={open}
      onClose={onClose}
      title={`Invite ${card.name} to apply`}
      description={card.label ? `As ${card.label}` : undefined}
    >
      {jobs.length > 1 || !defaultJobId ? (
        <div>
          <label className="label" htmlFor={`${uid}job`}>
            Job
          </label>
          <select id={`${uid}job`} className="input" value={jobId} onChange={(e) => pickJob(e.target.value)}>
            {jobs.map((j) => (
              <option key={j.id} value={j.id}>
                {j.title}
                {j.location ? ` · ${j.location}` : ''}
              </option>
            ))}
          </select>
        </div>
      ) : null}

      <div>
        <label className="label" htmlFor={`${uid}msg`}>
          Your message
        </label>
        <textarea
          id={`${uid}msg`}
          className="input"
          rows={6}
          maxLength={INVITE_MAX}
          value={message}
          onChange={(e) => {
            setTouched(true);
            setMessage(e.target.value);
          }}
        />
        <p className="hint flex justify-between gap-3">
          <span>Friendly and specific works best. Optional.</span>
          <span className="tabular-nums" style={left < 50 ? { color: 'var(--color-warn)' } : undefined}>
            {left}
          </span>
        </p>
      </div>

      <div>
        <p className="label">What {firstName || 'they'} will see</p>
        <div className="surface rounded-lg p-3 space-y-2 text-sm">
          <p>
            <span className="font-semibold">{companyName} invited you to apply</span>
            <br />
            <span className="muted">
              {job?.title ?? 'Your job'}
              {job?.location ? ` · ${job.location}` : ''}
            </span>
          </p>
          {message.trim() && (
            <p className="whitespace-pre-line break-words border-t hairline pt-2">{message.trim()}</p>
          )}
        </div>
        <p className="hint">
          They get an in-app notification and an email, and can apply or decline. They can see which company
          invited them.
        </p>
      </div>

      <ErrorLine message={error} />
      <div className="flex flex-wrap gap-2 justify-end">
        <button type="button" className="btn btn-ghost" onClick={onClose}>
          Cancel
        </button>
        <button type="button" className="btn btn-primary" onClick={send} disabled={pending || !job}>
          {pending ? 'Sending…' : 'Send invitation'}
        </button>
      </div>
    </Dialog>
  );
}

/* ------------------------------------------------------------------ */
/* Save to pool                                                        */
/* ------------------------------------------------------------------ */

function PoolDialog({
  open,
  onClose,
  card,
  pools,
  savedIn,
  onSaved,
}: {
  open: boolean;
  onClose: () => void;
  card: TalentCard;
  pools: Pool[];
  savedIn: string[];
  onSaved: (pool: Pool, created: boolean) => void;
}) {
  const uid = useId();
  const firstFree = pools.find((p) => !savedIn.includes(p.id));
  const [choice, setChoice] = useState<string>(firstFree?.id ?? 'new');
  const [newName, setNewName] = useState('');
  const [note, setNote] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  function save() {
    setError(null);
    start(async () => {
      const res = await addToPool(
        choice === 'new'
          ? { newPoolName: newName, identityId: card.workIdentityId, note }
          : { poolId: choice, identityId: card.workIdentityId, note }
      );
      if (!res.ok) return setError(res.error);
      onSaved(res.pool, res.created);
      onClose();
    });
  }

  return (
    <Dialog open={open} onClose={onClose} title={`Save ${card.name} to a pool`} description="Pools are shared with your hiring team.">
      <fieldset className="space-y-2">
        <legend className="label">Pool</legend>
        {pools.map((p) => {
          const already = savedIn.includes(p.id);
          return (
            <label key={p.id} className={`flex items-center gap-2 text-sm ${already ? 'opacity-60' : ''}`}>
              <input
                type="radio"
                name={`${uid}pool`}
                value={p.id}
                checked={choice === p.id}
                disabled={already}
                onChange={() => setChoice(p.id)}
              />
              <span className="break-words min-w-0">{p.name}</span>
              {already && <span className="pill">Already saved</span>}
            </label>
          );
        })}
        <label className="flex items-center gap-2 text-sm">
          <input type="radio" name={`${uid}pool`} value="new" checked={choice === 'new'} onChange={() => setChoice('new')} />
          <span>New pool…</span>
        </label>
        {choice === 'new' && (
          <input
            className="input"
            aria-label="New pool name"
            placeholder="e.g. Line cooks — Bengaluru"
            value={newName}
            maxLength={80}
            onChange={(e) => setNewName(e.target.value)}
            autoFocus
          />
        )}
      </fieldset>

      <div>
        <label className="label" htmlFor={`${uid}note`}>
          Note for your team <span className="muted font-normal">(optional)</span>
        </label>
        <textarea
          id={`${uid}note`}
          className="input"
          rows={3}
          maxLength={NOTE_MAX}
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="Why they stood out"
        />
        <p className="hint">Only your company sees this. {NOTE_MAX - note.length} characters left.</p>
      </div>

      <ErrorLine message={error} />
      <div className="flex flex-wrap gap-2 justify-end">
        <button type="button" className="btn btn-ghost" onClick={onClose}>
          Cancel
        </button>
        <button
          type="button"
          className="btn btn-primary"
          onClick={save}
          disabled={pending || (choice === 'new' && newName.trim().length < 2)}
        >
          {pending ? 'Saving…' : 'Save'}
        </button>
      </div>
    </Dialog>
  );
}

/* ------------------------------------------------------------------ */
/* Action row                                                          */
/* ------------------------------------------------------------------ */

/**
 * View profile / Invite / Save to pool for one candidate. Keeps the
 * invitation and pool membership in local state so the card updates without
 * running (and paying for) the search again.
 */
export default function TalentActions({
  card,
  jobs,
  jobId,
  companyName,
  pools: initialPools,
  onPoolCreated,
  profileHref,
  canAct,
}: {
  card: TalentCard;
  jobs: JobOption[];
  jobId: string | null;
  companyName: string;
  pools: Pool[];
  onPoolCreated?: (pool: Pool) => void;
  profileHref?: string;
  canAct: boolean;
}) {
  const [invitation, setInvitation] = useState(card.invitation);
  const [savedIn, setSavedIn] = useState(card.pools);
  const [localPools, setLocalPools] = useState<Pool[]>([]);
  const [dialog, setDialog] = useState<'invite' | 'pool' | null>(null);
  const [flash, setFlash] = useState<string | null>(null);
  const pools = [...initialPools, ...localPools.filter((p) => !initialPools.some((q) => q.id === p.id))];
  const savedNames = pools.filter((p) => savedIn.includes(p.id)).map((p) => p.name);

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap gap-2 items-center">
        {profileHref && (
          <Link href={profileHref} className="btn btn-ghost !h-9 !px-3 text-sm">
            View profile
          </Link>
        )}
        {invitation ? (
          <InvitationChip status={invitation.status} sentAt={invitation.sentAt} />
        ) : !canAct ? null : !card.allowInvitations ? (
          <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" disabled title="This person has turned invitations off">
            <span className="muted">Not accepting invitations</span>
          </button>
        ) : jobs.length === 0 ? (
          <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" disabled title="Publish a job first">
            <span className="muted">Invite (no published job)</span>
          </button>
        ) : (
          <button type="button" className="btn btn-primary !h-9 !px-3 text-sm" onClick={() => setDialog('invite')}>
            Invite to apply
          </button>
        )}
        {canAct && (
          <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setDialog('pool')}>
            {savedIn.length ? `Saved · ${savedIn.length === 1 ? '1 pool' : `${savedIn.length} pools`}` : 'Save to pool'}
          </button>
        )}
      </div>
      {savedNames.length > 0 && (
        <p className="text-xs muted break-words">In: {savedNames.join(', ')}</p>
      )}
      {flash && (
        <p className="text-sm" role="status" style={{ color: 'var(--color-verified)' }}>
          {flash}
        </p>
      )}

      {dialog === 'invite' && (
        <InviteDialog
          open
          onClose={() => setDialog(null)}
          card={card}
          jobs={jobs}
          defaultJobId={jobId}
          companyName={companyName}
          onInvited={(id, invitedJob) => {
            // Invitations are per job: only the job this card was loaded for gets the chip.
            if (invitedJob === jobId) setInvitation({ id, sentAt: new Date().toISOString(), status: 'pending' });
            setFlash('Invitation sent. They will get a notification and an email.');
          }}
        />
      )}
      {dialog === 'pool' && (
        <PoolDialog
          open
          onClose={() => setDialog(null)}
          card={card}
          pools={pools}
          savedIn={savedIn}
          onSaved={(pool, created) => {
            setSavedIn((s) => [...s, pool.id]);
            if (created) {
              setLocalPools((ps) => [...ps, pool]);
              onPoolCreated?.(pool);
            }
            setFlash(`Saved to “${pool.name}”.`);
          }}
        />
      )}
    </div>
  );
}
