'use client';

import { useActionState } from 'react';
import type { ActionState } from '../../actions';
import { startConversation } from '../../messages/actions';

/** Opens (or creates) the conversation for this application, then goes to it. */
export default function MessageButton({ applicationId }: { applicationId: string }) {
  const [state, action, pending] = useActionState<ActionState, FormData>(startConversation, {});
  return (
    <form action={action} className="flex flex-col gap-1">
      <input type="hidden" name="application_id" value={applicationId} />
      <button type="submit" className="btn btn-ghost" disabled={pending}>
        {pending ? 'Opening…' : 'Message'}
      </button>
      {state.error && (
        <p className="text-xs max-w-[18rem]" role="alert" style={{ color: 'var(--color-danger)' }}>
          {state.error}
        </p>
      )}
    </form>
  );
}
