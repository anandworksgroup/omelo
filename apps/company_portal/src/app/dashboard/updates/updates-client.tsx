'use client';

import { useId, useRef, useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import {
  ALT_TEXT_MAX,
  BODY_MAX,
  MEDIA_ACCEPT,
  MEDIA_BUCKET,
  MEDIA_BYTES_MAX,
  MEDIA_MAX,
  ORG_VISIBILITIES,
  REACTION_KINDS,
  REACTION_LABEL,
  VIDEO_SECONDS_MAX,
  VISIBILITY_HELP,
  VISIBILITY_LABEL,
  fileSizeText,
  mediaKindOf,
  mediaUrl,
  plural,
  type OrgVisibility,
  type PostCard,
} from '@/lib/network';
import {
  createOrganizationPost,
  deleteOrganizationPost,
  reactToPost,
  updateOrganizationPost,
  type MediaInput,
  type PostResult,
} from './actions';

/* ------------------------------------------------------------------ */
/* Small shared bits                                                   */
/* ------------------------------------------------------------------ */

export function Line({ text, ok }: { text: string | null; ok?: boolean }) {
  if (!text) return null;
  return (
    <p
      className="text-sm basis-full break-words"
      role={ok ? 'status' : 'alert'}
      style={{ color: ok ? 'var(--color-verified)' : 'var(--color-danger)' }}
    >
      {text}
    </p>
  );
}

export function useRun() {
  const router = useRouter();
  const [result, setResult] = useState<{ text: string; ok: boolean } | null>(null);
  const [pending, start] = useTransition();
  const run = (fn: () => Promise<PostResult>, after?: () => void) => {
    setResult(null);
    start(async () => {
      const res = await fn();
      if (!res.ok) return setResult({ text: res.error, ok: false });
      setResult({ text: res.message ?? 'Done.', ok: true });
      after?.();
      router.refresh();
    });
  };
  return { run, result, pending, setResult };
}

function Counter({ value, max }: { value: number; max: number }) {
  const left = max - value;
  const tight = left <= 100;
  return (
    <span
      className="text-xs tabular-nums"
      style={{ color: left < 0 ? 'var(--color-danger)' : tight ? 'var(--color-warn)' : 'var(--muted)' }}
    >
      {value} / {max}
    </span>
  );
}

function VisibilityPicker({
  value,
  onChange,
  id,
}: {
  value: OrgVisibility;
  onChange: (v: OrgVisibility) => void;
  id: string;
}) {
  return (
    <div className="min-w-[10rem]">
      <label className="label" htmlFor={id}>
        Who can see it
      </label>
      <select
        id={id}
        className="input !h-9 !py-0 text-sm"
        value={value}
        onChange={(e) => onChange(e.target.value as OrgVisibility)}
      >
        {ORG_VISIBILITIES.map((v) => (
          <option key={v} value={v}>
            {VISIBILITY_LABEL[v]}
          </option>
        ))}
      </select>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* The composer                                                        */
/* ------------------------------------------------------------------ */

export type JobOption = { id: string; title: string; locationText: string | null };

type Attachment = MediaInput & { id: string; previewUrl: string | null; label: string };

/** Reads an image's size or a video's length so the post card can reserve space. */
function measure(file: File, kind: 'image' | 'video'): Promise<{ width: number | null; height: number | null; durationSeconds: number | null }> {
  return new Promise((resolve) => {
    const blobUrl = URL.createObjectURL(file);
    const done = (v: { width: number | null; height: number | null; durationSeconds: number | null }) => {
      URL.revokeObjectURL(blobUrl);
      resolve(v);
    };
    const giveUp = () => done({ width: null, height: null, durationSeconds: null });
    const timer = setTimeout(giveUp, 8000);
    if (kind === 'image') {
      const img = new Image();
      img.onload = () => {
        clearTimeout(timer);
        done({ width: img.naturalWidth || null, height: img.naturalHeight || null, durationSeconds: null });
      };
      img.onerror = () => {
        clearTimeout(timer);
        giveUp();
      };
      img.src = blobUrl;
    } else {
      const v = document.createElement('video');
      v.preload = 'metadata';
      v.onloadedmetadata = () => {
        clearTimeout(timer);
        const secs = Number.isFinite(v.duration) ? Math.max(1, Math.round(v.duration)) : null;
        done({ width: v.videoWidth || null, height: v.videoHeight || null, durationSeconds: secs });
      };
      v.onerror = () => {
        clearTimeout(timer);
        giveUp();
      };
      v.src = blobUrl;
    }
  });
}

export function Composer({
  personId,
  jobs,
  organizationName,
}: {
  personId: string;
  jobs: JobOption[];
  organizationName: string;
}) {
  const uid = useId();
  const router = useRouter();
  const fileRef = useRef<HTMLInputElement>(null);
  const [body, setBody] = useState('');
  const [visibility, setVisibility] = useState<OrgVisibility>('public');
  const [jobId, setJobId] = useState('');
  const [media, setMedia] = useState<Attachment[]>([]);
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [result, setResult] = useState<{ text: string; ok: boolean } | null>(null);
  const [saving, startSave] = useTransition();

  const tooLong = body.length > BODY_MAX;
  const empty = body.trim().length === 0 && !jobId && media.length === 0;

  async function addFiles(files: FileList | null) {
    if (!files || files.length === 0) return;
    setUploadError(null);
    const room = MEDIA_MAX - media.length;
    if (room <= 0) {
      setUploadError(`A post carries up to ${MEDIA_MAX} images or videos.`);
      return;
    }
    const picked = Array.from(files).slice(0, room);
    setUploading(true);
    const supabase = createClient();
    const added: Attachment[] = [];
    for (const file of picked) {
      const kind = mediaKindOf(file.type);
      if (!kind) {
        setUploadError(`${file.name}: Omelo takes JPEG, PNG, WebP or GIF images and MP4 or WebM video.`);
        continue;
      }
      if (file.size > MEDIA_BYTES_MAX) {
        setUploadError(`${file.name} is ${fileSizeText(file.size)}. The limit is ${fileSizeText(MEDIA_BYTES_MAX)}.`);
        continue;
      }
      const sizes = await measure(file, kind);
      if (kind === 'video' && sizes.durationSeconds != null && sizes.durationSeconds > VIDEO_SECONDS_MAX) {
        setUploadError(`${file.name} is longer than ${VIDEO_SECONDS_MAX / 60} minutes.`);
        continue;
      }
      // Storage only lets a person write inside their own folder.
      const ext = (file.name.split('.').pop() ?? '').replace(/[^a-z0-9]/gi, '').slice(0, 8).toLowerCase();
      const path = `${personId}/${crypto.randomUUID()}${ext ? `.${ext}` : ''}`;
      const { error } = await supabase.storage
        .from(MEDIA_BUCKET)
        .upload(path, file, { contentType: file.type, upsert: false });
      if (error) {
        setUploadError(`${file.name} could not be uploaded: ${error.message}`);
        continue;
      }
      added.push({
        id: path,
        kind,
        storagePath: path,
        mimeType: file.type,
        width: sizes.width,
        height: sizes.height,
        durationSeconds: sizes.durationSeconds,
        altText: '',
        previewUrl: mediaUrl(path),
        label: file.name,
      });
    }
    setMedia((list) => [...list, ...added]);
    setUploading(false);
    if (fileRef.current) fileRef.current.value = '';
  }

  function removeAttachment(id: string) {
    setMedia((list) => list.filter((m) => m.id !== id));
    // Best effort: take the orphan out of the bucket too.
    void createClient().storage.from(MEDIA_BUCKET).remove([id]);
  }

  return (
    <div className="space-y-3">
      <div>
        <label className="label" htmlFor={`${uid}b`}>
          Post as {organizationName}
        </label>
        <textarea
          id={`${uid}b`}
          className="input"
          rows={4}
          value={body}
          onChange={(e) => setBody(e.target.value)}
          placeholder="What is happening at your organization? People outside it read this."
        />
        <div className="flex items-center justify-between gap-3 flex-wrap mt-1">
          <p className="hint !mt-0">Written as the organization, not as you.</p>
          <Counter value={body.length} max={BODY_MAX} />
        </div>
      </div>

      <div className="flex flex-wrap items-end gap-3">
        <VisibilityPicker value={visibility} onChange={setVisibility} id={`${uid}v`} />
        <div className="min-w-[12rem] flex-1">
          <label className="label" htmlFor={`${uid}j`}>
            Attach one of your live jobs
          </label>
          <select
            id={`${uid}j`}
            className="input !h-9 !py-0 text-sm"
            value={jobId}
            onChange={(e) => setJobId(e.target.value)}
            disabled={jobs.length === 0}
          >
            <option value="">{jobs.length === 0 ? 'No published jobs yet' : 'No job'}</option>
            {jobs.map((j) => (
              <option key={j.id} value={j.id}>
                {j.title}
                {j.locationText ? ` — ${j.locationText}` : ''}
              </option>
            ))}
          </select>
        </div>
        <div>
          <input
            ref={fileRef}
            id={`${uid}f`}
            type="file"
            className="sr-only"
            accept={MEDIA_ACCEPT}
            multiple
            onChange={(e) => void addFiles(e.target.files)}
          />
          <label
            htmlFor={`${uid}f`}
            className="btn btn-ghost !h-9 !px-3 text-sm"
            aria-disabled={uploading || media.length >= MEDIA_MAX}
            style={uploading || media.length >= MEDIA_MAX ? { opacity: 0.55, cursor: 'not-allowed' } : undefined}
          >
            {uploading ? 'Uploading…' : 'Add photo or video'}
          </label>
        </div>
      </div>
      <p className="hint !mt-0">{VISIBILITY_HELP[visibility]}</p>
      <Line text={uploadError} />

      {media.length > 0 && (
        <ul className="grid gap-3 sm:grid-cols-2">
          {media.map((m) => (
            <li key={m.id} className="card p-3 space-y-2 min-w-0">
              <div className="flex items-start gap-3">
                <div className="w-20 h-20 rounded-lg overflow-hidden surface shrink-0 grid place-items-center">
                  {m.kind === 'image' && m.previewUrl ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={m.previewUrl} alt="" className="w-full h-full object-cover" />
                  ) : (
                    <span className="text-xs muted font-semibold">Video</span>
                  )}
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-xs font-semibold break-words">{m.label}</p>
                  <p className="text-xs muted">
                    {m.width && m.height ? `${m.width}×${m.height}` : m.kind}
                    {m.durationSeconds ? ` · ${m.durationSeconds}s` : ''}
                  </p>
                  <button
                    type="button"
                    className="btn btn-ghost !h-8 !px-2.5 text-xs mt-1"
                    onClick={() => removeAttachment(m.id)}
                  >
                    Remove
                  </button>
                </div>
              </div>
              <div>
                <label className="label" htmlFor={`${uid}alt${m.id}`}>
                  Describe it <span className="muted font-normal">· read aloud to people who cannot see it</span>
                </label>
                <input
                  id={`${uid}alt${m.id}`}
                  className="input !h-9 text-sm"
                  maxLength={ALT_TEXT_MAX}
                  value={m.altText ?? ''}
                  onChange={(e) =>
                    setMedia((list) => list.map((x) => (x.id === m.id ? { ...x, altText: e.target.value } : x)))
                  }
                />
              </div>
            </li>
          ))}
        </ul>
      )}

      <Line text={result?.text ?? null} ok={result?.ok} />
      <div className="flex items-center gap-2 flex-wrap">
        <button
          type="button"
          className="btn btn-primary"
          disabled={saving || uploading || empty || tooLong}
          onClick={() => {
            setResult(null);
            startSave(async () => {
              const res = await createOrganizationPost({
                body,
                visibility,
                jobId: jobId || null,
                media: media.map(({ kind, storagePath, mimeType, width, height, durationSeconds, altText }) => ({
                  kind,
                  storagePath,
                  mimeType,
                  width,
                  height,
                  durationSeconds,
                  altText,
                })),
              });
              if (!res.ok) return setResult({ text: res.error, ok: false });
              setBody('');
              setJobId('');
              setMedia([]);
              setVisibility('public');
              setResult({ text: res.message ?? 'Posted.', ok: true });
              router.refresh();
            });
          }}
        >
          {saving ? 'Posting…' : 'Post'}
        </button>
        {media.length > 0 && <span className="text-xs muted">{plural(media.length, 'attachment')}</span>}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Editing and removing one post                                       */
/* ------------------------------------------------------------------ */

export function PostControls({
  post,
  canEdit,
  canDelete,
}: {
  post: Pick<PostCard, 'id' | 'body' | 'visibility'>;
  canEdit: boolean;
  canDelete: boolean;
}) {
  const uid = useId();
  const [open, setOpen] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [body, setBody] = useState(post.body ?? '');
  const [visibility, setVisibility] = useState<OrgVisibility>(
    (ORG_VISIBILITIES as readonly string[]).includes(post.visibility)
      ? (post.visibility as OrgVisibility)
      : 'public'
  );
  const { run, result, pending } = useRun();

  if (!canEdit && !canDelete) return null;

  if (open)
    return (
      <div className="space-y-3 border-t hairline pt-3">
        <div>
          <label className="label" htmlFor={`${uid}b`}>
            Edit this post
          </label>
          <textarea
            id={`${uid}b`}
            className="input"
            rows={4}
            value={body}
            onChange={(e) => setBody(e.target.value)}
          />
          <div className="flex items-center justify-between gap-3 flex-wrap mt-1">
            <p className="hint !mt-0">The media and the job stay as they are.</p>
            <Counter value={body.length} max={BODY_MAX} />
          </div>
        </div>
        <VisibilityPicker value={visibility} onChange={setVisibility} id={`${uid}v`} />
        <p className="hint !mt-0">{VISIBILITY_HELP[visibility]}</p>
        <Line text={result?.text ?? null} ok={result?.ok} />
        <div className="flex gap-2 flex-wrap">
          <button
            type="button"
            className="btn btn-primary !h-9 !px-3 text-sm"
            disabled={pending || body.length > BODY_MAX}
            onClick={() => run(() => updateOrganizationPost(post.id, body, visibility), () => setOpen(false))}
          >
            {pending ? 'Saving…' : 'Save'}
          </button>
          <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setOpen(false)}>
            Cancel
          </button>
        </div>
      </div>
    );

  return (
    <div className="flex items-center gap-2 flex-wrap">
      {canEdit && (
        <button type="button" className="btn btn-ghost !h-8 !px-2.5 text-xs" onClick={() => setOpen(true)}>
          Edit
        </button>
      )}
      {canDelete &&
        (confirming ? (
          <>
            <span className="text-xs muted">Delete it everywhere?</span>
            <button
              type="button"
              className="btn btn-ghost !h-8 !px-2.5 text-xs"
              style={{ color: 'var(--color-danger)' }}
              disabled={pending}
              onClick={() => run(() => deleteOrganizationPost(post.id), () => setConfirming(false))}
            >
              {pending ? 'Deleting…' : 'Yes, delete'}
            </button>
            <button
              type="button"
              className="btn btn-ghost !h-8 !px-2.5 text-xs"
              onClick={() => setConfirming(false)}
            >
              Keep it
            </button>
          </>
        ) : (
          <button
            type="button"
            className="btn btn-ghost !h-8 !px-2.5 text-xs"
            style={{ color: 'var(--color-danger)' }}
            onClick={() => setConfirming(true)}
          >
            Delete
          </button>
        ))}
      {result && <Line text={result.text} ok={result.ok} />}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Reacting — as the signed-in person, never as the organization        */
/* ------------------------------------------------------------------ */

export function ReactionBar({ postId, mine }: { postId: string; mine: string | null }) {
  const { run, result, pending } = useRun();
  return (
    <div className="flex items-center gap-1.5 flex-wrap">
      {REACTION_KINDS.map((k) => {
        const on = mine === k;
        return (
          <button
            key={k}
            type="button"
            aria-pressed={on}
            className="pill"
            disabled={pending}
            style={
              on
                ? { color: 'var(--color-brand-700)', borderColor: 'var(--color-brand-600)', background: 'var(--color-brand-50)' }
                : undefined
            }
            onClick={() => run(() => reactToPost(postId, on ? null : k))}
          >
            {REACTION_LABEL[k]}
          </button>
        );
      })}
      <span className="text-xs muted">as you, not as the organization</span>
      {result && !result.ok && <Line text={result.text} />}
    </div>
  );
}
