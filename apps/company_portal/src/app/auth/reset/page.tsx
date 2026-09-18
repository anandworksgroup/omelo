import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { getUser } from '@/lib/supabase/server';
import PasswordForm from '@/components/account/password-form';

export const metadata: Metadata = {
  title: 'Choose a new password · Omelo for Employers',
  robots: { index: false, follow: false },
};

/**
 * Where the password recovery email lands.
 *
 * With `?code=` (PKCE) the code is exchanged by /auth/callback, which sets the
 * session cookies and comes straight back here. Once signed in by the link,
 * the user chooses a new password.
 */
export default async function ResetPasswordPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const code = typeof sp.code === 'string' ? sp.code : null;
  if (code) {
    redirect(`/auth/callback?code=${encodeURIComponent(code)}&next=${encodeURIComponent('/auth/reset')}`);
  }

  // Our callback sets error=link_invalid; Supabase itself may add
  // error / error_code (e.g. otp_expired) when the link is already spent.
  const linkFailed = Boolean(sp.error || sp.error_code);
  const user = linkFailed ? null : await getUser();

  return (
    <main className="min-h-screen grid place-items-center px-5 sm:px-6 py-10 sm:py-16">
      <div className="w-full max-w-sm">
        <Link href="/" className="block mb-8">
          <span className="text-2xl font-black tracking-tight text-brand-600">Omelo</span>
          <span className="block text-sm muted mt-0.5">for employers</span>
        </Link>

        {user ? (
          <>
            <h1 className="text-2xl font-bold mb-1">Choose a new password</h1>
            <p className="text-sm muted mb-6">
              For <span className="font-semibold">{user.email}</span>. You will stay signed in on this device.
            </p>
            <PasswordForm mode="reset" />
          </>
        ) : (
          <>
            <h1 className="text-2xl font-bold mb-1">This link has expired</h1>
            <p className="text-sm muted mb-6 leading-relaxed">
              Password reset links work once, for a short time, and only in the browser where you asked for
              them. Request a new link and open it here.
            </p>
            <div className="space-y-3">
              <Link href="/forgot-password" className="btn btn-primary w-full">
                Send a new link
              </Link>
              <Link href="/sign-in" className="btn btn-ghost w-full">
                Back to sign in
              </Link>
            </div>
          </>
        )}
      </div>
    </main>
  );
}
