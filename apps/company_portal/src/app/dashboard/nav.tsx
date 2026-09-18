'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { CountBadge } from '@/components/notifications/bell';
import { useUnreadMessages } from '@/lib/realtime/unread';

type Item = { href: string; label: string; badge?: boolean; exact?: boolean };

const EMPLOYER_NAV: Item[] = [
  { href: '/dashboard', label: 'Overview', exact: true },
  { href: '/dashboard/jobs', label: 'Jobs' },
  { href: '/dashboard/candidates', label: 'Candidates' },
  { href: '/dashboard/talent', label: 'Find talent' },
  { href: '/dashboard/messages', label: 'Messages', badge: true },
  { href: '/dashboard/interviews', label: 'Interviews' },
  { href: '/dashboard/offers', label: 'Offers' },
  { href: '/dashboard/workforce', label: 'Workforce' },
  { href: '/dashboard/agencies', label: 'Agencies' },
  { href: '/dashboard/team', label: 'Team' },
  { href: '/dashboard/company', label: 'Company' },
  { href: '/dashboard/settings', label: 'Settings' },
];

const A = '/dashboard/agency';
const AGENCY_NAV: Item[] = [
  { href: A, label: 'Dashboard', exact: true },
  { href: `${A}/clients`, label: 'Clients' },
  { href: `${A}/job-orders`, label: 'Job Orders' },
  { href: `${A}/talent`, label: 'Talent Search' },
  { href: `${A}/candidates`, label: 'Candidates' },
  { href: `${A}/pools`, label: 'Talent Pools' },
  { href: `${A}/submissions`, label: 'Submissions' },
  { href: `${A}/interviews`, label: 'Interviews' },
  { href: `${A}/offers`, label: 'Offers' },
  { href: `${A}/placements`, label: 'Placements' },
  { href: '/dashboard/workforce', label: 'Workforce' },
  { href: `${A}/analytics`, label: 'Analytics' },
  { href: `${A}/billing`, label: 'Billing' },
  { href: '/dashboard/team', label: 'Team' },
  { href: '/dashboard/company', label: 'Settings' },
];

/** Shown only to platform admins (decided server-side by the layout). */
const ADMIN_ITEM: Item = { href: '/admin', label: 'Admin' };

/**
 * Dashboard navigation: one row under the header, wrapping on desktop and
 * scrolling sideways on phones. Agencies and employers get different menus;
 * the current workspace decides which.
 */
export default function DashboardNav({
  companyId,
  kind,
  isAdmin = false,
}: {
  companyId: string;
  kind: 'employer' | 'agency';
  isAdmin?: boolean;
}) {
  const base = kind === 'agency' ? AGENCY_NAV : EMPLOYER_NAV;
  const items = isAdmin ? [...base, ADMIN_ITEM] : base;
  const unreadMessages = useUnreadMessages(companyId);
  const path = usePathname();

  return (
    <nav
      aria-label={kind === 'agency' ? 'Agency' : 'Dashboard'}
      className="max-w-6xl mx-auto px-4 sm:px-6 pb-2 flex gap-1 overflow-x-auto md:flex-wrap md:overflow-visible"
    >
      {items.map((n) => {
        const active = n.exact ? path === n.href : path === n.href || path.startsWith(n.href + '/');
        return (
          <Link
            key={n.href}
            href={n.href}
            aria-current={active ? 'page' : undefined}
            className="px-3 py-1.5 rounded-lg text-sm font-medium whitespace-nowrap inline-flex items-center gap-1.5 hover:bg-[var(--surface)]"
            style={active ? { color: 'var(--color-brand-600)', fontWeight: 700, background: 'var(--surface)' } : undefined}
          >
            {n.label}
            {n.badge && <CountBadge count={unreadMessages} label="unread messages" />}
          </Link>
        );
      })}
    </nav>
  );
}
