'use client';

import Link from 'next/link';
import { useId, useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { timeAgo } from '@/lib/format';
import {
  BODY_MAX,
  ORG_VISIBILITIES,
  VISIBILITY_HELP,
  VISIBILITY_LABEL,
  plural,
  type OrgVisibility,
} from '@/lib/network';
import { shareJobToFeed } from '../../updates/actions';

export type ExistingShare = { id: string; createdAt: string; visibility: string };

/*
 * Release 9 — "Share to the organization's feed" on a job.
 *
 * One click posts the job as the organization: the body is written for us and
 * stays editable, because nobody should publish words they have not read. The
 * database only accepts a published job of this organization's (R9-003), so
 * the button is offered only when that is true.
 */
export default function ShareToFeed({
  jobId,
  suggested,
  canPost,
  isPublished,
  shares,
}: {
  jobId: string;
  suggested: string;
  canPost: boolean;
  isPublished: boolean;
  shares: ExistingShare[];
}) {
  const uid = useId();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [body, setBody] = useState(suggested);
  const [visibility, setVisibility] = useState<OrgVisibility>('public');
  const [result, setResult] = useState<{ text: string; ok: boolean } | null>(null);
  const [saving, start] = useTransition();
  const tooLong = body.length > BODY_MAX;

  return (
    <section className="card p-5 space-y-3">
      <h2 className="font-bold">Share this job with your followers</h2>

      {shares.length > 0 ? (
        <div className="space-y-1">
          <p className="text-sm" style={{ color: 'var(--color-verified)' }}>
            Already shared {shares.length > 1 ? `${plural(shares.length, 'time')}` : timeAgo(shares[0].createdAt)}.
          </p>
          <ul className="text-sm muted space-y-0.5">
            {shares.slice(0, 3).map((s) => (
              <li key={s.id}>
                <Link href={`/dashboard/updates/${s.id}`} className="underline">
                  {timeAgo(s.createdAt)}
                </Link>{' '}
                · {VISIBILITY_LABEL[s.visibility] ?? s.visibility}
              </li>
            ))}
          </ul>
        </div>
      ) : (
        <p className="text-sm muted leading-relaxed">
          A post reaches the people already following your organization, and anyone who finds your page.
          It does not replace the job listing — it points at it.
        </p>
      )}

      {!isPublished ? (
        <p className="text-sm" style={{ color: 'var(--color-warn)' }}>
          Publish the job first. Omelo only shares live jobs, so nobody opens a post about a role they cannot apply for.
        </p>
      ) : !canPost ? (
        <p className="text-sm muted">
          You can&apos;t post for this organization. Only an owner, admin, recruiter or HR can.
        </p>
      ) : !open ? (
        <div className="flex items-center gap-3 flex-wrap">
          <button type="button" className="btn btn-primary" onClick={() => setOpen(true)}>
            {shares.length > 0 ? 'Share it again' : 'Share to the organization feed'}
          </button>
          {result?.ok && (
            <span className="text-sm" role="status" style={{ color: 'var(--color-verified)' }}>
              {result.text}
            </span>
          )}
        </div>
      ) : (
        <div className="space-y-3">
          <div>
            <label className="label" htmlFor={`${uid}b`}>
              What the post says
            </label>
            <textarea
              id={`${uid}b`}
              className="input"
              rows={5}
              value={body}
              onChange={(e) => setBody(e.target.value)}
            />
            <div className="flex items-center justify-between gap-3 flex-wrap mt-1">
              <p className="hint !mt-0">The job card is attached automatically.</p>
              <span
                className="text-xs tabular-nums"
                style={{ color: tooLong ? 'var(--color-danger)' : 'var(--muted)' }}
              >
                {body.length} / {BODY_MAX}
              </span>
            </div>
          </div>

          <div className="min-w-[10rem] max-w-xs">
            <label className="label" htmlFor={`${uid}v`}>
              Who can see it
            </label>
            <select
              id={`${uid}v`}
              className="input !h-9 !py-0 text-sm"
              value={visibility}
              onChange={(e) => setVisibility(e.target.value as OrgVisibility)}
            >
              {ORG_VISIBILITIES.map((v) => (
                <option key={v} value={v}>
                  {VISIBILITY_LABEL[v]}
                </option>
              ))}
            </select>
            <p className="hint">{VISIBILITY_HELP[visibility]}</p>
          </div>

          {result && (
            <p
              className="text-sm break-words"
              role={result.ok ? 'status' : 'alert'}
              style={{ color: result.ok ? 'var(--color-verified)' : 'var(--color-danger)' }}
            >
              {result.text}
            </p>
          )}

          <div className="flex gap-2 flex-wrap">
            <button
              type="button"
              className="btn btn-primary"
              disabled={saving || tooLong}
              onClick={() => {
                setResult(null);
                start(async () => {
                  const res = await shareJobToFeed(jobId, body, visibility);
                  if (!res.ok) return setResult({ text: res.error, ok: false });
                  setOpen(false);
                  setResult({ text: res.message ?? 'Shared.', ok: true });
                  router.refresh();
                });
              }}
            >
              {saving ? 'Posting…' : 'Post it'}
            </button>
            <button
              type="button"
              className="btn btn-ghost"
              onClick={() => {
                setOpen(false);
                setBody(suggested);
              }}
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      <p className="hint">
        Posts live under{' '}
        <Link href="/dashboard/updates" className="underline">
          Updates
        </Link>
        , where you can edit or delete them.
      </p>
    </section>
  );
}
