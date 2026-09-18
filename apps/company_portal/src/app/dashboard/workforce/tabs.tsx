'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

const W = '/dashboard/workforce';

/** Second-level navigation inside Workforce; scrolls sideways on phones. */
export default function WorkforceTabs({
  kind,
  canPay,
  canApprove,
  showSites,
}: {
  kind: 'employer' | 'agency';
  canPay: boolean;
  canApprove: boolean;
  showSites: boolean;
}) {
  const path = usePathname();
  const items: { href: string; label: string; exact?: boolean }[] = [
    { href: W, label: 'Overview', exact: true },
    { href: `${W}/requirements`, label: 'Requirements' },
    { href: `${W}/assignments`, label: 'Assignments' },
    { href: `${W}/shifts`, label: 'Schedule' },
    ...(canApprove ? [{ href: `${W}/approvals`, label: 'Approvals' }] : []),
    ...(canPay ? [{ href: `${W}/pay`, label: kind === 'agency' ? 'Pay & billing' : 'Pay' }] : []),
    { href: `${W}/bulk`, label: 'Bulk jobs' },
    ...(kind === 'employer' && (showSites || path.startsWith(`${W}/sites`)) ? [{ href: `${W}/sites`, label: 'At your sites' }] : []),
  ];
  return (
    <nav
      aria-label="Workforce"
      className="flex gap-1 overflow-x-auto -mx-4 px-4 sm:mx-0 sm:px-0 pb-1 border-b hairline"
    >
      {items.map((n) => {
        const active = n.exact ? path === n.href : path === n.href || path.startsWith(n.href + '/');
        return (
          <Link
            key={n.href}
            href={n.href}
            aria-current={active ? 'page' : undefined}
            className="px-3 py-2 text-sm font-semibold whitespace-nowrap border-b-2 -mb-px"
            style={
              active
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
