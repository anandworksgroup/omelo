'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

const TABS = [
  { href: '/admin', label: 'System health' },
  { href: '/admin/kpis', label: 'KPIs' },
  { href: '/admin/matching', label: 'Matching' },
  { href: '/admin/companies', label: 'Companies' },
];

export default function AdminTabs() {
  const path = usePathname();
  return (
    <nav aria-label="Admin" className="flex gap-1 overflow-x-auto max-w-full">
      {TABS.map((t) => {
        const active = path === t.href;
        return (
          <Link
            key={t.href}
            href={t.href}
            aria-current={active ? 'page' : undefined}
            className="px-3 py-1.5 rounded-lg text-sm font-medium whitespace-nowrap hover:opacity-70"
            style={active ? { color: 'var(--color-brand-600)', fontWeight: 700 } : undefined}
          >
            {t.label}
          </Link>
        );
      })}
    </nav>
  );
}
