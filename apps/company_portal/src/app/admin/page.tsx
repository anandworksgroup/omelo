import { notFound } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { num, type SystemHealth } from '@/lib/admin';
import LocalTime from '../dashboard/local-time';
import { Card, Stat, WindowSelector, parseChoice } from './ui';

const WINDOWS = [
  { value: 1, label: '1h' },
  { value: 24, label: '24h' },
  { value: 168, label: '7d' },
];

const EMAIL_STATUS_ORDER = ['queued', 'sending', 'sent', 'failed', 'cancelled', 'skipped'];

function tone(n: number | null | undefined, warnAt = 1, badAt = Infinity): 'warn' | 'bad' | undefined {
  const v = Number(n ?? 0);
  if (v >= badAt) return 'bad';
  if (v >= warnAt) return 'warn';
  return undefined;
}

function cronTone(status: string | null) {
  if (!status) return 'var(--muted)';
  if (status === 'succeeded') return 'var(--color-verified)';
  if (status === 'failed') return 'var(--color-danger)';
  return 'var(--color-warn)';
}

export default async function SystemHealthPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const hours = parseChoice(sp.hours, WINDOWS.map((w) => w.value), 24);

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('omelo_admin_system_health', { p_hours: hours });
  if (error) {
    if (error.code === '42501') notFound();
    throw error;
  }
  const h = data as unknown as SystemHealth;

  const efFailRate = h.edge_function_calls.total ? h.edge_function_calls.failed / h.edge_function_calls.total : 0;
  const emailStatuses = Object.entries(h.email.by_status ?? {}).sort(
    ([a], [b]) =>
      (EMAIL_STATUS_ORDER.indexOf(a) + 1 || 99) - (EMAIL_STATUS_ORDER.indexOf(b) + 1 || 99) || a.localeCompare(b)
  );
  const events = Object.entries(h.events ?? {}).sort(([, a], [, b]) => b - a);
  const cronFailing = h.cron.filter((c) => c.active && c.last_status === 'failed').length;

  return (
    <div className="space-y-6">
      <div className="flex items-end justify-between gap-4 flex-wrap">
        <div>
          <h1 className="text-2xl font-bold">System health</h1>
          <p className="text-sm muted mt-1">
            Last {hours === 1 ? 'hour' : hours === 168 ? '7 days' : `${hours} hours`} · generated{' '}
            <LocalTime iso={h.generated_at} />
          </p>
        </div>
        <WindowSelector param="hours" options={WINDOWS} current={hours} basePath="/admin" label="Time window" />
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <Card title="Edge function calls" tone={h.edge_function_calls.failed ? (efFailRate > 0.1 ? 'bad' : 'warn') : 'ok'}>
          <div className="grid grid-cols-2 gap-3">
            <Stat label="Calls" value={num(h.edge_function_calls.total)} />
            <Stat
              label="Failed"
              value={num(h.edge_function_calls.failed)}
              tone={h.edge_function_calls.failed ? (efFailRate > 0.1 ? 'bad' : 'warn') : undefined}
            />
          </div>
          {h.edge_function_calls.last_error && (
            <div className="mt-3">
              <p className="text-xs font-semibold muted">Last error</p>
              <pre className="text-xs mt-1 p-2 rounded-md surface whitespace-pre-wrap break-all max-h-32 overflow-auto">
                {h.edge_function_calls.last_error}
              </pre>
            </div>
          )}
        </Card>

        <Card
          title="Email"
          tone={h.email.failed_recent || h.email.overdue_queued ? (h.email.overdue_queued ? 'bad' : 'warn') : 'ok'}
        >
          <div className="grid grid-cols-2 gap-3">
            <Stat label="Overdue in queue (>15 min)" value={num(h.email.overdue_queued)} tone={tone(h.email.overdue_queued, 1, 1)} />
            <Stat label="Failed in window" value={num(h.email.failed_recent)} tone={tone(h.email.failed_recent)} />
          </div>
          <div className="mt-3 flex flex-wrap gap-1.5">
            {emailStatuses.length ? (
              emailStatuses.map(([status, n]) => (
                <span key={status} className="pill">
                  {status} <span className="tabular-nums" style={{ color: 'var(--fg)' }}>{num(n)}</span>
                </span>
              ))
            ) : (
              <span className="text-xs muted">No email in this window.</span>
            )}
          </div>
        </Card>

        <Card title="Omelo Meet" tone={h.meet.abuse_reports_open || h.meet.expired_unended ? 'warn' : 'ok'}>
          <div className="grid grid-cols-3 gap-3">
            <Stat label="Rooms live now" value={num(h.meet.rooms_live)} />
            <Stat label="Sessions" value={num(h.meet.sessions)} />
            <Stat label="Joins" value={num(h.meet.joins)} />
            <Stat label="Expired, not ended" value={num(h.meet.expired_unended)} tone={tone(h.meet.expired_unended)} />
            <Stat label="Abuse reports open" value={num(h.meet.abuse_reports_open)} tone={tone(h.meet.abuse_reports_open, 1, 1)} />
          </div>
        </Card>

        <Card
          title="Trust & safety"
          tone={h.trust_and_safety.reports_open || h.trust_and_safety.fraud_signals ? 'warn' : 'ok'}
        >
          <div className="grid grid-cols-2 gap-3">
            <Stat label="Reports open" value={num(h.trust_and_safety.reports_open)} tone={tone(h.trust_and_safety.reports_open)} />
            <Stat label="Fraud signals in window" value={num(h.trust_and_safety.fraud_signals)} tone={tone(h.trust_and_safety.fraud_signals)} />
          </div>
        </Card>

        <Card title="Accounts">
          <div className="grid grid-cols-2 gap-3">
            <Stat label="Worker sign-ups in window" value={num(h.accounts.signups)} />
            <Stat label="Deletions pending" value={num(h.accounts.deletions_pending)} />
          </div>
        </Card>

        <Card title="Domain events">
          {events.length ? (
            <ul className="text-sm space-y-1 max-h-44 overflow-auto pr-1">
              {events.map(([type, n]) => (
                <li key={type} className="flex justify-between gap-3">
                  <span className="truncate">{type}</span>
                  <span className="tabular-nums font-semibold">{num(n)}</span>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm muted">No events in this window.</p>
          )}
        </Card>
      </div>

      <section className="card overflow-hidden" style={cronFailing ? { borderTop: '3px solid var(--color-danger)' } : undefined}>
        <div className="p-4 sm:p-5 pb-0 sm:pb-0">
          <h2 className="text-sm font-bold uppercase tracking-wide muted">Scheduled jobs (pg_cron)</h2>
          <p className="text-xs muted mt-1">Latest run of each job, regardless of the time window.</p>
        </div>
        <div className="overflow-x-auto mt-3">
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left muted border-b hairline">
                <th className="font-semibold px-4 sm:px-5 py-2">Job</th>
                <th className="font-semibold px-3 py-2">Schedule</th>
                <th className="font-semibold px-3 py-2">Last status</th>
                <th className="font-semibold px-3 py-2">Last run</th>
                <th className="font-semibold px-3 py-2 pr-4 sm:pr-5">Message</th>
              </tr>
            </thead>
            <tbody>
              {h.cron.map((c) => (
                <tr key={c.job} className="border-b hairline last:border-0 align-top">
                  <td className="px-4 sm:px-5 py-2 font-medium whitespace-nowrap">
                    {c.job}
                    {!c.active && <span className="pill ml-2">paused</span>}
                  </td>
                  <td className="px-3 py-2 font-mono text-xs whitespace-nowrap">{c.schedule}</td>
                  <td className="px-3 py-2 whitespace-nowrap font-semibold" style={{ color: cronTone(c.last_status) }}>
                    {c.last_status ?? 'never run'}
                  </td>
                  <td className="px-3 py-2 whitespace-nowrap muted">
                    {c.last_run ? <LocalTime iso={c.last_run} /> : '—'}
                  </td>
                  <td className="px-3 py-2 pr-4 sm:pr-5 text-xs muted max-w-xs break-words">{c.last_message ?? ''}</td>
                </tr>
              ))}
              {!h.cron.length && (
                <tr>
                  <td colSpan={5} className="px-4 sm:px-5 py-3 muted">
                    No scheduled jobs.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}
