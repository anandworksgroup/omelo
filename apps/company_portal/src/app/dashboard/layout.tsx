import Link from 'next/link';
import { redirect } from 'next/navigation';
import { getCompanyContext, getUser } from '@/lib/supabase/server';
import { signOut } from '../auth/actions';

const NAV = [
  { href: '/dashboard', label: 'Overview' },
  { href: '/dashboard/jobs', label: 'Jobs' },
  { href: '/dashboard/candidates', label: 'Candidates' },
  { href: '/dashboard/company', label: 'Company' },
];

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
        <div className="max-w-6xl mx-auto px-6 h-14 flex items-center gap-6">
          <Link href="/dashboard" className="font-black tracking-tight text-brand-600">
            Omelo
          </Link>

          <span className="pill">
            {ctx.companyName}
            {ctx.isVerified ? (
              <span style={{ color: 'var(--color-verified)' }}>· verified</span>
            ) : (
              <span style={{ color: 'var(--color-warn)' }}>· unverified</span>
            )}
          </span>

          <nav className="hidden sm:flex gap-1 ml-2">
            {NAV.map((n) => (
              <Link
                key={n.href}
                href={n.href}
                className="px-3 py-1.5 rounded-lg text-sm font-medium hover:opacity-70"
              >
                {n.label}
              </Link>
            ))}
          </nav>

          <div className="ml-auto flex items-center gap-3">
            <span className="text-sm muted hidden md:inline">{user.email}</span>
            <form action={signOut}>
              <button className="text-sm underline muted">Sign out</button>
            </form>
          </div>
        </div>

        <nav className="sm:hidden flex gap-1 px-4 pb-2 overflow-x-auto">
          {NAV.map((n) => (
            <Link
              key={n.href}
              href={n.href}
              className="px-3 py-1.5 rounded-lg text-sm font-medium whitespace-nowrap surface"
            >
              {n.label}
            </Link>
          ))}
        </nav>
      </header>

      <main className="flex-1 max-w-6xl w-full mx-auto px-6 py-8">{children}</main>
    </div>
  );
}
