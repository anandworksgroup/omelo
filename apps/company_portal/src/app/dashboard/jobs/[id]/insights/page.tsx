import Link from 'next/link';
import { notFound } from 'next/navigation';
import type { ReactNode } from 'react';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { hours, num } from '@/lib/admin';
import { formatMoney } from '@/lib/format';
import { TALENT_ROLES } from '@/lib/talent';
import {
  BOTTLENECK_CARD,
  BOTTLENECK_LABEL,
  PAY_POSITION_COLOR,
  PAY_POSITION_LABEL,
  humanize,
  intelligenceError,
  parseJobIntelligence,
  recommendationLink,
  type ChainCard,
  type JobIntelligence,
} from '@/lib/intelligence';
import { DifficultyGauge } from '@/components/insights/difficulty-gauge';
import { FunnelSteps } from '@/components/insights/funnel-steps';
import { PayRange } from '@/components/insights/pay-range';
import LocalTime from '../../../local-time';
import JobTabs from '../job-tabs';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const CHAIN: { key: ChainCard; label: string }[] = [
  { key: 'job', label: 'Job' },
  { key: 'supply', label: 'Supply' },
  { key: 'compensation', label: 'Compensation' },
  { key: 'match', label: 'Match quality' },
  { key: 'applications', label: 'Applications' },
  { key: 'interviews', label: 'Interviews' },
  { key: 'offers', label: 'Offers' },
];

export default async function JobInsightsPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID_RE.test(id)) notFound();
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  const [intelRes, ownRes] = await Promise.all([
    supabase.rpc('omelo_job_intelligence', { p_job: id }),
    // Readable only when this workspace owns the job; an agency working a
    // job order for it sees the insights but not the employer's job page.
    supabase.from('jobs').select('id').eq('id', id).eq('company_id', ctx.companyId).maybeSingle(),
  ]);
  const own = !!ownRes.data;
  const back = own
    ? { href: `/dashboard/jobs/${id}`, label: 'Job details' }
    : ctx.kind === 'agency'
      ? { href: '/dashboard/agency/job-orders', label: 'Job orders' }
      : { href: '/dashboard/insights', label: 'Insights' };

  if (intelRes.error) {
    const e = intelligenceError(intelRes.error);
    if (intelRes.error.code === '22023') notFound();
    return (
      <div className="space-y-6 max-w-3xl">
        <Link href={back.href} className="text-sm underline muted">
          ← {back.label}
        </Link>
        {own && <JobTabs jobId={id} active="insights" />}
        <div className="card p-6 sm:p-8 text-center" style={e.forbidden ? { borderTop: '3px solid var(--color-warn)' } : undefined}>
          <p className="font-semibold mb-1">{e.forbidden ? 'Only the hiring team can see this' : 'Could not load hiring insights'}</p>
          <p className="text-sm muted max-w-md mx-auto leading-relaxed">
            {e.forbidden
              ? `Hiring insights are shown to the job's hiring team (owners, admins, recruiters, hiring managers and HR) and to agencies working a job order for it. Ask an owner or admin of ${ctx.companyName} if you need access.`
              : e.text}
          </p>
        </div>
      </div>
    );
  }

  const intel = parseJobIntelligence(intelRes.data);
  if (!intel) {
    return (
      <div className="space-y-6 max-w-3xl">
        <Link href={back.href} className="text-sm underline muted">
          ← {back.label}
        </Link>
        <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
          Could not read the hiring insights for this job.
        </p>
      </div>
    );
  }

  const links =
    own
      ? {
          talent: TALENT_ROLES.includes(ctx.role) ? `/dashboard/talent?job=${id}` : null,
          unreviewed: `/dashboard/candidates?job=${id}&tab=new`,
          shortlisted: `/dashboard/candidates?job=${id}&tab=shortlisted`,
        }
      : ctx.kind === 'agency'
        ? { talent: '/dashboard/agency/talent', unreviewed: '/dashboard/agency/submissions', shortlisted: null }
        : { talent: null, unreviewed: null, shortlisted: null };

  const stage = intel.bottleneck.stage;
  const hot = stage ? BOTTLENECK_CARD[stage] : null;

  return (
    <div className="space-y-6 max-w-4xl">
      <div className="space-y-3">
        <Link href={back.href} className="text-sm underline muted">
          ← {back.label}
        </Link>
        <div className="flex items-start gap-3 flex-wrap">
          <h1 className="text-xl sm:text-2xl font-bold flex-1 min-w-0 break-words">{intel.title}</h1>
          {intel.status && <span className="pill">{intel.status}</span>}
        </div>
        {own && <JobTabs jobId={id} active="insights" />}
      </div>

      {/* Difficulty, bottleneck, what to do */}
      <section className="card p-4 sm:p-5">
        <div className="flex flex-col sm:flex-row gap-5 sm:gap-6 sm:items-start">
          <div className="flex flex-col items-center gap-1 sm:pt-1">
            <DifficultyGauge score={intel.difficulty.score} label={intel.difficulty.label} />
            <p className="text-xs muted">Hiring difficulty, 0 to 100</p>
          </div>
          <div className="flex-1 min-w-0 space-y-4">
            <div
              className="rounded-xl p-3.5"
              style={{
                background:
                  stage && stage !== 'none' && stage !== 'filled'
                    ? 'color-mix(in srgb, var(--color-warn) 10%, var(--bg))'
                    : 'var(--surface)',
              }}
            >
              <p className="text-xs font-semibold uppercase tracking-wide muted">Bottleneck</p>
              <p className="font-bold mt-0.5" style={stage && stage !== 'none' && stage !== 'filled' ? { color: 'var(--color-warn)' } : undefined}>
                {stage ? BOTTLENECK_LABEL[stage] : 'Unknown'}
              </p>
              {intel.bottleneck.explanation && <p className="text-sm mt-0.5">{intel.bottleneck.explanation}</p>}
              {hot && (
                <a href={`#${hot}`} className="text-sm underline mt-1 inline-block">
                  See the {CHAIN.find((c) => c.key === hot)?.label.toLowerCase()} numbers
                </a>
              )}
            </div>

            <div>
              <h2 className="font-bold">What to do next</h2>
              {intel.recommendations.length === 0 ? (
                <p className="text-sm muted mt-1">No recommendations right now.</p>
              ) : (
                <ol className="mt-2 space-y-2">
                  {intel.recommendations.map((r, i) => {
                    const link = recommendationLink(r, links);
                    return (
                      <li key={i} className="flex gap-3 items-start">
                        <span
                          aria-hidden
                          className="w-6 h-6 rounded-full grid place-items-center text-xs font-bold shrink-0"
                          style={{ background: 'var(--color-brand-100)', color: 'var(--color-brand-700)' }}
                        >
                          {i + 1}
                        </span>
                        <div className="min-w-0 flex-1 text-sm flex flex-wrap items-center gap-x-3 gap-y-1">
                          <span className="break-words">{r}</span>
                          {link && (
                            <Link
                              href={link.href}
                              className="btn btn-ghost"
                              style={{ height: 32, padding: '0 .75rem', fontSize: '.8rem' }}
                            >
                              {link.label} →
                            </Link>
                          )}
                        </div>
                      </li>
                    );
                  })}
                </ol>
              )}
            </div>
          </div>
        </div>
      </section>

      {/* The chain, as jump links */}
      <nav aria-label="Hiring chain" className="flex gap-1 items-center overflow-x-auto -mx-4 px-4 sm:mx-0 sm:px-0 sm:flex-wrap pb-1">
        {CHAIN.map((c, i) => (
          <span key={c.key} className="flex items-center gap-1 shrink-0">
            {i > 0 && (
              <span aria-hidden className="muted text-xs">
                →
              </span>
            )}
            <a
              href={`#${c.key}`}
              className="px-2.5 py-1 rounded-lg text-xs sm:text-sm font-medium whitespace-nowrap border hairline"
              style={
                c.key === hot
                  ? { borderColor: 'var(--color-warn)', color: 'var(--color-warn)', fontWeight: 700 }
                  : { background: 'var(--surface)' }
              }
            >
              {c.label}
              {c.key === hot && <span className="sr-only"> (bottleneck)</span>}
            </a>
          </span>
        ))}
      </nav>

      <div className="space-y-4">
        <ChainSection id="job" title="Job" hot={hot}>
          <JobCard intel={intel} />
        </ChainSection>
        <ChainSection id="supply" title="Supply" hot={hot}>
          <SupplyCard intel={intel} />
        </ChainSection>
        <ChainSection id="compensation" title="Compensation" hot={hot}>
          <CompensationCard intel={intel} />
        </ChainSection>
        <ChainSection id="match" title="Match quality" hot={hot}>
          <MatchCard intel={intel} />
        </ChainSection>
        <ChainSection id="applications" title="Application funnel" hot={hot}>
          <ApplicationsCard intel={intel} />
        </ChainSection>
        <ChainSection id="interviews" title="Interview funnel" hot={hot}>
          <InterviewsCard intel={intel} />
        </ChainSection>
        <ChainSection id="offers" title="Offer funnel" hot={hot} last>
          <OffersCard intel={intel} />
        </ChainSection>
      </div>

      <div className="text-xs muted space-y-1">
        {intel.note && <p>{intel.note}</p>}
        {intel.computedAt && (
          <p>
            Computed <LocalTime iso={intel.computedAt} />.
          </p>
        )}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */

function ChainSection({
  id,
  title,
  hot,
  last = false,
  children,
}: {
  id: ChainCard;
  title: string;
  hot: ChainCard | null;
  last?: boolean;
  children: ReactNode;
}) {
  const isHot = hot === id;
  return (
    <>
      <section
        id={id}
        aria-labelledby={`${id}-title`}
        className="card p-4 sm:p-5 space-y-4 min-w-0 scroll-mt-4"
        style={isHot ? { borderColor: 'var(--color-warn)', boxShadow: '0 0 0 1px var(--color-warn)' } : undefined}
      >
        <div className="flex items-center gap-2 flex-wrap">
          <h2 id={`${id}-title`} className="font-bold flex-1 min-w-0">
            {title}
          </h2>
          {isHot && (
            <span className="pill" style={{ color: 'var(--color-warn)', borderColor: 'var(--color-warn)' }}>
              Bottleneck
            </span>
          )}
        </div>
        {children}
      </section>
      {!last && (
        <p aria-hidden className="text-center muted text-sm leading-none -my-1">
          ↓
        </p>
      )}
    </>
  );
}

function Stats({ items }: { items: { label: string; value: ReactNode; hint?: string }[] }) {
  return (
    <dl className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-x-4 gap-y-3">
      {items.map((s) => (
        <div key={s.label} className="min-w-0">
          <dd className="text-xl font-black tabular-nums break-words">{s.value}</dd>
          <dt className="text-xs muted">{s.label}</dt>
          {s.hint && <p className="text-[0.7rem] muted">{s.hint}</p>}
        </div>
      ))}
    </dl>
  );
}

function JobCard({ intel }: { intel: JobIntelligence }) {
  const t = intel.timing;
  return (
    <Stats
      items={[
        { label: 'Openings', value: num(intel.openings) },
        { label: 'Still open', value: num(intel.openOpenings) },
        { label: 'Days open', value: num(t.daysOpen) },
        { label: 'To first application', value: hours(t.hoursToFirstApplication) },
        { label: 'Median time to first view', value: hours(t.medianHoursToFirstView) },
        { label: 'Applications not opened yet', value: num(t.unreviewed) },
      ]}
    />
  );
}

function SupplyCard({ intel }: { intel: JobIntelligence }) {
  const s = intel.supply;
  return (
    <>
      <Stats
        items={[
          { label: 'Workers in this profession', value: num(s.workersInProfession) },
          { label: 'Available soon', value: num(s.availableSoon), hint: 'Immediately, within 7 days, or flexible' },
          {
            label: 'Within 25 km',
            value: s.within25Km == null ? '—' : num(s.within25Km),
            hint: s.within25Km == null ? 'Not used for remote jobs' : undefined,
          },
          { label: 'Open to relocating here', value: num(s.openToRelocating) },
          { label: 'Competing open jobs', value: num(s.competingJobs) },
          { label: 'Available workers per opening', value: num(s.workersPerOpening) },
          { label: 'Workers per competing job', value: num(s.workersPerCompetingJob) },
        ]}
      />
    </>
  );
}

function CompensationCard({ intel }: { intel: JobIntelligence }) {
  const c = intel.compensation;
  const color = PAY_POSITION_COLOR[c.position];
  return (
    <>
      <div className="flex items-baseline gap-3 flex-wrap">
        <p className="text-sm">
          This job pays{' '}
          <strong className="tabular-nums">
            {c.jobMonthly == null ? 'an undisclosed amount' : `${formatMoney(c.jobMonthly, c.currency)} a month`}
          </strong>
        </p>
        <span className="pill" style={{ color, borderColor: color }}>
          {PAY_POSITION_LABEL[c.position]}
        </span>
      </div>
      <div className="grid gap-5 sm:grid-cols-2">
        <PayRange
          title="Comparable jobs"
          range={c.market}
          job={c.jobMonthly}
          currency={c.currency}
          sampleLabel="jobs"
        />
        <PayRange
          title="What workers expect"
          range={c.expectations}
          job={c.jobMonthly}
          currency={c.currency}
          sampleLabel="workers"
        />
      </div>
      {c.jobMonthly != null && (c.market || c.expectations) && (
        <p className="text-xs muted flex items-center gap-1.5">
          <span
            aria-hidden
            className="inline-block w-3 h-3 rounded-full"
            style={{ background: 'var(--color-accent-500)' }}
          />
          This job · shaded band is the middle half (25th to 75th percentile), the line is the median. Monthly, in{' '}
          {c.currency ?? 'the job’s currency'}.
        </p>
      )}
      <p className="text-sm">
        {c.meetsMinimumPct == null ? (
          <span className="muted">Not enough workers have set a minimum pay to say how many this job satisfies.</span>
        ) : (
          <>
            Meets the minimum pay of <strong className="tabular-nums">{Math.round(c.meetsMinimumPct)}%</strong> of workers
            in this profession who set one.
          </>
        )}
      </p>
      {c.rateSource && (
        <p className="text-xs muted">Other currencies converted with indicative rates ({c.rateSource}).</p>
      )}
    </>
  );
}

function MatchCard({ intel }: { intel: JobIntelligence }) {
  const m = intel.match;
  if (m.scored === 0) {
    return <p className="text-sm muted">No candidates have been scored against this job yet.</p>;
  }
  return (
    <>
      <Stats
        items={[
          { label: 'Candidates scored', value: num(m.scored) },
          { label: 'Eligible', value: num(m.eligible) },
          { label: 'Strong matches', value: num(m.strong), hint: 'Eligible, score 70 or more' },
        ]}
      />
      <FunnelSteps
        label="Match score distribution"
        steps={[
          { key: 'top', label: '80 and above', value: m.buckets.top },
          { key: 'mid', label: '60 to 79', value: m.buckets.mid },
          { key: 'low', label: 'Under 60', value: m.buckets.low },
        ]}
        showConversion={false}
      />
      {m.missingSkills.length > 0 && (
        <div>
          <p className="label">Skills candidates most often lack</p>
          <ul className="flex flex-wrap gap-2">
            {m.missingSkills.map((s) => (
              <li key={s.skill} className="pill">
                {s.skill} <span className="muted tabular-nums">· {num(s.candidates)}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
      {m.gateFailures.length > 0 && (
        <div>
          <p className="label">Why candidates are not eligible</p>
          <ul className="text-sm divide-y" style={{ borderColor: 'var(--line)' }}>
            {m.gateFailures.map((g) => (
              <li key={g.name} className="flex justify-between gap-3 py-1.5">
                <span className="break-words min-w-0">{humanize(g.name)}</span>
                <span className="tabular-nums font-semibold">{num(g.count)}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </>
  );
}

function ApplicationsCard({ intel }: { intel: JobIntelligence }) {
  const f = intel.applications;
  const empty = f.impressions === 0 && f.applied === 0;
  if (empty) return <p className="text-sm muted">Nothing yet. Numbers appear as workers see and apply to this job.</p>;
  return (
    <FunnelSteps
      label="Application funnel"
      steps={[
        { key: 'impressions', label: 'Seen', value: f.impressions, hint: 'Workers who saw the job in a list' },
        { key: 'applied', label: 'Applied', value: f.applied },
        { key: 'viewed', label: 'Viewed by you', value: f.viewed },
        { key: 'shortlisted', label: 'Shortlisted', value: f.shortlisted },
        { key: 'interviewed', label: 'Interviewed', value: f.interviewed },
        { key: 'offered', label: 'Offered', value: f.offered },
        { key: 'hired', label: 'Hired', value: f.hired },
      ]}
    />
  );
}

function InterviewsCard({ intel }: { intel: JobIntelligence }) {
  const i = intel.interviews;
  if (i.scheduled === 0) return <p className="text-sm muted">No interviews scheduled for this job yet.</p>;
  return (
    <>
      <FunnelSteps
        label="Interview funnel"
        steps={[
          { key: 'scheduled', label: 'Scheduled', value: i.scheduled },
          { key: 'completed', label: 'Completed', value: i.completed },
        ]}
      />
      <Stats
        items={[
          { label: 'Upcoming', value: num(i.upcoming) },
          { label: 'Cancelled', value: num(i.cancelled) },
          { label: 'Candidate no-show', value: num(i.noShowCandidate) },
          { label: 'Employer no-show', value: num(i.noShowEmployer) },
        ]}
      />
    </>
  );
}

function OffersCard({ intel }: { intel: JobIntelligence }) {
  const o = intel.offers;
  if (o.sent === 0) return <p className="text-sm muted">No offers sent for this job yet.</p>;
  return (
    <>
      <FunnelSteps
        label="Offer funnel"
        steps={[
          { key: 'sent', label: 'Sent', value: o.sent },
          { key: 'accepted', label: 'Accepted', value: o.accepted },
        ]}
      />
      <Stats
        items={[
          { label: 'Declined', value: num(o.declined) },
          { label: 'Expired', value: num(o.expired) },
          { label: 'Withdrawn', value: num(o.withdrawn) },
        ]}
      />
      {o.declineReasons.length > 0 && (
        <div>
          <p className="label">Reasons given for declining</p>
          <ul className="flex flex-wrap gap-2">
            {o.declineReasons.map((r) => (
              <li key={r} className="pill">
                {humanize(r)}
              </li>
            ))}
          </ul>
        </div>
      )}
    </>
  );
}
