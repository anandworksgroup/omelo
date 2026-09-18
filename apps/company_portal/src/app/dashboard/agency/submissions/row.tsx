/**
 * One submission as a card. No hooks, so any agency page can render it.
 * A card (not a table row) so it reads the same at 360px.
 */
import Link from 'next/link';
import type { ReactNode } from 'react';
import type { SubmissionRow } from '@/lib/agency';
import { timeAgo } from '@/lib/format';
import LocalTime from '../../local-time';
import { PlacementPill, SubmissionPill } from '../ui';
import { BASE, offerLabel, positionLine } from './lib';

const TABS = [
  { key: 'submissions', label: 'Submissions' },
  { key: 'interviews', label: 'Interviews' },
  { key: 'offers', label: 'Offers' },
  { key: 'placements', label: 'Placements' },
  { key: 'billing', label: 'Billing' },
  { key: 'analytics', label: 'Analytics' },
] as const;

/** Switch between the after-submission pages. Scrolls sideways on phones. */
export function WorkTabs({ active }: { active: (typeof TABS)[number]['key'] }) {
  return (
    <nav aria-label="Submissions and placements" className="flex gap-1.5 overflow-x-auto pb-1 -mx-4 px-4 sm:mx-0 sm:px-0 sm:flex-wrap">
      {TABS.map((t) => {
        const on = t.key === active;
        return (
          <Link
            key={t.key}
            href={`${BASE}/${t.key}`}
            aria-current={on ? 'page' : undefined}
            className="px-3 py-1.5 rounded-lg text-sm font-semibold whitespace-nowrap"
            style={on ? { background: 'var(--surface)', color: 'var(--fg)' } : { color: 'var(--muted)' }}
          >
            {t.label}
          </Link>
        );
      })}
    </nav>
  );
}

export function PlatformHint({ onOmelo }: { onOmelo: boolean }) {
  return (
    <span
      className="text-xs muted"
      title={
        onOmelo
          ? 'The client hires on Omelo: the status follows their hiring pipeline.'
          : 'The client is not on Omelo: you record their decisions yourself.'
      }
    >
      {onOmelo ? 'On Omelo' : 'Off-platform client'}
    </span>
  );
}

export function SubmissionCard({ row, extra }: { row: SubmissionRow; extra?: ReactNode }) {
  const offer = offerLabel(row.offerStatus);
  return (
    <li>
      <Link href={`${BASE}/submissions/${row.id}`} className="card p-4 block hover:opacity-90 min-w-0">
        <div className="flex items-start gap-2 flex-wrap">
          <div className="flex-1 min-w-0">
            <p className="font-semibold break-words">
              {row.candidate.name}
              {row.candidate.label && <span className="font-normal muted"> as {row.candidate.label}</span>}
            </p>
            <p className="text-sm muted break-words mt-0.5">{positionLine(row)}</p>
          </div>
          <div className="flex flex-wrap gap-1.5 items-center">
            <SubmissionPill status={row.status} />
            {row.placement && <PlacementPill status={row.placement.status} />}
          </div>
        </div>
        <div className="text-xs muted mt-2 flex flex-wrap gap-x-3 gap-y-1">
          <span>Submitted {timeAgo(row.submittedAt) || '—'}</span>
          {row.recruiter && <span className="break-words">by {row.recruiter}</span>}
          <PlatformHint onOmelo={row.onOmelo} />
        </div>
        {(row.nextInterview || offer) && (
          <div className="text-sm mt-2 flex flex-wrap gap-x-4 gap-y-1">
            {row.nextInterview && (
              <span>
                Next interview: <LocalTime iso={row.nextInterview} className="font-medium" />
              </span>
            )}
            {offer && (
              <span>
                Offer: <span className="font-medium">{offer}</span>
              </span>
            )}
          </div>
        )}
        {extra}
      </Link>
    </li>
  );
}
