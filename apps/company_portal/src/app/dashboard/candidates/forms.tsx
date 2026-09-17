'use client';

import { useActionState, useState } from 'react';
import type { ActionState } from '../actions';
import {
  addNote,
  cancelInterview,
  completeInterview,
  moveApplication,
  rankApplicants,
  rejectApplication,
  rescheduleInterview,
  scheduleInterview,
  sendOffer,
  withdrawOffer,
} from './actions';
import {
  INTERVIEW_TYPE_LABEL,
  PAY_PERIODS,
  RECOMMENDATIONS,
  REJECTION_REASONS,
  type InterviewType,
} from '@/lib/hiring';

/* ------------------------------------------------------------------ */
/* Building blocks                                                     */
/* ------------------------------------------------------------------ */

function Message({ state }: { state: ActionState }) {
  if (state.error)
    return (
      <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
        {state.error}
      </p>
    );
  if (state.ok && state.message)
    return (
      <p className="text-sm" role="status" style={{ color: 'var(--color-verified)' }}>
        {state.message}
      </p>
    );
  return null;
}

/**
 * A button that unfolds a small form beneath it. Native <details>, so it
 * works before hydration and needs no open/close state.
 */
function Panel({
  label,
  tone = 'ghost',
  children,
}: {
  label: string;
  tone?: 'ghost' | 'primary' | 'danger';
  children: React.ReactNode;
}) {
  const cls =
    tone === 'primary' ? 'btn btn-primary' : 'btn btn-ghost';
  return (
    <details className="group open:basis-full open:w-full">
      <summary
        className={`${cls} list-none [&::-webkit-details-marker]:hidden select-none`}
        style={tone === 'danger' ? { color: 'var(--color-danger)' } : undefined}
      >
        {label}
      </summary>
      <div className="card surface p-4 mt-2 space-y-4">{children}</div>
    </details>
  );
}

/** datetime-local is wall-clock time in the browser; send an absolute instant. */
function withInstant(fd: FormData) {
  const local = String(fd.get('scheduled_at') ?? '');
  if (local) {
    const d = new Date(local);
    if (!Number.isNaN(d.getTime())) fd.set('scheduled_at_iso', d.toISOString());
  }
  try {
    fd.set('timezone', Intl.DateTimeFormat().resolvedOptions().timeZone);
  } catch {
    /* older browsers: timezone stays unset */
  }
  return fd;
}

/* ------------------------------------------------------------------ */
/* Scoring                                                             */
/* ------------------------------------------------------------------ */

export function RescoreButton({
  jobId,
  label = 'Re-score',
  primary = false,
}: {
  jobId: string;
  label?: string;
  primary?: boolean;
}) {
  const [state, action, pending] = useActionState<ActionState, FormData>(rankApplicants, {});
  return (
    <form action={action} className="inline-flex flex-col gap-1 items-start">
      <input type="hidden" name="job_id" value={jobId} />
      <button
        className={primary ? 'btn btn-primary' : 'btn btn-ghost !h-9 !px-3 text-sm'}
        disabled={pending}
      >
        {pending ? 'Scoring…' : label}
      </button>
      <Message state={state} />
    </form>
  );
}

/* ------------------------------------------------------------------ */
/* Pipeline moves                                                      */
/* ------------------------------------------------------------------ */

export function MoveButton({
  applicationId,
  state: target,
  label,
  primary = false,
}: {
  applicationId: string;
  state: string;
  label: string;
  primary?: boolean;
}) {
  const [state, action, pending] = useActionState<ActionState, FormData>(moveApplication, {});
  return (
    <form action={action} className="contents">
      <input type="hidden" name="application_id" value={applicationId} />
      <input type="hidden" name="state" value={target} />
      <button className={primary ? 'btn btn-primary' : 'btn btn-ghost'} disabled={pending}>
        {pending ? 'Saving…' : label}
      </button>
      {state.error && (
        <p className="text-sm basis-full" role="alert" style={{ color: 'var(--color-danger)' }}>
          {state.error}
        </p>
      )}
    </form>
  );
}

export function RejectForm({ applicationId }: { applicationId: string }) {
  const [state, action, pending] = useActionState<ActionState, FormData>(rejectApplication, {});
  const [preset, setPreset] = useState('');

  return (
    <Panel label="Not moving forward" tone="danger">
      <form action={action} className="space-y-4">
        <input type="hidden" name="application_id" value={applicationId} />
        <fieldset>
          <legend className="label">Reason</legend>
          <div className="space-y-2">
            {REJECTION_REASONS.map((r) => (
              <label key={r} className="flex items-start gap-2 text-sm">
                <input
                  type="radio"
                  name="reason_preset"
                  value={r}
                  className="mt-1"
                  onChange={() => setPreset(r)}
                  required
                />
                <span>{r}</span>
              </label>
            ))}
            <label className="flex items-start gap-2 text-sm">
              <input
                type="radio"
                name="reason_preset"
                value="other"
                className="mt-1"
                onChange={() => setPreset('other')}
              />
              <span>Other…</span>
            </label>
          </div>
        </fieldset>
        {preset === 'other' && (
          <div>
            <label className="label" htmlFor="reason_other">
              Your reason
            </label>
            <textarea
              id="reason_other"
              name="reason_other"
              rows={2}
              minLength={3}
              maxLength={300}
              required
              className="input"
              placeholder="Be kind and specific — e.g. We need someone who can start this week."
            />
          </div>
        )}
        <p className="hint !mt-0">
          <strong>The candidate will see this reason.</strong> Any scheduled
          interview is cancelled and any open offer is withdrawn.
        </p>
        <Message state={state} />
        <button
          className="btn btn-primary w-full sm:w-auto"
          style={{ background: 'var(--color-danger)' }}
          disabled={pending}
        >
          {pending ? 'Saving…' : 'Confirm — not moving forward'}
        </button>
      </form>
    </Panel>
  );
}

/* ------------------------------------------------------------------ */
/* Interviews                                                          */
/* ------------------------------------------------------------------ */

const REMOTE_TYPES: InterviewType[] = ['phone', 'video'];

export function ScheduleInterviewForm({
  applicationId,
  defaultLocation,
  primary = false,
}: {
  applicationId: string;
  defaultLocation: string | null;
  primary?: boolean;
}) {
  const [state, action, pending] = useActionState<ActionState, FormData>(scheduleInterview, {});
  const [type, setType] = useState<InterviewType>('in_person');
  const remote = REMOTE_TYPES.includes(type);

  return (
    <Panel label="Schedule interview" tone={primary ? 'primary' : 'ghost'}>
      <form action={(fd) => action(withInstant(fd))} className="space-y-4">
        <input type="hidden" name="application_id" value={applicationId} />
        <div className="grid sm:grid-cols-2 gap-4">
          <div>
            <label className="label" htmlFor="iv_type">
              Type
            </label>
            <select
              id="iv_type"
              name="type"
              className="input"
              value={type}
              onChange={(e) => setType(e.target.value as InterviewType)}
            >
              {Object.entries(INTERVIEW_TYPE_LABEL).map(([v, l]) => (
                <option key={v} value={v}>
                  {l}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="label" htmlFor="iv_duration">
              Duration
            </label>
            <select id="iv_duration" name="duration_minutes" className="input" defaultValue="30">
              {[15, 30, 45, 60, 90, 120, 240, 480].map((m) => (
                <option key={m} value={m}>
                  {m < 60 ? `${m} min` : `${m / 60} hour${m === 60 ? '' : 's'}`}
                </option>
              ))}
            </select>
          </div>
        </div>
        <div>
          <label className="label" htmlFor="iv_at">
            Date and time
          </label>
          <input id="iv_at" type="datetime-local" name="scheduled_at" className="input" required />
          <p className="hint">In your local time.</p>
        </div>
        {remote ? (
          <div>
            <label className="label" htmlFor="iv_url">
              {type === 'phone' ? 'Phone number or call link (optional)' : 'Meeting link'}
            </label>
            <input id="iv_url" name="meeting_url" className="input" placeholder="https://" />
          </div>
        ) : (
          <div>
            <label className="label" htmlFor="iv_loc">
              Address
            </label>
            <input
              id="iv_loc"
              name="location_text"
              className="input"
              defaultValue={defaultLocation ?? ''}
              placeholder="Where should the candidate come?"
            />
          </div>
        )}
        <div>
          <label className="label" htmlFor="iv_instr">
            Instructions for the candidate (optional)
          </label>
          <textarea
            id="iv_instr"
            name="instructions"
            rows={2}
            className="input"
            placeholder="What to bring, who to ask for, what to wear…"
          />
        </div>
        <Message state={state} />
        <button className="btn btn-primary w-full sm:w-auto" disabled={pending}>
          {pending ? 'Scheduling…' : 'Send invitation'}
        </button>
      </form>
    </Panel>
  );
}

export function RescheduleForm({ interviewId }: { interviewId: string }) {
  const [state, action, pending] = useActionState<ActionState, FormData>(rescheduleInterview, {});
  return (
    <Panel label="Reschedule">
      <form action={(fd) => action(withInstant(fd))} className="space-y-4">
        <input type="hidden" name="interview_id" value={interviewId} />
        <div>
          <label className="label" htmlFor={`rs_at_${interviewId}`}>
            New date and time
          </label>
          <input
            id={`rs_at_${interviewId}`}
            type="datetime-local"
            name="scheduled_at"
            className="input"
            required
          />
        </div>
        <div>
          <label className="label" htmlFor={`rs_reason_${interviewId}`}>
            Reason (optional, shown to the candidate)
          </label>
          <input id={`rs_reason_${interviewId}`} name="reason" className="input" />
        </div>
        <Message state={state} />
        <button className="btn btn-primary w-full sm:w-auto" disabled={pending}>
          {pending ? 'Saving…' : 'Reschedule'}
        </button>
      </form>
    </Panel>
  );
}

export function CancelInterviewForm({ interviewId }: { interviewId: string }) {
  const [state, action, pending] = useActionState<ActionState, FormData>(cancelInterview, {});
  return (
    <Panel label="Cancel" tone="danger">
      <form action={action} className="space-y-4">
        <input type="hidden" name="interview_id" value={interviewId} />
        <div>
          <label className="label" htmlFor={`cx_${interviewId}`}>
            Reason
          </label>
          <input
            id={`cx_${interviewId}`}
            name="reason"
            className="input"
            minLength={3}
            required
            placeholder="e.g. The interviewer is unwell — we will send a new time"
          />
          <p className="hint">The candidate will see this reason.</p>
        </div>
        <Message state={state} />
        <button className="btn btn-primary w-full sm:w-auto" disabled={pending}>
          {pending ? 'Cancelling…' : 'Cancel interview'}
        </button>
      </form>
    </Panel>
  );
}

export function CompleteInterviewForm({ interviewId }: { interviewId: string }) {
  const [state, action, pending] = useActionState<ActionState, FormData>(completeInterview, {});
  const [outcome, setOutcome] = useState('completed');
  return (
    <Panel label="Record outcome" tone="primary">
      <form action={action} className="space-y-4">
        <input type="hidden" name="interview_id" value={interviewId} />
        <div>
          <label className="label" htmlFor={`oc_${interviewId}`}>
            What happened?
          </label>
          <select
            id={`oc_${interviewId}`}
            name="outcome"
            className="input"
            value={outcome}
            onChange={(e) => setOutcome(e.target.value)}
          >
            <option value="completed">Interview took place</option>
            <option value="no_show_candidate">Candidate did not attend</option>
            <option value="no_show_employer">Our team could not attend</option>
          </select>
        </div>
        {outcome === 'completed' && (
          <>
            <fieldset>
              <legend className="label">Rating</legend>
              <div className="flex flex-wrap gap-3">
                {[1, 2, 3, 4, 5].map((n) => (
                  <label key={n} className="flex items-center gap-1.5 text-sm">
                    <input type="radio" name="rating" value={n} /> {n}
                  </label>
                ))}
              </div>
            </fieldset>
            <fieldset>
              <legend className="label">Recommendation</legend>
              <div className="flex flex-wrap gap-3">
                {RECOMMENDATIONS.map((r) => (
                  <label key={r.value} className="flex items-center gap-1.5 text-sm">
                    <input type="radio" name="recommendation" value={r.value} /> {r.label}
                  </label>
                ))}
              </div>
            </fieldset>
          </>
        )}
        <div>
          <label className="label" htmlFor={`on_${interviewId}`}>
            Notes
          </label>
          <textarea id={`on_${interviewId}`} name="notes" rows={3} className="input" />
          <p className="hint">Private to your team. Saved as a scorecard note.</p>
        </div>
        <Message state={state} />
        <button className="btn btn-primary w-full sm:w-auto" disabled={pending}>
          {pending ? 'Saving…' : 'Save outcome'}
        </button>
      </form>
    </Panel>
  );
}

/* ------------------------------------------------------------------ */
/* Offers                                                              */
/* ------------------------------------------------------------------ */

export function SendOfferForm({
  applicationId,
  defaults,
  primary = false,
}: {
  applicationId: string;
  defaults: {
    title: string;
    payAmount: number | null;
    payPeriod: string | null;
    currency: string | null;
  };
  primary?: boolean;
}) {
  const [state, action, pending] = useActionState<ActionState, FormData>(sendOffer, {});
  return (
    <Panel label="Send offer" tone={primary ? 'primary' : 'ghost'}>
      <form action={action} className="space-y-4">
        <input type="hidden" name="application_id" value={applicationId} />
        <div>
          <label className="label" htmlFor="of_title">
            Job title
          </label>
          <input id="of_title" name="title" className="input" defaultValue={defaults.title} />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="label" htmlFor="of_pay">
              Pay ({defaults.currency ?? 'INR'})
            </label>
            <input
              id="of_pay"
              name="pay_amount"
              type="number"
              min={1}
              step="any"
              inputMode="decimal"
              required
              className="input"
              defaultValue={defaults.payAmount ?? ''}
            />
          </div>
          <div>
            <label className="label" htmlFor="of_period">
              Period
            </label>
            <select
              id="of_period"
              name="pay_period"
              className="input"
              defaultValue={defaults.payPeriod ?? 'month'}
            >
              {PAY_PERIODS.map((p) => (
                <option key={p.value} value={p.value}>
                  {p.label}
                </option>
              ))}
            </select>
          </div>
        </div>
        <div className="grid sm:grid-cols-2 gap-3">
          <div>
            <label className="label" htmlFor="of_start">
              Start date
            </label>
            <input id="of_start" name="start_date" type="date" required className="input" />
          </div>
          <div>
            <label className="label" htmlFor="of_exp">
              Candidate must reply within
            </label>
            <select id="of_exp" name="expires_days" className="input" defaultValue="7">
              <option value="2">2 days</option>
              <option value="3">3 days</option>
              <option value="7">7 days</option>
              <option value="14">14 days</option>
            </select>
          </div>
        </div>
        <div>
          <label className="label" htmlFor="of_cond">
            Conditions (optional)
          </label>
          <textarea
            id="of_cond"
            name="conditions"
            rows={2}
            className="input"
            placeholder="e.g. Subject to document check on the first day"
          />
          <p className="hint">The job&apos;s benefits are included automatically.</p>
        </div>
        <Message state={state} />
        <button className="btn btn-primary w-full sm:w-auto" disabled={pending}>
          {pending ? 'Sending…' : 'Send offer'}
        </button>
      </form>
    </Panel>
  );
}

export function WithdrawOfferForm({ offerId }: { offerId: string }) {
  const [state, action, pending] = useActionState<ActionState, FormData>(withdrawOffer, {});
  return (
    <Panel label="Withdraw offer" tone="danger">
      <form action={action} className="space-y-4">
        <input type="hidden" name="offer_id" value={offerId} />
        <div>
          <label className="label" htmlFor={`wo_${offerId}`}>
            Reason
          </label>
          <input
            id={`wo_${offerId}`}
            name="reason"
            className="input"
            minLength={3}
            required
            placeholder="e.g. The role is no longer available"
          />
          <p className="hint">
            The candidate will see this reason. Their application returns to the
            stage it was in before the offer.
          </p>
        </div>
        <Message state={state} />
        <button className="btn btn-primary w-full sm:w-auto" disabled={pending}>
          {pending ? 'Withdrawing…' : 'Withdraw offer'}
        </button>
      </form>
    </Panel>
  );
}

/* ------------------------------------------------------------------ */
/* Notes                                                               */
/* ------------------------------------------------------------------ */

export function NoteForm({ applicationId }: { applicationId: string }) {
  const [state, action, pending] = useActionState<ActionState, FormData>(addNote, {});
  return (
    <form action={action} className="space-y-2">
      <input type="hidden" name="application_id" value={applicationId} />
      <label className="sr-only" htmlFor="note_body">
        Add a note
      </label>
      <textarea
        id="note_body"
        name="body"
        rows={3}
        required
        className="input"
        placeholder="Only your team can see notes."
      />
      <Message state={state} />
      <button className="btn btn-ghost" disabled={pending}>
        {pending ? 'Saving…' : 'Add note'}
      </button>
    </form>
  );
}
