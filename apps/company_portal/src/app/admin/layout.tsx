import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound, redirect } from 'next/navigation';
import { getUser } from '@/lib/supabase/server';
import { isPlatformAdmin } from '@/lib/admin';
import AdminTabs from './tabs';

export const metadata: Metadata = {
  title: 'Admin · Omelo',
  robots: { index: false, follow: false },
};

/**
 * Platform admin area, outside the company dashboard chrome.
 *
 * Non-admins get the ordinary 404: the area's existence is not advertised.
 * The RPCs behind every page enforce platform-admin membership themselves
 * (42501 otherwise), so this check only controls what is rendered.
 */
export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  const user = await getUser();
  if (!user) redirect('/sign-in?next=/admin');
  if (!(await isPlatformAdmin())) notFound();

  return (
    <div className="min-h-screen flex flex-col">
      <header className="border-b hairline">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 min-h-14 py-2 flex items-center gap-3 sm:gap-6 flex-wrap">
          <Link href="/admin" className="font-black tracking-tight text-brand-600 shrink-0">
            Omelo <span className="pill ml-1">Admin</span>
          </Link>
          <AdminTabs />
          <Link href="/dashboard" className="ml-auto text-sm underline muted">
            Back to dashboard
          </Link>
        </div>
      </header>
      <main className="flex-1 max-w-6xl w-full mx-auto px-4 sm:px-6 py-6 sm:py-8">{children}</main>
    </div>
  );
}
