import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { REQUIREMENT_STATUSES, onlyWf, rate, requirementTone, wfCan } from '@/lib/workforce';
import { ErrorNote, FilterChips, Notice, PageHeader, TonePill, dateText, qs } from '../ui';

export const metadata: Metadata = { title: 'Requirements · Workforce · Omelo' };

const W = '/dashboard/workforce';

export default async function RequirementsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const status = typeof sp.status === 'string' && (REQUIREMENT_STATUSES as readonly string[]).includes(sp.status) ? sp.status : 'all';
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  let q = supabase
    .from('workforce_requirements')
    .select('id, title, openings, status, start_date, end_date, currency, pay_rate, pay_period, site_name, location_text, timezone, job_order_id, job_id')
    .eq('company_id', ctx.companyId)
    .order('created_at', { ascending: false })
    .limit(150);
  if (status !== 'all') q = q.eq('status', status);
  const { data, error } = await q;
  const reqs = data ?? [];
  const ids = reqs.map((r) => r.id);
  const { data: asg } = ids.length
    ? await supabase.from('assignments').select('requirement_id, status').in('requirement_id', ids).in('status', ['offered', 'accepted', 'active', 'paused'])
    : { data: [] as { requirement_id: string; status: string }[] };
  const filled = new Map<string, number>();
  const offered = new Map<string, number>();
  for (const a of asg ?? []) {
    const m = a.status === 'offered' ? offered : filled;
    m.set(a.requirement_id, (m.get(a.requirement_id) ?? 0) + 1);
  }
  const canManage = wfCan(ctx, 'manage_workforce');

  return (
    <div className="space-y-5">
      <PageHeader
        title="Requirements"
        subtitle={
          ctx.kind === 'agency'
            ? 'Staffing needs for your clients, each from a job order. Openings are a number — 1 or 1,000,000.'
            : 'Staffing needs: how many workers, where, when, on what terms.'
        }
        action={
          canManage ? (
            <Link href={`${W}/requirements/new`} className="btn btn-primary w-full sm:w-auto">
              New requirement
            </Link>
          ) : undefined
        }
      />
      <FilterChips
        label="Status"
        active={status}
        options={[{ value: 'all', label: 'All' }, ...REQUIREMENT_STATUSES.map((s) => ({ value: s, label: requirementTone(s).label }))]}
        hrefFor={(v) => `${W}/requirements${qs({ status: v })}`}
      />
      {error ? (
        <ErrorNote label="requirements" message={error.message} />
      ) : reqs.length === 0 ? (
        <Notice
          title="No requirements yet"
          action={
            canManage ? (
              <Link href={`${W}/requirements/new`} className="btn btn-primary">
                Create a requirement
              </Link>
            ) : undefined
          }
        >
          {canManage
            ? ctx.kind === 'agency'
              ? 'Start one from a job order: set openings, dates, pay, shifts and check-in, then offer the work to consented candidates.'
              : 'Start one from a job (to offer work to its applicants) or on its own.'
            : onlyWf(ctx.kind, 'manage_workforce', 'create requirements')}
        </Notice>
      ) : (
        <ul className="grid gap-3 md:grid-cols-2">
          {reqs.map((r) => {
            const n = filled.get(r.id) ?? 0;
            return (
              <li key={r.id} className="card p-4 space-y-2 min-w-0">
                <div className="flex items-start gap-2 flex-wrap">
                  <Link href={`${W}/requirements/${r.id}`} className="font-bold hover:underline break-words flex-1 min-w-[10rem]">
                    {r.title}
                  </Link>
                  <TonePill tone={requirementTone(r.status)} />
                </div>
                <p className="text-sm muted break-words">
                  {[r.site_name, r.location_text].filter(Boolean).join(', ') || r.timezone} · {dateText(r.start_date)}
                  {r.end_date ? ` – ${dateText(r.end_date)}` : ' onwards'}
                </p>
                <div className="flex items-center gap-3 text-sm flex-wrap">
                  <span className="tabular-nums">
                    <strong>{n.toLocaleString('en-IN')}</strong> / {r.openings.toLocaleString('en-IN')} filled
                  </span>
                  {(offered.get(r.id) ?? 0) > 0 && <span className="muted">{offered.get(r.id)} offered</span>}
                  <span className="muted">{rate(r.pay_rate, r.currency, r.pay_period)}</span>
                </div>
                <div className="h-1.5 rounded-full overflow-hidden" style={{ background: 'var(--surface)' }} aria-hidden>
                  <div
                    className="h-full"
                    style={{ width: `${Math.min(100, (n / Math.max(1, r.openings)) * 100)}%`, background: 'var(--color-brand-600)' }}
                  />
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
