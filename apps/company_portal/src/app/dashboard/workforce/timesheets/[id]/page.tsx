import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { UUID_RE } from '@/lib/talent';
import {
  earningTone,
  hours,
  loadWorkerNames,
  money,
  nice,
  onlyWf,
  parseApprovals,
  timesheetTone,
  wfCan,
} from '@/lib/workforce';
import { ErrorNote, Notice, PageHeader, Section, Table, TonePill, Why, dateText } from '../../ui';
import { ReopenTimesheet, TimesheetDecision } from './review';

export const metadata: Metadata = { title: 'Timesheet · Workforce · Omelo' };

const W = '/dashboard/workforce';

export default async function TimesheetPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID_RE.test(id)) notFound();
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const back = { href: `${W}/approvals#timesheets`, label: 'Approvals' };
  const { data: t, error } = await supabase.from('timesheets').select('*').eq('id', id).maybeSingle();
  if (error) return <ErrorNote label="the timesheet" message={error.message} />;
  if (!t) {
    return (
      <div className="space-y-5">
        <PageHeader title="Timesheet" back={back} />
        <Notice title="Not available">This timesheet does not exist or is not visible to you.</Notice>
      </div>
    );
  }

  const [entriesRes, asgRes, earnRes] = await Promise.all([
    supabase.from('timesheet_entries').select('id, attendance_id, work_date, minutes, kind, note').eq('timesheet_id', id).order('work_date'),
    supabase.from('assignments').select('id, company_id, client_company_id, title, person_id, work_identity_id').eq('id', t.assignment_id).maybeSingle(),
    supabase.from('earnings').select('id, gross_amount, currency, status').eq('timesheet_id', id).maybeSingle(),
  ]);
  const entries = entriesRes.data ?? [];
  const attIds = entries.map((e) => e.attendance_id).filter((x): x is string => !!x);
  const { data: pend } = attIds.length
    ? await supabase.from('attendance_exceptions').select('id, attendance_id').in('attendance_id', attIds).eq('status', 'pending')
    : { data: [] as { id: string; attendance_id: string }[] };
  const pendingByAtt = new Map<string, number>();
  for (const p of pend ?? []) pendingByAtt.set(p.attendance_id, (pendingByAtt.get(p.attendance_id) ?? 0) + 1);

  const asg = asgRes.data;
  const managing = t.company_id === ctx.companyId;
  const approverIsUs = asg ? (asg.client_company_id ? asg.client_company_id === ctx.companyId : asg.company_id === ctx.companyId) : true;
  const canApprove = wfCan(ctx, 'approve_time') && approverIsUs;
  const canPay = wfCan(ctx, 'manage_pay') && managing;

  let worker = 'Worker';
  let title = asg?.title ?? null;
  if (asg) {
    const names = await loadWorkerNames(supabase, ctx, [{ personId: asg.person_id, identityId: asg.work_identity_id }]);
    worker = names.get(asg.person_id) ?? worker;
  } else if (canApprove) {
    const ap = await supabase.rpc('omelo_workforce_approvals', { p_company: ctx.companyId });
    const hit = parseApprovals(ap.data ?? null).timesheets.find((x) => x.timesheetId === id);
    if (hit) {
      worker = hit.worker;
      title = hit.title;
    }
  }
  const earning = earnRes.data;
  const byDay = new Map<string, number>();
  for (const e of entries) if (e.kind !== 'leave') byDay.set(e.work_date, (byDay.get(e.work_date) ?? 0) + e.minutes);

  return (
    <div className="space-y-6">
      <PageHeader
        back={back}
        title={`${worker} · ${dateText(t.period_start)} – ${dateText(t.period_end)}`}
        subtitle={
          <span className="inline-flex gap-2 items-center flex-wrap">
            <TonePill tone={timesheetTone(t.status)} />
            {asg && managing ? (
              <Link href={`${W}/assignments/${asg.id}`} className="underline">
                {title}
              </Link>
            ) : (
              <span>{title}</span>
            )}
          </span>
        }
      />

      <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
        {[
          ['Total', hours(t.total_minutes)],
          ['Regular', hours(t.regular_minutes)],
          ['Overtime', hours(t.overtime_minutes)],
          ['Days worked', String(t.days_worked)],
          ['Shifts', String(t.shifts_worked)],
        ].map(([k, v]) => (
          <div key={k} className="card p-3 min-w-0">
            <div className="text-lg sm:text-xl font-black tabular-nums">{v}</div>
            <div className="text-xs muted">{k}</div>
          </div>
        ))}
      </div>
      <p className="text-xs muted">
        Overtime follows the overtime policy on the worker’s assignment, as your company configured it. Omelo does not
        assume a legal overtime rule; without a policy there is no overtime.
      </p>

      <Section title={`Entries (${entries.length})`}>
        {entries.length === 0 ? (
          <p className="text-sm muted">No entries. Timesheets collect finished attendance for the period.</p>
        ) : (
          <Table head={['Day', 'Time', 'Kind', 'Note', '']}>
            {entries.map((e) => (
              <tr key={e.id}>
                <td className="py-2 pr-3 whitespace-nowrap">{dateText(e.work_date)}</td>
                <td className="py-2 pr-3 tabular-nums whitespace-nowrap">{hours(e.minutes)}</td>
                <td className="py-2 pr-3">{e.kind === 'manual' ? 'Added by worker' : nice(e.kind)}</td>
                <td className="py-2 pr-3 break-words max-w-[16rem]">{e.note ?? ''}</td>
                <td className="py-2 pr-3 whitespace-nowrap">
                  {e.attendance_id && (
                    <Link href={`${W}/attendance/${e.attendance_id}`} className="text-xs underline">
                      {pendingByAtt.get(e.attendance_id) ? (
                        <span style={{ color: 'var(--color-warn)' }}>Needs review</span>
                      ) : (
                        'Attendance'
                      )}
                    </Link>
                  )}
                </td>
              </tr>
            ))}
          </Table>
        )}
        {byDay.size > 0 && (
          <p className="text-xs muted">
            {[...byDay.entries()].map(([d, m]) => `${d.slice(5)}: ${hours(m)}`).join(' · ')}
          </p>
        )}
      </Section>

      <Section title="Decision">
        {t.reject_reason && t.status === 'rejected' && <p className="text-sm">Returned: “{t.reject_reason}”</p>}
        {['submitted', 'under_review'].includes(t.status) ? (
          canApprove ? (
            <TimesheetDecision id={id} status={t.status} pendingExceptions={pend?.length ?? 0} canPayLink={canPay} />
          ) : (
            <Why>{approverIsUs ? onlyWf(ctx.kind, 'approve_time', 'approve timesheets') : 'The client approves timesheets for its site.'}</Why>
          )
        ) : t.status === 'draft' || t.status === 'rejected' ? (
          <Why>Waiting for the worker to submit it.</Why>
        ) : (
          <div className="space-y-3">
            {earning && (
              <p className="text-sm flex gap-2 items-center flex-wrap">
                Earnings: {canPay ? <strong>{money(earning.gross_amount, earning.currency)}</strong> : null}
                <TonePill tone={earningTone(earning.status)} />
                {canPay && (
                  <Link href={`${W}/pay?earning=${earning.id}#e-${earning.id}`} className="underline">
                    Open
                  </Link>
                )}
              </p>
            )}
            {canPay ? <ReopenTimesheet id={id} /> : <Why>Approved. {onlyWf(ctx.kind, 'manage_pay', 'reopen it')}</Why>}
          </div>
        )}
      </Section>
    </div>
  );
}
