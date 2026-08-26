'use client';

import { useActionState } from 'react';
import Link from 'next/link';
import { signUp, type AuthState } from '../auth/actions';

export default function SignUpPage() {
  const [state, action, pending] = useActionState<AuthState, FormData>(
    signUp,
    {}
  );

  return (
    <main className="min-h-screen grid place-items-center px-6 py-16">
      <div className="w-full max-w-sm">
        <Link href="/" className="block mb-8">
          <span className="text-2xl font-black tracking-tight text-brand-600">
            Omelo
          </span>
          <span className="block text-sm muted mt-0.5">for employers</span>
        </Link>

        <h1 className="text-2xl font-bold mb-1">Create an account</h1>
        <p className="text-sm muted mb-6">
          Free to post your first jobs. No card, no email to confirm — you go
          straight in.
        </p>

        <form action={action} className="space-y-4">
          <div>
            <label className="label" htmlFor="full_name">
              Your name
            </label>
            <input
              id="full_name"
              name="full_name"
              className="input"
              autoComplete="name"
              placeholder="Sarah Chen"
            />
          </div>
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
            <p className="hint">
              Use your company domain — it counts toward verification later.
              You will not be asked to confirm it.
            </p>
          </div>
          <div>
            <label className="label" htmlFor="password">
              Password
            </label>
            <input
              id="password"
              name="password"
              type="password"
              required
              minLength={8}
              autoComplete="new-password"
              className="input"
            />
            <p className="hint">At least 8 characters.</p>
          </div>

          {state.error && (
            <p className="text-sm" style={{ color: 'var(--color-danger)' }}>
              {state.error}
            </p>
          )}
          {state.notice && (
            <p
              className="text-sm rounded-lg p-3 surface"
              style={{ color: 'var(--color-verified)' }}
            >
              {state.notice}
            </p>
          )}

          <button className="btn btn-primary w-full" disabled={pending}>
            {pending ? 'Creating account…' : 'Create account'}
          </button>

          <p className="text-sm muted text-center">
            Already have one?{' '}
            <Link href="/sign-in" className="underline">
              Sign in
            </Link>
          </p>
        </form>
      </div>
    </main>
  );
}
