'use client';

import { useActionState } from 'react';
import { updatePassword, type AuthState } from '@/app/auth/actions';

/**
 * New password + confirm. `mode="reset"` redirects to the dashboard on
 * success; `mode="settings"` stays and shows a confirmation.
 */
export default function PasswordForm({ mode }: { mode: 'reset' | 'settings' }) {
  const [state, action, pending] = useActionState<AuthState, FormData>(updatePassword, {});

  return (
    <form action={action} className="space-y-4" key={state.notice ?? 'form'}>
      <input type="hidden" name="mode" value={mode} />
      <div>
        <label className="label" htmlFor={`${mode}-password`}>
          New password
        </label>
        <input
          id={`${mode}-password`}
          name="password"
          type="password"
          required
          minLength={8}
          autoComplete="new-password"
          className="input"
        />
        <p className="hint">At least 8 characters.</p>
      </div>
      <div>
        <label className="label" htmlFor={`${mode}-confirm`}>
          Confirm new password
        </label>
        <input
          id={`${mode}-confirm`}
          name="confirm"
          type="password"
          required
          minLength={8}
          autoComplete="new-password"
          className="input"
        />
      </div>

      {state.error && (
        <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
          {state.error}
        </p>
      )}
      {state.notice && (
        <p className="text-sm" role="status" style={{ color: 'var(--color-verified)' }}>
          {state.notice}
        </p>
      )}

      <button className={`btn btn-primary ${mode === 'reset' ? 'w-full' : ''}`} disabled={pending}>
        {pending ? 'Saving…' : mode === 'reset' ? 'Set new password' : 'Change password'}
      </button>
    </form>
  );
}
