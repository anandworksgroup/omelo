'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useEffect, useId, useState } from 'react';
import { CountBadge } from '@/components/notifications/bell';
import { useUnreadMessages } from '@/lib/realtime/unread';

type Item = { href: string; label: string; badge?: boolean; exact?: boolean };
/** A heading of null means the items sit at the top with no heading above them. */
type Group = { heading: string | null; items: Item[] };

/**
 * The employer menu, grouped by the job being done rather than listed flat.
 *
 * It was one row of seventeen links, which is a list of everything the portal
 * can do and no help in finding anything. The groups below are the four
 * questions an employer actually arrives with: who am I hiring, how is the
 * work going, what is happening, and who are we.
 */
const EMPLOYER_NAV: Group[] = [
  {
    heading: null,
    items: [
      { href: '/dashboard', label: 'Overview', exact: true },
      { href: '/dashboard/messages', label: 'Messages', badge: true },
      { href: '/dashboard/workforce', label: 'Workforce' },
      { href: '/dashboard/updates', label: 'Updates' },
    ],
  },
  {
    heading: 'Hiring',
    items: [
      { href: '/dashboard/jobs', label: 'Jobs' },
      { href: '/dashboard/candidates', label: 'Candidates' },
      { href: '/dashboard/talent', label: 'Find talent' },
      { href: '/dashboard/interviews', label: 'Interviews' },
      { href: '/dashboard/offers', label: 'Offers' },
      { href: '/dashboard/approvals', label: 'Approvals' },
    ],
  },
  {
    heading: 'Insight',
    items: [
      { href: '/dashboard/insights', label: 'Insights' },
      { href: '/dashboard/global', label: 'Global' },
    ],
  },
  {
    heading: 'Organization',
    items: [
      { href: '/dashboard/organization', label: 'Structure' },
      { href: '/dashboard/team', label: 'Team' },
      { href: '/dashboard/agencies', label: 'Agencies' },
      { href: '/dashboard/company', label: 'Company' },
      { href: '/dashboard/settings', label: 'Settings' },
    ],
  },
];

const A = '/dashboard/agency';
const AGENCY_NAV: Group[] = [
  {
    heading: null,
    items: [
      { href: A, label: 'Dashboard', exact: true },
      { href: '/dashboard/workforce', label: 'Workforce' },
      { href: '/dashboard/updates', label: 'Updates' },
    ],
  },
  {
    heading: 'Clients',
    items: [
      { href: `${A}/clients`, label: 'Clients' },
      { href: `${A}/job-orders`, label: 'Job orders' },
    ],
  },
  {
    heading: 'Talent',
    items: [
      { href: `${A}/talent`, label: 'Talent search' },
      { href: `${A}/candidates`, label: 'Candidates' },
      { href: `${A}/pools`, label: 'Talent pools' },
      { href: `${A}/submissions`, label: 'Submissions' },
    ],
  },
  {
    heading: 'Hiring',
    items: [
      { href: `${A}/interviews`, label: 'Interviews' },
      { href: `${A}/offers`, label: 'Offers' },
      { href: `${A}/placements`, label: 'Placements' },
    ],
  },
  {
    heading: 'Insight',
    items: [
      { href: `${A}/analytics`, label: 'Analytics' },
      { href: '/dashboard/global', label: 'Global' },
    ],
  },
  {
    heading: 'Organization',
    items: [
      { href: `${A}/billing`, label: 'Billing' },
      { href: '/dashboard/team', label: 'Team' },
      { href: '/dashboard/company', label: 'Settings' },
    ],
  },
];

/** Agencies see Insights only when they post jobs of their own. */
const INSIGHTS_ITEM: Item = { href: '/dashboard/insights', label: 'Insights' };

/** Shown only to platform admins (decided server-side by the layout). */
const ADMIN_ITEM: Item = { href: '/admin', label: 'Admin' };

/**
 * RPO belongs to both sides: the organization running recruiting for someone
 * else, and the one it is run for. The layout decides when to show it.
 */
const RPO_ITEM: Item = { href: '/dashboard/rpo', label: 'RPO' };

/** Add an item to a named group, keeping every other group as it was. */
function addTo(groups: Group[], heading: string, item: Item, at = -1): Group[] {
  return groups.map((g) =>
    g.heading === heading
      ? {
          ...g,
          items:
            at < 0
              ? [...g.items, item]
              : [...g.items.slice(0, at), item, ...g.items.slice(at)],
        }
      : g
  );
}

export function menuFor({
  kind,
  isAdmin = false,
  agencyHasJobs = false,
  showRpo = false,
}: {
  kind: 'employer' | 'agency';
  isAdmin?: boolean;
  agencyHasJobs?: boolean;
  showRpo?: boolean;
}): Group[] {
  let groups = kind === 'agency' ? AGENCY_NAV : EMPLOYER_NAV;
  if (kind === 'agency' && agencyHasJobs) groups = addTo(groups, 'Insight', INSIGHTS_ITEM, 0);
  // RPO is an organization-level relationship, so it sits with the rest of them.
  if (showRpo) groups = addTo(groups, 'Organization', RPO_ITEM);
  if (isAdmin) groups = [...groups, { heading: 'Platform', items: [ADMIN_ITEM] }];
  return groups;
}

function isActive(path: string, item: Item): boolean {
  return item.exact
    ? path === item.href
    : path === item.href || path.startsWith(item.href + '/');
}

function NavLink({
  item,
  active,
  unread,
  onNavigate,
}: {
  item: Item;
  active: boolean;
  unread: number;
  onNavigate?: () => void;
}) {
  return (
    <Link
      href={item.href}
      aria-current={active ? 'page' : undefined}
      onClick={onNavigate}
      className={`nav-link${active ? ' is-active' : ''}`}
    >
      <span className="truncate">{item.label}</span>
      {item.badge && <CountBadge count={unread} label="unread messages" />}
    </Link>
  );
}

function NavGroups({
  groups,
  path,
  unread,
  onNavigate,
}: {
  groups: Group[];
  path: string;
  unread: number;
  onNavigate?: () => void;
}) {
  return (
    <>
      {groups.map((group, i) => (
        <div key={group.heading ?? `top-${i}`} className={group.heading ? 'mt-5' : ''}>
          {group.heading && <p className="section-title px-3 mb-1.5">{group.heading}</p>}
          <div className="grid gap-0.5">
            {group.items.map((item) => (
              <NavLink
                key={item.href}
                item={item}
                active={isActive(path, item)}
                unread={unread}
                onNavigate={onNavigate}
              />
            ))}
          </div>
        </div>
      ))}
    </>
  );
}

/**
 * Dashboard navigation.
 *
 * On a wide screen it is a column beside the work, where the groups are
 * visible at a glance. On a phone it is a button that opens the same grouped
 * list as a sheet — seventeen links in a sideways-scrolling strip was a menu
 * you had to drag through to read.
 */
export default function DashboardNav({
  companyId,
  kind,
  isAdmin = false,
  agencyHasJobs = false,
  showRpo = false,
}: {
  companyId: string;
  kind: 'employer' | 'agency';
  isAdmin?: boolean;
  agencyHasJobs?: boolean;
  showRpo?: boolean;
}) {
  const groups = menuFor({ kind, isAdmin, agencyHasJobs, showRpo });
  const unreadMessages = useUnreadMessages(companyId);
  const path = usePathname();
  const [open, setOpen] = useState(false);
  const panelId = useId();
  const label = kind === 'agency' ? 'Agency' : 'Dashboard';

  // The sheet closes when the route changes, so following a link inside it —
  // or going back — does not leave it covering the page you just asked for.
  // Adjusted during render rather than in an effect: an effect would render
  // the sheet over the new page once before closing it.
  const [openedAt, setOpenedAt] = useState(path);
  if (openedAt !== path) {
    setOpenedAt(path);
    if (open) setOpen(false);
  }

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false);
    };
    document.addEventListener('keydown', onKey);
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.removeEventListener('keydown', onKey);
      document.body.style.overflow = prev;
    };
  }, [open]);

  const current =
    groups
      .flatMap((g) => g.items)
      .find((i) => isActive(path, i))?.label ?? 'Menu';

  return (
    <>
      {/* Phone and tablet: one button that says where you are. */}
      <div className="lg:hidden flex items-center gap-2 px-4 sm:px-6 py-2 border-b hairline">
        <button
          type="button"
          className="btn btn-ghost btn-sm"
          aria-expanded={open}
          aria-controls={panelId}
          onClick={() => setOpen((v) => !v)}
        >
          <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
            <path d="M2 4h12M2 8h12M2 12h12" />
          </svg>
          Menu
        </button>
        <span className="text-sm font-semibold truncate">{current}</span>
        {unreadMessages > 0 && path !== '/dashboard/messages' && (
          <Link href="/dashboard/messages" className="ml-auto pill pill-brand">
            {unreadMessages} unread
          </Link>
        )}
      </div>

      {open && (
        <div className="lg:hidden fixed inset-0 z-50 flex">
          <button
            type="button"
            aria-label="Close menu"
            className="absolute inset-0"
            style={{ background: 'rgb(0 0 0 / .45)' }}
            onClick={() => setOpen(false)}
          />
          <nav
            id={panelId}
            aria-label={label}
            className="relative w-[18rem] max-w-[85vw] h-full scroll-y p-3 shadow-lg"
            style={{ background: 'var(--bg)', borderRight: '1px solid var(--line)' }}
          >
            <div className="flex items-center justify-between px-3 pb-2">
              <span className="section-title">{label}</span>
              <button type="button" className="btn btn-quiet btn-sm" onClick={() => setOpen(false)}>
                Close
              </button>
            </div>
            <NavGroups
              groups={groups}
              path={path}
              unread={unreadMessages}
              onNavigate={() => setOpen(false)}
            />
          </nav>
        </div>
      )}

      {/* Desktop: a column that stays with you as the page scrolls. */}
      <nav
        aria-label={label}
        className="hidden lg:block w-56 shrink-0 sticky self-start scroll-y pr-1 pb-8"
        style={{ top: '0.75rem', maxHeight: 'calc(100vh - 1.5rem)' }}
      >
        <NavGroups groups={groups} path={path} unread={unreadMessages} />
      </nav>
    </>
  );
}
