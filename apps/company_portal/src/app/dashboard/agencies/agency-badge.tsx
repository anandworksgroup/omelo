/**
 * How an agency is named on the employer side: its name, a verified tick,
 * and "Independent recruiter" for solo recruiters. No hooks, so server and
 * client components share it.
 */
import type { AgencyRef } from '@/lib/agency';

const VERIFIED = 'var(--color-verified)';

export function AgencyName({
  agency,
  strong = true,
}: {
  /** `verified: null` when unknown (e.g. only the submission snapshot is readable). */
  agency: Pick<AgencyRef, 'name' | 'independent'> & { verified: boolean | null };
  strong?: boolean;
}) {
  return (
    <span className="inline-flex items-center gap-1.5 flex-wrap min-w-0 break-words">
      <span className={strong ? 'font-semibold' : undefined}>{agency.name}</span>
      {agency.verified ? (
        <span
          className="text-xs font-semibold"
          style={{ color: VERIFIED }}
          title="Verified by Omelo"
          aria-label="Verified by Omelo"
        >
          ✓ Verified
        </span>
      ) : agency.verified === null ? null : (
        <span className="text-xs muted" title="Not verified by Omelo yet">
          Unverified
        </span>
      )}
      {agency.independent && <span className="pill">Independent recruiter</span>}
    </span>
  );
}

/** A tone pill ({label, color}) as used by the agency label tables. */
export function TonePill({ tone }: { tone: { label: string; color: string } }) {
  return (
    <span className="pill" style={{ color: tone.color, borderColor: tone.color }}>
      {tone.label}
    </span>
  );
}
