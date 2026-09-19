import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { num } from '@/lib/admin';
import {
  PAY_POSITION_COLOR,
  PAY_POSITION_LABEL,
  bottleneckLabel,
  intelligenceError,
  parseCompanyIntelligence,
} from '@/lib/intelligence';
import { DifficultyChip } from '@/components/insights/difficulty-gauge';
import { Notice, PageHeader, Tile } from '../agency/ui';

export default async function InsightsPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('omelo_company_intelligence', { p_company: ctx.companyId });

  const header = (
    <PageHeader
      title="Hiring insights"
      subtitle="How hard each open job is to fill, where it gets stuck, and the first thing to try."
    />
  );

  if (error) {
    const e = intelligenceError(error);
    return (
      <div className="space-y-6">
        {header}
        {e.forbidden ? (
          <Notice title="Only the hiring team can see hiring insights" tone="warn">
            Owners, admins, recruiters, hiring managers and HR of {ctx.companyName} can see these. Ask an owner or admin
            to change your role if you need them.
          </Notice>
        ) : (
          <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
            Could not load hiring insights: <span className="muted">{e.text}</span>
          </p>
        )}
      </div>
    );
  }

  const intel = parseCompanyIntelligence(data);
  if (!intel) {
    return (
      <div className="space-y-6">
        {header}
        <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
          Could not read the hiring insights.
        </p>
      </div>
    );
  }

  if (intel.jobs.length === 0) {
    return (
      <div className="space-y-6">
        {header}
        <Notice
          title="No open jobs to analyse"
          action={
            ctx.kind === 'employer' ? (
              <Link href="/dashboard/jobs/new" className="btn btn-primary">
                Post a job
              </Link>
            ) : undefined
          }
        >
          Insights cover published jobs. Publish a job and its difficulty, bottleneck and recommendations appear here.
        </Notice>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {header}

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <Tile label="Open jobs" value={num(intel.openJobs)} hint={intel.openJobs >= 50 ? 'The 50 most recent' : undefined} />
        <Tile
          label="Hard or very hard"
          value={num(intel.hardOrVeryHard)}
          hint={intel.openJobs > 0 ? `of ${num(intel.openJobs)} open` : undefined}
        />
        <div className="card p-4 min-w-0 col-span-2">
          <p className="text-sm font-semibold">Bottlenecks</p>
          {intel.bottlenecks.length === 0 ? (
            <p className="text-sm muted mt-1">None recorded.</p>
          ) : (
            <ul className="mt-2 flex flex-wrap gap-2">
              {intel.bottlenecks.map((b) => (
                <li key={b.stage} className="pill">
                  {bottleneckLabel(b.stage)} <span className="tabular-nums font-bold ml-1">{b.count}</span>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>

      <section className="card p-4 sm:p-5 space-y-3 min-w-0">
        <h2 className="font-bold">Jobs, hardest to fill first</h2>

        {/* Phones: stacked cards. */}
        <ul className="md:hidden divide-y" style={{ borderColor: 'var(--line)' }}>
          {intel.jobs.map((j) => (
            <li key={j.jobId} className="py-3 space-y-1.5">
              <div className="flex items-start gap-2">
                <Link href={`/dashboard/jobs/${j.jobId}/insights`} className="font-semibold underline flex-1 min-w-0 break-words">
                  {j.title}
                </Link>
                <DifficultyChip label={j.difficulty} score={j.score} />
              </div>
              <p className="text-xs muted">
                {bottleneckLabel(j.bottleneck)} · {num(j.applied)} applied · {num(j.hired)} hired
                {j.daysOpen != null ? ` · ${num(j.daysOpen)} days open` : ''}
              </p>
              {j.topRecommendation && <p className="text-sm break-words">{j.topRecommendation}</p>}
            </li>
          ))}
        </ul>

        {/* Wider screens: a table. */}
        <div className="hidden md:block overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left muted text-xs border-b hairline">
                <th scope="col" className="font-semibold py-2 pr-3">Job</th>
                <th scope="col" className="font-semibold py-2 pr-3">Difficulty</th>
                <th scope="col" className="font-semibold py-2 pr-3">Bottleneck</th>
                <th scope="col" className="font-semibold py-2 pr-3">Pay</th>
                <th scope="col" className="font-semibold py-2 pr-3 text-right">Applied</th>
                <th scope="col" className="font-semibold py-2 pr-3 text-right">Hired</th>
                <th scope="col" className="font-semibold py-2 pr-3 text-right">Days open</th>
                <th scope="col" className="font-semibold py-2">Top recommendation</th>
              </tr>
            </thead>
            <tbody>
              {intel.jobs.map((j) => (
                <tr key={j.jobId} className="border-b hairline last:border-0 align-top">
                  <th scope="row" className="py-2.5 pr-3 font-semibold text-left">
                    <Link href={`/dashboard/jobs/${j.jobId}/insights`} className="underline break-words">
                      {j.title}
                    </Link>
                  </th>
                  <td className="py-2.5 pr-3">
                    <DifficultyChip label={j.difficulty} score={j.score} />
                  </td>
                  <td className="py-2.5 pr-3" title={j.bottleneckWhy ?? undefined}>
                    {bottleneckLabel(j.bottleneck)}
                  </td>
                  <td className="py-2.5 pr-3 whitespace-nowrap">
                    {j.payPosition ? (
                      <span style={{ color: PAY_POSITION_COLOR[j.payPosition] }}>{PAY_POSITION_LABEL[j.payPosition]}</span>
                    ) : (
                      '—'
                    )}
                  </td>
                  <td className="py-2.5 pr-3 text-right tabular-nums">{num(j.applied)}</td>
                  <td className="py-2.5 pr-3 text-right tabular-nums">{num(j.hired)}</td>
                  <td className="py-2.5 pr-3 text-right tabular-nums">{num(j.daysOpen)}</td>
                  <td className="py-2.5 min-w-[14rem] break-words">{j.topRecommendation ?? <span className="muted">—</span>}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
