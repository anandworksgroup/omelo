import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createClient, getCompanyContext, getUser } from '@/lib/supabase/server';
import { UUID_RE } from '@/lib/talent';
import {
  EXCEPTION_LABEL,
  attendanceTone,
  fmtIn,
  hours,
  nice,
  onlyWf,
  parseRoster,
  reviewTone,
  tzShort,
  utcToZonedInput,
  wfCan,
} from '@/lib/workforce';
import { loadHistory } from '../../data';
import { ErrorNote, ExceptionsAreForReview, Facts, History, Notice, PageHeader, Section, TonePill, Why } from '../../ui';
import { AttendanceReview, CorrectAttendance } from '../review-forms';

export const metadata: Metadata = { title: 'Attendance · Workforce · Omelo' };

const W = '/dashboard/workforce';

export default async function AttendancePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID_RE.test(id)) notFound();
  const ctx = (await getCompanyContext())!;
  const [supabase, user] = await Promise.all([createClient(), getUser()]);
  const { data: ar, error } = await supabase
    .from('attendance_records')
    .select(
      'id, shift_id, shift_worker_id, assignment_id, scheduled_start, scheduled_end, break_minutes, check_in_at, check_in_method, check_out_at, check_out_method, worked_minutes, payable_minutes, status, review_status, review_note, reviewed_at'
    )
    .eq('id', id)
    .maybeSingle();
  const back = { href: `${W}/approvals`, label: 'Approvals' };
  if (error) return <ErrorNote label="attendance" message={error.message} />;
  if (!ar) {
    return (
      <div className="space-y-5">
        <PageHeader title="Attendance" back={back} />
        <Notice title="Not available">This attendance record does not exist or is not visible to you.</Notice>
      </div>
    );
  }

  const [rosterRes, exRes, asgRes, tsRes, history] = await Promise.all([
    supabase.rpc('omelo_shift_roster', { p_shift: ar.shift_id }),
    supabase
      .from('attendance_exceptions')
      .select('id, kind, minutes, detail, status, resolution_note, resolved_at, created_at')
      .eq('attendance_id', id)
      .order('created_at'),
    supabase.from('assignments').select('id, company_id, client_company_id, title').eq('id', ar.assignment_id).maybeSingle(),
    supabase
      .from('timesheet_entries')
      .select('timesheet_id, timesheets ( status, period_start, period_end )')
      .eq('attendance_id', id)
      .maybeSingle(),
    loadHistory(supabase, ctx, user ? { id: user.id, email: user.email ?? null } : null, 'attendance', [id]),
  ]);
  const roster = parseRoster(rosterRes.data ?? null);
  const tz = roster.shift?.timezone ?? 'UTC';
  const worker = roster.workers.find((w) => w.shiftWorkerId === ar.shift_worker_id);
  const asg = asgRes.data;
  // The workplace approves: the client for agency workers at a client on Omelo.
  const approverIsUs = asg
    ? asg.client_company_id
      ? asg.client_company_id === ctx.companyId
      : asg.company_id === ctx.companyId
    : true;
  const canApprove = wfCan(ctx, 'approve_time') && approverIsUs;
  const ts = tsRes.data as { timesheet_id: string; timesheets: { status: string; period_start: string; period_end: string } | null } | null;
  const tsLocked = !!ts?.timesheets && ['approved', 'locked'].includes(ts.timesheets.status);
  const reviewed = ['approved', 'adjusted', 'rejected'].includes(ar.review_status);
  const when = (iso: string) => fmtIn(iso, tz, 'datetime');

  return (
    <div className="space-y-6">
      <PageHeader
        back={back}
        title={`${worker?.name ?? 'Worker'} · ${fmtIn(ar.scheduled_start, tz, 'day')}`}
        subtitle={
          <span className="inline-flex gap-2 items-center flex-wrap">
            <TonePill tone={attendanceTone(ar.status)} />
            <TonePill tone={reviewTone(ar.review_status)} />
            <Link href={`${W}/shifts/${ar.shift_id}`} className="underline">
              Shift {fmtIn(ar.scheduled_start, tz, 'time')}–{fmtIn(ar.scheduled_end, tz, 'time')}
            </Link>
            {asg && asg.company_id === ctx.companyId && (
              <Link href={`${W}/assignments/${asg.id}`} className="underline">
                {asg.title}
              </Link>
            )}
          </span>
        }
      />

      <Section title="Times">
        <Facts
          items={[
            ['Scheduled', `${fmtIn(ar.scheduled_start, tz, 'time')}–${fmtIn(ar.scheduled_end, tz, 'time')} (${tzShort(tz)})`],
            ['Arrived', ar.check_in_at ? `${fmtIn(ar.check_in_at, tz, 'datetime')} · ${nice(ar.check_in_method)}` : '—'],
            ['Left', ar.check_out_at ? `${fmtIn(ar.check_out_at, tz, 'datetime')} · ${nice(ar.check_out_method)}` : '—'],
            ['Break', `${ar.break_minutes} min`],
            ['Worked', hours(ar.worked_minutes)],
            ['Payable', ar.payable_minutes != null ? hours(ar.payable_minutes) : 'After review'],
            ['Review', ar.review_note ? `${reviewTone(ar.review_status).label} · “${ar.review_note}”` : reviewTone(ar.review_status).label],
            [
              'Timesheet',
              ts?.timesheets ? (
                <Link key="t" href={`${W}/timesheets/${ts.timesheet_id}`} className="underline">
                  {ts.timesheets.period_start} – {ts.timesheets.period_end} ({ts.timesheets.status.replace(/_/g, ' ')})
                </Link>
              ) : (
                'Not on a timesheet yet'
              ),
            ],
          ]}
        />
      </Section>

      <Section title="Exceptions">
        <ExceptionsAreForReview />
        {(exRes.data ?? []).length === 0 ? (
          <p className="text-sm muted">None.</p>
        ) : (
          <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
            {(exRes.data ?? []).map((x) => (
              <li key={x.id} className="py-2 flex items-center gap-2 flex-wrap text-sm">
                <span className="flex-1 min-w-[10rem] break-words">
                  <span className="font-semibold">{EXCEPTION_LABEL[x.kind] ?? x.kind}</span>
                  {x.minutes ? <span className="muted"> · {x.minutes} min</span> : null}
                  {x.detail ? <span className="muted"> · {x.detail}</span> : null}
                  {x.resolution_note ? <span className="block text-xs muted">“{x.resolution_note}”</span> : null}
                </span>
                <TonePill tone={reviewTone(x.status)} />
              </li>
            ))}
          </ul>
        )}
      </Section>

      <Section title="Decide">
        {!canApprove ? (
          <Why>
            {!approverIsUs
              ? 'The client approves attendance for its site.'
              : onlyWf(ctx.kind, 'approve_time', 'approve attendance')}
          </Why>
        ) : !reviewed ? (
          <AttendanceReview
            attendanceId={id}
            tz={tz}
            defaultIn={utcToZonedInput(ar.check_in_at ?? ar.scheduled_start, tz)}
            defaultOut={utcToZonedInput(ar.check_out_at ?? ar.scheduled_end, tz)}
            breakMinutes={ar.break_minutes}
          />
        ) : tsLocked ? (
          <Why>This attendance is on an approved timesheet. To correct it, the pay team reopens the timesheet first.</Why>
        ) : (
          <CorrectAttendance
            attendanceId={id}
            tz={tz}
            defaultIn={utcToZonedInput(ar.check_in_at ?? ar.scheduled_start, tz)}
            defaultOut={utcToZonedInput(ar.check_out_at ?? ar.scheduled_end, tz)}
          />
        )}
      </Section>

      <Section title="History">
        {asg && asg.company_id !== ctx.companyId ? (
          <p className="text-sm muted">The agency keeps this record’s history.</p>
        ) : (
          <History events={history} when={when} />
        )}
      </Section>
    </div>
  );
}
