'use client';

import { useRouter } from 'next/navigation';
import { useId, useState, useTransition } from 'react';
import {
  CONSENT_MESSAGE_MAX,
  SCOPES,
  SCOPE_HELP,
  SCOPE_LABEL,
  SUBMIT_NOTE_MAX,
  consentTone,
  scopeList,
  type Scope,
} from '@/lib/agency';
import Dialog from '../talent/dialog';
import { requestConsent, submitCandidate, withdrawConsentRequest } from './actions';

/** What the worker is told about the opportunity (from the job order). */
export type OrderSummary = {
  id: string;
  reference: string;
  title: string;
  client: string;
  location: string | null;
  pay: string | null;
  workType: string | null;
  workplace: string | null;
  startDate: string | null;
};

export type AgencySummary = { name: string; verified: boolean; independent: boolean };

function ErrorLine({ text }: { text: string | null }) {
  if (!text) return null;
  return (
    <p className="text-sm break-words" role="alert" style={{ color: 'var(--color-danger)' }}>
      {text}
    </p>
  );
}

const DAY_CHOICES = [7, 14, 30, 60, 90, 180];

/* ------------------------------------------------------------------ */
/* Ask for consent                                                     */
/* ------------------------------------------------------------------ */

export function ConsentDialog({
  open,
  onClose,
  candidate,
  order,
  agency,
  recruiterName,
  onRequested,
}: {
  open: boolean;
  onClose: () => void;
  candidate: { identityId: string; name: string; label: string | null };
  order: OrderSummary;
  agency: AgencySummary;
  recruiterName: string | null;
  onRequested: (consentId: string) => void;
}) {
  const uid = useId();
  const [scope, setScope] = useState<Scope[]>(['identity', 'skills', 'experience', 'evidence', 'answers', 'contact']);
  const [days, setDays] = useState(60);
  const [message, setMessage] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const firstName = candidate.name.split(' ')[0] || 'They';

  const toggle = (s: Scope) =>
    s === 'identity' ? undefined : setScope((cur) => (cur.includes(s) ? cur.filter((x) => x !== s) : [...cur, s]));

  function send() {
    setError(null);
    start(async () => {
      const res = await requestConsent({
        orderId: order.id,
        identityId: candidate.identityId,
        scope,
        validDays: days,
        message,
      });
      if (!res.ok) return setError(res.error);
      onRequested(res.consentId);
      onClose();
    });
  }

  const ordered = SCOPES.filter((s) => scope.includes(s));
  const facts = [order.location, order.workplace, order.workType, order.pay, order.startDate ? `Starts ${order.startDate}` : null].filter(
    Boolean
  );

  return (
    <Dialog
      open={open}
      onClose={onClose}
      title={`Ask ${candidate.name} for consent`}
      description={`To represent them for ${order.title} (${order.reference}) at ${order.client}`}
    >
      <fieldset className="space-y-2">
        <legend className="label">What they would share with you and {order.client}</legend>
        {SCOPES.map((s) => (
          <label key={s} className={`flex items-start gap-2 text-sm ${s === 'identity' ? 'opacity-80' : ''}`}>
            <input
              type="checkbox"
              className="mt-1"
              checked={scope.includes(s)}
              disabled={s === 'identity'}
              onChange={() => toggle(s)}
            />
            <span className="min-w-0">
              <span className="font-medium">{SCOPE_LABEL[s]}</span>
              {s === 'identity' && <span className="muted"> · always included</span>}
              <span className="block text-xs muted">{SCOPE_HELP[s]}</span>
            </span>
          </label>
        ))}
        <p className="hint">Ask only for what the client needs. They can say no, and you only ever see what they agree to.</p>
      </fieldset>

      <div>
        <label className="label" htmlFor={`${uid}days`}>
          Consent lasts
        </label>
        <select id={`${uid}days`} className="input" value={days} onChange={(e) => setDays(Number(e.target.value))}>
          {DAY_CHOICES.map((d) => (
            <option key={d} value={d}>
              {d} days
            </option>
          ))}
        </select>
        <p className="hint">Between 7 and 180 days from when they accept. Unanswered requests expire after 7 days.</p>
      </div>

      <div>
        <label className="label" htmlFor={`${uid}msg`}>
          Message <span className="muted font-normal">(optional)</span>
        </label>
        <textarea
          id={`${uid}msg`}
          className="input"
          rows={4}
          maxLength={CONSENT_MESSAGE_MAX}
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          placeholder={`Hi ${firstName}, I am recruiting for ${order.title} and think you would be a strong fit…`}
        />
        <p className="hint text-right tabular-nums">{CONSENT_MESSAGE_MAX - message.length} left</p>
      </div>

      <div>
        <p className="label">What {firstName} will see</p>
        <div className="surface rounded-lg p-3 space-y-2 text-sm">
          <p className="font-semibold break-words">
            {agency.name} wants to represent you{' '}
            {agency.verified ? (
              <span style={{ color: 'var(--color-verified)' }}>✓ verified</span>
            ) : (
              <span style={{ color: 'var(--color-warn)' }}>unverified</span>
            )}
          </p>
          <p className="break-words">
            <strong>{order.title}</strong> at {order.client}
          </p>
          {facts.length > 0 && <p className="muted break-words">{facts.join(' · ')}</p>}
          <p className="muted break-words">
            {agency.independent ? 'Independent recruiter' : 'Recruiter'}: {recruiterName ?? 'you'}
          </p>
          <p className="break-words">
            <span className="muted">Shared if you agree:</span> {scopeList(ordered)}
          </p>
          <p className="break-words">
            <span className="muted">For:</span> {days} days, for this job only
          </p>
          {message.trim() && <p className="whitespace-pre-line break-words border-t hairline pt-2">{message.trim()}</p>}
        </div>
        <p className="hint">
          {firstName} gets a notification and an email and can accept or decline. You cannot submit them anywhere until
          they accept.
        </p>
      </div>

      <ErrorLine text={error} />
      <div className="flex flex-wrap gap-2 justify-end">
        <button type="button" className="btn btn-ghost w-full sm:w-auto" onClick={onClose}>
          Cancel
        </button>
        <button type="button" className="btn btn-primary w-full sm:w-auto" disabled={pending} onClick={send}>
          {pending ? 'Sending…' : 'Send request'}
        </button>
      </div>
    </Dialog>
  );
}

/**
 * "Ask for consent" for one candidate and one job order, or the consent
 * status when a request already exists. Disabled with a reason when the
 * database would refuse.
 */
export function AskConsent({
  candidate,
  order,
  agency,
  recruiterName,
  existing,
  acceptsRequests,
  blockedReason,
  onRequested,
}: {
  candidate: { identityId: string; name: string; label: string | null };
  order: OrderSummary | null;
  agency: AgencySummary;
  recruiterName: string | null;
  existing: { id: string; status: string } | null;
  acceptsRequests: boolean;
  /** Role / verification / order-status reason, if any. */
  blockedReason: string | null;
  onRequested?: (consentId: string) => void;
}) {
  const [open, setOpen] = useState(false);
  const [sent, setSent] = useState<{ id: string; status: string } | null>(null);
  const current = sent ?? existing;
  // A closed request (declined/expired/withdrawn/revoked) can be asked again — the DB decides (e.g. 30-day cool-off).
  const live = current && ['requested', 'accepted', 'active'].includes(current.status);

  if (live) {
    const t = consentTone(current!.status);
    return (
      <span className="pill" style={{ color: t.color, borderColor: t.color }}>
        {t.label}
      </span>
    );
  }
  const reason = !order
    ? 'Choose a job order to ask for consent.'
    : !acceptsRequests
      ? 'This person is not accepting recruiter requests.'
      : blockedReason;

  return (
    <span className="inline-flex flex-col gap-1 min-w-0">
      <span className="inline-flex flex-wrap gap-2 items-center">
        {current && (
          <span className="pill" style={{ color: consentTone(current.status).color }}>
            {consentTone(current.status).label}
          </span>
        )}
        <button
          type="button"
          className="btn btn-primary !h-9 !px-3 text-sm"
          disabled={!!reason}
          title={reason ?? undefined}
          onClick={() => setOpen(true)}
        >
          {current ? 'Ask again' : 'Ask for consent'}
        </button>
      </span>
      {reason && <span className="text-xs muted break-words">{reason}</span>}
      {open && order && (
        <ConsentDialog
          open
          onClose={() => setOpen(false)}
          candidate={candidate}
          order={order}
          agency={agency}
          recruiterName={recruiterName}
          onRequested={(id) => {
            setSent({ id, status: 'requested' });
            onRequested?.(id);
          }}
        />
      )}
    </span>
  );
}

/* ------------------------------------------------------------------ */
/* Withdraw an unanswered request                                      */
/* ------------------------------------------------------------------ */

export function WithdrawRequest({ consentId }: { consentId: string }) {
  const router = useRouter();
  const [confirm, setConfirm] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  return (
    <span className="inline-flex flex-col gap-1">
      {confirm ? (
        <span className="inline-flex flex-wrap gap-2 items-center">
          <button
            type="button"
            className="btn btn-primary !h-9 !px-3 text-sm"
            style={{ background: 'var(--color-danger)' }}
            disabled={pending}
            onClick={() =>
              start(async () => {
                setError(null);
                const res = await withdrawConsentRequest(consentId);
                if (!res.ok) return setError(res.error);
                setConfirm(false);
                router.refresh();
              })
            }
          >
            {pending ? 'Withdrawing…' : 'Withdraw request'}
          </button>
          <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setConfirm(false)}>
            Keep
          </button>
        </span>
      ) : (
        <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setConfirm(true)}>
          Withdraw request
        </button>
      )}
      <ErrorLine text={error} />
    </span>
  );
}

/* ------------------------------------------------------------------ */
/* Submit to the client                                                */
/* ------------------------------------------------------------------ */

/**
 * Submit a consented candidate. Enabled only when the consent is accepted and
 * unexpired and your role may submit; otherwise the button is disabled and
 * the reason is shown. omelo_submit_candidate checks all of it again (plus
 * the assignment to the order) and its message is shown if it refuses.
 */
export function SubmitCandidate({
  consentId,
  candidateName,
  client,
  clientOnOmelo,
  scope,
  blocker,
}: {
  consentId: string;
  candidateName: string;
  client: string;
  clientOnOmelo: boolean;
  scope: string[];
  blocker: string | null;
}) {
  const uid = useId();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [note, setNote] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);
  const [pending, start] = useTransition();

  if (done)
    return (
      <span className="text-sm" role="status" style={{ color: 'var(--color-verified)' }}>
        Submitted to {client}.
      </span>
    );

  return (
    <span className="inline-flex flex-col gap-1 min-w-0">
      <button
        type="button"
        className="btn btn-primary !h-9 !px-3 text-sm w-full sm:w-auto"
        disabled={!!blocker}
        title={blocker ?? undefined}
        onClick={() => setOpen(true)}
      >
        Submit to client
      </button>
      {blocker && <span className="text-xs muted break-words">{blocker}</span>}
      {open && (
        <Dialog
          open
          onClose={() => setOpen(false)}
          title={`Submit ${candidateName} to ${client}`}
          description="With the candidate's consent, for this job order only."
        >
          <div className="surface rounded-lg p-3 text-sm space-y-1.5">
            <p>
              <span className="muted">The client receives:</span> {scopeList(scope)}
            </p>
            <p className="muted">
              {clientOnOmelo
                ? `${client} is on Omelo and has connected a job: the candidate goes straight into their hiring pipeline and the status updates here automatically.`
                : `${client} is not connected on Omelo: share the profile with them yourself and record their answers on the submission.`}
            </p>
          </div>
          <div>
            <label className="label" htmlFor={`${uid}note`}>
              Note to the client <span className="muted font-normal">(optional)</span>
            </label>
            <textarea
              id={`${uid}note`}
              className="input"
              rows={4}
              maxLength={SUBMIT_NOTE_MAX}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Why they fit, availability, notice period…"
            />
            <p className="hint text-right tabular-nums">{SUBMIT_NOTE_MAX - note.length} left</p>
          </div>
          <ErrorLine text={error} />
          <div className="flex flex-wrap gap-2 justify-end">
            <button type="button" className="btn btn-ghost w-full sm:w-auto" onClick={() => setOpen(false)}>
              Cancel
            </button>
            <button
              type="button"
              className="btn btn-primary w-full sm:w-auto"
              disabled={pending}
              onClick={() =>
                start(async () => {
                  setError(null);
                  const res = await submitCandidate(consentId, note);
                  if (!res.ok) return setError(res.error);
                  setOpen(false);
                  setDone(true);
                  router.refresh();
                })
              }
            >
              {pending ? 'Submitting…' : 'Submit'}
            </button>
          </div>
        </Dialog>
      )}
    </span>
  );
}
