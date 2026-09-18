'use client';

import { useRouter } from 'next/navigation';
import { useId, useMemo, useState, useTransition } from 'react';
import { JOB_ORDER_STATUS, JOB_ORDER_STATUSES, PRIORITIES, PRIORITY } from '@/lib/agency';
import { SHIFT_LABEL, WORKPLACE_LABEL, WORK_TYPE_LABEL } from '@/lib/format';
import { PAY_PERIODS } from '@/lib/hiring';
import { createJobOrder, updateJobOrder, type JobOrderInput } from '../actions';

export type Option = { id: string; label: string };

export type JobOrderInitial = JobOrderInput & { id: string; clientId: string };

const EMPTY: JobOrderInput = {
  title: '',
  reference: '',
  profession_id: null,
  openings: 1,
  location_id: null,
  location_text: '',
  workplace_type: 'onsite',
  work_type: 'full_time',
  shift_types: [],
  pay_min: null,
  pay_max: null,
  pay_period: 'month',
  pay_currency: 'INR',
  min_experience_months: null,
  required_skill_ids: [],
  hard_requirements: [],
  description: '',
  start_date: null,
  closing_date: null,
  priority: 'normal',
  status: 'open',
  notes: '',
};

const numOrNull = (s: string) => {
  if (!s.trim()) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
};

function Field({ label, htmlFor, hint, children, wide }: { label: string; htmlFor?: string; hint?: string; children: React.ReactNode; wide?: boolean }) {
  return (
    <div className={`min-w-0 ${wide ? 'sm:col-span-2' : ''}`}>
      <label className="label" htmlFor={htmlFor}>
        {label}
      </label>
      {children}
      {hint && <p className="hint">{hint}</p>}
    </div>
  );
}

/**
 * Create or edit a job order. The order is written only through
 * omelo_create_job_order / omelo_update_job_order, which check the role,
 * the client relationship and every field.
 */
export default function JobOrderForm({
  clients,
  defaultClientId,
  professions,
  skills,
  areas,
  initial,
}: {
  clients: Option[];
  defaultClientId: string | null;
  professions: Option[];
  skills: Option[];
  areas: Option[];
  initial?: JobOrderInitial;
}) {
  const uid = useId();
  const router = useRouter();
  const [clientId, setClientId] = useState(initial?.clientId ?? defaultClientId ?? clients[0]?.id ?? '');
  const [v, setV] = useState<JobOrderInput>(initial ?? EMPTY);
  const [requirements, setRequirements] = useState((initial?.hard_requirements ?? []).join('\n'));
  const [skillFilter, setSkillFilter] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  const set = <K extends keyof JobOrderInput>(k: K, value: JobOrderInput[K]) => setV((s) => ({ ...s, [k]: value }));
  const toggle = (k: 'shift_types' | 'required_skill_ids', value: string) =>
    setV((s) => ({ ...s, [k]: s[k].includes(value) ? s[k].filter((x) => x !== value) : [...s[k], value] }));

  const shownSkills = useMemo(() => {
    const f = skillFilter.trim().toLowerCase();
    const list = f ? skills.filter((s) => s.label.toLowerCase().includes(f)) : skills;
    // Selected skills always stay visible.
    return [...skills.filter((s) => v.required_skill_ids.includes(s.id) && !list.includes(s)), ...list];
  }, [skills, skillFilter, v.required_skill_ids]);

  function submit() {
    setError(null);
    const input: JobOrderInput = {
      ...v,
      hard_requirements: requirements
        .split('\n')
        .map((x) => x.trim())
        .filter(Boolean),
    };
    start(async () => {
      if (initial) {
        const res = await updateJobOrder(initial.id, input);
        if (!res.ok) return setError(res.error);
        router.push(`/dashboard/agency/job-orders/${initial.id}`);
        router.refresh();
      } else {
        if (!clientId) return setError('Choose a client.');
        const res = await createJobOrder(clientId, input);
        if (!res.ok) return setError(res.error);
        router.push(`/dashboard/agency/job-orders/${res.id}`);
      }
    });
  }

  const statuses = initial ? JOB_ORDER_STATUSES : (['draft', 'open'] as const);

  return (
    <form
      className="space-y-6"
      onSubmit={(e) => {
        e.preventDefault();
        submit();
      }}
    >
      <section className="card p-4 sm:p-5 grid gap-4 sm:grid-cols-2">
        <h2 className="font-bold sm:col-span-2">The role</h2>
        <Field label="Client *" htmlFor={`${uid}client`} wide>
          <select
            id={`${uid}client`}
            className="input"
            value={clientId}
            disabled={!!initial}
            onChange={(e) => setClientId(e.target.value)}
            required
          >
            {clients.length === 0 && <option value="">Add a client first</option>}
            {clients.map((c) => (
              <option key={c.id} value={c.id}>
                {c.label}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Job title *" htmlFor={`${uid}title`}>
          <input
            id={`${uid}title`}
            className="input"
            required
            minLength={2}
            maxLength={120}
            value={v.title}
            onChange={(e) => set('title', e.target.value)}
            placeholder="Warehouse picker"
          />
        </Field>
        <Field label="Reference" htmlFor={`${uid}ref`} hint={initial ? 'The reference cannot be changed.' : 'Leave empty for the next JO-number.'}>
          <input
            id={`${uid}ref`}
            className="input"
            maxLength={40}
            disabled={!!initial}
            value={v.reference ?? ''}
            onChange={(e) => set('reference', e.target.value)}
            placeholder="JO-1001"
          />
        </Field>
        <Field label="Profession" htmlFor={`${uid}prof`} hint="Used to find matching candidates.">
          <select
            id={`${uid}prof`}
            className="input"
            value={v.profession_id ?? ''}
            onChange={(e) => set('profession_id', e.target.value || null)}
          >
            <option value="">Choose…</option>
            {professions.map((p) => (
              <option key={p.id} value={p.id}>
                {p.label}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Openings" htmlFor={`${uid}open`}>
          <input
            id={`${uid}open`}
            className="input"
            type="number"
            min={1}
            max={10000}
            value={v.openings}
            onChange={(e) => set('openings', Number(e.target.value) || 1)}
          />
        </Field>
        <Field label="Area" htmlFor={`${uid}area`} hint="Candidates are found by distance from here.">
          <select
            id={`${uid}area`}
            className="input"
            value={v.location_id ?? ''}
            onChange={(e) => set('location_id', e.target.value || null)}
          >
            <option value="">Choose…</option>
            {areas.map((a) => (
              <option key={a.id} value={a.id}>
                {a.label}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Location details" htmlFor={`${uid}loct`}>
          <input
            id={`${uid}loct`}
            className="input"
            maxLength={200}
            value={v.location_text}
            onChange={(e) => set('location_text', e.target.value)}
            placeholder="Hosur Road warehouse"
          />
        </Field>
        <Field label="Workplace" htmlFor={`${uid}wp`}>
          <select id={`${uid}wp`} className="input" value={v.workplace_type} onChange={(e) => set('workplace_type', e.target.value)}>
            {Object.entries(WORKPLACE_LABEL).map(([k, l]) => (
              <option key={k} value={k}>
                {l}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Type of work" htmlFor={`${uid}wt`}>
          <select id={`${uid}wt`} className="input" value={v.work_type} onChange={(e) => set('work_type', e.target.value)}>
            {Object.entries(WORK_TYPE_LABEL).map(([k, l]) => (
              <option key={k} value={k}>
                {l}
              </option>
            ))}
          </select>
        </Field>
        <fieldset className="sm:col-span-2 min-w-0">
          <legend className="label">Shifts</legend>
          <div className="flex flex-wrap gap-x-4 gap-y-2">
            {Object.entries(SHIFT_LABEL).map(([k, l]) => (
              <label key={k} className="text-sm inline-flex items-center gap-1.5">
                <input type="checkbox" checked={v.shift_types.includes(k)} onChange={() => toggle('shift_types', k)} />
                {l}
              </label>
            ))}
          </div>
        </fieldset>
      </section>

      <section className="card p-4 sm:p-5 grid gap-4 sm:grid-cols-2">
        <h2 className="font-bold sm:col-span-2">Pay and dates</h2>
        <Field label="Pay from" htmlFor={`${uid}pmin`}>
          <input
            id={`${uid}pmin`}
            className="input"
            type="number"
            min={0}
            value={v.pay_min ?? ''}
            onChange={(e) => set('pay_min', numOrNull(e.target.value))}
          />
        </Field>
        <Field label="Pay up to" htmlFor={`${uid}pmax`}>
          <input
            id={`${uid}pmax`}
            className="input"
            type="number"
            min={0}
            value={v.pay_max ?? ''}
            onChange={(e) => set('pay_max', numOrNull(e.target.value))}
          />
        </Field>
        <Field label="Per" htmlFor={`${uid}pp`}>
          <select id={`${uid}pp`} className="input" value={v.pay_period ?? ''} onChange={(e) => set('pay_period', e.target.value || null)}>
            <option value="">—</option>
            {PAY_PERIODS.map((p) => (
              <option key={p.value} value={p.value}>
                {p.label}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Currency" htmlFor={`${uid}cur`}>
          <input
            id={`${uid}cur`}
            className="input uppercase"
            maxLength={3}
            value={v.pay_currency}
            onChange={(e) => set('pay_currency', e.target.value.toUpperCase())}
          />
        </Field>
        <Field label="Start date" htmlFor={`${uid}sd`}>
          <input
            id={`${uid}sd`}
            className="input"
            type="date"
            value={v.start_date ?? ''}
            onChange={(e) => set('start_date', e.target.value || null)}
          />
        </Field>
        <Field label="Closing date" htmlFor={`${uid}cd`}>
          <input
            id={`${uid}cd`}
            className="input"
            type="date"
            value={v.closing_date ?? ''}
            onChange={(e) => set('closing_date', e.target.value || null)}
          />
        </Field>
      </section>

      <section className="card p-4 sm:p-5 grid gap-4 sm:grid-cols-2">
        <h2 className="font-bold sm:col-span-2">Requirements</h2>
        <Field label="Minimum experience (months)" htmlFor={`${uid}exp`}>
          <input
            id={`${uid}exp`}
            className="input"
            type="number"
            min={0}
            max={720}
            value={v.min_experience_months ?? ''}
            onChange={(e) => set('min_experience_months', numOrNull(e.target.value))}
          />
        </Field>
        <Field label="Must-haves" htmlFor={`${uid}req`} hint="One per line, e.g. “Two-wheeler licence”. Shown to candidates." wide>
          <textarea
            id={`${uid}req`}
            className="input"
            rows={3}
            value={requirements}
            onChange={(e) => setRequirements(e.target.value)}
          />
        </Field>
        <fieldset className="sm:col-span-2 min-w-0">
          <legend className="label">Required skills {v.required_skill_ids.length > 0 && <span className="muted font-normal">· {v.required_skill_ids.length} chosen</span>}</legend>
          <input
            className="input mb-2"
            type="search"
            aria-label="Filter skills"
            placeholder="Filter skills"
            value={skillFilter}
            onChange={(e) => setSkillFilter(e.target.value)}
          />
          <div className="max-h-48 overflow-y-auto surface rounded-lg p-2 flex flex-wrap gap-x-4 gap-y-2">
            {shownSkills.map((s) => (
              <label key={s.id} className="text-sm inline-flex items-center gap-1.5">
                <input
                  type="checkbox"
                  checked={v.required_skill_ids.includes(s.id)}
                  onChange={() => toggle('required_skill_ids', s.id)}
                />
                {s.label}
              </label>
            ))}
            {shownSkills.length === 0 && <span className="text-sm muted">No skill matches.</span>}
          </div>
        </fieldset>
        <Field label="Description" htmlFor={`${uid}desc`} hint="Candidates see the first 1000 characters when you ask for their consent." wide>
          <textarea
            id={`${uid}desc`}
            className="input"
            rows={5}
            maxLength={8000}
            value={v.description}
            onChange={(e) => set('description', e.target.value)}
          />
        </Field>
      </section>

      <section className="card p-4 sm:p-5 grid gap-4 sm:grid-cols-2">
        <h2 className="font-bold sm:col-span-2">Tracking</h2>
        <Field label="Status" htmlFor={`${uid}st`}>
          <select id={`${uid}st`} className="input" value={v.status} onChange={(e) => set('status', e.target.value)}>
            {statuses.map((s) => (
              <option key={s} value={s}>
                {JOB_ORDER_STATUS[s].label}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Priority" htmlFor={`${uid}pr`}>
          <select id={`${uid}pr`} className="input" value={v.priority} onChange={(e) => set('priority', e.target.value)}>
            {PRIORITIES.map((p) => (
              <option key={p} value={p}>
                {PRIORITY[p].label}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Internal notes" htmlFor={`${uid}notes`} hint="Only your agency sees these." wide>
          <textarea
            id={`${uid}notes`}
            className="input"
            rows={3}
            maxLength={4000}
            value={v.notes}
            onChange={(e) => set('notes', e.target.value)}
          />
        </Field>
      </section>

      {error && (
        <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
          {error}
        </p>
      )}
      <div className="flex flex-wrap gap-2">
        <button className="btn btn-primary w-full sm:w-auto" disabled={pending || v.title.trim().length < 2 || !clientId}>
          {pending ? 'Saving…' : initial ? 'Save job order' : 'Create job order'}
        </button>
        <button type="button" className="btn btn-ghost w-full sm:w-auto" onClick={() => router.back()}>
          Cancel
        </button>
      </div>
    </form>
  );
}
