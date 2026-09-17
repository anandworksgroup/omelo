'use client';

import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import {
  DURATIONS,
  MEETING_MODE_LABEL,
  ROUND_KINDS,
  ROUND_PRESETS,
  meetingModeLabel,
  roundKindLabel,
  type MeetingMode,
  type PlannedRound,
} from '@/lib/meet';
import { saveInterviewRounds } from './rounds-actions';

type Row = {
  key: string;
  id?: string;
  name: string;
  kind: string;
  meeting_mode: string;
  duration_minutes: number;
};

let seq = 0;
const key = () => `r${++seq}`;

const toRows = (rounds: PlannedRound[]): Row[] =>
  [...rounds]
    .sort((a, b) => a.position - b.position)
    .map((r) => ({
      key: key(),
      id: r.id,
      name: r.name,
      kind: r.kind,
      meeting_mode: r.meeting_mode,
      duration_minutes: r.duration_minutes,
    }));

/** "Interview process" editor for a job: Technical → System Design → Hiring Manager → Final. */
export default function RoundsEditor({
  jobId,
  rounds,
  canEdit,
}: {
  jobId: string;
  rounds: PlannedRound[];
  canEdit: boolean;
}) {
  const router = useRouter();
  const [editing, setEditing] = useState(false);
  const [rows, setRows] = useState<Row[]>(() => toRows(rounds));
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [pending, start] = useTransition();

  const update = (k: string, patch: Partial<Row>) =>
    setRows((rs) => rs.map((r) => (r.key === k ? { ...r, ...patch } : r)));

  const move = (i: number, dir: -1 | 1) =>
    setRows((rs) => {
      const j = i + dir;
      if (j < 0 || j >= rs.length) return rs;
      const c = [...rs];
      [c[i], c[j]] = [c[j], c[i]];
      return c;
    });

  function add(preset?: (typeof ROUND_PRESETS)[number]) {
    setRows((rs) => [
      ...rs,
      {
        key: key(),
        name: preset?.name ?? '',
        kind: preset?.kind ?? 'general',
        meeting_mode: preset?.mode ?? 'omelo_meet',
        duration_minutes: preset?.duration ?? 30,
      },
    ]);
  }

  function save() {
    setError(null);
    start(async () => {
      const res = await saveInterviewRounds(
        jobId,
        rows.map(({ id, name, kind, meeting_mode, duration_minutes }) => ({
          id,
          name,
          kind,
          meeting_mode,
          duration_minutes,
        }))
      );
      if (res.error) {
        setError(res.error);
        return;
      }
      setSaved(true);
      setEditing(false);
      router.refresh();
    });
  }

  const sorted = [...rounds].sort((a, b) => a.position - b.position);

  return (
    <section className="card p-5">
      <div className="flex items-center gap-3 flex-wrap mb-1">
        <h2 className="font-bold flex-1 min-w-0">Interview process</h2>
        {canEdit && !editing && (
          <button
            className="btn btn-ghost !h-9 !px-3 text-sm"
            onClick={() => {
              setRows(toRows(rounds));
              setSaved(false);
              setEditing(true);
            }}
          >
            {sorted.length ? 'Edit' : 'Plan rounds'}
          </button>
        )}
      </div>
      <p className="text-sm muted mb-4 leading-relaxed">
        The rounds you plan here prefill each &quot;Schedule Interview&quot; and show
        applicants what comes next.
      </p>

      {!editing ? (
        sorted.length === 0 ? (
          <p className="text-sm muted">No rounds planned. Interviews default to a 30 minute Omelo Meet call.</p>
        ) : (
          <ol className="flex flex-wrap items-center gap-2 text-sm">
            {sorted.map((r, i) => (
              <li key={r.id} className="flex items-center gap-2">
                <span className="pill !text-[var(--fg)]">
                  {r.position}. {r.name}
                  <span className="muted font-normal">
                    · {meetingModeLabel(r.meeting_mode)} · {r.duration_minutes} min
                  </span>
                </span>
                {i < sorted.length - 1 && (
                  <span aria-hidden className="muted">
                    →
                  </span>
                )}
              </li>
            ))}
          </ol>
        )
      ) : (
        <div className="space-y-3">
          {rows.length === 0 && <p className="text-sm muted">No rounds yet. Add one below.</p>}
          <ol className="space-y-3">
            {rows.map((r, i) => (
              <li key={r.key} className="surface rounded-lg p-3 space-y-2">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-bold w-6 shrink-0">{i + 1}.</span>
                  <input
                    className="input flex-1 min-w-0"
                    value={r.name}
                    maxLength={80}
                    onChange={(e) => update(r.key, { name: e.target.value })}
                    placeholder="Round name"
                    aria-label={`Round ${i + 1} name`}
                  />
                  <div className="flex shrink-0">
                    <button
                      type="button"
                      className="px-2 py-2 text-xs muted disabled:opacity-30"
                      onClick={() => move(i, -1)}
                      disabled={i === 0}
                      aria-label="Move up"
                    >
                      ▲
                    </button>
                    <button
                      type="button"
                      className="px-2 py-2 text-xs muted disabled:opacity-30"
                      onClick={() => move(i, 1)}
                      disabled={i === rows.length - 1}
                      aria-label="Move down"
                    >
                      ▼
                    </button>
                    <button
                      type="button"
                      className="px-2 py-2 text-xs"
                      style={{ color: 'var(--color-danger)' }}
                      onClick={() => setRows((rs) => rs.filter((x) => x.key !== r.key))}
                      aria-label="Remove round"
                    >
                      ✕
                    </button>
                  </div>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-2 sm:pl-8">
                  <select
                    className="input"
                    value={r.kind}
                    onChange={(e) => update(r.key, { kind: e.target.value })}
                    aria-label="Kind"
                  >
                    {ROUND_KINDS.map((k) => (
                      <option key={k.value} value={k.value}>
                        {k.label}
                      </option>
                    ))}
                  </select>
                  <select
                    className="input"
                    value={r.meeting_mode}
                    onChange={(e) => update(r.key, { meeting_mode: e.target.value })}
                    aria-label="Format"
                  >
                    {(Object.keys(MEETING_MODE_LABEL) as MeetingMode[]).map((m) => (
                      <option key={m} value={m}>
                        {MEETING_MODE_LABEL[m]}
                      </option>
                    ))}
                  </select>
                  <select
                    className="input"
                    value={r.duration_minutes}
                    onChange={(e) => update(r.key, { duration_minutes: Number(e.target.value) })}
                    aria-label="Duration"
                  >
                    {[...new Set([...DURATIONS, r.duration_minutes])]
                      .sort((a, b) => a - b)
                      .map((m) => (
                        <option key={m} value={m}>
                          {m} min
                        </option>
                      ))}
                  </select>
                </div>
              </li>
            ))}
          </ol>

          {rows.length < 10 && (
            <div className="flex flex-wrap gap-2 items-center">
              <span className="text-xs muted">Add:</span>
              {ROUND_PRESETS.map((p) => (
                <button
                  key={p.name}
                  type="button"
                  className="pill hover:opacity-70"
                  onClick={() => add(p)}
                  title={roundKindLabel(p.kind)}
                >
                  + {p.name}
                </button>
              ))}
              <button type="button" className="pill hover:opacity-70" onClick={() => add()}>
                + Custom
              </button>
            </div>
          )}

          {error && (
            <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
              {error}
            </p>
          )}
          <div className="flex gap-2 flex-wrap">
            <button className="btn btn-primary" onClick={save} disabled={pending}>
              {pending ? 'Saving…' : 'Save process'}
            </button>
            <button className="btn btn-ghost" onClick={() => setEditing(false)} disabled={pending}>
              Cancel
            </button>
          </div>
        </div>
      )}
      {saved && !editing && (
        <p className="text-sm mt-3" role="status" style={{ color: 'var(--color-verified)' }}>
          Interview process saved.
        </p>
      )}
    </section>
  );
}
