'use client';

import { useActionState } from 'react';
import Link from 'next/link';
import { requestPasswordReset, type AuthState } from '../auth/actions';

export default function ForgotPasswordPage() {
  const [state, action, pending] = useActionState<AuthState, FormData>(requestPasswordReset, {});

  return (
    <main className="min-h-screen grid place-items-center px-5 sm:px-6 py-10 sm:py-16">
      <div className="w-full max-w-sm">
        <Link href="/" className="block mb-8">
          <span className="text-2xl font-black tracking-tight text-brand-600">Omelo</span>
          <span className="block text-sm muted mt-0.5">for employers</span>
        </Link>
        <h1 className="text-2xl font-bold mb-1">Reset your password</h1>

        {state.notice ? (
          <div className="space-y-4">
            <p className="text-sm rounded-lg p-3 surface leading-relaxed" role="status">
              {state.notice}
            </p>
            <p className="text-sm muted leading-relaxed">
              Open the link in this browser. It works once and expires after a short while.
            </p>
            <Link href="/sign-in" className="btn btn-ghost w-full">
              Back to sign in
            </Link>
          </div>
        ) : (
          <>
            <p className="text-sm muted mb-6">
              Enter the email you sign in with and we will send you a link to choose a new password.
            </p>
            <form action={action} className="space-y-4">
              <div>
                <label className="label" htmlFor="email">
                  Work email
                </label>
                <input
                  id="email"
                  name="email"
                  type="email"
                  required
                  autoComplete="email"
                  className="input"
                  placeholder="you@company.com"
                />
              </div>

              {state.error && (
                <p className="text-sm" style={{ color: 'var(--color-danger)' }}>
                  {state.error}
                </p>
              )}

              <button className="btn btn-primary w-full" disabled={pending}>
                {pending ? 'Sending…' : 'Send reset link'}
              </button>

              <p className="text-sm muted text-center">
                Remembered it?{' '}
                <Link href="/sign-in" className="underline">
                  Sign in
                </Link>
              </p>
            </form>
          </>
        )}
      </div>
    </main>
  );
}
