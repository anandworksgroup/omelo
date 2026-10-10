'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useId, useState } from 'react';
import { CountBadge } from '@/components/notifications/bell';
import { useUnreadMessages } from '@/lib/realtime/unread';

type Item = { href: string; label: string; badge?: boolean; exact?: boolean };
/** A heading of null means the items sit at the top with no heading above them. */
type Group = { heading: string | null; items: Item[] };

export type Capabilities = {
  client_recruitment?: boolean;
  workforce?: boolean;
  rpo?: boolean;
  billing?: boolean;
};

/**
 * One menu for every organization.
 *
 * There used to be two: an employer menu and an agency menu, chosen by what
 * kind of company this was, with two dashboards behind them. The core is the
 * same for everyone now — a page, jobs, candidates, interviews, hiring, posts,
 * a team — and the rest appears when the organization turns it on.
 *
 * What does NOT merge is the work itself. Hiring for yourself runs on jobs and
 * applications; recruiting for a client runs on job orders and submissions.
 * They are different records with different rules, so they stay different
 * sections. An organization doing both sees both, in one workspace.
 */
const A = '/dashboard/agency';

export function menuFor({
  isAdmin = false,
  capabilities = {},
}: {
  isAdmin?: boolean;
  capabilities?: Capabilities;
}): Group[] {
  const groups: Group[] = [
    {
      heading: null,
      items: [
        { href: '/dashboard', label: 'Overview', exact: true },
        { href: '/dashboard/messages', label: 'Messages', badge: true },
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
  ];

  if (capabilities.client_recruitment) {
    groups.push({
      heading: 'Client recruitment',
      items: [
        { href: A, label: 'Client overview', exact: true },
        { href: `${A}/clients`, label: 'Clients' },
        { href: `${A}/job-orders`, label: 'Job orders' },
        { href: `${A}/talent`, label: 'Client talent search' },
        { href: `${A}/candidates`, label: 'Represented candidates' },
        { href: `${A}/pools`, label: 'Talent pools' },
        { href: `${A}/submissions`, label: 'Submissions' },
        { href: `${A}/interviews`, label: 'Client interviews' },
        { href: `${A}/offers`, label: 'Client offers' },
        { href: `${A}/placements`, label: 'Placements' },
        ...(capabilities.billing ? [{ href: `${A}/billing`, label: 'Billing' }] : []),
      ],
    });
  }

  if (capabilities.workforce) {
    groups.push({
      heading: 'Workforce',
      items: [{ href: '/dashboard/workforce', label: 'Shifts and pay' }],
    });
  }

  groups.push({
    heading: 'Insight',
    items: [
      { href: '/dashboard/insights', label: 'Insights' },
      ...(capabilities.client_recruitment
        ? [{ href: `${A}/analytics`, label: 'Client analytics' }]
        : []),
      { href: '/dashboard/global', label: 'Global' },
    ],
  });

  groups.push({
    heading: 'Organization',
    items: [
      { href: '/dashboard/organization', label: 'Structure' },
      { href: '/dashboard/team', label: 'Team' },
      { href: '/dashboard/agencies', label: 'Agencies working for us' },
      ...(capabilities.rpo ? [{ href: '/dashboard/rpo', label: 'RPO' }] : []),
      { href: '/dashboard/company', label: 'Company' },
      { href: '/dashboard/settings', label: 'Settings' },
    ],
  });

  if (isAdmin) groups.push({ heading: 'Platform', items: [{ href: '/admin', label: 'Admin' }] });
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
 * On a wide screen the menu is a column beside the work, where the groups are
 * visible at a glance. On a phone it is a button that opens the same grouped
 * list as a sheet.
 */
export default function DashboardNav({
  companyId,
  isAdmin = false,
  capabilities = {},
}: {
  companyId: string;
  isAdmin?: boolean;
  capabilities?: Capabilities;
}) {
  const groups = menuFor({ isAdmin, capabilities });
  const unreadMessages = useUnreadMessages(companyId);
  const path = usePathname();
  const [open, setOpen] = useState(false);
  const panelId = useId();

  // The sheet closes when the route changes, so following a link inside it —
  // or going back — does not leave it covering the page you just asked for.
  // Adjusted during render rather than in an effect: an effect would render
  // the sheet over the new page once before closing it.
  const [openedAt, setOpenedAt] = useState(path);
  if (openedAt !== path) {
    setOpenedAt(path);
    if (open) setOpen(false);
  }

  const current =
    groups.flatMap((g) => g.items).find((i) => isActive(path, i))?.label ?? 'Menu';

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
          <svg
            width="16"
            height="16"
            viewBox="0 0 16 16"
            aria-hidden
            fill="none"
            stroke="currentColor"
            strokeWidth="1.8"
            strokeLinecap="round"
          >
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
            aria-label="Workspace"
            className="relative w-[18rem] max-w-[85vw] h-full scroll-y p-3 shadow-lg"
            style={{ background: 'var(--bg)', borderRight: '1px solid var(--line)' }}
          >
            <div className="flex items-center justify-between px-3 pb-2">
              <span className="section-title">Workspace</span>
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
        aria-label="Workspace"
        className="hidden lg:block w-56 shrink-0 sticky self-start scroll-y pr-1 pb-8"
        style={{ top: '0.75rem', maxHeight: 'calc(100vh - 1.5rem)' }}
      >
        <NavGroups groups={groups} path={path} unread={unreadMessages} />
      </nav>
    </>
  );
}
