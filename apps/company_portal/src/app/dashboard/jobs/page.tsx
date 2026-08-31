import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { formatPay, timeAgo, WORK_TYPE_LABEL } from '@/lib/format';

const STATUS_STYLE: Record<string, string> = {
  published: 'var(--color-verified)',
  draft: 'var(--muted)',
  paused: 'var(--color-warn)',
  closed: 'var(--muted)',
  expired: 'var(--muted)',
};

export default async function JobsPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  const { data: jobs } = await supabase
    .from('jobs')
    .select(
      'id, title, status, location_text, pay_min, pay_max, pay_period, pay_currency, pay_negotiable, work_type, applicant_count, view_count, published_at, created_at, openings'
    )
    .eq('company_id', ctx.companyId)
    .order('created_at', { ascending: false });

  const { data: apps } = await supabase
    .from('applications')
    .select('job_id')
    .eq('company_id', ctx.companyId);

  const countFor = (id: string) =>
    (apps ?? []).filter((a) => a.job_id === id).length;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <h1 className="text-xl sm:text-2xl font-bold">Jobs</h1>
        <Link href="/dashboard/jobs/new" className="btn btn-primary w-full sm:w-auto">
          Post a job
        </Link>
      </div>

      {(jobs ?? []).length === 0 ? (
        <div className="card p-10 text-center">
          <p className="font-semibold mb-1">Nothing posted yet</p>
          <p className="text-sm muted mb-5">
            Post your first job and workers nearby will see it immediately.
          </p>
          <Link href="/dashboard/jobs/new" className="btn btn-primary">
            Post a job
          </Link>
        </div>
      ) : (
        <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          {(jobs ?? []).map((j) => (
            <Link key={j.id} href={`/dashboard/jobs/${j.id}`} className="card p-5 hover:opacity-90">
              <div className="flex items-start gap-4 flex-wrap">
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <h2 className="font-bold truncate">{j.title}</h2>
                    <span
                      className="pill"
                      style={{ color: STATUS_STYLE[j.status] ?? 'var(--muted)' }}
                    >
                      {j.status}
                    </span>
                  </div>
                  <p className="text-sm muted mt-1">
                    {j.location_text ?? '—'} ·{' '}
                    {WORK_TYPE_LABEL[j.work_type] ?? j.work_type}
                    {(j.openings ?? 1) > 1 ? ` · ${j.openings} openings` : ''}
                  </p>
                  <p className="text-sm font-semibold mt-2">
                    {formatPay({
                      min: j.pay_min,
                      max: j.pay_max,
                      currency: j.pay_currency,
                      period: j.pay_period,
                      negotiable: j.pay_negotiable,
                    })}
                  </p>
                </div>

                <div className="flex gap-6 text-center shrink-0">
                  <div>
                    <div className="font-bold">{countFor(j.id)}</div>
                    <div className="text-xs muted">applicants</div>
                  </div>
                  <div>
                    <div className="font-bold">{j.view_count}</div>
                    <div className="text-xs muted">views</div>
                  </div>
                </div>
              </div>

              <p className="text-xs muted mt-3">
                {j.status === 'published'
                  ? `Published ${timeAgo(j.published_at)}`
                  : `Created ${timeAgo(j.created_at)}`}
              </p>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
