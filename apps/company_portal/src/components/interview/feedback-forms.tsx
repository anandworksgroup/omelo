'use client';

import { useId, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import {
  ASSESSMENT_OPTIONS,
  EVALUATION_OPTIONS,
  RECOMMENDATION_OPTIONS,
  type Assessment,
  type Evaluation,
} from '@/lib/meet';
import { useInterviewFeedback, type FeedbackController } from './use-feedback';

/* ------------------------------------------------------------------ */
/* Small pieces                                                        */
/* ------------------------------------------------------------------ */

export function Chips<T extends string>({
  options,
  value,
  onChange,
  label,
  size = 'md',
}: {
  options: { value: T; label: string; tone: string }[];
  value: T | null;
  onChange: (v: T | null) => void;
  label: string;
  size?: 'sm' | 'md';
}) {
  return (
    <div role="radiogroup" aria-label={label} className="flex flex-wrap gap-1.5">
      {options.map((o) => {
        const on = value === o.value;
        return (
          <button
            key={o.value}
            type="button"
            role="radio"
            aria-checked={on}
            onClick={() => onChange(on ? null : o.value)}
            className={`rounded-full border font-semibold transition-colors ${
              size === 'sm' ? 'text-[11px] px-2 py-0.5' : 'text-xs px-2.5 py-1'
            }`}
            style={{
              borderColor: on ? o.tone : 'var(--line)',
              color: on ? o.tone : 'var(--muted)',
              background: on ? 'var(--surface)' : 'transparent',
              boxShadow: on ? `inset 0 0 0 1px ${o.tone}` : undefined,
            }}
          >
            {o.label}
          </button>
        );
      })}
    </div>
  );
}

export function SaveIndicator({ fb }: { fb: FeedbackController }) {
  const s = fb.save;
  const text =
    s.kind === 'saving'
      ? 'Saving…'
      : s.kind === 'dirty'
        ? 'Unsaved changes'
        : s.kind === 'saved'
          ? `${fb.status === 'submitted' ? 'Saved' : 'Draft saved'} · ${new Date(s.at).toLocaleTimeString([], {
              hour: 'numeric',
              minute: '2-digit',
            })}`
          : s.kind === 'error'
            ? s.message
            : fb.status === 'submitted'
              ? 'Submitted'
              : fb.status === 'draft'
                ? 'Draft'
                : 'Not started';
  return (
    <span
      className="text-xs"
      role="status"
      aria-live="polite"
      style={{ color: s.kind === 'error' ? 'var(--color-danger)' : 'var(--muted)' }}
    >
      {text}
    </span>
  );
}

/* ------------------------------------------------------------------ */
/* Questions                                                           */
/* ------------------------------------------------------------------ */

export function QuestionsEvaluator({
  fb,
  interviewId,
  canAddQuestions,
}: {
  fb: FeedbackController;
  interviewId: string;
  canAddQuestions: boolean;
}) {
  const [newQ, setNewQ] = useState('');
  const [adding, setAdding] = useState(false);
  const [addError, setAddError] = useState<string | null>(null);

  async function add() {
    const text = newQ.trim();
    if (text.length < 3) return;
    setAdding(true);
    setAddError(null);
    const supabase = createClient();
    const { error } = await supabase.from('interview_questions').insert({
      interview_id: interviewId,
      position: (fb.questions.at(-1)?.position ?? 0) + 1,
      question: text.slice(0, 500),
      category: 'general',
      source: 'custom',
    });
    setAdding(false);
    if (error) {
      setAddError(error.message);
      return;
    }
    setNewQ('');
    await fb.reloadQuestions();
  }

  if (fb.loading) return <p className="text-sm muted">Loading questions…</p>;

  return (
    <div className="space-y-3">
      {fb.questionsError && (
        <p className="text-sm" style={{ color: 'var(--color-danger)' }}>
          Could not load questions: {fb.questionsError}
        </p>
      )}
      {fb.questions.length === 0 && !fb.questionsError && (
        <p className="text-sm muted">No questions for this interview.</p>
      )}
      <ol className="space-y-3">
        {fb.questions.map((q, i) => {
          const a = fb.draft.answers[q.id] ?? { evaluation: null, notes: '' };
          const setAnswer = (patch: Partial<typeof a>) =>
            fb.change((d) => ({
              answers: { ...d.answers, [q.id]: { ...(d.answers[q.id] ?? { evaluation: null, notes: '' }), ...patch } },
            }));
          return (
            <li key={q.id} className="rounded-lg border hairline p-3 space-y-2">
              <p className="text-sm font-medium break-words">
                <span className="muted">{i + 1}.</span> {q.question}
              </p>
              {q.category && q.category !== 'general' && (
                <span className="pill !text-[10px]">{q.category.replace(/_/g, ' ')}</span>
              )}
              <Chips<Evaluation>
                label={`Evaluation for question ${i + 1}`}
                options={EVALUATION_OPTIONS}
                value={a.evaluation}
                onChange={(v) => setAnswer({ evaluation: v })}
                size="sm"
              />
              <textarea
                className="input !text-sm"
                rows={2}
                value={a.notes}
                placeholder="Notes on their answer"
                aria-label={`Notes for question ${i + 1}`}
                onChange={(e) => setAnswer({ notes: e.target.value })}
              />
            </li>
          );
        })}
      </ol>
      {canAddQuestions && (
        <div className="space-y-1">
          <div className="flex gap-2">
            <input
              className="input flex-1 min-w-0 !text-sm"
              value={newQ}
              onChange={(e) => setNewQ(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.preventDefault();
                  void add();
                }
              }}
              placeholder="Add a question"
              aria-label="Add a question"
            />
            <button type="button" className="btn btn-ghost !h-11 shrink-0" onClick={() => void add()} disabled={adding}>
              {adding ? 'Adding…' : 'Add'}
            </button>
          </div>
          {addError && (
            <p className="text-xs" style={{ color: 'var(--color-danger)' }}>
              {addError}
            </p>
          )}
        </div>
      )}
      <div className="flex justify-end">
        <SaveIndicator fb={fb} />
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Notes & evaluation                                                  */
/* ------------------------------------------------------------------ */

export function EvaluationForm({ fb, onSubmitted }: { fb: FeedbackController; onSubmitted?: () => void }) {
  const uid = useId();
  const [newComp, setNewComp] = useState('');
  const d = fb.draft;

  if (fb.loading) return <p className="text-sm muted">Loading your feedback…</p>;

  const addCompetency = () => {
    const name = newComp.trim();
    if (!name || d.competencies.some((c) => c.name.toLowerCase() === name.toLowerCase())) return;
    fb.change({ competencies: [...d.competencies, { name, assessment: 'not_assessed' }] });
    setNewComp('');
  };

  return (
    <div className="space-y-5">
      {fb.loadError && (
        <p className="text-sm" style={{ color: 'var(--color-danger)' }}>
          Could not load your saved feedback: {fb.loadError}
        </p>
      )}
      <p className="hint !mt-0">
        Private to your hiring team. The candidate never sees feedback. Drafts save automatically.
      </p>

      <div>
        <label className="label" htmlFor={`${uid}st`}>
          Candidate strengths
        </label>
        <textarea
          id={`${uid}st`}
          className="input !text-sm"
          rows={3}
          value={d.strengths}
          onChange={(e) => fb.change({ strengths: e.target.value })}
        />
      </div>
      <div>
        <label className="label" htmlFor={`${uid}co`}>
          Concerns
        </label>
        <textarea
          id={`${uid}co`}
          className="input !text-sm"
          rows={3}
          value={d.concerns}
          onChange={(e) => fb.change({ concerns: e.target.value })}
        />
      </div>

      <fieldset>
        <legend className="label">Skills demonstrated</legend>
        {d.skills.length === 0 ? (
          <p className="text-sm muted">This job lists no skills.</p>
        ) : (
          <ul className="grid grid-cols-1 sm:grid-cols-2 gap-1.5">
            {d.skills.map((s) => (
              <li key={s.name}>
                <label className="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    checked={s.demonstrated}
                    onChange={(e) =>
                      fb.change((cur) => ({
                        skills: cur.skills.map((x) =>
                          x.name === s.name ? { ...x, demonstrated: e.target.checked } : x
                        ),
                      }))
                    }
                  />
                  <span className="break-words min-w-0">{s.name}</span>
                </label>
              </li>
            ))}
          </ul>
        )}
      </fieldset>

      <fieldset>
        <legend className="label">Competencies</legend>
        <ul className="space-y-2.5">
          {d.competencies.map((c) => (
            <li key={c.name} className="space-y-1">
              <div className="flex items-center gap-2">
                <span className="text-sm font-medium flex-1 min-w-0 break-words">{c.name}</span>
                <button
                  type="button"
                  className="text-xs muted hover:opacity-70"
                  aria-label={`Remove ${c.name}`}
                  onClick={() =>
                    fb.change((cur) => ({ competencies: cur.competencies.filter((x) => x.name !== c.name) }))
                  }
                >
                  ✕
                </button>
              </div>
              <Chips<Assessment>
                label={c.name}
                options={ASSESSMENT_OPTIONS}
                value={c.assessment === 'not_assessed' ? null : c.assessment}
                onChange={(v) =>
                  fb.change((cur) => ({
                    competencies: cur.competencies.map((x) =>
                      x.name === c.name ? { ...x, assessment: v ?? 'not_assessed' } : x
                    ),
                  }))
                }
                size="sm"
              />
            </li>
          ))}
        </ul>
        <div className="flex gap-2 mt-2">
          <input
            className="input flex-1 min-w-0 !text-sm"
            value={newComp}
            onChange={(e) => setNewComp(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                e.preventDefault();
                addCompetency();
              }
            }}
            placeholder="Add a competency, e.g. Kubernetes"
            aria-label="Add a competency"
            maxLength={60}
          />
          <button type="button" className="btn btn-ghost !h-11 shrink-0" onClick={addCompetency}>
            Add
          </button>
        </div>
      </fieldset>

      <fieldset>
        <legend className="label">Overall rating</legend>
        <div className="flex gap-1.5">
          {[1, 2, 3, 4, 5].map((n) => (
            <button
              key={n}
              type="button"
              aria-pressed={d.rating === n}
              onClick={() => fb.change({ rating: d.rating === n ? null : n })}
              className="h-9 w-9 rounded-lg border text-sm font-bold"
              style={{
                borderColor: d.rating === n ? 'var(--color-brand-600)' : 'var(--line)',
                background: d.rating === n ? 'var(--color-brand-600)' : 'transparent',
                color: d.rating === n ? '#fff' : 'var(--fg)',
              }}
            >
              {n}
            </button>
          ))}
        </div>
      </fieldset>

      <div>
        <label className="label" htmlFor={`${uid}no`}>
          Private notes
        </label>
        <textarea
          id={`${uid}no`}
          className="input !text-sm"
          rows={3}
          value={d.notes}
          onChange={(e) => fb.change({ notes: e.target.value })}
        />
      </div>

      <fieldset>
        <legend className="label">Recommendation</legend>
        <div className="grid grid-cols-2 gap-2">
          {RECOMMENDATION_OPTIONS.map((r) => (
            <label
              key={r.value}
              className="flex items-center gap-2 text-sm rounded-lg border px-3 py-2 cursor-pointer"
              style={{ borderColor: d.recommendation === r.value ? r.tone : 'var(--line)' }}
            >
              <input
                type="radio"
                name={`${uid}rec`}
                checked={d.recommendation === r.value}
                onChange={() => fb.change({ recommendation: r.value })}
              />
              <span className="font-medium" style={{ color: d.recommendation === r.value ? r.tone : undefined }}>
                {r.label}
              </span>
            </label>
          ))}
        </div>
      </fieldset>

      <div className="flex items-center gap-2 flex-wrap">
        <button type="button" className="btn btn-ghost" onClick={() => void fb.saveNow()} disabled={fb.save.kind === 'saving'}>
          Save draft
        </button>
        <button
          type="button"
          className="btn btn-primary"
          onClick={async () => {
            if ((await fb.submit()) && onSubmitted) onSubmitted();
          }}
          disabled={fb.save.kind === 'saving' || !d.recommendation}
          title={!d.recommendation ? 'Choose a recommendation first' : undefined}
        >
          {fb.status === 'submitted' ? 'Update feedback' : 'Submit feedback'}
        </button>
        <SaveIndicator fb={fb} />
      </div>
      {fb.status === 'submitted' && (
        <p className="text-xs" style={{ color: 'var(--color-verified)' }}>
          ✓ Feedback submitted. You can still edit it; changes save automatically.
        </p>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Candidate page: questions + evaluation after the interview         */
/* ------------------------------------------------------------------ */

export function FeedbackEditor({
  interviewId,
  jobId,
  canAddQuestions,
}: {
  interviewId: string;
  jobId: string;
  canAddQuestions: boolean;
}) {
  const fb = useInterviewFeedback(interviewId, jobId);
  const router = useRouter();
  const [tab, setTab] = useState<'evaluation' | 'questions'>('evaluation');
  return (
    <div className="space-y-4">
      <div className="flex gap-1 border-b hairline" role="tablist">
        {(
          [
            ['evaluation', 'Notes & evaluation'],
            ['questions', `Questions${fb.questions.length ? ` (${fb.questions.length})` : ''}`],
          ] as const
        ).map(([k, l]) => (
          <button
            key={k}
            type="button"
            role="tab"
            aria-selected={tab === k}
            onClick={() => setTab(k)}
            className="px-3 py-2 text-sm font-semibold -mb-px border-b-2"
            style={{
              borderColor: tab === k ? 'var(--color-brand-600)' : 'transparent',
              color: tab === k ? 'var(--fg)' : 'var(--muted)',
            }}
          >
            {l}
          </button>
        ))}
      </div>
      {tab === 'evaluation' ? (
        <EvaluationForm fb={fb} onSubmitted={() => router.refresh()} />
      ) : (
        <QuestionsEvaluator fb={fb} interviewId={interviewId} canAddQuestions={canAddQuestions} />
      )}
    </div>
  );
}
