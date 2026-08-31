'use client';

import { useActionState } from 'react';
import Link from 'next/link';
import { useSearchParams } from 'next/navigation';
import { Suspense } from 'react';
import { signIn, type AuthState } from '../auth/actions';

function Form() {
  const params = useSearchParams();
  const next = params.get('next') ?? '/dashboard';
  const [state, action, pending] = useActionState<AuthState, FormData>(
    signIn,
    {}
  );

  return (
    <form action={action} className="space-y-4">
      <input type="hidden" name="next" value={next} />
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
      <div>
        <label className="label" htmlFor="password">
          Password
        </label>
        <input
          id="password"
          name="password"
          type="password"
          required
          autoComplete="current-password"
          className="input"
        />
      </div>

      {state.error && (
        <p className="text-sm" style={{ color: 'var(--color-danger)' }}>
          {state.error}
        </p>
      )}

      <button className="btn btn-primary w-full" disabled={pending}>
        {pending ? 'Signing in…' : 'Sign in'}
      </button>

      <p className="text-sm muted text-center">
        No account?{' '}
        <Link href="/sign-up" className="underline">
          Create one
        </Link>
      </p>
    </form>
  );
}

export default function SignInPage() {
  return (
    <main className="min-h-screen grid place-items-center px-5 sm:px-6 py-10 sm:py-16">
      <div className="w-full max-w-sm">
        <Link href="/" className="block mb-8">
          <span className="text-2xl font-black tracking-tight text-brand-600">
            Omelo
          </span>
          <span className="block text-sm muted mt-0.5">for employers</span>
        </Link>
        <h1 className="text-2xl font-bold mb-1">Sign in</h1>
        <p className="text-sm muted mb-6">
          Manage your jobs, candidates and hiring.
        </p>
        <Suspense fallback={null}>
          <Form />
        </Suspense>
      </div>
    </main>
  );
}
