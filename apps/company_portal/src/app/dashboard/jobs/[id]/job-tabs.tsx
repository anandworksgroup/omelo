import Link from 'next/link';

/** Second-level navigation on a job: details and hiring insights. Scrolls sideways on phones. */
export default function JobTabs({
  jobId,
  active,
  showDetails = true,
}: {
  jobId: string;
  active: 'details' | 'insights';
  showDetails?: boolean;
}) {
  const items = [
    ...(showDetails ? [{ key: 'details', href: `/dashboard/jobs/${jobId}`, label: 'Details' }] : []),
    { key: 'insights', href: `/dashboard/jobs/${jobId}/insights`, label: 'Hiring insights' },
  ];
  return (
    <nav aria-label="Job" className="flex gap-1 overflow-x-auto -mx-4 px-4 sm:mx-0 sm:px-0 border-b hairline">
      {items.map((n) => {
        const on = n.key === active;
        return (
          <Link
            key={n.key}
            href={n.href}
            aria-current={on ? 'page' : undefined}
            className="px-3 py-2 text-sm font-semibold whitespace-nowrap border-b-2 -mb-px"
            style={
              on
                ? { borderColor: 'var(--color-brand-600)', color: 'var(--color-brand-600)' }
                : { borderColor: 'transparent', color: 'var(--muted)' }
            }
          >
            {n.label}
          </Link>
        );
      })}
    </nav>
  );
}
