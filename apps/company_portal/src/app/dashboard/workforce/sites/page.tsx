import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { assignmentTone, parseClientWorkforce, wfCan } from '@/lib/workforce';
import LocalTime from '../../local-time';
import { ErrorNote, Notice, PageHeader, Table, TonePill, dateText } from '../ui';

export const metadata: Metadata = { title: 'Workforce at your sites · Omelo' };

const W = '/dashboard/workforce';

/**
 * The client company's view of agency workers placed at its sites. Built
 * from omelo_client_workforce, which never returns the worker's pay (and the
 * agency's bill rate reaches the client only as its own bills).
 */
export default async function SitesPage() {
  const ctx = (await getCompanyContext())!;
  if (ctx.kind !== 'employer') {
    return (
      <div className="space-y-5">
        <PageHeader title="Workforce at your sites" />
        <Notice title="For employers">This view is for companies whose sites host agency workers.</Notice>
      </div>
    );
  }
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('omelo_client_workforce', { p_company: ctx.companyId });
  const rows = parseClientWorkforce(data ?? null);
  const agencies = new Map<string, number>();
  for (const r of rows) if (r.status === 'active') agencies.set(r.agency ?? 'Agency', (agencies.get(r.agency ?? 'Agency') ?? 0) + 1);

  return (
    <div className="space-y-5">
      <PageHeader
        title="Workforce at your sites"
        subtitle="Agency workers placed with you through agencies you linked on Omelo. The agency manages their assignment and pay; you approve their attendance and timesheets as the workplace."
        action={
          wfCan(ctx, 'approve_time') ? (
            <Link href={`${W}/approvals`} className="btn btn-primary w-full sm:w-auto">
              Approvals
            </Link>
          ) : undefined
        }
      />
      {agencies.size > 0 && (
        <div className="flex gap-2 flex-wrap">
          {[...agencies.entries()].map(([a, n]) => (
            <span key={a} className="pill">
              {a}: {n} working
            </span>
          ))}
        </div>
      )}
      {error ? (
        <ErrorNote label="agency workers" message={error.message} />
      ) : rows.length === 0 ? (
        <Notice title="No agency workers at your sites">
          When an agency you have linked with places workers here, they appear with their next shift. Manage agency links
          under Agencies.
        </Notice>
      ) : (
        <div className="card p-4">
          <Table head={['Worker', 'Agency', 'Status', 'Dates', 'Next shift']}>
            {rows.map((r) => (
              <tr key={r.assignmentId}>
                <td className="py-2 pr-3">
                  <p className="font-semibold">{r.worker}</p>
                  <p className="text-xs muted">
                    {r.title}
                    {r.identityLabel ? ` · as ${r.identityLabel}` : ''}
                  </p>
                </td>
                <td className="py-2 pr-3">{r.agency ?? '—'}</td>
                <td className="py-2 pr-3">
                  <TonePill tone={assignmentTone(r.status)} />
                </td>
                <td className="py-2 pr-3 whitespace-nowrap">
                  {dateText(r.startDate)}
                  {r.endDate ? ` – ${dateText(r.endDate)}` : ''}
                </td>
                <td className="py-2 pr-3 whitespace-nowrap">{r.nextShift ? <LocalTime iso={r.nextShift} /> : '—'}</td>
              </tr>
            ))}
          </Table>
          <p className="text-xs muted mt-2">
            Shift rosters, check-in codes and attendance for these workers are in the{' '}
            <Link href={`${W}/shifts`} className="underline">
              schedule
            </Link>
            .
          </p>
        </div>
      )}
    </div>
  );
}
