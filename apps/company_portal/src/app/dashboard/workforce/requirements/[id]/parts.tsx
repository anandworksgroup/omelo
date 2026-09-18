'use client';

import { useRouter } from 'next/navigation';
import { useId, useMemo, useState, useTransition } from 'react';
import { SHIFT_LABEL } from '@/lib/format';
import { PAY_PERIODS } from '@/lib/hiring';
import {
  COMPONENT_KINDS,
  DAY_LABEL,
  PAY_BASES,
  PAY_BASIS_LABEL,
  SHIFT_KINDS,
  daysText,
  money,
  nice,
} from '@/lib/workforce';
import {
  createShift,
  generateShifts,
  offerAssignment,
  removePayComponent,
  saveShiftTemplate,
  savePayComponent,
  startBulkGenerate,
  startBulkOffer,
  type OfferInput,
  type TemplateInput,
} from '../../actions';
import BulkProgress, { type JobState } from '../../bulk-progress';
import { ErrorLine, OkLine } from '../../ui';

const queued = (id: string, kind: string, total: number): JobState => ({
  id,
  kind,
  status: 'queued',
  total,
  processed: 0,
  succeeded: 0,
  failed: 0,
  errors: [],
  createdAt: null,
  finishedAt: null,
});

/* ------------------------------------------------------------------ */
/* Offer to workers                                                    */
/* ------------------------------------------------------------------ */

export type Candidate = {
  identityId: string;
  name: string;
  detail: string;
  /** Already has an open assignment on this requirement. */
  existing: string | null;
};

const EMPTY_OFFER: OfferInput = {
  start_date: '',
  end_date: '',
  pay_rate: '',
  pay_period: '',
  pay_frequency: '',
  employment_type: '',
  title: '',
  supervisor_id: null,
  bill_rate: '',
  bill_period: 'hour',
};

export function OfferPanel({
  requirementId,
  candidates,
  canBill,
  isAgency,
  canManageJobs,
}: {
  requirementId: string;
  candidates: Candidate[];
  canBill: boolean;
  isAgency: boolean;
  canManageJobs: boolean;
}) {
  const uid = useId();
  const router = useRouter();
  const [filter, setFilter] = useState('');
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [terms, setTerms] = useState<OfferInput>(EMPTY_OFFER);
  const [done, setDone] = useState<Record<string, string>>({});
  const [rowError, setRowError] = useState<Record<string, string>>({});
  const [error, setError] = useState<string | null>(null);
  const [job, setJob] = useState<{ state: JobState; labels: Record<number, string> } | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [pending, start] = useTransition();

  const open = candidates.filter((c) => !c.existing && !done[c.identityId]);
  const shown = useMemo(() => {
    const f = filter.trim().toLowerCase();
    return f ? candidates.filter((c) => `${c.name} ${c.detail}`.toLowerCase().includes(f)) : candidates;
  }, [candidates, filter]);
  const set = (k: keyof OfferInput) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) =>
    setTerms((t) => ({ ...t, [k]: e.target.value }));
  const toggle = (id: string) =>
    setPicked((p) => {
      const n = new Set(p);
      if (n.has(id)) n.delete(id);
      else n.add(id);
      return n;
    });

  function offerOne(c: Candidate) {
    setBusy(c.identityId);
    setRowError((r) => ({ ...r, [c.identityId]: '' }));
    start(async () => {
      const res = await offerAssignment(requirementId, c.identityId, terms);
      setBusy(null);
      if (!res.ok) return setRowError((r) => ({ ...r, [c.identityId]: res.error }));
      setDone((d) => ({ ...d, [c.identityId]: res.id }));
      router.refresh();
    });
  }

  function offerBulk() {
    const ids = [...picked].filter((id) => open.some((c) => c.identityId === id));
    if (ids.length === 0) return setError('Choose workers who have not been offered this work yet.');
    setError(null);
    start(async () => {
      const res = await startBulkOffer(requirementId, ids, terms);
      if (!res.ok) return setError(res.error);
      const labels: Record<number, string> = {};
      ids.forEach((id, i) => (labels[i] = candidates.find((c) => c.identityId === id)?.name ?? `Worker ${i + 1}`));
      setJob({ state: queued(res.jobId, 'offer_assignments', ids.length), labels });
      setPicked(new Set());
    });
  }

  if (candidates.length === 0) {
    return (
      <p className="text-sm muted">
        {isAgency
          ? 'Nobody has consented to representation for this job order yet. Ask candidates for consent from Talent Search; only they can be offered this work.'
          : 'No applicants to offer this work to. Link a job and invite people to apply, or find talent.'}
      </p>
    );
  }

  return (
    <div className="space-y-3">
      <details className="surface rounded-lg p-3">
        <summary className="cursor-pointer text-sm font-semibold">Offer terms (optional — defaults come from the requirement)</summary>
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 mt-3">
          <div>
            <label className="label" htmlFor={`${uid}sd`}>
              Start date
            </label>
            <input id={`${uid}sd`} type="date" className="input" value={terms.start_date} onChange={set('start_date')} />
          </div>
          <div>
            <label className="label" htmlFor={`${uid}ed`}>
              End date
            </label>
            <input id={`${uid}ed`} type="date" className="input" value={terms.end_date} onChange={set('end_date')} />
          </div>
          <div>
            <label className="label" htmlFor={`${uid}t`}>
              Title
            </label>
            <input id={`${uid}t`} className="input" maxLength={120} value={terms.title} onChange={set('title')} />
          </div>
          <div className="grid grid-cols-2 gap-2">
            <div>
              <label className="label" htmlFor={`${uid}pr`}>
                Pay rate
              </label>
              <input id={`${uid}pr`} type="number" min={0} step="0.01" className="input" value={terms.pay_rate} onChange={set('pay_rate')} />
            </div>
            <div>
              <label className="label" htmlFor={`${uid}pp`}>
                Per
              </label>
              <select id={`${uid}pp`} className="input" value={terms.pay_period} onChange={set('pay_period')}>
                <option value="">Default</option>
                {PAY_PERIODS.map((p) => (
                  <option key={p.value} value={p.value}>
                    {p.label.replace('per ', '')}
                  </option>
                ))}
              </select>
            </div>
          </div>
          {canBill && (
            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="label" htmlFor={`${uid}br`}>
                  Bill rate to client
                </label>
                <input id={`${uid}br`} type="number" min={0} step="0.01" className="input" value={terms.bill_rate} onChange={set('bill_rate')} />
              </div>
              <div>
                <label className="label" htmlFor={`${uid}bp`}>
                  Per
                </label>
                <select id={`${uid}bp`} className="input" value={terms.bill_period} onChange={set('bill_period')}>
                  {PAY_PERIODS.filter((p) => p.value !== 'per_task').map((p) => (
                    <option key={p.value} value={p.value}>
                      {p.label.replace('per ', '')}
                    </option>
                  ))}
                </select>
              </div>
              <p className="hint col-span-2">The worker never sees the bill rate; the client never sees the worker’s pay.</p>
            </div>
          )}
        </div>
      </details>

      <div className="flex gap-2 flex-wrap items-center">
        <input
          className="input flex-1 min-w-[12rem]"
          placeholder="Filter by name"
          aria-label="Filter candidates"
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
        />
        <button
          type="button"
          className="btn btn-ghost"
          onClick={() =>
            setPicked((p) => (p.size === open.length ? new Set() : new Set(open.map((c) => c.identityId))))
          }
        >
          {picked.size === open.length && open.length > 0 ? 'Clear selection' : `Select all (${open.length})`}
        </button>
        {canManageJobs && (
          <button type="button" className="btn btn-primary" disabled={pending || picked.size === 0} onClick={offerBulk}>
            Offer to {picked.size || '…'} selected
          </button>
        )}
      </div>
      <p className="hint">
        One worker at a time is offered straight away. Offering to several runs as a bulk job in the background (up to
        20,000); each item is checked again, and failures are listed.
      </p>
      <ErrorLine text={error} />
      {job && <BulkProgress initial={job.state} canCancel labelFor={job.labels} />}

      <ul className="divide-y max-h-[32rem] overflow-y-auto" style={{ borderColor: 'var(--line)' }}>
        {shown.map((c) => {
          const already = c.existing ?? (done[c.identityId] ? 'offered' : null);
          return (
            <li key={c.identityId} className="py-2.5 flex items-center gap-3 flex-wrap">
              <input
                type="checkbox"
                className="w-4 h-4 shrink-0"
                aria-label={`Select ${c.name}`}
                disabled={!!already}
                checked={picked.has(c.identityId)}
                onChange={() => toggle(c.identityId)}
              />
              <div className="flex-1 min-w-[10rem]">
                <p className="font-semibold text-sm break-words">{c.name}</p>
                <p className="text-xs muted break-words">{c.detail}</p>
              </div>
              {already ? (
                <span className="pill">{nice(already)}</span>
              ) : (
                <button
                  type="button"
                  className="btn btn-ghost"
                  style={{ height: 34 }}
                  disabled={pending && busy === c.identityId}
                  onClick={() => offerOne(c)}
                >
                  {busy === c.identityId ? 'Offering…' : 'Offer'}
                </button>
              )}
              <ErrorLine text={rowError[c.identityId] || null} />
            </li>
          );
        })}
      </ul>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Shift templates                                                     */
/* ------------------------------------------------------------------ */

export type Template = {
  id: string;
  name: string;
  days: number[];
  start: string;
  end: string;
  breakMinutes: number;
  requiredWorkers: number;
  shiftType: string | null;
  validFrom: string | null;
  validUntil: string | null;
  status: string;
};

function TemplateForm({ requirementId, t, onDone }: { requirementId: string; t: Template | null; onDone: () => void }) {
  const uid = useId();
  const router = useRouter();
  const [v, setV] = useState<TemplateInput>({
    name: t?.name ?? '',
    days_of_week: t?.days ?? [1, 2, 3, 4, 5],
    start_time: t?.start ?? '09:00',
    end_time: t?.end ?? '17:00',
    break_minutes: String(t?.breakMinutes ?? 30),
    required_workers: String(t?.requiredWorkers ?? 1),
    shift_type: t?.shiftType ?? '',
    valid_from: t?.validFrom ?? '',
    valid_until: t?.validUntil ?? '',
    status: t?.status ?? 'active',
  });
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const set = (k: keyof TemplateInput) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) =>
    setV((s) => ({ ...s, [k]: e.target.value }));
  const overnight = v.end_time && v.start_time && v.end_time <= v.start_time;

  return (
    <form
      className="surface rounded-lg p-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-4"
      onSubmit={(e) => {
        e.preventDefault();
        setError(null);
        start(async () => {
          const res = await saveShiftTemplate(requirementId, t?.id ?? null, v);
          if (!res.ok) return setError(res.error);
          router.refresh();
          onDone();
        });
      }}
    >
      <div className="sm:col-span-2">
        <label className="label" htmlFor={`${uid}n`}>
          Name *
        </label>
        <input id={`${uid}n`} className="input" required maxLength={80} value={v.name} onChange={set('name')} placeholder="Night shift" />
      </div>
      <div>
        <label className="label" htmlFor={`${uid}s`}>
          Starts
        </label>
        <input id={`${uid}s`} type="time" className="input" required value={v.start_time} onChange={set('start_time')} />
      </div>
      <div>
        <label className="label" htmlFor={`${uid}e`}>
          Ends
        </label>
        <input id={`${uid}e`} type="time" className="input" required value={v.end_time} onChange={set('end_time')} />
        {overnight && <p className="hint">Ends the next day (overnight).</p>}
      </div>
      <fieldset className="sm:col-span-2 lg:col-span-4">
        <legend className="label">Days *</legend>
        <div className="flex flex-wrap gap-1.5">
          {[1, 2, 3, 4, 5, 6, 7].map((d) => {
            const on = v.days_of_week.includes(d);
            return (
              <button
                key={d}
                type="button"
                aria-pressed={on}
                className="px-3 py-1.5 rounded-lg text-sm font-semibold border hairline"
                style={on ? { background: 'var(--color-brand-600)', color: '#fff', borderColor: 'transparent' } : undefined}
                onClick={() =>
                  setV((s) => ({
                    ...s,
                    days_of_week: on ? s.days_of_week.filter((x) => x !== d) : [...s.days_of_week, d].sort(),
                  }))
                }
              >
                {DAY_LABEL[d]}
              </button>
            );
          })}
        </div>
      </fieldset>
      <div>
        <label className="label" htmlFor={`${uid}b`}>
          Break (min)
        </label>
        <input id={`${uid}b`} type="number" min={0} max={480} className="input" value={v.break_minutes} onChange={set('break_minutes')} />
      </div>
      <div>
        <label className="label" htmlFor={`${uid}r`}>
          Workers needed
        </label>
        <input id={`${uid}r`} type="number" min={1} max={100000} className="input" value={v.required_workers} onChange={set('required_workers')} />
      </div>
      <div>
        <label className="label" htmlFor={`${uid}ty`}>
          Shift type
        </label>
        <select id={`${uid}ty`} className="input" value={v.shift_type} onChange={set('shift_type')}>
          <option value="">—</option>
          {Object.entries(SHIFT_LABEL).map(([k, l]) => (
            <option key={k} value={k}>
              {l}
            </option>
          ))}
        </select>
      </div>
      <div>
        <label className="label" htmlFor={`${uid}st`}>
          Status
        </label>
        <select id={`${uid}st`} className="input" value={v.status} onChange={set('status')}>
          <option value="active">Active</option>
          <option value="archived">Archived</option>
        </select>
      </div>
      <div>
        <label className="label" htmlFor={`${uid}vf`}>
          Valid from
        </label>
        <input id={`${uid}vf`} type="date" className="input" value={v.valid_from} onChange={set('valid_from')} />
      </div>
      <div>
        <label className="label" htmlFor={`${uid}vu`}>
          Valid until
        </label>
        <input id={`${uid}vu`} type="date" className="input" value={v.valid_until} onChange={set('valid_until')} />
      </div>
      <div className="sm:col-span-2 flex gap-2 flex-wrap items-end">
        <button className="btn btn-primary" disabled={pending}>
          {pending ? 'Saving…' : t ? 'Save template' : 'Add template'}
        </button>
        <button type="button" className="btn btn-ghost" onClick={onDone}>
          Cancel
        </button>
      </div>
      <ErrorLine text={error} />
    </form>
  );
}

function GenerateForm({ t, onDone }: { t: Template; onDone: () => void }) {
  const uid = useId();
  const router = useRouter();
  const [from, setFrom] = useState(t.validFrom ?? '');
  const [to, setTo] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [ok, setOk] = useState<string | null>(null);
  const [job, setJob] = useState<JobState | null>(null);
  const [pending, start] = useTransition();
  return (
    <form
      className="surface rounded-lg p-3 flex gap-3 flex-wrap items-end"
      onSubmit={(e) => {
        e.preventDefault();
        setError(null);
        setOk(null);
        start(async () => {
          const res = await generateShifts(t.id, from, to);
          if (!res.ok) return setError(res.error);
          setOk(
            res.count === 0
              ? 'No new shifts: they already exist for these dates (generating again never duplicates).'
              : `${res.count} shift${res.count === 1 ? '' : 's'} created.`
          );
          router.refresh();
        });
      }}
    >
      <div>
        <label className="label" htmlFor={`${uid}f`}>
          From
        </label>
        <input id={`${uid}f`} type="date" className="input" required value={from} onChange={(e) => setFrom(e.target.value)} />
      </div>
      <div>
        <label className="label" htmlFor={`${uid}t`}>
          To
        </label>
        <input id={`${uid}t`} type="date" className="input" required value={to} onChange={(e) => setTo(e.target.value)} />
      </div>
      <button className="btn btn-primary" disabled={pending}>
        {pending ? 'Generating…' : 'Generate shifts'}
      </button>
      <button
        type="button"
        className="btn btn-ghost"
        disabled={pending || !from || !to}
        onClick={() =>
          start(async () => {
            setError(null);
            const res = await startBulkGenerate(t.id, from, to);
            if (!res.ok) return setError(res.error);
            setJob(queued(res.jobId, 'generate_shifts', 1));
          })
        }
      >
        Run in background
      </button>
      <button type="button" className="btn btn-ghost" onClick={onDone}>
        Close
      </button>
      <p className="hint basis-full">At most 400 days at a time, within the requirement’s and template’s dates.</p>
      <OkLine text={ok} />
      <ErrorLine text={error} />
      {job && (
        <div className="basis-full">
          <BulkProgress initial={job} canCancel />
        </div>
      )}
    </form>
  );
}

export function TemplatesPanel({
  requirementId,
  templates,
  canManage,
}: {
  requirementId: string;
  templates: Template[];
  canManage: boolean;
}) {
  const [editing, setEditing] = useState<string | null>(null);
  const [generating, setGenerating] = useState<string | null>(null);
  return (
    <div className="space-y-3">
      {templates.length === 0 && editing !== 'new' && (
        <p className="text-sm muted">No recurring shifts. Add a template (for example Mon–Sat 22:00–06:00) and generate shifts from it.</p>
      )}
      <ul className="space-y-2">
        {templates.map((t) => (
          <li key={t.id} className="space-y-2">
            {editing === t.id ? (
              <TemplateForm requirementId={requirementId} t={t} onDone={() => setEditing(null)} />
            ) : (
              <div className="flex items-center gap-3 flex-wrap">
                <div className="flex-1 min-w-[12rem]">
                  <p className="font-semibold text-sm break-words">
                    {t.name}
                    {t.status === 'archived' && <span className="muted font-normal"> · archived</span>}
                  </p>
                  <p className="text-xs muted break-words">
                    {daysText(t.days)} · {t.start}–{t.end}
                    {t.end <= t.start ? ' (overnight)' : ''} · {t.breakMinutes} min break · {t.requiredWorkers} worker
                    {t.requiredWorkers === 1 ? '' : 's'}
                    {t.shiftType ? ` · ${SHIFT_LABEL[t.shiftType] ?? t.shiftType}` : ''}
                  </p>
                </div>
                {canManage && (
                  <>
                    {t.status === 'active' && (
                      <button type="button" className="btn btn-ghost" style={{ height: 34 }} onClick={() => setGenerating(t.id)}>
                        Generate shifts
                      </button>
                    )}
                    <button type="button" className="btn btn-ghost" style={{ height: 34 }} onClick={() => setEditing(t.id)}>
                      Edit
                    </button>
                  </>
                )}
              </div>
            )}
            {generating === t.id && <GenerateForm t={t} onDone={() => setGenerating(null)} />}
          </li>
        ))}
      </ul>
      {canManage &&
        (editing === 'new' ? (
          <TemplateForm requirementId={requirementId} t={null} onDone={() => setEditing(null)} />
        ) : (
          <button type="button" className="btn btn-ghost" onClick={() => setEditing('new')}>
            Add a shift template
          </button>
        ))}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* One-off shift                                                       */
/* ------------------------------------------------------------------ */

export function NewShiftForm({ requirementId, tz }: { requirementId: string; tz: string }) {
  const uid = useId();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [v, setV] = useState({
    starts_at: '',
    ends_at: '',
    break_minutes: '0',
    required_workers: '1',
    shift_type: '',
    kind: 'regular',
    instructions: '',
    location_text: '',
  });
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const set = (k: keyof typeof v) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) =>
    setV((s) => ({ ...s, [k]: e.target.value }));
  if (!open)
    return (
      <button type="button" className="btn btn-ghost" onClick={() => setOpen(true)}>
        Add a single shift
      </button>
    );
  return (
    <form
      className="surface rounded-lg p-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-4"
      onSubmit={(e) => {
        e.preventDefault();
        setError(null);
        start(async () => {
          const res = await createShift(requirementId, tz, v);
          if (!res.ok) return setError(res.error);
          router.push(`/dashboard/workforce/shifts/${res.id}`);
        });
      }}
    >
      <p className="hint sm:col-span-2 lg:col-span-4">Times are in the site’s time zone ({tz.replace(/_/g, ' ')}).</p>
      <div className="sm:col-span-2">
        <label className="label" htmlFor={`${uid}s`}>
          Starts *
        </label>
        <input id={`${uid}s`} type="datetime-local" className="input" required value={v.starts_at} onChange={set('starts_at')} />
      </div>
      <div className="sm:col-span-2">
        <label className="label" htmlFor={`${uid}e`}>
          Ends *
        </label>
        <input id={`${uid}e`} type="datetime-local" className="input" required value={v.ends_at} onChange={set('ends_at')} />
      </div>
      <div>
        <label className="label" htmlFor={`${uid}k`}>
          Kind
        </label>
        <select id={`${uid}k`} className="input" value={v.kind} onChange={set('kind')}>
          {SHIFT_KINDS.map((k) => (
            <option key={k} value={k}>
              {nice(k)}
            </option>
          ))}
        </select>
      </div>
      <div>
        <label className="label" htmlFor={`${uid}t`}>
          Shift type
        </label>
        <select id={`${uid}t`} className="input" value={v.shift_type} onChange={set('shift_type')}>
          <option value="">—</option>
          {Object.entries(SHIFT_LABEL).map(([k, l]) => (
            <option key={k} value={k}>
              {l}
            </option>
          ))}
        </select>
      </div>
      <div>
        <label className="label" htmlFor={`${uid}b`}>
          Break (min)
        </label>
        <input id={`${uid}b`} type="number" min={0} max={480} className="input" value={v.break_minutes} onChange={set('break_minutes')} />
      </div>
      <div>
        <label className="label" htmlFor={`${uid}r`}>
          Workers needed
        </label>
        <input id={`${uid}r`} type="number" min={1} className="input" value={v.required_workers} onChange={set('required_workers')} />
      </div>
      <div className="sm:col-span-2">
        <label className="label" htmlFor={`${uid}l`}>
          Location (if not the site)
        </label>
        <input id={`${uid}l`} className="input" maxLength={200} value={v.location_text} onChange={set('location_text')} />
      </div>
      <div className="sm:col-span-2">
        <label className="label" htmlFor={`${uid}i`}>
          Instructions for workers
        </label>
        <input id={`${uid}i`} className="input" maxLength={2000} value={v.instructions} onChange={set('instructions')} placeholder="Report to gate 3" />
      </div>
      <div className="flex gap-2 flex-wrap sm:col-span-2 lg:col-span-4">
        <button className="btn btn-primary" disabled={pending}>
          {pending ? 'Creating…' : 'Create shift'}
        </button>
        <button type="button" className="btn btn-ghost" onClick={() => setOpen(false)}>
          Cancel
        </button>
      </div>
      <ErrorLine text={error} />
    </form>
  );
}

/* ------------------------------------------------------------------ */
/* Pay components                                                      */
/* ------------------------------------------------------------------ */

export type PayComponent = {
  id: string;
  kind: string;
  name: string;
  amount: number;
  basis: string;
  shiftTypes: string[];
};

export function PayComponentsPanel({
  requirementId,
  assignmentId,
  components,
  currency,
  canPay,
}: {
  requirementId: string | null;
  assignmentId: string | null;
  components: PayComponent[];
  currency: string;
  canPay: boolean;
}) {
  const uid = useId();
  const router = useRouter();
  const [adding, setAdding] = useState(false);
  const [v, setV] = useState({ kind: 'allowance', name: '', amount: '', basis: 'per_shift', shiftTypes: [] as string[] });
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  return (
    <div className="space-y-3">
      {components.length === 0 ? (
        <p className="text-sm muted">No allowances, bonuses or deductions.</p>
      ) : (
        <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
          {components.map((c) => (
            <li key={c.id} className="py-2 flex items-center gap-3 flex-wrap text-sm">
              <span className="flex-1 min-w-[10rem] break-words">
                <span className="font-semibold">{c.name}</span>{' '}
                <span className="muted">
                  · {nice(c.kind)} · {money(c.amount, currency)} {PAY_BASIS_LABEL[c.basis] ?? c.basis}
                  {c.shiftTypes.length ? ` · ${c.shiftTypes.map((s) => SHIFT_LABEL[s] ?? s).join(', ')} shifts` : ''}
                </span>
              </span>
              {canPay && (
                <button
                  type="button"
                  className="text-sm underline muted"
                  disabled={pending}
                  onClick={() =>
                    start(async () => {
                      setError(null);
                      const res = await removePayComponent(c.id);
                      if (!res.ok) return setError(res.error);
                      router.refresh();
                    })
                  }
                >
                  Remove
                </button>
              )}
            </li>
          ))}
        </ul>
      )}
      {canPay &&
        (adding ? (
          <form
            className="surface rounded-lg p-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-4"
            onSubmit={(e) => {
              e.preventDefault();
              setError(null);
              start(async () => {
                const res = await savePayComponent({ requirementId, assignmentId }, v);
                if (!res.ok) return setError(res.error);
                setAdding(false);
                setV({ kind: 'allowance', name: '', amount: '', basis: 'per_shift', shiftTypes: [] });
                router.refresh();
              });
            }}
          >
            <div>
              <label className="label" htmlFor={`${uid}k`}>
                Kind
              </label>
              <select id={`${uid}k`} className="input" value={v.kind} onChange={(e) => setV((s) => ({ ...s, kind: e.target.value }))}>
                {COMPONENT_KINDS.map((k) => (
                  <option key={k} value={k}>
                    {nice(k)}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <label className="label" htmlFor={`${uid}n`}>
                Name *
              </label>
              <input
                id={`${uid}n`}
                className="input"
                required
                maxLength={80}
                value={v.name}
                placeholder="Night allowance"
                onChange={(e) => setV((s) => ({ ...s, name: e.target.value }))}
              />
            </div>
            <div>
              <label className="label" htmlFor={`${uid}a`}>
                Amount ({currency}) *
              </label>
              <input
                id={`${uid}a`}
                className="input"
                type="number"
                min={0}
                step="0.01"
                required
                value={v.amount}
                onChange={(e) => setV((s) => ({ ...s, amount: e.target.value }))}
              />
            </div>
            <div>
              <label className="label" htmlFor={`${uid}b`}>
                Counted
              </label>
              <select id={`${uid}b`} className="input" value={v.basis} onChange={(e) => setV((s) => ({ ...s, basis: e.target.value }))}>
                {PAY_BASES.map((b) => (
                  <option key={b} value={b}>
                    {PAY_BASIS_LABEL[b]}
                  </option>
                ))}
              </select>
            </div>
            {v.basis === 'per_shift' && (
              <fieldset className="sm:col-span-2 lg:col-span-4">
                <legend className="label">Only on these shift types (none = every shift)</legend>
                <div className="flex flex-wrap gap-1.5">
                  {Object.entries(SHIFT_LABEL).map(([k, l]) => {
                    const on = v.shiftTypes.includes(k);
                    return (
                      <button
                        key={k}
                        type="button"
                        aria-pressed={on}
                        className="px-2.5 py-1 rounded-lg text-xs font-semibold border hairline"
                        style={on ? { background: 'var(--color-brand-600)', color: '#fff', borderColor: 'transparent' } : undefined}
                        onClick={() =>
                          setV((s) => ({ ...s, shiftTypes: on ? s.shiftTypes.filter((x) => x !== k) : [...s.shiftTypes, k] }))
                        }
                      >
                        {l}
                      </button>
                    );
                  })}
                </div>
              </fieldset>
            )}
            <div className="flex gap-2 flex-wrap sm:col-span-2 lg:col-span-4">
              <button className="btn btn-primary" disabled={pending}>
                {pending ? 'Saving…' : 'Add'}
              </button>
              <button type="button" className="btn btn-ghost" onClick={() => setAdding(false)}>
                Cancel
              </button>
            </div>
            <ErrorLine text={error} />
          </form>
        ) : (
          <button type="button" className="btn btn-ghost" onClick={() => setAdding(true)}>
            Add allowance, bonus or deduction
          </button>
        ))}
      {!adding && <ErrorLine text={error} />}
    </div>
  );
}
