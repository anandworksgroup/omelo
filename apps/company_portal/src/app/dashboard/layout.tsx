import Link from 'next/link';
import { redirect } from 'next/navigation';
import { getCompanyContext, getUser } from '@/lib/supabase/server';
import NotificationBell from '@/components/notifications/bell';
import { signOut } from '../auth/actions';
import DashboardNav from './nav';

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const user = await getUser();
  if (!user) redirect('/sign-in');

  const ctx = await getCompanyContext();
  if (!ctx) redirect('/onboarding');

  return (
    <div className="min-h-screen flex flex-col">
      <header className="border-b hairline">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 min-h-14 py-2 flex items-center gap-3 sm:gap-6 flex-wrap">
          <Link href="/dashboard" className="font-black tracking-tight text-brand-600 shrink-0">
            Omelo
          </Link>

          <span className="pill max-w-[45vw] sm:max-w-none truncate">
            {ctx.companyName}
            {ctx.isVerified ? (
              <span style={{ color: 'var(--color-verified)' }}>· verified</span>
            ) : (
              <span style={{ color: 'var(--color-warn)' }}>· unverified</span>
            )}
          </span>

          <DashboardNav companyId={ctx.companyId} variant="desktop" />

          <div className="ml-auto flex items-center gap-2 sm:gap-3">
            <NotificationBell personId={user.id} />
            <span className="text-sm muted hidden lg:inline">{user.email}</span>
            <form action={signOut}>
              <button className="text-sm underline muted">Sign out</button>
            </form>
          </div>
        </div>

        <DashboardNav companyId={ctx.companyId} variant="mobile" />
      </header>

      <main className="flex-1 max-w-6xl w-full mx-auto px-4 sm:px-6 py-6 sm:py-8">
        {children}
      </main>
    </div>
  );
}
