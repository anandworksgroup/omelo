import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { STATE_LABEL } from '@/lib/format';
import { MESSAGING_CLOSED_STATES } from '@/lib/messaging';
import { InboxLive, InboxTime } from './live';

export const metadata: Metadata = { title: 'Messages · Omelo for Employers' };

const PAGE_SIZE = 100;

type Snapshot = { person?: { display_name?: string } };

export default async function MessagesPage({
  searchParams,
}: {
  searchParams: Promise<{ view?: string }>;
}) {
  const { view } = await searchParams;
  const archived = view === 'archived';
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: rows, error } = await supabase
    .from('conversations')
    .select(
      `id, subject, application_id, job_id, company_archived, last_message_at, created_at,
       jobs ( title ),
       applications ( state, identity_snapshot, persons!applications_person_id_fkey ( display_name ) ),
       messages ( id, sender_type, sender_person_id, body, sent_at )`
    )
    .eq('company_id', ctx.companyId)
    .eq('company_archived', archived)
    .order('last_message_at', { ascending: false, nullsFirst: false })
    .order('created_at', { ascending: false })
    .order('id', { referencedTable: 'messages', ascending: false })
    .limit(1, { referencedTable: 'messages' })
    .limit(PAGE_SIZE);

  const conversations = rows ?? [];
  const ids = conversations.map((c) => c.id);

  const unreadRes = ids.length
    ? await supabase
        .from('messages')
        .select('conversation_id')
        .in('conversation_id', ids)
        .eq('sender_type', 'candidate')
        .is('read_at', null)
        .limit(10_000)
    : { data: [], error: null };
  const unread: Record<string, number> = {};
  for (const m of unreadRes.data ?? []) unread[m.conversation_id] = (unread[m.conversation_id] ?? 0) + 1;

  const tab = (active: boolean) =>
    `px-3 py-1.5 rounded-lg text-sm font-medium ${active ? 'surface border hairline' : 'muted hover:opacity-70'}`;

  return (
    <div className="space-y-5 max-w-3xl">
      <InboxLive companyId={ctx.companyId} />
      <div className="flex items-end gap-3 flex-wrap">
        <div className="flex-1 min-w-0">
          <h1 className="text-xl sm:text-2xl font-bold">Messages</h1>
          <p className="text-sm muted mt-1">
            Conversations with candidates, one per application. Start one from a candidate&apos;s page.
          </p>
        </div>
        <nav className="flex gap-1" aria-label="Inbox filter">
          <Link href="/dashboard/messages" className={tab(!archived)} aria-current={!archived ? 'page' : undefined}>
            Inbox
          </Link>
          <Link
            href="/dashboard/messages?view=archived"
            className={tab(archived)}
            aria-current={archived ? 'page' : undefined}
          >
            Archived
          </Link>
        </nav>
      </div>

      {error ? (
        <div className="card p-5" style={{ borderColor: 'var(--color-danger)' }}>
          <p className="font-semibold mb-1" style={{ color: 'var(--color-danger)' }}>
            Could not load conversations
          </p>
          <p className="text-sm muted">{error.message}</p>
        </div>
      ) : conversations.length === 0 ? (
        <div className="card p-6 text-sm muted">
          {archived ? (
            'No archived conversations.'
          ) : (
            <>
              No conversations yet. Open a candidate from{' '}
              <Link href="/dashboard/candidates" className="underline">
                Candidates
              </Link>{' '}
              and choose <strong>Message</strong>.
            </>
          )}
        </div>
      ) : (
        <ul className="card divide-y divide-[var(--line)] overflow-hidden">
          {conversations.map((c) => {
            const app = c.applications as unknown as {
              state: string;
              identity_snapshot: Snapshot | null;
              persons: { display_name: string | null } | null;
            } | null;
            const job = c.jobs as unknown as { title: string } | null;
            const last = (c.messages ?? [])[0] ?? null;
            const n = unread[c.id] ?? 0;
            const name =
              app?.persons?.display_name ?? app?.identity_snapshot?.person?.display_name ?? 'Candidate';
            const closed = app ? MESSAGING_CLOSED_STATES.includes(app.state) : false;
            const preview = last
              ? `${last.sender_type === 'candidate' ? '' : last.sender_person_id === user?.id ? 'You: ' : 'Team: '}${(last.body ?? '').replace(/\s+/g, ' ')}`
              : 'No messages yet';

            return (
              <li key={c.id}>
                <Link
                  href={`/dashboard/messages/${c.id}`}
                  className="flex items-start gap-3 px-4 py-3.5 hover:bg-[var(--surface)]"
                >
                  <span
                    aria-hidden
                    className="mt-2 h-2 w-2 rounded-full shrink-0"
                    style={{ background: n > 0 ? 'var(--color-brand-600)' : 'transparent' }}
                  />
                  <span className="flex-1 min-w-0">
                    <span className="flex items-baseline gap-2">
                      <span className={`truncate ${n > 0 ? 'font-bold' : 'font-semibold'}`}>{name}</span>
                      <span className="text-xs muted ml-auto shrink-0">
                        <InboxTime iso={last?.sent_at ?? c.last_message_at ?? c.created_at} />
                      </span>
                    </span>
                    <span className="block text-xs muted truncate">
                      {job?.title ?? c.subject ?? 'Job'}
                      {closed && app ? ` · ${STATE_LABEL[app.state] ?? app.state}` : ''}
                    </span>
                    <span className="flex items-center gap-2 mt-1">
                      <span className={`text-sm truncate flex-1 ${n > 0 ? '' : 'muted'}`}>{preview}</span>
                      {n > 0 && (
                        <span
                          className="inline-flex items-center justify-center min-w-[1.3rem] h-[1.3rem] px-1.5 rounded-full text-xs font-bold text-white shrink-0"
                          style={{ background: 'var(--color-brand-600)' }}
                          aria-label={`${n} unread`}
                        >
                          {n > 99 ? '99+' : n}
                        </span>
                      )}
                    </span>
                  </span>
                </Link>
              </li>
            );
          })}
        </ul>
      )}
      {unreadRes.error && (
        <p className="text-sm" style={{ color: 'var(--color-warn)' }}>
          Unread counts could not be loaded: {unreadRes.error.message}
        </p>
      )}
      {conversations.length >= PAGE_SIZE && (
        <p className="text-xs muted">Showing the {PAGE_SIZE} most recently active conversations.</p>
      )}
    </div>
  );
}
