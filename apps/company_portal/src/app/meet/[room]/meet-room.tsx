'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { LiveKitRoom } from '@livekit/components-react';
import { DisconnectReason } from 'livekit-client';
import { FunctionsFetchError, FunctionsHttpError } from '@supabase/supabase-js';
import { createClient } from '@/lib/supabase/client';
import { countdown } from '@/lib/meet';
import { useNow } from '@/lib/use-now';
import { PreJoin } from './media';
import type { Admitted, InterviewPayload, Unavailable } from './types';
import Workspace, { Notice } from './workspace';

type Phase =
  | { kind: 'loading' }
  | { kind: 'too_early'; opensAt: string; scheduledAt: string | null; interview: InterviewPayload }
  | { kind: 'waiting'; interview: InterviewPayload }
  | { kind: 'prejoin'; join: Admitted }
  | { kind: 'live'; join: Admitted; audio: boolean; video: boolean }
  | { kind: 'novideo'; join: Unavailable }
  | { kind: 'disconnected'; join: Admitted; message: string }
  | { kind: 'error'; title: string; message: string; retry: boolean; link?: { href: string; label: string } };

type TokenResponse = { status: number; body: Record<string, unknown> };

async function requestToken(roomName: string): Promise<TokenResponse> {
  const supabase = createClient();
  const { data, error } = await supabase.functions.invoke('meet-token', { body: { room_name: roomName } });
  if (!error) return { status: 200, body: (data ?? {}) as Record<string, unknown> };
  if (error instanceof FunctionsHttpError) {
    const res = error.context as Response;
    const body = (await res.json().catch(() => ({}))) as Record<string, unknown>;
    return { status: res.status, body };
  }
  if (error instanceof FunctionsFetchError) {
    return { status: 0, body: { error: 'Could not reach Omelo. Check your connection and try again.' } };
  }
  return { status: 0, body: { error: error.message } };
}

function errorTitle(status: number, message: string) {
  if (status === 401) return 'Sign in to join';
  if (/cancel/i.test(message)) return 'This interview was cancelled';
  if (/ended/i.test(message)) return 'This interview has ended';
  if (/removed|cannot join/i.test(message)) return 'You cannot join this interview';
  if (status === 429 || /too many/i.test(message)) return 'Too many attempts';
  if (status === 404 || /not found/i.test(message)) return 'Interview not found';
  return 'Could not join the interview';
}

export default function MeetRoom({ roomName }: { roomName: string }) {
  const router = useRouter();
  const [phase, setPhase] = useState<Phase>({ kind: 'loading' });
  const [joining, setJoining] = useState(false);

  const attempt = useCallback(async (): Promise<Phase> => {
    const { status, body } = await requestToken(roomName);
    const state = body.state as string | undefined;
    const interview = body.interview as InterviewPayload | undefined;
    if (status === 200 && state === 'too_early' && interview) {
      return {
        kind: 'too_early',
        opensAt: String(body.opens_at),
        scheduledAt: (body.scheduled_at as string | null) ?? interview.scheduled_at,
        interview,
      };
    }
    if (status === 200 && state === 'waiting' && interview) return { kind: 'waiting', interview };
    if (status === 200 && state === 'admitted') return { kind: 'prejoin', join: body as unknown as Admitted };
    if (state === 'unavailable' && interview) return { kind: 'novideo', join: body as unknown as Unavailable };
    const message = String(body.error ?? 'Something went wrong. Try again.');
    return {
      kind: 'error',
      title: errorTitle(status, message),
      message,
      retry: status === 0 || status === 429 || status >= 500,
    };
  }, [roomName]);

  const load = useCallback(async () => {
    setPhase(await attempt());
  }, [attempt]);

  // First attempt.
  useEffect(() => {
    let cancelled = false;
    void attempt().then((p) => {
      if (!cancelled) setPhase(p);
    });
    return () => {
      cancelled = true;
    };
  }, [attempt]);

  // Too early: try again when the room opens (re-checking at least every minute).
  const opensAt = phase.kind === 'too_early' ? phase.opensAt : null;
  useEffect(() => {
    if (!opensAt) return;
    const wait = Math.max(1000, Math.min(new Date(opensAt).getTime() - Date.now() + 500, 60_000));
    const t = setTimeout(() => {
      void attempt().then(setPhase);
    }, wait);
    return () => clearTimeout(t);
  }, [opensAt, attempt]);

  // Waiting room (candidates): ask again every 8 seconds.
  const isWaiting = phase.kind === 'waiting';
  useEffect(() => {
    if (!isWaiting) return;
    const t = setInterval(() => {
      void attempt().then((p) => {
        if (p.kind !== 'waiting') setPhase(p);
      });
    }, 8000);
    return () => clearInterval(t);
  }, [isWaiting, attempt]);

  async function joinWithDevices(join: Admitted, opts: { audio: boolean; video: boolean }) {
    setJoining(true);
    // Media tokens live 10 minutes; fetch a fresh one if this one is close to expiry.
    let current = join;
    if (new Date(join.expires_at).getTime() - Date.now() < 60_000) {
      const next = await attempt();
      if (next.kind !== 'prejoin') {
        setJoining(false);
        setPhase(next);
        return;
      }
      current = next.join;
    }
    setJoining(false);
    setPhase({ kind: 'live', join: current, ...opts });
  }

  const exitTo = (applicationId: string, interviewId: string, ended: boolean, moderator: boolean) => {
    if (!moderator) router.push('/dashboard');
    else if (ended) router.push(`/dashboard/candidates/${applicationId}#interview-${interviewId}`);
    else router.push(`/dashboard/candidates/${applicationId}`);
  };

  switch (phase.kind) {
    case 'loading':
      return <Notice title="Joining Omelo Meet…" body="Checking your invitation." />;

    case 'error':
      return (
        <Notice
          title={phase.title}
          body={phase.message}
          action={
            <>
              {phase.retry && (
                <button className="btn btn-primary" onClick={() => void load()}>
                  Try again
                </button>
              )}
              {phase.link ? (
                <Link href={phase.link.href} className="btn btn-primary">
                  {phase.link.label}
                </Link>
              ) : null}
              <Link href="/dashboard/interviews" className="btn border border-white/20 text-white hover:bg-white/10">
                Back to interviews
              </Link>
            </>
          }
        />
      );

    case 'too_early':
      return <TooEarly phase={phase} onRetry={() => void load()} />;

    case 'waiting':
      return (
        <Notice
          title="Waiting for the interviewer to let you in"
          body={`${phase.interview.round_name ?? 'Interview'} · ${phase.interview.company_name ?? ''}. Keep this page open.`}
        />
      );

    case 'prejoin':
      return (
        <PreJoin
          name={phase.join.display_name}
          title={`${phase.join.interview.round_name ?? 'Interview'}`}
          subtitle={[phase.join.interview.candidate_name, phase.join.interview.job_title].filter(Boolean).join(' · ')}
          joining={joining}
          onJoin={(opts) => void joinWithDevices(phase.join, opts)}
          onCancel={async () => {
            // The database already admitted us; say we left before going back.
            await createClient().rpc('omelo_meet_leave', { p_interview_id: phase.join.interview.interview_id });
            exitTo(phase.join.interview.application_id, phase.join.interview.interview_id, false, phase.join.can_moderate);
          }}
        />
      );

    case 'disconnected':
      return (
        <Notice
          title="You were disconnected"
          body={phase.message}
          action={
            <button className="btn btn-primary" onClick={() => void load()}>
              Rejoin
            </button>
          }
        />
      );

    case 'novideo':
      return (
        <Workspace
          join={phase.join}
          mode="novideo"
          unavailableMessage={phase.join.error ?? null}
          onLeave={({ ended }) =>
            exitTo(phase.join.interview.application_id, phase.join.interview.interview_id, ended, phase.join.can_moderate)
          }
          onEnded={() => {}}
        />
      );

    case 'live': {
      const { join } = phase;
      return (
        <LiveKitRoom
          serverUrl={join.url}
          token={join.token}
          connect
          audio={phase.audio}
          video={phase.video}
          onDisconnected={(reason) => {
            if (reason === DisconnectReason.CLIENT_INITIATED) return;
            if (reason === DisconnectReason.ROOM_DELETED) {
              // The host ended the interview; the workspace's roster shows the end screen,
              // but the media connection is gone, so show it here too.
              setPhase({
                kind: 'error',
                title: 'This interview has ended',
                message: join.can_moderate ? 'Record your feedback while it is fresh.' : 'Thank you for joining.',
                retry: false,
                link: join.can_moderate
                  ? {
                      href: `/dashboard/candidates/${join.interview.application_id}#interview-${join.interview.interview_id}`,
                      label: 'Go to feedback',
                    }
                  : undefined,
              });
              return;
            }
            if (reason === DisconnectReason.PARTICIPANT_REMOVED) {
              setPhase({ kind: 'error', title: 'You were removed from this interview', message: 'You cannot rejoin.', retry: false });
              return;
            }
            setPhase({ kind: 'disconnected', join, message: 'The connection dropped. Rejoin to continue.' });
          }}
          onError={(e) => setPhase({ kind: 'disconnected', join, message: e.message || 'Could not connect to video.' })}
          style={{ height: '100dvh' }}
        >
          <Workspace
            join={join}
            mode="live"
            onLeave={({ ended }) => exitTo(join.interview.application_id, join.interview.interview_id, ended, join.can_moderate)}
            onEnded={() => {}}
          />
        </LiveKitRoom>
      );
    }
  }
}

function TooEarly({
  phase,
  onRetry,
}: {
  phase: Extract<Phase, { kind: 'too_early' }>;
  onRetry: () => void;
}) {
  const now = useNow();
  const target = new Date(phase.scheduledAt ?? phase.opensAt).getTime();
  const opens = new Date(phase.opensAt);
  const iv = phase.interview;
  return (
    <Notice
      title={now ? `Interview starts in ${countdown(target - now)}` : 'Interview starts soon'}
      body={
        <>
          <p className="font-semibold text-white">
            {iv.round_name ?? 'Interview'}
            {iv.candidate_name ? ` · ${iv.candidate_name}` : ''}
            {iv.job_title ? ` · ${iv.job_title}` : ''}
          </p>
          <p className="mt-1">
            The room opens at {opens.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}
            {opens.toDateString() !== new Date().toDateString()
              ? ` on ${opens.toLocaleDateString([], { weekday: 'short', day: 'numeric', month: 'short' })}`
              : ''}
            . This page will let you in automatically.
          </p>
        </>
      }
      action={
        <>
          <button className="btn border border-white/20 text-white hover:bg-white/10" onClick={onRetry}>
            Check again
          </button>
          <Link href={`/dashboard/candidates/${iv.application_id}`} className="btn btn-primary">
            Prepare: candidate profile
          </Link>
        </>
      }
    />
  );
}
