/**
 * Presentational pieces shared by the workforce pages. No hooks, so server
 * and client components can both use them.
 */
import type { ReactNode } from 'react';
import type { Tone } from '@/lib/workforce';
import { Pill } from '../agency/ui';

export { ErrorNote, FilterChips, Notice, PageHeader, Pill, Section, Tile, Why, dateText, qs } from '../agency/ui';

export function TonePill({ tone, title }: { tone: Tone; title?: string }) {
  return <Pill label={tone.label} color={tone.color} title={title} />;
}

export function ErrorLine({ text }: { text: string | null }) {
  if (!text) return null;
  return (
    <p className="text-sm basis-full break-words" role="alert" style={{ color: 'var(--color-danger)' }}>
      {text}
    </p>
  );
}

export function OkLine({ text }: { text: string | null }) {
  if (!text) return null;
  return (
    <p className="text-sm basis-full break-words" role="status" style={{ color: 'var(--color-verified)' }}>
      {text}
    </p>
  );
}

/** Key/value facts in a responsive grid. */
export function Facts({ items }: { items: [string, ReactNode][] }) {
  return (
    <dl className="grid gap-x-6 gap-y-3 grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 text-sm">
      {items.map(([k, v]) => (
        <div key={k} className="min-w-0">
          <dt className="muted text-xs">{k}</dt>
          <dd className="font-medium break-words">{v ?? '—'}</dd>
        </div>
      ))}
    </dl>
  );
}

/** A plain table that scrolls sideways on phones instead of breaking the page. */
export function Table({ head, children, empty }: { head: string[]; children: ReactNode; empty?: ReactNode }) {
  return (
    <div className="overflow-x-auto -mx-4 px-4 sm:mx-0 sm:px-0">
      <table className="w-full text-sm min-w-[36rem]">
        <thead>
          <tr className="text-left muted text-xs">
            {head.map((h) => (
              <th key={h} className="font-semibold py-2 pr-3 whitespace-nowrap">
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y" style={{ borderColor: 'var(--line)' }}>
          {children}
        </tbody>
      </table>
      {empty}
    </div>
  );
}

/** The note every screen that surfaces exceptions carries. */
export function ExceptionsAreForReview() {
  return (
    <p className="text-xs muted">
      Exceptions (late, left early, no check-in, no check-out, location, corrections) are flagged for a person to
      review. Omelo never applies a penalty automatically.
    </p>
  );
}

export type HistoryEvent = {
  id: number;
  event: string;
  actor: string | null;
  reason: string | null;
  occurredAt: string;
  before: unknown;
  after: unknown;
};

const EVENT_LABEL: Record<string, string> = {
  AssignmentOffered: 'Offered',
  AssignmentStarted: 'Started',
  AssignmentStatusChanged: 'Status changed',
  AttendanceRecordedBySupervisor: 'Recorded by a supervisor',
  AttendanceReviewed: 'Reviewed',
  AttendanceCorrected: 'Corrected',
  RequirementUpdated: 'Requirement updated',
  ShiftChanged: 'Shift changed',
  TimesheetReopened: 'Timesheet reopened',
  EarningAdjusted: 'Earnings adjusted',
};

function statusChange(before: unknown, after: unknown): string | null {
  const b = before && typeof before === 'object' ? (before as Record<string, unknown>).status : null;
  const a = after && typeof after === 'object' ? (after as Record<string, unknown>).status : null;
  if (typeof a !== 'string') return null;
  return typeof b === 'string' && b !== a ? `${b.replace(/_/g, ' ')} → ${a.replace(/_/g, ' ')}` : a.replace(/_/g, ' ');
}

/** Audit trail from workforce_events. `when` renders a timestamp (server-safe). */
export function History({ events, when }: { events: HistoryEvent[]; when: (iso: string) => ReactNode }) {
  if (events.length === 0) return <p className="text-sm muted">Nothing recorded yet.</p>;
  return (
    <ol className="space-y-3">
      {events.map((e) => {
        const change = statusChange(e.before, e.after);
        return (
          <li key={e.id} className="flex gap-3">
            <span aria-hidden className="mt-1.5 w-2 h-2 rounded-full shrink-0" style={{ background: 'var(--color-brand-600)' }} />
            <div className="min-w-0 text-sm">
              <p className="font-semibold break-words">
                {EVENT_LABEL[e.event] ?? e.event.replace(/([a-z])([A-Z])/g, '$1 $2')}
                {change ? <span className="muted font-normal"> · {change}</span> : null}
              </p>
              <p className="text-xs muted break-words">
                {when(e.occurredAt)}
                {e.actor ? ` · ${e.actor}` : ''}
              </p>
              {e.reason && <p className="text-sm break-words mt-0.5">“{e.reason}”</p>}
            </div>
          </li>
        );
      })}
    </ol>
  );
}

export function ProgressBar({ value, max, label }: { value: number; max: number; label: string }) {
  const pct = max > 0 ? Math.min(100, Math.round((value / max) * 100)) : 0;
  return (
    <div
      role="progressbar"
      aria-label={label}
      aria-valuemin={0}
      aria-valuemax={max}
      aria-valuenow={value}
      className="h-2.5 rounded-full overflow-hidden"
      style={{ background: 'var(--surface)', boxShadow: 'inset 0 0 0 1px var(--line)' }}
    >
      <div className="h-full rounded-full transition-all" style={{ width: `${pct}%`, background: 'var(--color-brand-600)' }} />
    </div>
  );
}
