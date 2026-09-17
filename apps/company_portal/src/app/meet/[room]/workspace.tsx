'use client';

import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { createClient } from '@/lib/supabase/client';
import { EvaluationForm, QuestionsEvaluator } from '@/components/interview/feedback-forms';
import { useInterviewFeedback, type FeedbackController } from '@/components/interview/use-feedback';
import {
  CandidateTab,
  ExperienceTab,
  JobTab,
  MatchTab,
  SkillsTab,
  useCandidateContext,
} from './candidate-context';
import { useChat, useRoster } from './live-data';
import { DisabledControls, LiveControls, LiveStage, PresenceStage } from './media';
import { ROLE_LABEL, type JoinInfo, type Participant } from './types';
import { BarButton, Icon, Modal } from './ui';

type Tab =
  | 'candidate'
  | 'experience'
  | 'skills'
  | 'job'
  | 'match'
  | 'questions'
  | 'evaluation'
  | 'chat'
  | 'people';

const MOD_TABS: { key: Tab; label: string }[] = [
  { key: 'candidate', label: 'Candidate' },
  { key: 'experience', label: 'Experience' },
  { key: 'skills', label: 'Skills' },
  { key: 'job', label: 'Job' },
  { key: 'match', label: 'Match' },
  { key: 'questions', label: 'Questions' },
  { key: 'evaluation', label: 'Notes & Evaluation' },
  { key: 'chat', label: 'Chat' },
  { key: 'people', label: 'People' },
];
const GUEST_TABS: { key: Tab; label: string }[] = [
  { key: 'chat', label: 'Chat' },
  { key: 'people', label: 'People' },
];

const REPORT_REASONS = [
  { value: 'harassment', label: 'Harassment' },
  { value: 'discrimination', label: 'Discrimination' },
  { value: 'inappropriate_content', label: 'Inappropriate content' },
  { value: 'impersonation', label: 'Impersonation' },
  { value: 'scam_or_fee_request', label: 'Scam or request for money' },
  { value: 'other', label: 'Something else' },
];

type ControlResult = { ok: true } | { ok: false; message: string };

async function meetControl(body: Record<string, unknown>): Promise<ControlResult> {
  const supabase = createClient();
  const { error } = await supabase.functions.invoke('meet-control', { body });
  if (!error) return { ok: true };
  const ctx = (error as { context?: Response }).context;
  if (ctx && typeof ctx.json === 'function') {
    const b = (await ctx.json().catch(() => ({}))) as { error?: string };
    return { ok: false, message: b.error ?? 'That did not work. Try again.' };
  }
  return { ok: false, message: error.message };
}

/* ------------------------------------------------------------------ */
/* Waiting room                                                        */
/* ------------------------------------------------------------------ */

function WaitingAlerts({ waiting, interviewId, onChanged }: { waiting: Participant[]; interviewId: string; onChanged: () => void }) {
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  if (waiting.length === 0) return null;

  async function decide(personId: string, admit: boolean) {
    setBusy(personId);
    setError(null);
    const supabase = createClient();
    const { error: e } = await supabase.rpc('omelo_meet_admit', {
      p_interview_id: interviewId,
      p_person_id: personId,
      p_admit: admit,
    });
    setBusy(null);
    if (e) setError(e.message);
    onChanged();
  }

  return (
    <div className="px-2 sm:px-4 pt-2 sm:pt-3 space-y-2" aria-live="polite">
      {waiting.map((p) => (
        <div
          key={p.person_id}
          role="alert"
          className="flex items-center gap-3 flex-wrap rounded-xl px-4 py-3"
          style={{ background: '#fff7e6', color: '#3b2a05', boxShadow: '0 0 0 2px var(--color-accent-500)' }}
        >
          <span className="relative flex h-3 w-3 shrink-0" aria-hidden>
            <span className="absolute inline-flex h-full w-full rounded-full opacity-75 animate-ping" style={{ background: 'var(--color-accent-500)' }} />
            <span className="relative inline-flex h-3 w-3 rounded-full" style={{ background: 'var(--color-accent-500)' }} />
          </span>
          <p className="text-sm flex-1 min-w-[10rem]">
            <span className="font-bold">{p.display_name ?? 'The candidate'}</span> is waiting
            {p.role !== 'candidate' ? ` (${ROLE_LABEL[p.role] ?? p.role})` : ''}
          </p>
          <div className="flex gap-2">
            <button
              className="btn btn-primary !h-9 !px-4 text-sm"
              disabled={busy === p.person_id}
              onClick={() => void decide(p.person_id, true)}
            >
              Admit
            </button>
            <button
              className="btn !h-9 !px-4 text-sm border"
              style={{ borderColor: '#d8c39a' }}
              disabled={busy === p.person_id}
              onClick={() => void decide(p.person_id, false)}
            >
              Deny
            </button>
          </div>
        </div>
      ))}
      {error && <p className="text-sm text-red-300">{error}</p>}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Chat                                                                */
/* ------------------------------------------------------------------ */

function ChatPanel({ chat, myId }: { chat: ReturnType<typeof useChat>; myId: string }) {
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);
  const listRef = useRef<HTMLOListElement>(null);
  const count = chat.messages.length;

  useEffect(() => {
    const el = listRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [count]);

  async function send() {
    if (!text.trim()) return;
    setSending(true);
    const ok = await chat.send(text);
    setSending(false);
    if (ok) setText('');
  }

  return (
    <div className="flex flex-col h-full min-h-0">
      <p className="hint !mt-0 mb-2">Everyone admitted to the room can read the chat. Keep private notes in Notes &amp; Evaluation.</p>
      <ol ref={listRef} className="flex-1 min-h-0 overflow-y-auto space-y-2 pr-1">
        {chat.messages.length === 0 && <li className="text-sm muted">No messages yet.</li>}
        {chat.messages.map((m) => {
          const mine = m.sender_id === myId;
          return (
            <li key={m.id} className={`flex flex-col ${mine ? 'items-end' : 'items-start'}`}>
              <span className="text-[11px] muted">
                {mine ? 'You' : (m.sender_name ?? 'Participant')} ·{' '}
                {new Date(m.sent_at).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}
              </span>
              <span
                className="text-sm rounded-xl px-3 py-2 max-w-[90%] whitespace-pre-wrap break-words"
                style={{
                  background: mine ? 'var(--color-brand-600)' : 'var(--surface)',
                  color: mine ? '#fff' : 'var(--fg)',
                }}
              >
                {m.body}
              </span>
            </li>
          );
        })}
      </ol>
      {chat.error && (
        <p className="text-xs mt-2" role="alert" style={{ color: 'var(--color-danger)' }}>
          {chat.error}
        </p>
      )}
      <form
        className="flex gap-2 mt-2"
        onSubmit={(e) => {
          e.preventDefault();
          void send();
        }}
      >
        <input
          className="input flex-1 min-w-0"
          value={text}
          maxLength={2000}
          onChange={(e) => setText(e.target.value)}
          placeholder="Send a message"
          aria-label="Message"
        />
        <button className="btn btn-primary shrink-0" disabled={sending || !text.trim()}>
          Send
        </button>
      </form>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* People                                                              */
/* ------------------------------------------------------------------ */

const STATUS_LABEL: Record<string, string> = {
  invited: 'Invited',
  waiting: 'Waiting',
  admitted: 'Admitted',
  in_room: 'In the room',
  left: 'Left',
  removed: 'Removed',
  denied: 'Denied',
};

function PeoplePanel({
  participants,
  myId,
  canModerate,
  onRemove,
  error,
}: {
  participants: Participant[];
  myId: string;
  canModerate: boolean;
  onRemove: (p: Participant) => void;
  error: string | null;
}) {
  return (
    <div className="space-y-2">
      {error && (
        <p className="text-sm" style={{ color: 'var(--color-danger)' }}>
          {error}
        </p>
      )}
      <ul className="space-y-2">
        {participants.map((p) => (
          <li key={p.person_id} className="flex items-center gap-3 rounded-lg border hairline px-3 py-2">
            <div className="flex-1 min-w-0">
              <p className="text-sm font-semibold truncate">
                {p.display_name ?? 'Participant'}
                {p.person_id === myId ? ' (you)' : ''}
              </p>
              <p className="text-xs muted">
                {ROLE_LABEL[p.role] ?? p.role} · {STATUS_LABEL[p.status] ?? p.status}
              </p>
            </div>
            {canModerate && p.person_id !== myId && p.role !== 'host' && !['removed', 'denied'].includes(p.status) && (
              <button
                className="text-xs font-semibold hover:opacity-70"
                style={{ color: 'var(--color-danger)' }}
                onClick={() => onRemove(p)}
              >
                Remove
              </button>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Dialogs                                                             */
/* ------------------------------------------------------------------ */

function ReportDialog({
  interviewId,
  participants,
  myId,
  onClose,
}: {
  interviewId: string;
  participants: Participant[];
  myId: string;
  onClose: () => void;
}) {
  const [reason, setReason] = useState('');
  const [details, setDetails] = useState('');
  const [person, setPerson] = useState('');
  const [state, setState] = useState<'idle' | 'sending' | 'done'>('idle');
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    if (!reason) {
      setError('Choose what happened.');
      return;
    }
    setState('sending');
    const supabase = createClient();
    const { error: e } = await supabase.rpc('omelo_report_meet_abuse', {
      p_interview_id: interviewId,
      p_reason: reason,
      p_details: details.trim() || undefined,
      p_reported_person_id: person || undefined,
    });
    if (e) {
      setError(e.message);
      setState('idle');
      return;
    }
    setState('done');
  }

  return (
    <Modal title="Report a problem" onClose={onClose}>
      {state === 'done' ? (
        <>
          <p className="text-sm">Thank you. Omelo&apos;s safety team has your report and the room&apos;s audit trail.</p>
          <button className="btn btn-primary w-full" onClick={onClose}>
            Close
          </button>
        </>
      ) : (
        <>
          <div>
            <label className="label" htmlFor="rp_reason">
              What happened?
            </label>
            <select id="rp_reason" className="input" value={reason} onChange={(e) => setReason(e.target.value)}>
              <option value="">Choose…</option>
              {REPORT_REASONS.map((r) => (
                <option key={r.value} value={r.value}>
                  {r.label}
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="label" htmlFor="rp_person">
              Who is it about? (optional)
            </label>
            <select id="rp_person" className="input" value={person} onChange={(e) => setPerson(e.target.value)}>
              <option value="">Not about a person</option>
              {participants
                .filter((p) => p.person_id !== myId)
                .map((p) => (
                  <option key={p.person_id} value={p.person_id}>
                    {p.display_name ?? 'Participant'} ({ROLE_LABEL[p.role] ?? p.role})
                  </option>
                ))}
            </select>
          </div>
          <div>
            <label className="label" htmlFor="rp_details">
              Details (optional)
            </label>
            <textarea id="rp_details" className="input" rows={3} maxLength={2000} value={details} onChange={(e) => setDetails(e.target.value)} />
          </div>
          {error && (
            <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
              {error}
            </p>
          )}
          <div className="flex gap-2">
            <button className="btn btn-primary flex-1" disabled={state === 'sending'} onClick={() => void submit()}>
              {state === 'sending' ? 'Sending…' : 'Send report'}
            </button>
            <button className="btn btn-ghost" onClick={onClose}>
              Cancel
            </button>
          </div>
        </>
      )}
    </Modal>
  );
}

function ConfirmDialog({
  title,
  body,
  confirmLabel,
  danger,
  withReason,
  onConfirm,
  onClose,
}: {
  title: string;
  body: React.ReactNode;
  confirmLabel: string;
  danger?: boolean;
  withReason?: boolean;
  onConfirm: (reason: string) => Promise<ControlResult>;
  onClose: () => void;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [reason, setReason] = useState('');
  return (
    <Modal title={title} onClose={busy ? () => {} : onClose}>
      <div className="text-sm space-y-2">{body}</div>
      {withReason && (
        <div>
          <label className="label" htmlFor="cf_reason">
            Reason (optional)
          </label>
          <input id="cf_reason" className="input" maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)} />
        </div>
      )}
      {error && (
        <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
          {error}
        </p>
      )}
      <div className="flex gap-2">
        <button
          className="btn btn-primary flex-1"
          style={danger ? { background: 'var(--color-danger)' } : undefined}
          disabled={busy}
          onClick={async () => {
            setBusy(true);
            setError(null);
            const res = await onConfirm(reason);
            if (!res.ok) {
              setError(res.message);
              setBusy(false);
            }
          }}
        >
          {busy ? 'Working…' : confirmLabel}
        </button>
        <button className="btn btn-ghost" onClick={onClose} disabled={busy}>
          Cancel
        </button>
      </div>
    </Modal>
  );
}

/* ------------------------------------------------------------------ */
/* Side panel                                                          */
/* ------------------------------------------------------------------ */

function SidePanelBody({
  tab,
  join,
  ctx,
  fb,
  chat,
  roster,
  onRemove,
}: {
  tab: Tab;
  join: JoinInfo;
  ctx: ReturnType<typeof useCandidateContext>;
  fb: FeedbackController;
  chat: ReturnType<typeof useChat>;
  roster: ReturnType<typeof useRoster>;
  onRemove: (p: Participant) => void;
}) {
  switch (tab) {
    case 'candidate':
      return <CandidateTab ctx={ctx} fallbackName={join.interview.candidate_name} />;
    case 'experience':
      return <ExperienceTab ctx={ctx} />;
    case 'skills':
      return <SkillsTab ctx={ctx} />;
    case 'job':
      return <JobTab ctx={ctx} />;
    case 'match':
      return <MatchTab ctx={ctx} />;
    case 'questions':
      return <QuestionsEvaluator fb={fb} interviewId={join.interview.interview_id} canAddQuestions={ctx.isHiringTeam} />;
    case 'evaluation':
      return <EvaluationForm fb={fb} />;
    case 'chat':
      return <ChatPanel chat={chat} myId={join.identity} />;
    case 'people':
      return (
        <PeoplePanel
          participants={roster.participants}
          myId={join.identity}
          canModerate={join.can_moderate}
          onRemove={onRemove}
          error={roster.error}
        />
      );
  }
}

/* ------------------------------------------------------------------ */
/* Workspace                                                           */
/* ------------------------------------------------------------------ */

export default function Workspace({
  join,
  mode,
  unavailableMessage,
  onLeave,
  onEnded,
}: {
  join: JoinInfo;
  mode: 'live' | 'novideo';
  unavailableMessage?: string | null;
  /** Called after the DB has been told we left (or ended). */
  onLeave: (opts: { ended: boolean }) => void;
  onEnded: () => void;
}) {
  const iv = join.interview;
  const mod = join.can_moderate;
  const tabs = mod ? MOD_TABS : GUEST_TABS;

  const [tab, setTab] = useState<Tab>(mod ? 'candidate' : 'chat');
  const [panelOpen, setPanelOpen] = useState(true); // desktop
  const [sheetOpen, setSheetOpen] = useState(false); // phone
  const [menuOpen, setMenuOpen] = useState(false);
  const [dialog, setDialog] = useState<null | { kind: 'end' } | { kind: 'leave' } | { kind: 'report' } | { kind: 'remove'; p: Participant }>(null);
  const [toast, setToast] = useState<string | null>(null);
  const [exiting, setExiting] = useState(false);

  const roster = useRoster(iv.interview_id);
  const ctx = useCandidateContext(iv.interview_id, iv.application_id);
  const fb = useInterviewFeedback(iv.interview_id, null);
  const chatVisible = tab === 'chat' && (panelOpen || sheetOpen);
  const chat = useChat(iv.interview_id, join.identity, chatVisible);

  const waiting = mod ? roster.participants.filter((p) => p.status === 'waiting') : [];
  const me = roster.participants.find((p) => p.person_id === join.identity);
  const ended = roster.roomStatus != null && ['ended', 'expired', 'cancelled'].includes(roster.roomStatus);
  const removed = me?.status === 'removed' || me?.status === 'denied';

  // Leave the room when the tab closes. keepalive lets the request outlive the page.
  const accessToken = useRef<string | null>(null);
  const gone = useRef(false);
  useEffect(() => {
    const supabase = createClient();
    void supabase.auth.getSession().then(({ data }) => {
      accessToken.current = data.session?.access_token ?? null;
    });
    const { data: sub } = supabase.auth.onAuthStateChange((_e, session) => {
      accessToken.current = session?.access_token ?? null;
    });
    const onPageHide = () => {
      if (gone.current || !accessToken.current) return;
      void fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/rpc/omelo_meet_leave`, {
        method: 'POST',
        keepalive: true,
        headers: {
          apikey: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
          Authorization: `Bearer ${accessToken.current}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ p_interview_id: iv.interview_id }),
      }).catch(() => {});
    };
    window.addEventListener('pagehide', onPageHide);
    return () => {
      window.removeEventListener('pagehide', onPageHide);
      sub.subscription.unsubscribe();
    };
  }, [iv.interview_id]);

  function openTab(t: Tab) {
    if (tab === 'chat' && t !== 'chat') chat.markSeen();
    setTab(t);
    setPanelOpen(true);
    setSheetOpen(true);
  }

  function toggleChat() {
    const visible = tab === 'chat' && (panelOpen || sheetOpen);
    chat.markSeen();
    if (visible) {
      setPanelOpen(false);
      setSheetOpen(false);
    } else openTab('chat');
  }

  async function leave() {
    gone.current = true;
    setExiting(true);
    await fb.flush();
    const supabase = createClient();
    await supabase.rpc('omelo_meet_leave', { p_interview_id: iv.interview_id });
    onLeave({ ended: false });
  }

  async function end(): Promise<ControlResult> {
    setExiting(true);
    await fb.flush();
    const res = await meetControl({ interview_id: iv.interview_id, action: 'end' });
    if (res.ok) {
      gone.current = true;
      onLeave({ ended: true });
    } else setExiting(false);
    return res;
  }

  if (removed) {
    return (
      <Notice
        title={me?.status === 'denied' ? 'You were not admitted' : 'You were removed from this interview'}
        body="If you think this is a mistake, contact the employer."
      />
    );
  }
  if (ended && !exiting) {
    return (
      <Notice
        title="This interview has ended"
        body={mod ? 'Record your feedback while it is fresh.' : 'Thank you for joining.'}
        action={
          mod ? (
            <Link className="btn btn-primary" href={`/dashboard/candidates/${iv.application_id}#interview-${iv.interview_id}`} onClick={onEnded}>
              Go to feedback
            </Link>
          ) : (
            <Link className="btn btn-primary" href="/dashboard">
              Done
            </Link>
          )
        }
      />
    );
  }

  const subtitle = [iv.candidate_name, iv.job_title].filter(Boolean).join(' · ');
  const panelContent = (
    <>
      <div className="flex items-center gap-1 overflow-x-auto border-b hairline px-2 shrink-0" role="tablist">
        {tabs.map((t) => (
          <button
            key={t.key}
            role="tab"
            aria-selected={tab === t.key}
            onClick={() => openTab(t.key)}
            className="relative px-2.5 py-2.5 text-[13px] font-semibold whitespace-nowrap -mb-px border-b-2"
            style={{
              borderColor: tab === t.key ? 'var(--color-brand-600)' : 'transparent',
              color: tab === t.key ? 'var(--fg)' : 'var(--muted)',
            }}
          >
            {t.label}
            {t.key === 'chat' && chat.unread > 0 && (
              <span className="ml-1 rounded-full px-1.5 text-[10px]" style={{ background: 'var(--color-accent-500)', color: '#1b1b1b' }}>
                {chat.unread}
              </span>
            )}
            {t.key === 'people' && waiting.length > 0 && (
              <span className="ml-1 rounded-full px-1.5 text-[10px]" style={{ background: 'var(--color-accent-500)', color: '#1b1b1b' }}>
                {waiting.length}
              </span>
            )}
          </button>
        ))}
      </div>
      <div className={`flex-1 min-h-0 p-4 ${tab === 'chat' ? 'flex flex-col' : 'overflow-y-auto'}`}>
        <SidePanelBody
          tab={tab}
          join={join}
          ctx={ctx}
          fb={fb}
          chat={chat}
          roster={roster}
          onRemove={(p) => setDialog({ kind: 'remove', p })}
        />
      </div>
    </>
  );

  return (
    <div className="h-dvh flex flex-col overflow-hidden" style={{ background: '#0f1714' }}>
      {/* ------------------------------------------------ Top bar */}
      <header className="flex items-center gap-2 sm:gap-3 px-3 sm:px-4 h-14 shrink-0 text-white border-b border-white/10">
        <span className="font-black tracking-tight shrink-0" style={{ color: 'var(--color-brand-200)' }}>
          Omelo Meet
        </span>
        <div className="min-w-0 flex-1">
          <p className="text-sm font-semibold truncate">
            {iv.round_name ?? 'Interview'}
            <span className="hidden sm:inline font-normal text-white/70">{subtitle ? ` · ${subtitle}` : ''}</span>
          </p>
          <p className="sm:hidden text-xs text-white/60 truncate">{subtitle}</p>
        </div>
        <span
          className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-semibold shrink-0"
          style={{ background: 'rgba(255,255,255,.08)' }}
          title="Omelo Meet never records interviews"
        >
          <span className="h-2 w-2 rounded-full bg-white/50" aria-hidden />
          Not recorded
        </span>
        {mod && (
          <Link
            href={`/dashboard/candidates/${iv.application_id}`}
            target="_blank"
            className="hidden md:inline-flex items-center gap-1 text-xs text-white/70 hover:text-white shrink-0"
          >
            Full profile <Icon name="external" className="h-3.5 w-3.5" />
          </Link>
        )}
        <button
          className="hidden lg:inline-flex h-9 w-9 items-center justify-center rounded-lg hover:bg-white/10 shrink-0"
          onClick={() => setPanelOpen((o) => !o)}
          aria-label={panelOpen ? 'Hide side panel' : 'Show side panel'}
          aria-pressed={panelOpen}
        >
          <Icon name="panel" />
        </button>
      </header>

      {mode === 'novideo' && (
        <div className="px-3 sm:px-4 py-2 text-sm shrink-0" role="status" style={{ background: '#3a2c0b', color: '#fde9b8' }}>
          <strong>Video isn&apos;t switched on for this environment yet.</strong>{' '}
          <span className="opacity-90">
            {unavailableMessage && !/not switched on/i.test(unavailableMessage) ? `${unavailableMessage} ` : ''}
            You are in the room: the waiting room, chat, candidate details and feedback all work.
          </span>
        </div>
      )}

      <div className="flex-1 min-h-0 flex">
        {/* ---------------------------------------------- Stage */}
        <main className="flex-1 min-w-0 flex flex-col">
          {mod && <WaitingAlerts waiting={waiting} interviewId={iv.interview_id} onChanged={() => void roster.refresh()} />}
          {mode === 'live' ? <LiveStage localRole={join.role} /> : <PresenceStage participants={roster.participants} myId={join.identity} />}

          {toast && (
            <div className="mx-auto mb-2 max-w-md rounded-lg px-3 py-2 text-sm text-white flex gap-3 items-start" style={{ background: '#5b1c17' }} role="alert">
              <span className="flex-1">{toast}</span>
              <button onClick={() => setToast(null)} aria-label="Dismiss">
                <Icon name="close" className="h-4 w-4" />
              </button>
            </div>
          )}

          {/* ---------------------------------------------- Bottom bar */}
          <div className="shrink-0 flex items-center justify-center gap-2 sm:gap-3 px-2 py-3 border-t border-white/10 flex-wrap">
            {mode === 'live' ? <LiveControls onError={setToast} /> : <DisabledControls />}
            <BarButton icon="chat" label="Chat" onClick={toggleChat} badge={chat.unread} pressed={chatVisible} />
            <button
              className="lg:hidden inline-flex items-center justify-center h-11 px-3 rounded-full text-sm font-semibold text-white"
              style={{ background: 'rgba(255,255,255,.12)' }}
              onClick={() => {
                if (tab === 'chat') chat.markSeen();
                setSheetOpen(true);
              }}
            >
              {mod ? 'Notes' : 'Panel'}
              {waiting.length > 0 && <span className="ml-1.5 h-2 w-2 rounded-full" style={{ background: 'var(--color-accent-500)' }} />}
            </button>
            <div className="relative">
              <BarButton icon="more" label="More" onClick={() => setMenuOpen((o) => !o)} pressed={menuOpen} />
              {menuOpen && (
                <>
                  <div className="fixed inset-0 z-30" onClick={() => setMenuOpen(false)} aria-hidden />
                  <ul
                    role="menu"
                    className="absolute bottom-14 left-1/2 -translate-x-1/2 z-40 card shadow-xl py-1 w-56"
                    style={{ color: 'var(--fg)' }}
                  >
                    <li>
                      <button
                        role="menuitem"
                        className="w-full text-left px-4 py-2.5 text-sm hover:bg-[var(--surface)] flex items-center gap-2"
                        onClick={() => {
                          setMenuOpen(false);
                          openTab('people');
                        }}
                      >
                        <Icon name="users" className="h-4 w-4" /> Participants
                      </button>
                    </li>
                    <li>
                      <button
                        role="menuitem"
                        className="w-full text-left px-4 py-2.5 text-sm hover:bg-[var(--surface)] flex items-center gap-2"
                        onClick={() => {
                          setMenuOpen(false);
                          setDialog({ kind: 'report' });
                        }}
                      >
                        <Icon name="flag" className="h-4 w-4" /> Report a problem
                      </button>
                    </li>
                    {mod && (
                      <li>
                        <Link
                          role="menuitem"
                          href={`/dashboard/candidates/${iv.application_id}`}
                          target="_blank"
                          className="w-full text-left px-4 py-2.5 text-sm hover:bg-[var(--surface)] flex items-center gap-2"
                          onClick={() => setMenuOpen(false)}
                        >
                          <Icon name="external" className="h-4 w-4" /> Open full profile
                        </Link>
                      </li>
                    )}
                  </ul>
                </>
              )}
            </div>
            {mod && (
              <button
                className="inline-flex items-center justify-center h-11 px-4 rounded-full text-sm font-semibold"
                style={{ background: '#fff', color: 'var(--color-danger)' }}
                onClick={() => setDialog({ kind: 'end' })}
              >
                <span className="sm:hidden">End</span>
                <span className="hidden sm:inline">End interview</span>
              </button>
            )}
            <BarButton icon="leave" label="Leave" danger showLabel onClick={() => setDialog({ kind: 'leave' })} />
          </div>
        </main>

        {/* ---------------------------------------------- Desktop side panel */}
        {panelOpen && (
          <aside className="hidden lg:flex w-[420px] xl:w-[460px] shrink-0 flex-col min-h-0 border-l border-white/10" style={{ background: 'var(--bg)', color: 'var(--fg)' }}>
            {panelContent}
          </aside>
        )}
      </div>

      {/* ---------------------------------------------- Phone bottom sheet */}
      {sheetOpen && (
        <div className="lg:hidden fixed inset-0 z-40 flex flex-col justify-end" style={{ background: 'rgba(0,0,0,.4)' }} onMouseDown={(e) => { if (e.target === e.currentTarget) setSheetOpen(false); }}>
          <div className="h-[78dvh] rounded-t-2xl flex flex-col min-h-0 shadow-2xl" style={{ background: 'var(--bg)', color: 'var(--fg)' }}>
            <div className="flex items-center px-4 pt-2 shrink-0">
              <span className="mx-auto h-1.5 w-10 rounded-full" style={{ background: 'var(--line)' }} aria-hidden />
              <button
                className="absolute right-3 mt-1 h-9 w-9 grid place-items-center muted"
                onClick={() => {
                  if (tab === 'chat') chat.markSeen();
                  setSheetOpen(false);
                }}
                aria-label="Close panel"
              >
                <Icon name="close" />
              </button>
            </div>
            <div className="flex-1 min-h-0 flex flex-col mt-2">{panelContent}</div>
          </div>
        </div>
      )}

      {/* ---------------------------------------------- Dialogs */}
      {dialog?.kind === 'report' && (
        <ReportDialog interviewId={iv.interview_id} participants={roster.participants} myId={join.identity} onClose={() => setDialog(null)} />
      )}
      {dialog?.kind === 'leave' && (
        <ConfirmDialog
          title="Leave the interview?"
          body={
            <p>
              {mod
                ? 'The interview keeps going for everyone else. You can rejoin while the room is open. To finish it for everyone, use End interview.'
                : 'You can rejoin while the room is open.'}
            </p>
          }
          confirmLabel="Leave"
          danger
          onConfirm={async () => {
            await leave();
            return { ok: true };
          }}
          onClose={() => setDialog(null)}
        />
      )}
      {dialog?.kind === 'end' && (
        <ConfirmDialog
          title="End the interview for everyone?"
          body={
            <>
              <p>Everyone leaves the room and it closes. The round is marked completed and the candidate is told it has gone to your team.</p>
              <p className="muted">Your notes are saved. You will go to the candidate&apos;s page to finish feedback.</p>
            </>
          }
          confirmLabel="End interview"
          danger
          onConfirm={end}
          onClose={() => setDialog(null)}
        />
      )}
      {dialog?.kind === 'remove' && (
        <ConfirmDialog
          title={`Remove ${dialog.p.display_name ?? 'this person'}?`}
          body={<p>They leave the room and cannot rejoin this interview.</p>}
          confirmLabel="Remove"
          danger
          withReason
          onConfirm={async (reason) => {
            const res = await meetControl({
              interview_id: iv.interview_id,
              action: 'remove',
              person_id: dialog.p.person_id,
              reason: reason.trim() || undefined,
            });
            if (res.ok) {
              setDialog(null);
              void roster.refresh();
            }
            return res;
          }}
          onClose={() => setDialog(null)}
        />
      )}
    </div>
  );
}

export function Notice({ title, body, action }: { title: string; body?: React.ReactNode; action?: React.ReactNode }) {
  return (
    <main className="min-h-dvh grid place-items-center p-6 text-center" style={{ background: '#0f1714', color: '#fff' }}>
      <div className="max-w-md space-y-3">
        <p className="text-xs uppercase tracking-wider text-white/60">Omelo Meet</p>
        <h1 className="text-xl font-bold">{title}</h1>
        {body && <div className="text-sm text-white/75">{body}</div>}
        {action && <div className="pt-2 flex justify-center gap-2 flex-wrap">{action}</div>}
      </div>
    </main>
  );
}
