'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import {
  RoomAudioRenderer,
  StartAudio,
  VideoTrack,
  isTrackReference,
  useIsSpeaking,
  useLocalParticipant,
  usePreviewTracks,
  useTracks,
  type TrackReferenceOrPlaceholder,
} from '@livekit/components-react';
import { Track, type LocalVideoTrack } from 'livekit-client';
import { initials } from '@/lib/meet';
import { BarButton, Icon } from './ui';
import { ROLE_LABEL, type Participant } from './types';

/* ------------------------------------------------------------------ */
/* Tiles                                                               */
/* ------------------------------------------------------------------ */

function gridClass(n: number) {
  if (n <= 1) return 'grid-cols-1';
  if (n === 2) return 'grid-cols-1 sm:grid-cols-2';
  if (n <= 4) return 'grid-cols-2';
  return 'grid-cols-2 lg:grid-cols-3';
}

function Avatar({ name }: { name: string }) {
  return (
    <div
      className="h-16 w-16 sm:h-20 sm:w-20 rounded-full grid place-items-center text-xl sm:text-2xl font-bold"
      style={{ background: 'var(--color-brand-700)', color: '#fff' }}
    >
      {initials(name)}
    </div>
  );
}

function TileFrame({
  name,
  role,
  speaking = false,
  muted,
  children,
}: {
  name: string;
  role: string | null;
  speaking?: boolean;
  muted?: boolean;
  children: React.ReactNode;
}) {
  return (
    <div
      className="relative rounded-xl overflow-hidden grid place-items-center min-h-40 aspect-video w-full"
      style={{
        background: '#1a2420',
        boxShadow: speaking ? 'inset 0 0 0 3px var(--color-brand-400)' : 'inset 0 0 0 1px rgba(255,255,255,.06)',
      }}
    >
      {children}
      <div
        className="absolute left-2 bottom-2 max-w-[calc(100%-1rem)] flex items-center gap-1.5 rounded-md px-2 py-1 text-xs text-white"
        style={{ background: 'rgba(0,0,0,.55)' }}
      >
        {muted && <Icon name="mic-off" className="h-3.5 w-3.5 shrink-0" />}
        <span className="font-semibold truncate">{name}</span>
        {role && <span className="opacity-75 shrink-0">· {ROLE_LABEL[role] ?? role}</span>}
      </div>
    </div>
  );
}

function roleOf(metadata: string | undefined) {
  try {
    return (JSON.parse(metadata ?? '{}') as { role?: string }).role ?? null;
  } catch {
    return null;
  }
}

function LiveTile({ trackRef, localRole }: { trackRef: TrackReferenceOrPlaceholder; localRole: string }) {
  const p = trackRef.participant;
  const speaking = useIsSpeaking(p);
  const name = p.name || 'Participant';
  const role = p.isLocal ? localRole : roleOf(p.metadata);
  const isScreen = trackRef.source === Track.Source.ScreenShare;
  const hasVideo = isTrackReference(trackRef) && !trackRef.publication.isMuted && !!trackRef.publication.track;
  const micMuted = !p.isMicrophoneEnabled;

  return (
    <TileFrame
      name={isScreen ? `${name} (screen)` : p.isLocal ? `${name} (you)` : name}
      role={isScreen ? null : role}
      speaking={!isScreen && speaking}
      muted={!isScreen && micMuted}
    >
      {hasVideo && isTrackReference(trackRef) ? (
        <VideoTrack
          trackRef={trackRef}
          className={`absolute inset-0 h-full w-full ${isScreen ? 'object-contain' : 'object-cover'}`}
          style={p.isLocal && !isScreen ? { transform: 'scaleX(-1)' } : undefined}
        />
      ) : (
        <Avatar name={name} />
      )}
    </TileFrame>
  );
}

/** Video grid when connected to the media server. */
export function LiveStage({ localRole }: { localRole: string }) {
  const tracks = useTracks(
    [
      { source: Track.Source.Camera, withPlaceholder: true },
      { source: Track.Source.ScreenShare, withPlaceholder: false },
    ],
    { onlySubscribed: false }
  );
  // Screen shares first: they are what people need to read.
  const ordered = [...tracks].sort(
    (a, b) => Number(b.source === Track.Source.ScreenShare) - Number(a.source === Track.Source.ScreenShare)
  );
  return (
    <div className="flex-1 min-h-0 overflow-auto p-2 sm:p-4">
      <div className={`grid gap-2 sm:gap-3 ${gridClass(ordered.length)} content-center min-h-full`}>
        {ordered.map((t) => (
          <LiveTile key={`${t.participant.identity}-${t.source}`} trackRef={t} localRole={localRole} />
        ))}
      </div>
      <RoomAudioRenderer />
      <div className="fixed left-1/2 -translate-x-1/2 top-20 z-30">
        <StartAudio label="Click to allow audio" className="btn btn-primary shadow-lg" />
      </div>
    </div>
  );
}

/** Presence grid from the database when video is not available. */
export function PresenceStage({ participants, myId }: { participants: Participant[]; myId: string }) {
  const here = participants.filter((p) => p.status === 'in_room' || p.status === 'admitted');
  return (
    <div className="flex-1 min-h-0 overflow-auto p-2 sm:p-4">
      {here.length === 0 ? (
        <div className="h-full grid place-items-center text-sm text-white/70">Nobody is in the room yet.</div>
      ) : (
        <div className={`grid gap-2 sm:gap-3 ${gridClass(here.length)} content-center min-h-full`}>
          {here.map((p) => {
            const name = p.display_name ?? 'Participant';
            return (
              <TileFrame
                key={p.person_id}
                name={p.person_id === myId ? `${name} (you)` : name}
                role={p.role}
              >
                <div className="flex flex-col items-center gap-2">
                  <Avatar name={name} />
                  <span className="text-xs text-white/60">Video off</span>
                </div>
              </TileFrame>
            );
          })}
        </div>
      )}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Controls                                                            */
/* ------------------------------------------------------------------ */

export function LiveControls({ onError }: { onError: (message: string) => void }) {
  const { localParticipant, isMicrophoneEnabled, isCameraEnabled, isScreenShareEnabled } = useLocalParticipant();
  const [busy, setBusy] = useState<string | null>(null);

  async function toggle(kind: 'mic' | 'cam' | 'screen') {
    setBusy(kind);
    try {
      if (kind === 'mic') await localParticipant.setMicrophoneEnabled(!isMicrophoneEnabled);
      if (kind === 'cam') await localParticipant.setCameraEnabled(!isCameraEnabled);
      if (kind === 'screen') await localParticipant.setScreenShareEnabled(!isScreenShareEnabled);
    } catch (e) {
      const msg = (e as Error).message ?? '';
      onError(
        /permission|denied|notallowed/i.test(msg)
          ? kind === 'screen'
            ? 'Screen sharing was not allowed.'
            : 'Your browser blocked the microphone or camera. Allow access in the address bar and try again.'
          : msg || 'That did not work. Try again.'
      );
    } finally {
      setBusy(null);
    }
  }

  const canShare = typeof navigator !== 'undefined' && !!navigator.mediaDevices?.getDisplayMedia;

  return (
    <>
      <BarButton
        icon={isMicrophoneEnabled ? 'mic' : 'mic-off'}
        label={isMicrophoneEnabled ? 'Mute microphone' : 'Unmute microphone'}
        active={isMicrophoneEnabled}
        pressed={!isMicrophoneEnabled}
        disabled={busy === 'mic'}
        onClick={() => void toggle('mic')}
      />
      <BarButton
        icon={isCameraEnabled ? 'cam' : 'cam-off'}
        label={isCameraEnabled ? 'Turn camera off' : 'Turn camera on'}
        active={isCameraEnabled}
        pressed={!isCameraEnabled}
        disabled={busy === 'cam'}
        onClick={() => void toggle('cam')}
      />
      {canShare && (
        <BarButton
          icon="screen"
          label={isScreenShareEnabled ? 'Stop sharing' : 'Share screen'}
          active={!isScreenShareEnabled}
          pressed={isScreenShareEnabled}
          disabled={busy === 'screen'}
          onClick={() => void toggle('screen')}
        />
      )}
    </>
  );
}

export function DisabledControls() {
  const why = 'Video is not switched on for this environment yet';
  return (
    <>
      <BarButton icon="mic-off" label={why} disabled />
      <BarButton icon="cam-off" label={why} disabled />
      <BarButton icon="screen" label={why} disabled />
    </>
  );
}

/* ------------------------------------------------------------------ */
/* Pre-join                                                            */
/* ------------------------------------------------------------------ */

function PreviewVideo({ track }: { track: LocalVideoTrack }) {
  const ref = useRef<HTMLVideoElement>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    track.attach(el);
    return () => {
      track.detach(el);
    };
  }, [track]);
  return <video ref={ref} className="absolute inset-0 h-full w-full object-cover" style={{ transform: 'scaleX(-1)' }} muted playsInline />;
}

export function PreJoin({
  name,
  title,
  subtitle,
  onJoin,
  onCancel,
  joining,
}: {
  name: string;
  title: string;
  subtitle: string;
  onJoin: (opts: { audio: boolean; video: boolean }) => void;
  onCancel: () => void;
  joining: boolean;
}) {
  const [audio, setAudio] = useState(true);
  const [video, setVideo] = useState(true);
  const [deviceError, setDeviceError] = useState<string | null>(null);
  const options = useMemo(() => ({ audio, video }), [audio, video]);
  const tracks = usePreviewTracks(options, (e) =>
    setDeviceError(
      /permission|denied|notallowed/i.test(e.message)
        ? 'Your browser blocked the camera or microphone. Allow access in the address bar, or join with them off.'
        : 'No camera or microphone was found. You can still join.'
    )
  );
  const videoTrack = tracks?.find((t) => t.kind === Track.Kind.Video) as LocalVideoTrack | undefined;

  return (
    <main className="min-h-dvh grid place-items-center p-4" style={{ background: '#0f1714', color: '#fff' }}>
      <div className="w-full max-w-lg space-y-5">
        <div>
          <p className="text-xs uppercase tracking-wider text-white/60">Omelo Meet · Not recorded</p>
          <h1 className="text-xl font-bold mt-1 break-words">{title}</h1>
          <p className="text-sm text-white/70 break-words">{subtitle}</p>
        </div>
        <div className="relative aspect-video rounded-xl overflow-hidden grid place-items-center" style={{ background: '#1a2420' }}>
          {video && videoTrack ? (
            <PreviewVideo track={videoTrack} />
          ) : (
            <div className="flex flex-col items-center gap-2">
              <Avatar name={name} />
              <span className="text-xs text-white/60">Camera is off</span>
            </div>
          )}
          <div className="absolute bottom-3 inset-x-0 flex justify-center gap-3">
            <BarButton
              icon={audio ? 'mic' : 'mic-off'}
              label={audio ? 'Microphone on' : 'Microphone off'}
              active={audio}
              pressed={!audio}
              onClick={() => setAudio((a) => !a)}
            />
            <BarButton
              icon={video ? 'cam' : 'cam-off'}
              label={video ? 'Camera on' : 'Camera off'}
              active={video}
              pressed={!video}
              onClick={() => setVideo((v) => !v)}
            />
          </div>
        </div>
        {deviceError && <p className="text-sm text-amber-300">{deviceError}</p>}
        <p className="text-sm text-white/70">Joining as <span className="font-semibold text-white">{name}</span></p>
        <div className="flex gap-2">
          <button className="btn btn-primary flex-1" disabled={joining} onClick={() => onJoin({ audio, video })}>
            {joining ? 'Joining…' : 'Join interview'}
          </button>
          <button className="btn border border-white/20 text-white hover:bg-white/10" onClick={onCancel}>
            Back
          </button>
        </div>
      </div>
    </main>
  );
}
