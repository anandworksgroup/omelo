import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createClient, getCompanyContext, getUser } from '@/lib/supabase/server';
import { WORK_TYPE_LABEL } from '@/lib/format';
import { UUID_RE } from '@/lib/talent';
import { loadTeam, memberName } from '@/lib/team';
import {
  CHECK_IN_LABEL,
  LEAVE_LABEL,
  PAY_BASIS_LABEL,
  PAY_FREQUENCY_LABEL,
  addDays,
  assignmentTone,
  attendanceTone,
  daysText,
  earningTone,
  fmtIn,
  hours,
  leaveTone,
  loadWorkerNames,
  money,
  nice,
  onlyWf,
  parseAgreement,
  rate,
  reviewTone,
  shiftWorkerTone,
  timesheetTone,
  wfCan,
  zonedDate,
} from '@/lib/workforce';
import { loadHistory, serverNow } from '../../data';
import { PayComponentsPanel } from '../../requirements/[id]/parts';
import { ErrorNote, ExceptionsAreForReview, Facts, History, Notice, PageHeader, Section, Table, TonePill, Why, dateText } from '../../ui';
import { AssignmentActions, BillingForm, BuildTimesheet } from './parts';

export const metadata: Metadata = { title: 'Assignment · Workforce · Omelo' };

const W = '/dashboard/workforce';

export default async function AssignmentPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID_RE.test(id)) notFound();
  const ctx = (await getCompanyContext())!;
  const [supabase, user] = await Promise.all([createClient(), getUser()]);
  const { data: a, error } = await supabase
    .from('assignments')
    .select('*, work_identities ( label ), workforce_requirements ( title, check_in_method )')
    .eq('id', id)
    .eq('company_id', ctx.companyId)
    .maybeSingle();
  if (error) return <ErrorNote label="the assignment" message={error.message} />;
  if (!a) {
    return (
      <div className="space-y-5">
        <PageHeader title="Assignment" back={{ href: `${W}/assignments`, label: 'Assignments' }} />
        <Notice title="Not one of your company’s assignments">
          {ctx.kind === 'employer'
            ? 'If this is an agency worker at your site, see Workforce at your sites — the agency manages the assignment; you approve time.'
            : 'It may belong to another workspace. Switch workspace and try again.'}
        </Notice>
      </div>
    );
  }

  const now = serverNow();
  const tz = a.timezone;
  const today = zonedDate(now, tz);
  const isAgency = ctx.kind === 'agency';
  const canManage = wfCan(ctx, 'manage_workforce');
  const canPay = wfCan(ctx, 'manage_pay');
  const clientApproves = !!a.client_company_id && a.client_company_id !== ctx.companyId;
  const req = a.workforce_requirements as unknown as { title: string; check_in_method: string } | null;

  const [names, shiftsRes, attRes, tsRes, earnRes, leaveRes, compRes, billRes, clientRes, team, history] = await Promise.all([
    loadWorkerNames(supabase, ctx, [{ personId: a.person_id, identityId: a.work_identity_id }]),
    supabase
      .from('shift_workers')
      .select('id, status, starts_at, ends_at, shift_id, shifts ( timezone, status, kind )')
      .eq('assignment_id', id)
      .gte('ends_at', new Date(now).toISOString())
      .order('starts_at')
      .limit(20),
    supabase
      .from('attendance_records')
      .select('id, scheduled_start, scheduled_end, check_in_at, check_out_at, status, review_status, worked_minutes, payable_minutes')
      .eq('assignment_id', id)
      .order('scheduled_start', { ascending: false })
      .limit(200),
    supabase
      .from('timesheets')
      .select('id, period_start, period_end, status, total_minutes, overtime_minutes')
      .eq('assignment_id', id)
      .order('period_start', { ascending: false }),
    supabase
      .from('earnings')
      .select('id, period_start, period_end, gross_amount, currency, status')
      .eq('assignment_id', id)
      .order('period_start', { ascending: false }),
    supabase
      .from('leave_requests')
      .select('id, leave_type, label, start_date, end_date, status, reason')
      .eq('assignment_id', id)
      .order('start_date', { ascending: false }),
    supabase.from('pay_components').select('id, kind, name, amount, basis, applies_to_shift_types').eq('assignment_id', id),
    isAgency && canPay
      ? supabase.from('assignment_billing').select('bill_rate, bill_period, currency, note, updated_at').eq('assignment_id', id).maybeSingle()
      : Promise.resolve({ data: null }),
    a.client_id ? supabase.from('agency_clients').select('name').eq('id', a.client_id).maybeSingle() : Promise.resolve({ data: null }),
    loadTeam(supabase, ctx.companyId, user?.id ?? null, user?.email ?? null),
    loadHistory(supabase, ctx, user ? { id: user.id, email: user.email ?? null } : null, 'assignment', [id]),
  ]);

  const name = names.get(a.person_id) ?? 'Worker';
  const identity = (a.work_identities as unknown as { label: string | null } | null)?.label ?? null;
  const agreement = parseAgreement(a.agreement);
  const att = attRes.data ?? [];
  const byStatus = new Map<string, number>();
  for (const r of att) byStatus.set(r.status, (byStatus.get(r.status) ?? 0) + 1);
  const worked = att.reduce((s, r) => s + (r.payable_minutes ?? r.worked_minutes ?? 0), 0);
  const pendingReview = att.filter((r) => r.review_status === 'pending').length;
  const supervisor = team.members.find((m) => m.personId === a.supervisor_id);
  const billing = billRes.data as { bill_rate: number; bill_period: string; currency: string; note: string | null } | null;
  const client = (clientRes.data as { name: string } | null)?.name ?? agreement.client;
  const when = (iso: string) => fmtIn(iso, tz, 'datetime');

  return (
    <div className="space-y-6">
      <PageHeader
        back={{ href: `${W}/assignments`, label: 'Assignments' }}
        title={name}
        subtitle={
          <span className="inline-flex gap-2 items-center flex-wrap">
            <TonePill tone={assignmentTone(a.status)} />
            <span>
              {a.title}
              {identity ? ` · as ${identity}` : ''}
              {client ? ` · at ${client}` : ''}
            </span>
          </span>
        }
      />

      <Section title="Terms">
        <Facts
          items={[
            ['Requirement', <Link key="r" href={`${W}/requirements/${a.requirement_id}`} className="underline">{req?.title ?? 'Open'}</Link>],
            ['Dates', `${dateText(a.start_date)}${a.end_date ? ` – ${dateText(a.end_date)}` : ' onwards'}`],
            ['Pay', rate(a.pay_rate, a.currency, a.pay_period)],
            ['Paid', PAY_FREQUENCY_LABEL[a.pay_frequency] ?? a.pay_frequency],
            ['Employment', `${nice(a.employment_type)} · ${WORK_TYPE_LABEL[a.work_type] ?? a.work_type}`],
            ['Location', a.location_text || '—'],
            ['Supervisor', supervisor ? memberName(supervisor) : agreement.supervisor ?? '—'],
            ['Source', nice(a.source)],
            ['Offered', a.offered_at ? fmtIn(a.offered_at, tz, 'date') : '—'],
            ['Answered', a.responded_at ? fmtIn(a.responded_at, tz, 'date') : a.status === 'offered' ? `Offer expires ${fmtIn(a.offer_expires_at, tz, 'date')}` : '—'],
            ['Started', a.activated_at ? fmtIn(a.activated_at, tz, 'date') : '—'],
            ['Ended', a.ended_at ? `${fmtIn(a.ended_at, tz, 'date')}${a.end_reason ? ` · ${a.end_reason}` : ''}` : '—'],
          ]}
        />
        {a.decline_reason && <p className="text-sm">Declined: “{a.decline_reason}”</p>}
        {a.employment_id && (
          <p className="text-xs muted">
            This work is recorded as employment; when it completes it becomes verified experience on the worker’s identity.
          </p>
        )}
      </Section>

      <Section title="What the worker agreed to">
        <Facts
          items={[
            ['Employer', agreement.employer ?? '—'],
            ['Client', agreement.client ?? '—'],
            ['Hours a week', agreement.hoursPerWeek != null ? String(agreement.hoursPerWeek) : '—'],
            ['Check-in', agreement.checkIn ? (CHECK_IN_LABEL[agreement.checkIn] ?? agreement.checkIn) : '—'],
            [
              'Overtime',
              agreement.overtime
                ? `${agreement.overtime.name} ×${agreement.overtime.multiplier}${agreement.overtime.daily != null ? ` after ${hours(agreement.overtime.daily)}/day` : ''}${agreement.overtime.weekly != null ? ` after ${hours(agreement.overtime.weekly)}/week` : ''}`
                : 'None',
            ],
          ]}
        />
        {agreement.shifts.length > 0 && (
          <ul className="text-sm space-y-0.5">
            {agreement.shifts.map((s, i) => (
              <li key={i}>
                <span className="font-semibold">{s.name}</span>{' '}
                <span className="muted">
                  {daysText(s.days)} · {s.start}–{s.end} · {s.breakMinutes} min break
                </span>
              </li>
            ))}
          </ul>
        )}
        {agreement.allowances.length > 0 && (
          <ul className="text-sm space-y-0.5">
            {agreement.allowances.map((x, i) => (
              <li key={i}>
                {x.name} <span className="muted">· {nice(x.kind)} · {money(x.amount, a.currency)} {PAY_BASIS_LABEL[x.basis] ?? x.basis}</span>
              </li>
            ))}
          </ul>
        )}
      </Section>

      <Section title="Status">
        {canManage ? (
          <AssignmentActions id={id} status={a.status} today={today} />
        ) : (
          <Why>{onlyWf(ctx.kind, 'manage_workforce', 'change an assignment')}</Why>
        )}
      </Section>

      {isAgency && canPay && (
        <Section title="Billing to the client">
          <p className="text-xs muted">
            Only your pay team sees this. The worker never sees the bill rate; the client sees its bills, never the worker’s pay.
          </p>
          <BillingForm id={id} billRate={billing?.bill_rate ?? null} billPeriod={billing?.bill_period ?? null} note={billing?.note ?? null} />
        </Section>
      )}

      <div className="grid gap-6 lg:grid-cols-2 items-start">
        <Section
          title="Upcoming shifts"
          aside={
            <Link href={`${W}/shifts?req=${a.requirement_id}`} className="text-sm underline muted">
              Schedule
            </Link>
          }
        >
          {(shiftsRes.data ?? []).length === 0 ? (
            <p className="text-sm muted">No upcoming shifts.</p>
          ) : (
            <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
              {(shiftsRes.data ?? []).map((w) => {
                const s = w.shifts as unknown as { timezone: string; status: string } | null;
                const z = s?.timezone ?? tz;
                return (
                  <li key={w.id} className="py-2 flex items-center gap-2 flex-wrap text-sm">
                    <Link href={`${W}/shifts/${w.shift_id}`} className="flex-1 min-w-[10rem] hover:underline">
                      {fmtIn(w.starts_at, z, 'datetime')}–{fmtIn(w.ends_at, z, 'time')}
                    </Link>
                    <TonePill tone={shiftWorkerTone(s?.status === 'cancelled' ? 'cancelled' : w.status)} />
                  </li>
                );
              })}
            </ul>
          )}
        </Section>

        <Section title="Attendance">
          <div className="flex gap-4 flex-wrap text-sm">
            <span>
              <strong className="tabular-nums">{att.length}</strong> <span className="muted">shifts recorded</span>
            </span>
            <span>
              <strong className="tabular-nums">{hours(worked)}</strong> <span className="muted">worked</span>
            </span>
            {pendingReview > 0 && (
              <span style={{ color: 'var(--color-warn)' }}>
                <strong>{pendingReview}</strong> need review
              </span>
            )}
          </div>
          <div className="flex gap-1.5 flex-wrap">
            {[...byStatus.entries()].map(([s, n]) => (
              <span key={s} className="pill">
                {attendanceTone(s).label} {n}
              </span>
            ))}
          </div>
          {clientApproves && (
            <p className="text-xs muted">
              The client approves attendance and timesheets at its own site; you see the results here.
            </p>
          )}
          <ExceptionsAreForReview />
          {att.length > 0 && (
            <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
              {att.slice(0, 10).map((r) => (
                <li key={r.id} className="py-2 flex items-center gap-2 flex-wrap text-sm">
                  <Link href={`${W}/attendance/${r.id}`} className="flex-1 min-w-[10rem] hover:underline">
                    {fmtIn(r.scheduled_start, tz, 'day')} · {r.check_in_at ? fmtIn(r.check_in_at, tz, 'time') : '—'}–
                    {r.check_out_at ? fmtIn(r.check_out_at, tz, 'time') : '—'}
                  </Link>
                  <TonePill tone={attendanceTone(r.status)} />
                  {r.review_status !== 'none' && <TonePill tone={reviewTone(r.review_status)} />}
                </li>
              ))}
            </ul>
          )}
        </Section>
      </div>

      <div className="grid gap-6 lg:grid-cols-2 items-start">
        <Section title="Timesheets">
          {(tsRes.data ?? []).length === 0 ? (
            <p className="text-sm muted">No timesheets yet.</p>
          ) : (
            <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
              {(tsRes.data ?? []).map((t) => (
                <li key={t.id} className="py-2 flex items-center gap-2 flex-wrap text-sm">
                  <Link href={`${W}/timesheets/${t.id}`} className="flex-1 min-w-[10rem] hover:underline">
                    {dateText(t.period_start)} – {dateText(t.period_end)}
                  </Link>
                  <span className="text-xs tabular-nums">
                    {hours(t.total_minutes)}
                    {t.overtime_minutes ? ` (${hours(t.overtime_minutes)} OT)` : ''}
                  </span>
                  <TonePill tone={timesheetTone(t.status)} />
                </li>
              ))}
            </ul>
          )}
          {canManage && ['accepted', 'active', 'paused', 'completed', 'terminated'].includes(a.status) && (
            <BuildTimesheet id={id} defaultFrom={addDays(today, -6)} defaultTo={today} />
          )}
        </Section>

        <Section title="Earnings">
          {earnRes.error || (earnRes.data ?? []).length === 0 ? (
            <p className="text-sm muted">
              {wfCan(ctx, 'manage_pay') || wfCan(ctx, 'approve_time')
                ? 'No earnings yet. They are calculated when a timesheet is approved.'
                : onlyWf(ctx.kind, 'manage_pay', 'see earnings')}
            </p>
          ) : (
            <Table head={['Period', 'Gross', 'Status']}>
              {(earnRes.data ?? []).map((e) => (
                <tr key={e.id}>
                  <td className="py-2 pr-3 whitespace-nowrap">
                    {canPay ? (
                      <Link href={`${W}/pay?earning=${e.id}#e-${e.id}`} className="hover:underline">
                        {dateText(e.period_start)} – {dateText(e.period_end)}
                      </Link>
                    ) : (
                      `${dateText(e.period_start)} – ${dateText(e.period_end)}`
                    )}
                  </td>
                  <td className="py-2 pr-3 tabular-nums">{money(e.gross_amount, e.currency)}</td>
                  <td className="py-2 pr-3">
                    <TonePill tone={earningTone(e.status)} />
                  </td>
                </tr>
              ))}
            </Table>
          )}
        </Section>
      </div>

      <div className="grid gap-6 lg:grid-cols-2 items-start">
        <Section title="Leave">
          {(leaveRes.data ?? []).length === 0 ? (
            <p className="text-sm muted">No leave requested.</p>
          ) : (
            <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
              {(leaveRes.data ?? []).map((l) => (
                <li key={l.id} className="py-2 flex items-center gap-2 flex-wrap text-sm">
                  <span className="flex-1 min-w-[10rem]">
                    {l.label ?? LEAVE_LABEL[l.leave_type] ?? l.leave_type} · {dateText(l.start_date)}
                    {l.end_date !== l.start_date ? ` – ${dateText(l.end_date)}` : ''}
                  </span>
                  <TonePill tone={leaveTone(l.status)} />
                </li>
              ))}
            </ul>
          )}
        </Section>

        <Section title="Pay for this worker only">
          <PayComponentsPanel
            requirementId={null}
            assignmentId={id}
            currency={a.currency}
            canPay={canPay}
            components={(compRes.data ?? []).map((c) => ({
              id: c.id,
              kind: c.kind,
              name: c.name,
              amount: Number(c.amount),
              basis: c.basis,
              shiftTypes: c.applies_to_shift_types ?? [],
            }))}
          />
        </Section>
      </div>

      <Section title="History">
        <History events={history} when={when} />
      </Section>
    </div>
  );
}
