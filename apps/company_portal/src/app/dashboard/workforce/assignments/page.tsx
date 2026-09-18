import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { UUID_RE } from '@/lib/talent';
import { ASSIGNMENT_STATUSES, assignmentTone, loadWorkerNames, rate } from '@/lib/workforce';
import { ErrorNote, FilterChips, Notice, PageHeader, Table, TonePill, dateText, qs } from '../ui';

export const metadata: Metadata = { title: 'Assignments · Workforce · Omelo' };

const W = '/dashboard/workforce';

export default async function AssignmentsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const status = typeof sp.status === 'string' && (ASSIGNMENT_STATUSES as readonly string[]).includes(sp.status) ? sp.status : 'all';
  const req = typeof sp.req === 'string' && UUID_RE.test(sp.req) ? sp.req : null;
  const term = typeof sp.q === 'string' ? sp.q.trim().slice(0, 80) : '';
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  let q = supabase
    .from('assignments')
    .select(
      'id, person_id, work_identity_id, requirement_id, title, status, start_date, end_date, pay_rate, pay_period, currency, source, work_identities ( label ), workforce_requirements ( title )'
    )
    .eq('company_id', ctx.companyId)
    .order('updated_at', { ascending: false })
    .limit(500);
  if (status !== 'all') q = q.eq('status', status);
  if (req) q = q.eq('requirement_id', req);
  const [{ data, error }, reqs] = await Promise.all([
    q,
    supabase.from('workforce_requirements').select('id, title').eq('company_id', ctx.companyId).order('created_at', { ascending: false }).limit(100),
  ]);
  const rows = data ?? [];
  const names = await loadWorkerNames(
    supabase,
    ctx,
    rows.map((a) => ({ personId: a.person_id, identityId: a.work_identity_id }))
  );
  const label = (a: (typeof rows)[number]) =>
    names.get(a.person_id) ?? (a.work_identities as unknown as { label: string } | null)?.label ?? 'Worker';
  const shown = term ? rows.filter((a) => `${label(a)} ${a.title}`.toLowerCase().includes(term.toLowerCase())) : rows;

  return (
    <div className="space-y-5">
      <PageHeader
        title="Assignments"
        subtitle="Each worker’s terms for one requirement: dates, pay, status and history."
      />
      <FilterChips
        label="Status"
        active={status}
        options={[{ value: 'all', label: 'All' }, ...ASSIGNMENT_STATUSES.map((s) => ({ value: s, label: assignmentTone(s).label }))]}
        hrefFor={(v) => `${W}/assignments${qs({ status: v, req, q: term || null })}`}
      />
      <form className="flex gap-2 flex-wrap" action={`${W}/assignments`}>
        {status !== 'all' && <input type="hidden" name="status" value={status} />}
        <select name="req" defaultValue={req ?? ''} className="input flex-1 min-w-[12rem] sm:max-w-xs" aria-label="Requirement">
          <option value="">All requirements</option>
          {(reqs.data ?? []).map((r) => (
            <option key={r.id} value={r.id}>
              {r.title}
            </option>
          ))}
        </select>
        <input name="q" defaultValue={term} className="input flex-1 min-w-[12rem]" placeholder="Worker or title" aria-label="Search" />
        <button className="btn btn-ghost">Filter</button>
      </form>
      {error ? (
        <ErrorNote label="assignments" message={error.message} />
      ) : shown.length === 0 ? (
        <Notice title="No assignments">
          Offer work to workers from a requirement. Assignments appear here as soon as they are offered.
        </Notice>
      ) : (
        <div className="card p-4">
          <Table head={['Worker', 'Requirement', 'Status', 'Dates', 'Pay']}>
            {shown.map((a) => (
              <tr key={a.id}>
                <td className="py-2 pr-3">
                  <Link href={`${W}/assignments/${a.id}`} className="font-semibold hover:underline">
                    {label(a)}
                  </Link>
                  <p className="text-xs muted">{a.title}</p>
                </td>
                <td className="py-2 pr-3">
                  <Link href={`${W}/requirements/${a.requirement_id}`} className="hover:underline">
                    {(a.workforce_requirements as unknown as { title: string } | null)?.title ?? '—'}
                  </Link>
                </td>
                <td className="py-2 pr-3">
                  <TonePill tone={assignmentTone(a.status)} />
                </td>
                <td className="py-2 pr-3 whitespace-nowrap">
                  {dateText(a.start_date)}
                  {a.end_date ? ` – ${dateText(a.end_date)}` : ''}
                </td>
                <td className="py-2 pr-3 whitespace-nowrap">{rate(a.pay_rate, a.currency, a.pay_period)}</td>
              </tr>
            ))}
          </Table>
          {rows.length === 500 && <p className="text-xs muted mt-2">Showing the 500 most recently changed. Filter to narrow down.</p>}
        </div>
      )}
    </div>
  );
}
