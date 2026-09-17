'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { CountBadge } from '@/components/notifications/bell';
import { useUnreadMessages } from '@/lib/realtime/unread';

const NAV = [
  { href: '/dashboard', label: 'Overview' },
  { href: '/dashboard/jobs', label: 'Jobs' },
  { href: '/dashboard/candidates', label: 'Candidates' },
  { href: '/dashboard/messages', label: 'Messages', badge: true },
  { href: '/dashboard/interviews', label: 'Interviews' },
  { href: '/dashboard/offers', label: 'Offers' },
  { href: '/dashboard/company', label: 'Company' },
];

/** Dashboard navigation. Rendered twice (desktop row, mobile strip). */
export default function DashboardNav({
  companyId,
  variant,
}: {
  companyId: string;
  variant: 'desktop' | 'mobile';
}) {
  const unreadMessages = useUnreadMessages(companyId);
  const path = usePathname();

  return (
    <nav
      aria-label="Dashboard"
      className={
        variant === 'desktop' ? 'hidden md:flex gap-1 ml-2' : 'md:hidden flex gap-1 px-4 pb-2 overflow-x-auto'
      }
    >
      {NAV.map((n) => {
        const active = n.href === '/dashboard' ? path === n.href : path === n.href || path.startsWith(n.href + '/');
        return (
          <Link
            key={n.href}
            href={n.href}
            aria-current={active ? 'page' : undefined}
            className={`px-3 py-1.5 rounded-lg text-sm font-medium whitespace-nowrap inline-flex items-center gap-1.5 ${
              variant === 'mobile' ? 'surface' : 'hover:opacity-70'
            }`}
            style={active ? { color: 'var(--color-brand-600)', fontWeight: 700 } : undefined}
          >
            {n.label}
            {n.badge && <CountBadge count={unreadMessages} label="unread messages" />}
          </Link>
        );
      })}
    </nav>
  );
}
