import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import {
  EXCEPTION_LABEL,
  LEAVE_LABEL,
  fmtIn,
  hours,
  onlyWf,
  parseApprovals,
  timesheetTone,
  utcToZonedInput,
  wfCan,
  type ApprovalException,
} from '@/lib/workforce';
import { AttendanceReview } from '../attendance/review-forms';
import { ErrorNote, ExceptionsAreForReview, Notice, PageHeader, Section, TonePill, dateText } from '../ui';
import LeaveReview from './leave-review';

export const metadata: Metadata = { title: 'Approvals · Workforce · Omelo' };

const W = '/dashboard/workforce';

export default async function ApprovalsPage() {
  const ctx = (await getCompanyContext())!;
  if (!wfCan(ctx, 'approve_time')) {
    return (
      <div className="space-y-5">
        <PageHeader title="Approvals" />
        <Notice title="Not available to your role">{onlyWf(ctx.kind, 'approve_time', 'approve attendance, timesheets and leave')}</Notice>
      </div>
    );
  }
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('omelo_workforce_approvals', { p_company: ctx.companyId });
  if (error) {
    return (
      <div className="space-y-5">
        <PageHeader title="Approvals" />
        <ErrorNote label="approvals" message={error.message} />
      </div>
    );
  }
  const ap = parseApprovals(data);

  // One review per attendance record (it resolves all of its pending exceptions).
  const byAttendance = new Map<string, ApprovalException[]>();
  for (const x of ap.exceptions) byAttendance.set(x.attendanceId, [...(byAttendance.get(x.attendanceId) ?? []), x]);
  const attIds = [...byAttendance.keys()];
  const { data: att } = attIds.length
    ? await supabase
        .from('attendance_records')
        .select('id, break_minutes, scheduled_end, shift_id, shifts ( timezone )')
        .in('id', attIds.slice(0, 500))
    : { data: [] as { id: string; break_minutes: number; scheduled_end: string; shift_id: string; shifts: unknown }[] };
  const meta = new Map(
    (att ?? []).map((a) => [
      a.id,
      {
        tz: (a.shifts as { timezone: string } | null)?.timezone ?? 'UTC',
        breakMinutes: a.break_minutes,
        scheduledEnd: a.scheduled_end,
        shiftId: a.shift_id,
      },
    ])
  );

  return (
    <div className="space-y-6">
      <PageHeader
        title="Approvals"
        subtitle={
          ctx.kind === 'employer'
            ? 'Attendance, timesheets and leave for your workers — including agency workers at your sites, whose time you approve as the workplace.'
            : 'Attendance, timesheets and leave for your workers. Time worked at clients on Omelo is approved by the client.'
        }
      />

      <Section title={`Attendance exceptions (${byAttendance.size})`} id="exceptions">
        <ExceptionsAreForReview />
        {byAttendance.size === 0 ? (
          <p className="text-sm muted">Nothing to review.</p>
        ) : (
          <ul className="space-y-4">
            {[...byAttendance.entries()].map(([attId, xs]) => {
              const first = xs[0];
              const m = meta.get(attId) ?? { tz: 'UTC', breakMinutes: 0, scheduledEnd: null, shiftId: null };
              return (
                <li key={attId} className="surface rounded-lg p-3 space-y-3">
                  <div className="flex gap-2 flex-wrap items-start">
                    <div className="flex-1 min-w-[12rem]">
                      <p className="font-semibold break-words">
                        <Link href={`${W}/attendance/${attId}`} className="hover:underline">
                          {first.worker}
                        </Link>
                        <span className="muted font-normal"> · {first.title}</span>
                      </p>
                      <p className="text-xs muted">
                        {fmtIn(first.scheduledStart, m.tz, 'datetime')} · in {first.checkInAt ? fmtIn(first.checkInAt, m.tz, 'time') : '—'} · out{' '}
                        {first.checkOutAt ? fmtIn(first.checkOutAt, m.tz, 'time') : '—'}
                      </p>
                    </div>
                    <div className="flex gap-1.5 flex-wrap">
                      {xs.map((x) => (
                        <span key={x.exceptionId} className="pill" style={{ color: 'var(--color-warn)', borderColor: 'var(--color-warn)' }}>
                          {EXCEPTION_LABEL[x.kind] ?? x.kind}
                          {x.minutes ? ` · ${x.minutes} min` : ''}
                        </span>
                      ))}
                    </div>
                  </div>
                  <AttendanceReview
                    compact
                    attendanceId={attId}
                    tz={m.tz}
                    breakMinutes={m.breakMinutes}
                    defaultIn={utcToZonedInput(first.checkInAt ?? first.scheduledStart, m.tz)}
                    defaultOut={utcToZonedInput(first.checkOutAt ?? m.scheduledEnd, m.tz)}
                  />
                </li>
              );
            })}
          </ul>
        )}
      </Section>

      <Section title={`Timesheets (${ap.timesheets.length})`} id="timesheets">
        {ap.timesheets.length === 0 ? (
          <p className="text-sm muted">No timesheets waiting.</p>
        ) : (
          <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
            {ap.timesheets.map((t) => (
              <li key={t.timesheetId} className="py-2.5 flex items-center gap-3 flex-wrap">
                <div className="flex-1 min-w-[12rem]">
                  <Link href={`${W}/timesheets/${t.timesheetId}`} className="font-semibold text-sm hover:underline break-words">
                    {t.worker} · {t.title}
                  </Link>
                  <p className="text-xs muted">
                    {dateText(t.periodStart)} – {dateText(t.periodEnd)}
                  </p>
                </div>
                <span className="text-sm tabular-nums whitespace-nowrap">
                  {hours(t.totalMinutes)}
                  {t.overtimeMinutes ? <span className="muted"> · {hours(t.overtimeMinutes)} overtime</span> : null}
                </span>
                <TonePill tone={timesheetTone(t.status)} />
                <Link href={`${W}/timesheets/${t.timesheetId}`} className="btn btn-ghost" style={{ height: 34 }}>
                  Review
                </Link>
              </li>
            ))}
          </ul>
        )}
      </Section>

      <Section title={`Leave (${ap.leave.length})`} id="leave">
        {ap.leave.length === 0 ? (
          <p className="text-sm muted">No leave requests waiting.</p>
        ) : (
          <ul className="space-y-3">
            {ap.leave.map((l) => (
              <li key={l.leaveId} className="surface rounded-lg p-3 space-y-2">
                <p className="text-sm break-words">
                  <strong>{l.worker}</strong> <span className="muted">· {l.title}</span>
                </p>
                <p className="text-sm">
                  {l.label ?? LEAVE_LABEL[l.leaveType] ?? l.leaveType} · {dateText(l.startDate)}
                  {l.endDate !== l.startDate ? ` – ${dateText(l.endDate)}` : ''}
                </p>
                {l.reason && <p className="text-sm muted break-words">“{l.reason}”</p>}
                <LeaveReview leaveId={l.leaveId} />
              </li>
            ))}
          </ul>
        )}
      </Section>
    </div>
  );
}
