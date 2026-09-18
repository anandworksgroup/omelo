import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { createClient } from '@/lib/supabase/server';
import { num, pct } from '@/lib/admin';
import { parseMatchingMetrics, surfaceLabel } from '@/lib/talent';
import { Card, Stat, WindowSelector, parseChoice } from '../ui';

export const metadata: Metadata = { title: 'Matching · Omelo Admin', robots: { index: false, follow: false } };

const WINDOWS = [
  { value: 7, label: '7 days' },
  { value: 30, label: '30 days' },
  { value: 90, label: '90 days' },
];

const BAND_LABEL: Record<string, string> = {
  '85-100': 'Score 85–100',
  '70-84': 'Score 70–84',
  '50-69': 'Score 50–69',
  '0-49': 'Score 0–49',
  unscored: 'Not scored',
};

/** A rate as a number plus a thin bar, so bands can be compared at a glance. */
function RateCell({ value, max }: { value: number | null; max: number }) {
  const w = value == null || max <= 0 ? 0 : Math.max(0, Math.min(1, value / max)) * 100;
  return (
    <td className="px-3 py-2 align-middle">
      <div className="flex items-center gap-2 justify-end">
        <div className="hidden sm:block w-24 h-2 rounded-full surface overflow-hidden" aria-hidden>
          <div className="h-full rounded-full" style={{ width: `${w}%`, background: 'var(--color-brand-600)' }} />
        </div>
        <span className="tabular-nums font-semibold w-12 text-right">{pct(value)}</span>
      </div>
    </td>
  );
}

/**
 * Is the score calibrated? Among scored bands with applications, a higher
 * band should hire (and progress) at least as often as the band below it.
 */
function calibration(bands: { band: string; applications: number; hireRate: number | null }[]) {
  const ordered = ['0-49', '50-69', '70-84', '85-100']
    .map((b) => bands.find((x) => x.band === b))
    .filter((b): b is (typeof bands)[number] => !!b && b.applications > 0 && b.hireRate != null);
  if (ordered.length < 2) return null;
  const monotonic = ordered.every((b, i) => i === 0 || (b.hireRate ?? 0) >= (ordered[i - 1].hireRate ?? 0));
  return monotonic;
}

export default async function MatchingPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const days = parseChoice(sp.days, WINDOWS.map((w) => w.value), 30);

  const supabase = await createClient();
  const { data, error } = await supabase.rpc('omelo_admin_matching_metrics', { p_days: days });
  if (error) {
    if (error.code === '42501') notFound();
    throw error;
  }
  const m = parseMatchingMetrics(data);
  const maxProgress = Math.max(0, ...m.byScoreBand.map((b) => b.progressedRate ?? 0));
  const maxHire = Math.max(0, ...m.byScoreBand.map((b) => b.hireRate ?? 0));
  const calibrated = calibration(m.byScoreBand);
  const totalMatches = m.engines.reduce((a, e) => a + e.matches, 0);

  return (
    <div className="space-y-6">
      <div className="flex items-end justify-between gap-4 flex-wrap">
        <div>
          <h1 className="text-2xl font-bold">Matching</h1>
          <p className="text-sm muted mt-1">Last {m.days} days · where applications come from and whether scores predict hires</p>
        </div>
        <WindowSelector param="days" options={WINDOWS} current={days} basePath="/admin/matching" label="Time window" />
      </div>

      <section className="card overflow-hidden">
        <div className="p-4 sm:p-5 pb-0 sm:pb-0">
          <h2 className="text-sm font-bold uppercase tracking-wide muted">By surface</h2>
          <p className="text-xs muted mt-1">
            Unique person–job pairs seen and opened; view rate = opened ÷ seen, apply rate = applied ÷ opened.
          </p>
        </div>
        <div className="overflow-x-auto mt-3">
          <table className="w-full text-sm min-w-[36rem]">
            <thead>
              <tr className="text-left muted border-b hairline">
                <th className="font-semibold px-4 sm:px-5 py-2">Surface</th>
                <th className="font-semibold px-3 py-2 text-right">Seen</th>
                <th className="font-semibold px-3 py-2 text-right">Opened</th>
                <th className="font-semibold px-3 py-2 text-right">Applied</th>
                <th className="font-semibold px-3 py-2 text-right">View rate</th>
                <th className="font-semibold px-3 py-2 pr-4 sm:pr-5 text-right">Apply rate</th>
              </tr>
            </thead>
            <tbody>
              {m.bySurface.map((s) => (
                <tr key={s.surface} className="border-b hairline last:border-0">
                  <td className="px-4 sm:px-5 py-2 font-medium whitespace-nowrap">{surfaceLabel(s.surface)}</td>
                  <td className="px-3 py-2 text-right tabular-nums">{num(s.impressions)}</td>
                  <td className="px-3 py-2 text-right tabular-nums">{num(s.views)}</td>
                  <td className="px-3 py-2 text-right tabular-nums">{num(s.applications)}</td>
                  <td className="px-3 py-2 text-right tabular-nums font-semibold">{pct(s.viewRate)}</td>
                  <td className="px-3 py-2 pr-4 sm:pr-5 text-right tabular-nums font-semibold">{pct(s.applyRate)}</td>
                </tr>
              ))}
              {!m.bySurface.length && (
                <tr>
                  <td colSpan={6} className="px-4 sm:px-5 py-3 muted">
                    No tracked events in this window.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>

      <section
        className="card overflow-hidden"
        style={
          calibrated === false
            ? { borderTop: '3px solid var(--color-warn)' }
            : calibrated
              ? { borderTop: '3px solid var(--color-verified)' }
              : undefined
        }
      >
        <div className="p-4 sm:p-5 pb-0 sm:pb-0">
          <h2 className="text-sm font-bold uppercase tracking-wide muted">By match score</h2>
          <p className="text-xs muted mt-1">
            Applications in the window, by the score at the moment they applied. Progressed = shortlisted,
            interviewed, offered or hired. If the score works, higher bands progress and hire more often.
          </p>
          {calibrated != null && (
            <p
              className="text-sm font-semibold mt-2"
              style={{ color: calibrated ? 'var(--color-verified)' : 'var(--color-warn)' }}
            >
              {calibrated
                ? '✓ Hire rate rises with the score band.'
                : '! Hire rate does not rise steadily with the score band. Check the engine weights.'}
            </p>
          )}
        </div>
        <div className="overflow-x-auto mt-3">
          <table className="w-full text-sm min-w-[28rem]">
            <thead>
              <tr className="text-left muted border-b hairline">
                <th className="font-semibold px-4 sm:px-5 py-2">Band</th>
                <th className="font-semibold px-3 py-2 text-right">Applications</th>
                <th className="font-semibold px-3 py-2 text-right">Progressed</th>
                <th className="font-semibold px-3 py-2 pr-4 sm:pr-5 text-right">Hired</th>
              </tr>
            </thead>
            <tbody>
              {m.byScoreBand.map((b) => (
                <tr key={b.band} className="border-b hairline last:border-0">
                  <td className="px-4 sm:px-5 py-2 font-medium whitespace-nowrap">{BAND_LABEL[b.band] ?? b.band}</td>
                  <td className="px-3 py-2 text-right tabular-nums">{num(b.applications)}</td>
                  <RateCell value={b.progressedRate} max={maxProgress} />
                  <RateCell value={b.hireRate} max={maxHire} />
                </tr>
              ))}
              {!m.byScoreBand.length && (
                <tr>
                  <td colSpan={4} className="px-4 sm:px-5 py-3 muted">
                    No attributed applications in this window.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>

      <div className="grid gap-4 sm:grid-cols-2">
        <Card title="Talent search & invitations">
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
            <Stat label="Searches" value={num(m.talent.searches)} />
            <Stat label="Companies searching" value={num(m.talent.companiesSearching)} />
            <Stat label="Invitations sent" value={num(m.talent.invitationsSent)} />
            <Stat label="Invitations → applied" value={num(m.talent.invitationsApplied)} />
            <Stat label="Declined" value={num(m.talent.invitationsDeclined)} />
            <Stat label="Invitation apply rate" value={pct(m.talent.invitationApplyRate)} />
          </div>
        </Card>
        <Card title="Engine versions">
          {m.engines.length ? (
            <ul className="text-sm space-y-1.5">
              {m.engines.map((e) => (
                <li key={e.engineVersion} className="flex justify-between gap-3">
                  <span className="font-mono text-xs truncate">{e.engineVersion}</span>
                  <span className="tabular-nums">
                    <span className="font-semibold">{num(e.matches)}</span>
                    <span className="muted text-xs ml-1.5">{pct(totalMatches ? e.matches / totalMatches : null)}</span>
                  </span>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm muted">No matches computed in this window.</p>
          )}
        </Card>
      </div>
    </div>
  );
}
