'use client';

import { useActionState, useId, useRef, useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import type { ActionState } from '../actions';
import { scheduleInterview } from './actions';
import { Message, Panel } from './forms';
import {
  DURATIONS,
  MEETING_MODE_LABEL,
  ROUND_KINDS,
  ROUND_PRESETS,
  type MeetingMode,
  type PlannedRound,
  type RoundKind,
} from '@/lib/meet';

export type TeamMember = {
  personId: string;
  role: string;
  name: string | null;
  isYou: boolean;
};

type Q = { key: string; question: string; category: string; template_id?: string };

const CUSTOM = '__custom__';
let keySeq = 0;
const nextKey = () => `q${++keySeq}`;

const ROLE_LABEL: Record<string, string> = {
  owner: 'Owner',
  admin: 'Admin',
  recruiter: 'Recruiter',
  hiring_manager: 'Hiring manager',
  interviewer: 'Interviewer',
  hr: 'HR',
};

/**
 * Schedule an interview round. Everything the employer leaves out falls
 * back to the job's planned round inside omelo_schedule_interview.
 */
export function ScheduleInterviewForm({
  applicationId,
  jobId,
  defaultLocation,
  plannedRounds,
  nextRound,
  team,
  label = 'Schedule Interview',
  defaultRoundName,
  primary = false,
}: {
  applicationId: string;
  jobId: string;
  defaultLocation: string | null;
  plannedRounds: PlannedRound[];
  /** 1-based number of the round this would create. */
  nextRound: number;
  team: TeamMember[];
  label?: string;
  defaultRoundName?: string | null;
  primary?: boolean;
}) {
  const uid = useId();
  const [state, action, pending] = useActionState<ActionState, FormData>(scheduleInterview, {});

  const planned = plannedRounds.find((r) => r.position === nextRound) ?? null;

  const nameOptions: { name: string; kind: RoundKind; mode?: MeetingMode; duration?: number; planned: number | null }[] = [
    ...plannedRounds.map((r) => ({
      name: r.name,
      kind: r.kind as RoundKind,
      mode: r.meeting_mode as MeetingMode,
      duration: r.duration_minutes,
      planned: r.position,
    })),
    ...ROUND_PRESETS.filter((p) => !plannedRounds.some((r) => r.name === p.name)).map((p) => ({
      ...p,
      planned: null,
    })),
  ];

  const initialName = defaultRoundName ?? planned?.name ?? ROUND_PRESETS[0].name;
  const initialOpt = nameOptions.find((o) => o.name === initialName) ?? null;

  const [nameChoice, setNameChoice] = useState<string>(initialOpt ? initialOpt.name : CUSTOM);
  const [customName, setCustomName] = useState(initialOpt ? '' : initialName);
  const [kind, setKind] = useState<RoundKind>(initialOpt?.kind ?? 'general');
  const [mode, setMode] = useState<MeetingMode>(initialOpt?.mode ?? 'omelo_meet');
  const [duration, setDuration] = useState<number>(initialOpt?.duration ?? 30);
  const [interviewers, setInterviewers] = useState<string[]>(
    team.filter((m) => m.isYou).map((m) => m.personId)
  );

  const [questions, setQuestions] = useState<Q[]>([]);
  const [questionsTouched, setQuestionsTouched] = useState(false);
  const [questionsState, setQuestionsState] = useState<'idle' | 'loading' | 'error'>('idle');
  const [newQuestion, setNewQuestion] = useState('');
  const loadedKind = useRef<string | null>(null);

  async function loadSuggestions(forKind: RoundKind, force = false) {
    if (!force && (questionsTouched || loadedKind.current === forKind)) return;
    loadedKind.current = forKind;
    setQuestionsState('loading');
    const supabase = createClient();
    const { data, error } = await supabase.rpc('omelo_interview_question_suggestions', {
      p_job_id: jobId,
      p_round_kind: forKind,
    });
    if (error) {
      setQuestionsState('error');
      return;
    }
    setQuestions(
      (data ?? []).slice(0, 8).map((q) => ({
        key: nextKey(),
        question: q.question,
        category: q.category,
        template_id: q.id,
      }))
    );
    setQuestionsState('idle');
  }

  function chooseName(value: string) {
    setNameChoice(value);
    const opt = nameOptions.find((o) => o.name === value);
    if (!opt) return;
    setKind(opt.kind);
    if (opt.mode) setMode(opt.mode);
    if (opt.duration) setDuration(opt.duration);
    void loadSuggestions(opt.kind);
  }

  function chooseKind(value: RoundKind) {
    setKind(value);
    void loadSuggestions(value);
  }

  function editQuestion(key: string, text: string) {
    setQuestionsTouched(true);
    // An edited template question becomes the employer's own.
    setQuestions((qs) => qs.map((q) => (q.key === key ? { ...q, question: text, template_id: undefined } : q)));
  }

  function removeQuestion(key: string) {
    setQuestionsTouched(true);
    setQuestions((qs) => qs.filter((q) => q.key !== key));
  }

  function moveQuestion(key: string, dir: -1 | 1) {
    setQuestionsTouched(true);
    setQuestions((qs) => {
      const i = qs.findIndex((q) => q.key === key);
      const j = i + dir;
      if (i < 0 || j < 0 || j >= qs.length) return qs;
      const copy = [...qs];
      [copy[i], copy[j]] = [copy[j], copy[i]];
      return copy;
    });
  }

  function addQuestion() {
    const text = newQuestion.trim();
    if (text.length < 3) return;
    setQuestionsTouched(true);
    setQuestions((qs) => [...qs, { key: nextKey(), question: text, category: 'general' }]);
    setNewQuestion('');
  }

  function submit(fd: FormData) {
    const date = String(fd.get('date') ?? '');
    const time = String(fd.get('time') ?? '');
    if (date && time) {
      const d = new Date(`${date}T${time}`);
      if (!Number.isNaN(d.getTime())) fd.set('scheduled_at_iso', d.toISOString());
    }
    try {
      fd.set('timezone', Intl.DateTimeFormat().resolvedOptions().timeZone);
    } catch {
      /* timezone stays unset */
    }
    fd.set('round_name', nameChoice === CUSTOM ? customName.trim() : nameChoice);
    fd.set(
      'questions_json',
      JSON.stringify(
        questions.map((q) => ({
          question: q.question,
          category: q.category,
          ...(q.template_id ? { template_id: q.template_id } : {}),
        }))
      )
    );
    return action(fd);
  }

  const toggleInterviewer = (id: string) =>
    setInterviewers((cur) => (cur.includes(id) ? cur.filter((x) => x !== id) : [...cur, id]));

  return (
    <Panel label={label} tone={primary ? 'primary' : 'ghost'} onOpen={() => void loadSuggestions(kind)}>
      <form action={submit} className="space-y-5">
        <input type="hidden" name="application_id" value={applicationId} />
        <p className="text-sm muted !mt-0">
          This will be interview #{nextRound} for this candidate.
          {planned ? ` Your plan for this job says: ${planned.name}.` : ''}
        </p>

        {/* ---- Interview type */}
        <div className="grid sm:grid-cols-2 gap-4">
          <div>
            <label className="label" htmlFor={`${uid}name`}>
              Interview type
            </label>
            <select
              id={`${uid}name`}
              className="input"
              value={nameChoice}
              onChange={(e) => chooseName(e.target.value)}
            >
              {plannedRounds.length > 0 && (
                <optgroup label="This job's interview process">
                  {nameOptions
                    .filter((o) => o.planned != null)
                    .map((o) => (
                      <option key={`p-${o.name}`} value={o.name}>
                        {o.planned}. {o.name}
                      </option>
                    ))}
                </optgroup>
              )}
              <optgroup label="Common">
                {nameOptions
                  .filter((o) => o.planned == null)
                  .map((o) => (
                    <option key={`c-${o.name}`} value={o.name}>
                      {o.name}
                    </option>
                  ))}
              </optgroup>
              <option value={CUSTOM}>Custom…</option>
            </select>
          </div>
          <div>
            <label className="label" htmlFor={`${uid}kind`}>
              Kind of round
            </label>
            <select
              id={`${uid}kind`}
              name="round_kind"
              className="input"
              value={kind}
              onChange={(e) => chooseKind(e.target.value as RoundKind)}
            >
              {ROUND_KINDS.map((k) => (
                <option key={k.value} value={k.value}>
                  {k.label}
                </option>
              ))}
            </select>
          </div>
        </div>
        {nameChoice === CUSTOM && (
          <div>
            <label className="label" htmlFor={`${uid}custom`}>
              Round name
            </label>
            <input
              id={`${uid}custom`}
              className="input"
              value={customName}
              onChange={(e) => setCustomName(e.target.value)}
              minLength={2}
              maxLength={80}
              required
              placeholder="e.g. Kitchen trial, Portfolio review"
            />
          </div>
        )}

        {/* ---- Format */}
        <fieldset>
          <legend className="label">Format</legend>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-2">
            {(Object.keys(MEETING_MODE_LABEL) as MeetingMode[]).map((m) => (
              <label
                key={m}
                className="flex items-center gap-2 text-sm rounded-lg border px-3 py-2.5 cursor-pointer"
                style={{
                  borderColor: mode === m ? 'var(--color-brand-600)' : 'var(--line)',
                  background: mode === m ? 'var(--bg)' : 'transparent',
                }}
              >
                <input
                  type="radio"
                  name="meeting_mode"
                  value={m}
                  checked={mode === m}
                  onChange={() => setMode(m)}
                />
                <span className="font-medium">
                  {MEETING_MODE_LABEL[m]}
                  {m === 'omelo_meet' && <span className="muted font-normal"> · default</span>}
                </span>
              </label>
            ))}
          </div>
          {mode === 'omelo_meet' && (
            <p className="hint">
              The candidate joins inside Omelo — no outside links. The room opens 15 minutes
              before the start, and your team admits the candidate from the waiting room.
            </p>
          )}
        </fieldset>
        {mode === 'in_person' && (
          <div>
            <label className="label" htmlFor={`${uid}loc`}>
              Address
            </label>
            <input
              id={`${uid}loc`}
              name="location_text"
              className="input"
              defaultValue={defaultLocation ?? ''}
              required
              placeholder="Where should the candidate come?"
            />
          </div>
        )}
        {mode === 'phone' && (
          <div>
            <label className="label" htmlFor={`${uid}phone`}>
              Call details (optional)
            </label>
            <input
              id={`${uid}phone`}
              name="location_text"
              className="input"
              placeholder="e.g. We will call the number on your Omelo profile"
            />
          </div>
        )}

        {/* ---- When */}
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
          <div>
            <label className="label" htmlFor={`${uid}date`}>
              Date
            </label>
            <input id={`${uid}date`} type="date" name="date" className="input" required />
          </div>
          <div>
            <label className="label" htmlFor={`${uid}time`}>
              Time
            </label>
            <input id={`${uid}time`} type="time" name="time" className="input" required />
          </div>
          <div className="col-span-2 sm:col-span-1">
            <label className="label" htmlFor={`${uid}dur`}>
              Duration
            </label>
            <select
              id={`${uid}dur`}
              name="duration_minutes"
              className="input"
              value={duration}
              onChange={(e) => setDuration(Number(e.target.value))}
            >
              {[...new Set([...DURATIONS, duration])]
                .sort((a, b) => a - b)
                .map((m) => (
                  <option key={m} value={m}>
                    {m} min
                  </option>
                ))}
            </select>
          </div>
        </div>
        <p className="hint !-mt-3">In your local time.</p>

        {/* ---- Interviewers */}
        <fieldset>
          <legend className="label">Interviewers</legend>
          {team.length === 0 ? (
            <p className="text-sm muted">Could not load your team.</p>
          ) : (
            <div className="grid sm:grid-cols-2 gap-2">
              {team.map((m) => (
                <label
                  key={m.personId}
                  className="flex items-center gap-2 text-sm rounded-lg border hairline px-3 py-2"
                >
                  <input
                    type="checkbox"
                    name="interviewer_ids"
                    value={m.personId}
                    checked={interviewers.includes(m.personId)}
                    onChange={() => toggleInterviewer(m.personId)}
                  />
                  <span className="min-w-0 truncate">
                    {m.isYou ? 'You' : (m.name ?? 'Teammate')}
                    <span className="muted"> · {ROLE_LABEL[m.role] ?? m.role}</span>
                  </span>
                </label>
              ))}
            </div>
          )}
          <p className="hint">
            The first interviewer you pick hosts the room, unless you include yourself.
          </p>
        </fieldset>

        {/* ---- Instructions */}
        <div>
          <label className="label" htmlFor={`${uid}instr`}>
            Instructions for the candidate (optional)
          </label>
          <textarea
            id={`${uid}instr`}
            name="instructions"
            rows={2}
            className="input"
            placeholder={
              mode === 'omelo_meet'
                ? 'e.g. Use a laptop if you can. Have your ID ready.'
                : 'What to bring, who to ask for, what to wear…'
            }
          />
        </div>

        {/* ---- Questions */}
        <fieldset>
          <legend className="label">Questions</legend>
          <p className="hint !mt-0 mb-2">
            Private to your team — the candidate never sees them. Suggested from your
            profession&apos;s question bank; edit freely.
            {questionsTouched && (
              <>
                {' '}
                <button
                  type="button"
                  className="underline"
                  onClick={() => {
                    setQuestionsTouched(false);
                    void loadSuggestions(kind, true);
                  }}
                >
                  Reset to suggestions
                </button>
              </>
            )}
          </p>
          {questionsState === 'loading' ? (
            <p className="text-sm muted">Loading suggestions…</p>
          ) : questionsState === 'error' ? (
            <p className="text-sm" style={{ color: 'var(--color-warn)' }}>
              Could not load suggestions. Add your own, or leave empty to use the question bank.
            </p>
          ) : null}
          <ol className="space-y-2">
            {questions.map((q, i) => (
              <li key={q.key} className="flex items-start gap-2">
                <span className="text-xs muted w-5 pt-3 text-right shrink-0">{i + 1}.</span>
                <textarea
                  aria-label={`Question ${i + 1}`}
                  className="input flex-1 min-w-0"
                  rows={2}
                  value={q.question}
                  maxLength={500}
                  onChange={(e) => editQuestion(q.key, e.target.value)}
                />
                <div className="flex flex-col shrink-0">
                  <button
                    type="button"
                    className="text-xs px-2 py-1 muted hover:opacity-70 disabled:opacity-30"
                    onClick={() => moveQuestion(q.key, -1)}
                    disabled={i === 0}
                    aria-label="Move up"
                  >
                    ▲
                  </button>
                  <button
                    type="button"
                    className="text-xs px-2 py-1 muted hover:opacity-70 disabled:opacity-30"
                    onClick={() => moveQuestion(q.key, 1)}
                    disabled={i === questions.length - 1}
                    aria-label="Move down"
                  >
                    ▼
                  </button>
                  <button
                    type="button"
                    className="text-xs px-2 py-1 hover:opacity-70"
                    style={{ color: 'var(--color-danger)' }}
                    onClick={() => removeQuestion(q.key)}
                    aria-label="Remove question"
                  >
                    ✕
                  </button>
                </div>
              </li>
            ))}
          </ol>
          <div className="flex gap-2 mt-2">
            <input
              className="input flex-1 min-w-0"
              value={newQuestion}
              onChange={(e) => setNewQuestion(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.preventDefault();
                  addQuestion();
                }
              }}
              placeholder="Add your own question"
              aria-label="New question"
            />
            <button type="button" className="btn btn-ghost shrink-0" onClick={addQuestion}>
              Add
            </button>
          </div>
        </fieldset>

        {/* ---- Delivery */}
        <fieldset className="space-y-2">
          <legend className="label">Invitation</legend>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" name="send_email" defaultChecked /> Send email invitation
          </label>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" name="send_notification" defaultChecked /> Send Omelo notification
          </label>
          <label className="flex items-center gap-2 text-sm muted">
            <input type="checkbox" checked disabled readOnly /> Always added to the interview timeline
          </label>
        </fieldset>

        <Message state={state} />
        <button className="btn btn-primary w-full sm:w-auto" disabled={pending}>
          {pending ? 'Sending…' : 'Send Interview Invite'}
        </button>
      </form>
    </Panel>
  );
}
