'use client';

import { useActionState } from 'react';
import type { ActionState } from '../../actions';
import { setConversationArchived } from '../actions';

export function ArchiveButton({ conversationId, archived }: { conversationId: string; archived: boolean }) {
  const [state, action, pending] = useActionState<ActionState, FormData>(setConversationArchived, {});
  return (
    <form action={action} className="flex flex-col items-end gap-1">
      <input type="hidden" name="conversation_id" value={conversationId} />
      <input type="hidden" name="archived" value={archived ? 'false' : 'true'} />
      <button type="submit" className="btn btn-ghost" disabled={pending}>
        {pending ? 'Saving…' : archived ? 'Unarchive' : 'Archive'}
      </button>
      {state.error && (
        <p className="text-xs max-w-[16rem] text-right" role="alert" style={{ color: 'var(--color-danger)' }}>
          {state.error}
        </p>
      )}
    </form>
  );
}
