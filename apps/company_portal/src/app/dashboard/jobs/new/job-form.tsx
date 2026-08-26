'use client';

import { useActionState, useEffect, useMemo, useState, useTransition } from 'react';
import { createJob, type ActionState } from '../../actions';
import { previewPool, type PoolPreview } from './preview';
import { BENEFIT_LABEL, SHIFT_LABEL, WORK_TYPE_LABEL, formatPay } from '@/lib/format';

type Profession = {
  id: string;
  name: string;
  category_id: string;
  is_entry_level_friendly: boolean;
  requires_license: boolean;
};

const PAY_PERIODS = ['hour', 'day', 'week', 'month', 'year', 'per_task'];
const WORK_TYPES = Object.keys(WORK_TYPE_LABEL);
const SHIFTS = Object.keys(SHIFT_LABEL);
const COMMON_BENEFITS = [
  'transport',
  'meals',
  'accommodation',
  'health_insurance',
  'overtime_pay',
  'uniform_provided',
  'tips',
  'training',
  'equipment_provided',
  'paid_leave',
];

export default function JobForm({
  categories,
  professions,
  areas,
  companyName,
}: {
  categories: { id: string; slug: string; name: string }[];
  professions: Profession[];
  areas: { id: string; label: string }[];
  companyName: string;
}) {
  const [state, action, pending] = useActionState<ActionState, FormData>(createJob, {});

  const [categoryId, setCategoryId] = useState('');
  const [professionId, setProfessionId] = useState('');
  const [locationId, setLocationId] = useState('');
  const [workplace, setWorkplace] = useState('onsite');
  const [payPeriod, setPayPeriod] = useState('month');
  const [payMin, setPayMin] = useState('');
  const [payMax, setPayMax] = useState('');
  const [noExp, setNoExp] = useState(true);
  const [minExpMonths, setMinExpMonths] = useState('');
  const [preview, setPreview] = useState<PoolPreview | null>(null);
  const [, startTransition] = useTransition();

  const filteredProfessions = useMemo(
    () => (categoryId ? professions.filter((p) => p.category_id === categoryId) : professions),
    [categoryId, professions]
  );

  const selectedProfession = professions.find((p) => p.id === professionId);

  useEffect(() => {
    if (!professionId) {
      setPreview(null);
      return;
    }
    startTransition(async () => {
      const p = await previewPool({
        professionId,
        locationId: locationId || undefined,
        minExperienceMonths: noExp ? null : Number(minExpMonths) || null,
        acceptsNoExperience: noExp,
      });
      setPreview(p);
    });
  }, [professionId, locationId, noExp, minExpMonths]);

  return (
    <form action={action} className="space-y-8 pb-16">
      {/* 1 — Basics */}
      <Section n={1} title="The basics">
        <Field label="Job title" hint="Write it the way a worker would say it. “Delivery Executive”, not “Logistics Associate II”.">
          <input name="title" required className="input" placeholder="Delivery Executive" />
        </Field>

        <div className="grid sm:grid-cols-2 gap-4">
          <Field label="Category">
            <select
              className="input"
              value={categoryId}
              onChange={(e) => {
                setCategoryId(e.target.value);
                setProfessionId('');
              }}
            >
              <option value="">All categories</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name}
                </option>
              ))}
            </select>
          </Field>

          <Field label="Kind of work *" hint="This drives who sees the job.">
            <select
              name="profession_id"
              required
              className="input"
              value={professionId}
              onChange={(e) => setProfessionId(e.target.value)}
            >
              <option value="">Choose…</option>
              {filteredProfessions.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.name}
                </option>
              ))}
            </select>
          </Field>
        </div>

        {selectedProfession?.requires_license && (
          <Callout tone="warn">
            {selectedProfession.name} usually requires a licence. Workers
            without a valid one will not pass the eligibility gate for this job.
          </Callout>
        )}

        <Field label="Openings">
          <input name="openings" type="number" min={1} defaultValue={1} className="input w-32" />
        </Field>
      </Section>

      {/* 2 — Where */}
      <Section n={2} title="Where the work happens">
        <div className="grid sm:grid-cols-2 gap-4">
          <Field label="Workplace">
            <select
              name="workplace_type"
              className="input"
              value={workplace}
              onChange={(e) => setWorkplace(e.target.value)}
            >
              <option value="onsite">On-site</option>
              <option value="hybrid">Hybrid</option>
              <option value="remote">Remote</option>
              <option value="field_based">Field based</option>
              <option value="client_site">Client site</option>
            </select>
          </Field>

          <Field
            label={workplace === 'remote' ? 'Area (optional)' : 'Area *'}
            hint="Workers find jobs by distance from home."
          >
            <select
              name="location_id"
              className="input"
              value={locationId}
              onChange={(e) => setLocationId(e.target.value)}
              required={workplace !== 'remote'}
            >
              <option value="">Choose an area…</option>
              {areas.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.label}
                </option>
              ))}
            </select>
          </Field>
        </div>

        <Field label="Address or landmark" hint="Shown to candidates who are invited to interview.">
          <input name="location_text" className="input" placeholder="Warehouse 3, near Gate 2" />
        </Field>
      </Section>

      {/* 3 — Pay */}
      <Section n={3} title="Pay">
        <div className="grid sm:grid-cols-3 gap-4">
          <Field label="From">
            <input
              name="pay_min"
              type="number"
              min={0}
              className="input"
              value={payMin}
              onChange={(e) => setPayMin(e.target.value)}
              placeholder="18000"
            />
          </Field>
          <Field label="To">
            <input
              name="pay_max"
              type="number"
              min={0}
              className="input"
              value={payMax}
              onChange={(e) => setPayMax(e.target.value)}
              placeholder="28000"
            />
          </Field>
          <Field label="Per">
            <select
              name="pay_period"
              className="input"
              value={payPeriod}
              onChange={(e) => setPayPeriod(e.target.value)}
            >
              {PAY_PERIODS.map((p) => (
                <option key={p} value={p}>
                  {p === 'per_task' ? 'Per task' : p}
                </option>
              ))}
            </select>
          </Field>
        </div>
        <input type="hidden" name="pay_currency" value="INR" />

        {payMin && (
          <p className="text-sm">
            Workers will see{' '}
            <strong>
              {formatPay({
                min: Number(payMin),
                max: Number(payMax) || null,
                currency: 'INR',
                period: payPeriod,
              })}
            </strong>
          </p>
        )}

        <Check name="pay_negotiable" label="Pay is negotiable" />

        <Callout>
          Jobs that show pay get far more applications. Hiding it mostly filters
          out the people who cannot afford to waste an interview.
        </Callout>

        {preview && (preview.payLow || preview.note) && (
          <div className="card p-4 text-sm">
            <strong>Comparable jobs on Omelo</strong>
            {preview.payLow ? (
              <p className="muted mt-1 leading-relaxed">
                Similar {selectedProfession?.name} roles pay{' '}
                <strong>
                  {formatPay({ min: preview.payLow, max: preview.payHigh, currency: preview.currency, period: 'month' })}
                </strong>{' '}
                (middle 50% of {preview.similarJobs} live postings, converted to
                a monthly figure).
              </p>
            ) : (
              <p className="muted mt-1">{preview.note}</p>
            )}
          </div>
        )}
      </Section>

      {/* 4 — Schedule */}
      <Section n={4} title="Hours and schedule">
        <Field label="Type of work">
          <select name="work_type" className="input" defaultValue="full_time">
            {WORK_TYPES.map((w) => (
              <option key={w} value={w}>
                {WORK_TYPE_LABEL[w]}
              </option>
            ))}
          </select>
        </Field>

        <Field label="Shifts" hint="Pick every shift this job could cover.">
          <div className="flex flex-wrap gap-2">
            {SHIFTS.map((s) => (
              <label key={s} className="pill cursor-pointer">
                <input type="checkbox" name="shift_types" value={s} className="mr-1" />
                {SHIFT_LABEL[s]}
              </label>
            ))}
          </div>
        </Field>

        <div className="grid sm:grid-cols-2 gap-4">
          <Field label="Hours per week">
            <input name="hours_per_week" type="number" min={0} max={100} className="input" placeholder="48" />
          </Field>
          <Field label="Days per week">
            <input name="working_days" type="number" min={0} max={7} className="input" placeholder="6" />
          </Field>
        </div>

        <Check name="is_immediate_start" label="Can start immediately" defaultChecked />
      </Section>

      {/* 5 — Requirements */}
      <Section n={5} title="Who can do this job">
        <Check
          name="accepts_no_experience"
          label="Accept people with no experience"
          defaultChecked
          onChange={setNoExp}
        />

        {!noExp && (
          <Field label="Minimum experience (months)">
            <input
              name="min_experience_months"
              type="number"
              min={0}
              className="input w-40"
              value={minExpMonths}
              onChange={(e) => setMinExpMonths(e.target.value)}
              placeholder="12"
            />
          </Field>
        )}

        <Check
          name="requires_resume"
          label="Require a resume"
          hint="Most workers do not have one. Requiring it removes them from your pool entirely."
        />

        <Field label="One screening question" hint="Answered yes/no when applying.">
          <input name="question" className="input" placeholder="Do you have your own two-wheeler?" />
        </Field>

        {preview && (
          <div className="card p-4">
            <div className="flex items-baseline gap-2">
              <span className="text-2xl font-bold">{preview.workers}</span>
              <span className="text-sm muted">
                worker{preview.workers === 1 ? '' : 's'} on Omelo currently match
                this
              </span>
            </div>
            {preview.workers === 0 && (
              <p className="hint">
                Omelo is new in this area, so the worker pool is still small.
                Your job is still visible to everyone who joins and matches.
              </p>
            )}
            {!noExp && minExpMonths && (
              <p className="hint">
                Requiring {minExpMonths} months of experience narrows this pool.
                Turn the experience requirement off to see the difference.
              </p>
            )}
          </div>
        )}
      </Section>

      {/* 6 — Benefits */}
      <Section n={6} title="What you offer">
        <Field label="Benefits" hint="Transport, meals and accommodation matter more than perks for most jobs.">
          <div className="flex flex-wrap gap-2">
            {COMMON_BENEFITS.map((b) => (
              <label key={b} className="pill cursor-pointer">
                <input type="checkbox" name="benefits" value={b} className="mr-1" />
                {BENEFIT_LABEL[b]}
              </label>
            ))}
          </div>
        </Field>

        <Field label="Describe the work">
          <textarea
            name="description"
            rows={5}
            className="input"
            placeholder="What the person will actually do day to day."
          />
        </Field>
      </Section>

      {state.error && (
        <p className="text-sm" style={{ color: 'var(--color-danger)' }}>
          {state.error}
        </p>
      )}

      <div className="flex items-center gap-3">
        <button className="btn btn-primary" disabled={pending}>
          {pending ? 'Saving…' : 'Save draft'}
        </button>
        <span className="text-sm muted">
          Posting as {companyName}. You review before publishing.
        </span>
      </div>
    </form>
  );
}

/* ---------- small presentational helpers ---------- */

function Section({ n, title, children }: { n: number; title: string; children: React.ReactNode }) {
  return (
    <section className="space-y-4">
      <h2 className="font-bold text-lg flex items-center gap-2">
        <span className="pill">{n}</span>
        {title}
      </h2>
      {children}
    </section>
  );
}

function Field({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <div>
      <label className="label">{label}</label>
      {children}
      {hint && <p className="hint">{hint}</p>}
    </div>
  );
}

function Check({
  name,
  label,
  hint,
  defaultChecked,
  onChange,
}: {
  name: string;
  label: string;
  hint?: string;
  defaultChecked?: boolean;
  onChange?: (v: boolean) => void;
}) {
  return (
    <div>
      <label className="flex items-start gap-2.5 cursor-pointer">
        <input
          type="checkbox"
          name={name}
          defaultChecked={defaultChecked}
          onChange={(e) => onChange?.(e.target.checked)}
          className="mt-1"
        />
        <span className="text-sm font-medium">{label}</span>
      </label>
      {hint && <p className="hint ml-6">{hint}</p>}
    </div>
  );
}

function Callout({ children, tone }: { children: React.ReactNode; tone?: 'warn' }) {
  return (
    <div
      className="rounded-xl p-3.5 text-sm leading-relaxed surface"
      style={tone === 'warn' ? { color: 'var(--color-warn)' } : undefined}
    >
      {children}
    </div>
  );
}
