/**
 * Job funnel panel. Plain-CSS horizontal bars, one hue: bar length is the
 * share of the largest step, counts are always printed, and the step-to-step
 * conversion sits between rows so nothing depends on reading bar length.
 */
import { num, pct } from '@/lib/admin';
import { surfaceLabel, type JobFunnel } from '@/lib/talent';

type Step = { key: string; label: string; hint: string; value: number };

function steps(f: JobFunnel): Step[] {
  return [
    { key: 'impressions', label: 'Seen in lists', hint: 'People who saw this job in a list', value: f.impressions },
    { key: 'views', label: 'Opened', hint: 'People who opened the job', value: f.views },
    { key: 'applied', label: 'Applied', hint: 'Applications', value: f.applied },
    { key: 'viewed', label: 'Viewed by you', hint: 'Applications your team opened', value: f.viewed },
    { key: 'shortlisted', label: 'Shortlisted', hint: 'Reached shortlist or later', value: f.shortlisted },
    { key: 'interviewed', label: 'Interviewed', hint: 'Had an interview scheduled', value: f.interviewed },
    { key: 'offered', label: 'Offered', hint: 'Received an offer', value: f.offered },
    { key: 'hired', label: 'Hired', hint: 'Hired', value: f.hired },
  ];
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="min-w-0">
      <p className="text-xl font-black tabular-nums">{value}</p>
      <p className="text-xs muted">{label}</p>
    </div>
  );
}

export default function FunnelPanel({ funnel, error }: { funnel: JobFunnel | null; error?: string }) {
  if (error || !funnel) {
    return (
      <section className="card p-5">
        <h2 className="font-bold mb-1">Funnel</h2>
        <p className="text-sm" style={{ color: 'var(--color-danger)' }}>
          Could not load the funnel: <span className="muted">{error ?? 'no data'}</span>
        </p>
      </section>
    );
  }

  const list = steps(funnel);
  const top = Math.max(1, ...list.map((s) => s.value));
  const empty = list.every((s) => s.value === 0);
  const inv = funnel.invitations;

  return (
    <section className="card p-5 space-y-5">
      <div>
        <h2 className="font-bold">Funnel</h2>
        <p className="text-sm muted mt-1">
          From people seeing this job to people hired. Counts are unique people for the first two steps and
          applications after that.
        </p>
      </div>

      {empty ? (
        <p className="text-sm muted">Nothing to show yet. Numbers appear as workers see and open this job.</p>
      ) : (
        <ol className="space-y-0.5" aria-label="Hiring funnel">
          {list.map((s, i) => {
            const prev = i > 0 ? list[i - 1].value : null;
            const share = s.value / top;
            return (
              <li key={s.key}>
                {prev != null && (
                  <p
                    className="text-xs muted py-0.5 pl-[6.5rem] sm:pl-[8.25rem]"
                    aria-label={`Conversion from ${list[i - 1].label}`}
                  >
                    ↓ {prev > 0 ? pct(s.value / prev) : '—'}
                  </p>
                )}
                <div className="flex items-center gap-2 sm:gap-3" title={`${s.hint}: ${num(s.value)}`}>
                  <span className="w-[6rem] sm:w-[7.75rem] shrink-0 text-xs sm:text-sm font-semibold">{s.label}</span>
                  <div className="flex-1 h-6 rounded-md surface overflow-hidden min-w-0">
                    <div
                      className="h-full"
                      style={{
                        width: `${s.value > 0 ? Math.max(share * 100, 1) : 0}%`,
                        background: 'var(--color-brand-600)',
                        borderRadius: '0 4px 4px 0',
                      }}
                    />
                  </div>
                  <span className="w-12 sm:w-14 shrink-0 text-right tabular-nums font-bold text-sm">{num(s.value)}</span>
                </div>
              </li>
            );
          })}
        </ol>
      )}
      {funnel.viewCount > 0 && (
        <p className="hint !mt-2">Total job page opens, counting repeat visits: {num(funnel.viewCount)}.</p>
      )}

      <div>
        <p className="label">Where applicants came from</p>
        {funnel.bySurface.length === 0 ? (
          <p className="text-sm muted">No source data yet.</p>
        ) : (
          <div className="overflow-x-auto -mx-5 px-5">
            <table className="w-full text-sm min-w-[22rem]">
              <thead>
                <tr className="text-left muted border-b hairline">
                  <th className="font-semibold py-2 pr-3">Source</th>
                  <th className="font-semibold py-2 px-2 text-right">Seen</th>
                  <th className="font-semibold py-2 px-2 text-right">Opened</th>
                  <th className="font-semibold py-2 pl-2 text-right">Applied</th>
                </tr>
              </thead>
              <tbody>
                {funnel.bySurface.map((s) => (
                  <tr key={s.surface} className="border-b hairline last:border-0">
                    <td className="py-2 pr-3">{surfaceLabel(s.surface)}</td>
                    <td className="py-2 px-2 text-right tabular-nums">{num(s.impressions)}</td>
                    <td className="py-2 px-2 text-right tabular-nums">{num(s.views)}</td>
                    <td className="py-2 pl-2 text-right tabular-nums font-semibold">{num(s.applications)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <div>
        <p className="label">Outreach</p>
        <div className="grid grid-cols-3 sm:grid-cols-6 gap-3">
          <Stat label="Talent searches" value={num(funnel.talentSearches)} />
          <Stat label="Invited" value={num(inv.sent)} />
          <Stat label="Seen by them" value={num(inv.viewed)} />
          <Stat label="Applied" value={num(inv.applied)} />
          <Stat label="Declined" value={num(inv.declined)} />
          <Stat label="Waiting" value={num(inv.pending)} />
        </div>
        {inv.sent > 0 && (
          <p className="hint">{pct(inv.applied / inv.sent)} of people you invited have applied.</p>
        )}
      </div>
    </section>
  );
}
