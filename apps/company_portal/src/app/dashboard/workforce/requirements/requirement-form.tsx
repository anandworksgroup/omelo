'use client';

import { useRouter } from 'next/navigation';
import { useId, useState, useTransition } from 'react';
import { WORK_TYPE_LABEL } from '@/lib/format';
import { PAY_PERIODS } from '@/lib/hiring';
import {
  CHECK_IN_LABEL,
  CHECK_IN_METHODS,
  CURRENCIES,
  EMPLOYMENT_TYPES,
  PAY_FREQUENCIES,
  PAY_FREQUENCY_LABEL,
  REQUIREMENT_STATUSES,
  nice,
  requirementTone,
} from '@/lib/workforce';
import { createRequirement, updateRequirement, type RequirementInput } from '../actions';
import { ErrorLine } from '../ui';

export type Option = { id: string; label: string };

export const EMPTY_REQUIREMENT: RequirementInput = {
  job_id: null,
  job_order_id: null,
  title: '',
  profession_id: null,
  openings: null,
  location_id: null,
  location_text: '',
  site_name: '',
  country_code: '',
  currency: '',
  timezone: '',
  employment_type: 'temporary',
  work_type: '',
  pay_rate: '',
  pay_period: '',
  pay_frequency: 'monthly',
  hours_per_week: '',
  start_date: '',
  end_date: '',
  check_in_method: 'app',
  geofence_radius_m: '',
  late_grace_minutes: '10',
  overtime_policy_id: null,
  supervisor_id: null,
  status: 'open',
  notes: '',
};

function Field({
  label,
  htmlFor,
  hint,
  children,
  wide,
}: {
  label: string;
  htmlFor?: string;
  hint?: string;
  children: React.ReactNode;
  wide?: boolean;
}) {
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
 * Create or edit a workforce requirement. Written only through
 * omelo_create_requirement / omelo_update_requirement, which check the role,
 * the job / job order, the supervisor, the time zone and every field.
 */
export default function RequirementForm({
  kind,
  sources,
  professions,
  areas,
  policies,
  supervisors,
  timeZones,
  initial,
  editId,
}: {
  kind: 'employer' | 'agency';
  sources: Option[];
  professions: Option[];
  areas: Option[];
  policies: Option[];
  supervisors: Option[];
  timeZones: string[];
  initial: RequirementInput;
  editId?: string;
}) {
  const uid = useId();
  const router = useRouter();
  const [v, setV] = useState<RequirementInput>(initial);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const creating = !editId;
  const linked = !!(v.job_id || v.job_order_id);
  const set = <K extends keyof RequirementInput>(k: K, value: RequirementInput[K]) => setV((s) => ({ ...s, [k]: value }));
  const inp = (k: keyof RequirementInput) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>) =>
    set(k, e.target.value as never);

  const currencies = v.currency && !CURRENCIES.includes(v.currency) ? [v.currency, ...CURRENCIES] : CURRENCIES;
  const fromSource = creating && linked ? ' Leave empty to copy it from the ' + (kind === 'agency' ? 'job order.' : 'job.') : '';

  function submit() {
    setError(null);
    start(async () => {
      if (editId) {
        const res = await updateRequirement(editId, v);
        if (!res.ok) return setError(res.error);
        router.push(`/dashboard/workforce/requirements/${editId}`);
        router.refresh();
      } else {
        const res = await createRequirement(v);
        if (!res.ok) return setError(res.error);
        router.push(`/dashboard/workforce/requirements/${res.id}`);
      }
    });
  }

  return (
    <form
      className="space-y-6"
      onSubmit={(e) => {
        e.preventDefault();
        submit();
      }}
    >
      <section className="card p-4 sm:p-5 grid gap-4 sm:grid-cols-2">
        <h2 className="font-bold sm:col-span-2">The work</h2>
        {kind === 'agency' ? (
          <Field
            label="Job order *"
            htmlFor={`${uid}src`}
            wide
            hint="Workers can be offered this work only if they consented to representation for this job order."
          >
            <select
              id={`${uid}src`}
              className="input"
              required
              disabled={!creating}
              value={v.job_order_id ?? ''}
              onChange={(e) => set('job_order_id', e.target.value || null)}
            >
              <option value="">{sources.length ? 'Choose a job order…' : 'Create a job order first'}</option>
              {sources.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.label}
                </option>
              ))}
            </select>
          </Field>
        ) : (
          <Field
            label="From a job (optional)"
            htmlFor={`${uid}src`}
            wide
            hint="Linking a job lets you offer work to its applicants and copies its title, place and pay."
          >
            <select
              id={`${uid}src`}
              className="input"
              disabled={!creating}
              value={v.job_id ?? ''}
              onChange={(e) => set('job_id', e.target.value || null)}
            >
              <option value="">No job — a standalone requirement</option>
              {sources.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.label}
                </option>
              ))}
            </select>
          </Field>
        )}
        <Field label={linked && creating ? 'Title' : 'Title *'} htmlFor={`${uid}title`} hint={fromSource || undefined}>
          <input
            id={`${uid}title`}
            className="input"
            maxLength={120}
            required={!linked || !creating}
            value={v.title}
            onChange={inp('title')}
            placeholder="Night warehouse associate"
          />
        </Field>
        <Field label="Profession" htmlFor={`${uid}prof`}>
          <select id={`${uid}prof`} className="input" value={v.profession_id ?? ''} onChange={(e) => set('profession_id', e.target.value || null)}>
            <option value="">{linked && creating ? 'From the source' : 'Choose…'}</option>
            {professions.map((p) => (
              <option key={p.id} value={p.id}>
                {p.label}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Openings" htmlFor={`${uid}open`} hint="One number: 1 or 1,000,000 workers.">
          <input
            id={`${uid}open`}
            className="input"
            type="number"
            min={1}
            max={1000000}
            value={v.openings ?? ''}
            placeholder={linked && creating ? 'From the source' : '1'}
            onChange={(e) => set('openings', e.target.value ? Math.round(Number(e.target.value)) : null)}
          />
        </Field>
        <Field label="Employment type" htmlFor={`${uid}emp`}>
          <select id={`${uid}emp`} className="input" value={v.employment_type} onChange={inp('employment_type')}>
            {EMPLOYMENT_TYPES.map((t) => (
              <option key={t} value={t}>
                {nice(t)}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Work type" htmlFor={`${uid}wt`}>
          <select id={`${uid}wt`} className="input" value={v.work_type} onChange={inp('work_type')} required={!creating}>
            {creating && <option value="">{linked ? 'From the source' : 'Full-time'}</option>}
            {Object.entries(WORK_TYPE_LABEL).map(([k, l]) => (
              <option key={k} value={k}>
                {l}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Status" htmlFor={`${uid}st`}>
          <select id={`${uid}st`} className="input" value={v.status} onChange={inp('status')}>
            {(creating ? (['draft', 'open'] as const) : REQUIREMENT_STATUSES).map((s) => (
              <option key={s} value={s}>
                {requirementTone(s).label}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Start date" htmlFor={`${uid}sd`}>
          <input id={`${uid}sd`} className="input" type="date" value={v.start_date} onChange={inp('start_date')} />
        </Field>
        <Field label="End date" htmlFor={`${uid}ed`} hint="Leave empty for ongoing work.">
          <input id={`${uid}ed`} className="input" type="date" value={v.end_date} onChange={inp('end_date')} />
        </Field>
      </section>

      <section className="card p-4 sm:p-5 grid gap-4 sm:grid-cols-2">
        <h2 className="font-bold sm:col-span-2">Where</h2>
        <Field label="Site name" htmlFor={`${uid}site`}>
          <input id={`${uid}site`} className="input" maxLength={120} value={v.site_name} onChange={inp('site_name')} placeholder="Warehouse 3" />
        </Field>
        <Field label="Area" htmlFor={`${uid}area`}>
          <select id={`${uid}area`} className="input" value={v.location_id ?? ''} onChange={(e) => set('location_id', e.target.value || null)}>
            <option value="">{linked && creating ? 'From the source' : 'Choose…'}</option>
            {areas.map((a) => (
              <option key={a.id} value={a.id}>
                {a.label}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Address or directions" htmlFor={`${uid}loc`} wide>
          <input id={`${uid}loc`} className="input" maxLength={200} value={v.location_text} onChange={inp('location_text')} />
        </Field>
        <Field label="Country code" htmlFor={`${uid}cc`} hint="Two letters, like IN or AE.">
          <input
            id={`${uid}cc`}
            className="input uppercase"
            maxLength={2}
            value={v.country_code}
            onChange={(e) => set('country_code', e.target.value.toUpperCase())}
          />
        </Field>
        <Field
          label={creating ? 'Time zone' : 'Time zone *'}
          htmlFor={`${uid}tz`}
          hint="Shift times are shown and entered in the site’s time zone."
        >
          <select id={`${uid}tz`} className="input" value={v.timezone} onChange={inp('timezone')} required={!creating}>
            {creating && <option value="">From the area (or UTC)</option>}
            {timeZones.map((z) => (
              <option key={z} value={z}>
                {z.replace(/_/g, ' ')}
              </option>
            ))}
          </select>
        </Field>
      </section>

      <section className="card p-4 sm:p-5 grid gap-4 sm:grid-cols-2">
        <h2 className="font-bold sm:col-span-2">Pay</h2>
        <Field label={linked && creating ? 'Currency' : 'Currency *'} htmlFor={`${uid}cur`} hint={fromSource || undefined}>
          <select id={`${uid}cur`} className="input" value={v.currency} onChange={inp('currency')} required={!linked || !creating}>
            <option value="">Choose…</option>
            {currencies.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </Field>
        <div className="grid grid-cols-2 gap-2 min-w-0">
          <Field label="Pay rate" htmlFor={`${uid}pay`}>
            <input id={`${uid}pay`} className="input" type="number" min={0} step="0.01" value={v.pay_rate} onChange={inp('pay_rate')} />
          </Field>
          <Field label="Per" htmlFor={`${uid}per`}>
            <select id={`${uid}per`} className="input" value={v.pay_period} onChange={inp('pay_period')}>
              <option value="">—</option>
              {PAY_PERIODS.map((p) => (
                <option key={p.value} value={p.value}>
                  {p.label.replace('per ', '')}
                </option>
              ))}
            </select>
          </Field>
        </div>
        <Field label="Paid" htmlFor={`${uid}freq`}>
          <select id={`${uid}freq`} className="input" value={v.pay_frequency} onChange={inp('pay_frequency')}>
            {PAY_FREQUENCIES.map((f) => (
              <option key={f} value={f}>
                {PAY_FREQUENCY_LABEL[f]}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Hours a week" htmlFor={`${uid}hpw`}>
          <input
            id={`${uid}hpw`}
            className="input"
            type="number"
            min={0}
            max={168}
            step="0.5"
            value={v.hours_per_week}
            onChange={inp('hours_per_week')}
          />
        </Field>
        <Field
          label="Overtime policy"
          htmlFor={`${uid}ot`}
          wide
          hint="Omelo does not assume a legal overtime rule — configure your jurisdiction’s under Pay. Without a policy, extra hours are paid at the normal rate."
        >
          <select
            id={`${uid}ot`}
            className="input"
            value={v.overtime_policy_id ?? ''}
            onChange={(e) => set('overtime_policy_id', e.target.value || null)}
          >
            <option value="">No overtime policy</option>
            {policies.map((p) => (
              <option key={p.id} value={p.id}>
                {p.label}
              </option>
            ))}
          </select>
        </Field>
      </section>

      <section className="card p-4 sm:p-5 grid gap-4 sm:grid-cols-2">
        <h2 className="font-bold sm:col-span-2">Attendance</h2>
        <Field label="Check-in method" htmlFor={`${uid}ci`}>
          <select id={`${uid}ci`} className="input" value={v.check_in_method} onChange={inp('check_in_method')}>
            {CHECK_IN_METHODS.map((m) => (
              <option key={m} value={m}>
                {CHECK_IN_LABEL[m]}
              </option>
            ))}
          </select>
        </Field>
        {v.check_in_method === 'geofence' ? (
          <Field label="Site radius (metres) *" htmlFor={`${uid}geo`}>
            <input
              id={`${uid}geo`}
              className="input"
              type="number"
              min={25}
              max={5000}
              required
              value={v.geofence_radius_m}
              onChange={inp('geofence_radius_m')}
            />
          </Field>
        ) : (
          <div className="hidden sm:block" />
        )}
        <Field label="Late grace (minutes)" htmlFor={`${uid}grace`} hint="Arrivals later than this are flagged for review, never penalised automatically.">
          <input
            id={`${uid}grace`}
            className="input"
            type="number"
            min={0}
            max={240}
            required
            value={v.late_grace_minutes}
            onChange={inp('late_grace_minutes')}
          />
        </Field>
        <Field label="Supervisor" htmlFor={`${uid}sup`} hint="From your team. They see check-in codes and record attendance.">
          <select id={`${uid}sup`} className="input" value={v.supervisor_id ?? ''} onChange={(e) => set('supervisor_id', e.target.value || null)}>
            <option value="">No supervisor</option>
            {supervisors.map((p) => (
              <option key={p.id} value={p.id}>
                {p.label}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Notes" htmlFor={`${uid}notes`} wide>
          <textarea id={`${uid}notes`} className="input min-h-24" maxLength={4000} value={v.notes} onChange={inp('notes')} />
        </Field>
      </section>

      <div className="flex flex-wrap gap-2 items-center">
        <button className="btn btn-primary w-full sm:w-auto" disabled={pending}>
          {pending ? 'Saving…' : editId ? 'Save changes' : 'Create requirement'}
        </button>
        <button type="button" className="btn btn-ghost w-full sm:w-auto" onClick={() => router.back()}>
          Cancel
        </button>
        <ErrorLine text={error} />
      </div>
    </form>
  );
}
