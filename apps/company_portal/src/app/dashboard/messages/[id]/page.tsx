import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { STATE_LABEL } from '@/lib/format';
import { MESSAGE_COLUMNS, MESSAGING_CLOSED_STATES, isUuid, type ThreadMessage } from '@/lib/messaging';
import { ArchiveButton } from './archive-button';
import Thread from './thread';

export const metadata: Metadata = { title: 'Conversation · Omelo for Employers' };

const HISTORY = 200;

type Snapshot = { person?: { display_name?: string } };

export default async function ConversationPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!isUuid(id)) notFound();
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: convo, error } = await supabase
    .from('conversations')
    .select(
      `id, application_id, job_id, subject, company_archived, created_at,
       jobs ( id, title ),
       applications ( id, state, identity_snapshot, persons!applications_person_id_fkey ( display_name ) )`
    )
    .eq('id', id)
    .eq('company_id', ctx.companyId)
    .maybeSingle();

  if (error) {
    return (
      <div className="max-w-3xl space-y-4">
        <Link href="/dashboard/messages" className="text-sm underline muted">
          ← Messages
        </Link>
        <div className="card p-5" style={{ borderColor: 'var(--color-danger)' }}>
          <p className="font-semibold mb-1" style={{ color: 'var(--color-danger)' }}>
            Could not load this conversation
          </p>
          <p className="text-sm muted">{error.message}</p>
        </div>
      </div>
    );
  }
  if (!convo || !user) notFound();

  const { data: recent, error: msgError } = await supabase
    .from('messages')
    .select(MESSAGE_COLUMNS)
    .eq('conversation_id', id)
    .order('id', { ascending: false })
    .limit(HISTORY);

  const app = convo.applications as unknown as {
    id: string;
    state: string;
    identity_snapshot: Snapshot | null;
    persons: { display_name: string | null } | null;
  } | null;
  const job = convo.jobs as unknown as { id: string; title: string } | null;
  const name = app?.persons?.display_name ?? app?.identity_snapshot?.person?.display_name ?? 'Candidate';
  const closed = app ? MESSAGING_CLOSED_STATES.includes(app.state) : false;
  const initial = ((recent ?? []) as ThreadMessage[]).slice().reverse();

  return (
    <div className="max-w-3xl space-y-4">
      <Link
        href={`/dashboard/messages${convo.company_archived ? '?view=archived' : ''}`}
        className="text-sm underline muted"
      >
        ← Messages
      </Link>

      <header className="card p-4 sm:p-5 flex items-start gap-3 flex-wrap">
        <div className="flex-1 min-w-[12rem]">
          <h1 className="text-lg sm:text-xl font-bold break-words">{name}</h1>
          <p className="text-sm muted mt-0.5 break-words">
            {job ? (
              <Link href={`/dashboard/jobs/${job.id}`} className="underline">
                {job.title}
              </Link>
            ) : (
              (convo.subject ?? 'Job conversation')
            )}
            {app && (
              <>
                {' · '}
                <span>{STATE_LABEL[app.state] ?? app.state}</span>
              </>
            )}
          </p>
        </div>
        <div className="flex gap-2 flex-wrap items-start">
          {convo.application_id && (
            <Link href={`/dashboard/candidates/${convo.application_id}`} className="btn btn-ghost">
              View application
            </Link>
          )}
          <ArchiveButton conversationId={convo.id} archived={convo.company_archived} />
        </div>
      </header>

      {msgError ? (
        <div className="card p-5" style={{ borderColor: 'var(--color-danger)' }}>
          <p className="font-semibold mb-1" style={{ color: 'var(--color-danger)' }}>
            Could not load messages
          </p>
          <p className="text-sm muted">{msgError.message}</p>
        </div>
      ) : (
        <Thread
          conversationId={convo.id}
          myId={user.id}
          candidateName={name}
          initial={initial}
          truncated={(recent ?? []).length >= HISTORY}
          closedReason={
            closed
              ? app?.state === 'withdrawn'
                ? `${name} withdrew from this job, so you can no longer send messages.`
                : `${name} declined your offer, so you can no longer send messages.`
              : null
          }
        />
      )}
    </div>
  );
}
