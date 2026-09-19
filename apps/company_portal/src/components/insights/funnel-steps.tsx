/**
 * A funnel as horizontal bar steps. One hue; bar length is the share of the
 * largest step; counts are always printed and the step-to-step conversion
 * sits between rows, so nothing depends on reading bar length alone.
 */
import { num, pct } from '@/lib/admin';

export type FunnelStep = { key: string; label: string; value: number; hint?: string };

export function FunnelSteps({
  steps,
  label,
  showConversion = true,
}: {
  steps: FunnelStep[];
  label: string;
  /** Off for a distribution (buckets), where step-to-step conversion means nothing. */
  showConversion?: boolean;
}) {
  const top = Math.max(1, ...steps.map((s) => s.value));
  return (
    <ol className="space-y-0.5" aria-label={label}>
      {steps.map((s, i) => {
        const prev = i > 0 ? steps[i - 1] : null;
        const share = s.value / top;
        return (
          <li key={s.key} className={!showConversion && i > 0 ? 'pt-1.5' : undefined}>
            {prev && showConversion && (
              <p className="text-xs muted py-0.5 pl-[6.5rem] sm:pl-[8.25rem]">
                <span aria-hidden>↓ </span>
                <span className="sr-only">
                  Conversion from {prev.label} to {s.label}:{' '}
                </span>
                {prev.value > 0 ? pct(s.value / prev.value) : '—'}
              </p>
            )}
            <div className="flex items-center gap-2 sm:gap-3" title={s.hint ? `${s.hint}: ${num(s.value)}` : undefined}>
              <span className="w-[6rem] sm:w-[7.75rem] shrink-0 text-xs sm:text-sm font-semibold">{s.label}</span>
              <div className="flex-1 h-6 rounded-md surface overflow-hidden min-w-0" aria-hidden>
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
  );
}
