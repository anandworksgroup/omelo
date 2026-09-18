import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { hours, num, pct, type Kpis } from '@/lib/admin';
import { Card, Stat, WindowSelector, parseChoice } from '../ui';

export const metadata: Metadata = { title: 'KPIs · Omelo Admin', robots: { index: false, follow: false } };

const WINDOWS = [
  { value: 7, label: '7 days' },
  { value: 30, label: '30 days' },
  { value: 90, label: '90 days' },
];

type Step = { key: keyof Kpis['funnel']; label: string; conv?: keyof Kpis['conversion'] };

const STEPS: Step[] = [
  { key: 'applied', label: 'Applied' },
  { key: 'shortlisted', label: 'Shortlisted', conv: 'apply_to_shortlist' },
  { key: 'interviewed', label: 'Interviewed', conv: 'shortlist_to_interview' },
  { key: 'offered', label: 'Offered', conv: 'interview_to_offer' },
  { key: 'hired', label: 'Hired', conv: 'offer_to_hire' },
];

/**
 * Horizontal step chart in plain CSS. One series, so one hue (brand) and no
 * legend; bar length is the share of applications that reached the step, the
 * step-to-step conversion sits between rows. Counts are always printed, so
 * nothing depends on reading bar length alone.
 */
function Funnel({ k }: { k: Kpis }) {
  const top = Math.max(1, Number(k.funnel.applied) || 0);
  return (
    <ol className="space-y-1" aria-label="Hiring funnel">
      {STEPS.map((s, i) => {
        const n = Number(k.funnel[s.key] ?? 0);
        const share = Math.min(1, n / top);
        return (
          <li key={s.key}>
            {s.conv && (
              <p className="text-xs muted pl-[7.5rem] sm:pl-[8.5rem] py-1" aria-label={`Conversion from ${STEPS[i - 1].label}`}>
                ↓ {pct(k.conversion[s.conv])} from {STEPS[i - 1].label.toLowerCase()}
              </p>
            )}
            <div className="flex items-center gap-3" title={`${s.label}: ${num(n)} (${pct(n / top)} of applied)`}>
              <span className="w-[6.75rem] sm:w-[7.75rem] shrink-0 text-sm font-semibold">{s.label}</span>
              <div className="flex-1 h-7 rounded-md surface relative overflow-hidden">
                <div
                  className="h-full"
                  style={{
                    width: `${n > 0 ? Math.max(share * 100, 0.75) : 0}%`,
                    background: 'var(--color-brand-600)',
                    borderRadius: '0 4px 4px 0',
                    transition: 'width .3s ease',
                  }}
                />
              </div>
              <span className="w-24 shrink-0 text-right tabular-nums">
                <span className="font-bold">{num(n)}</span>
                {i > 0 && <span className="text-xs muted ml-1.5">{pct(n / top)}</span>}
              </span>
            </div>
          </li>
        );
      })}
    </ol>
  );
}

export default async function KpisPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const days = parseChoice(sp.days, WINDOWS.map((w) => w.value), 30);

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('omelo_admin_kpis', { p_days: days });
  if (error) {
    if (error.code === '42501') notFound();
    throw error;
  }
  const k = data as unknown as Kpis;

  return (
    <div className="space-y-6">
      <div className="flex items-end justify-between gap-4 flex-wrap">
        <div>
          <h1 className="text-2xl font-bold">KPIs</h1>
          <p className="text-sm muted mt-1">Last {k.window_days} days</p>
        </div>
        <WindowSelector param="days" options={WINDOWS} current={days} basePath="/admin/kpis" label="Time window" />
      </div>

      <div className="grid gap-4 grid-cols-2 lg:grid-cols-4">
        <div className="card p-4">
          <Stat label="Active workers" value={num(k.marketplace.active_workers)} />
        </div>
        <div className="card p-4">
          <Stat label="Active employers" value={num(k.marketplace.active_employers)} />
        </div>
        <div className="card p-4">
          <Stat label="Published jobs (now)" value={num(k.marketplace.published_jobs)} />
        </div>
        <div className="card p-4">
          <Stat label="Job fill rate" value={pct(k.marketplace.job_fill_rate)} hint="Closed jobs with a hire" />
        </div>
      </div>

      <section className="card p-4 sm:p-6">
        <div className="flex items-baseline justify-between gap-3 flex-wrap">
          <h2 className="text-lg font-bold">Hiring funnel</h2>
          <p className="text-sm">
            <span className="muted">Apply → hire </span>
            <span className="font-bold tabular-nums">{pct(k.conversion.apply_to_hire)}</span>
            <span className="muted"> · Offer acceptance </span>
            <span className="font-bold tabular-nums">{pct(k.conversion.offer_acceptance)}</span>
          </p>
        </div>
        <p className="text-xs muted mt-1 mb-4">{k.definition}</p>
        <Funnel k={k} />
      </section>

      <div className="grid gap-4 sm:grid-cols-2">
        <Card title="Median time from application">
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <Stat label="To shortlist" value={hours(k.median_hours.to_shortlist)} />
            <Stat label="To interview" value={hours(k.median_hours.to_interview)} />
            <Stat label="To offer" value={hours(k.median_hours.to_offer)} />
            <Stat label="To hire" value={hours(k.median_hours.to_hire)} />
          </div>
        </Card>
        <Card title="Worker trust (all time)">
          <div className="grid grid-cols-2 gap-3">
            <Stat label="Email verified" value={num(k.workers.email_verified)} />
            <Stat label="With a verified employment" value={num(k.workers.with_verified_employment)} />
          </div>
        </Card>
      </div>
    </div>
  );
}
