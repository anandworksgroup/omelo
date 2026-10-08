'use client';

import { useId, useState } from 'react';
import { COMMENT_MAX, plural, type CommentCard, type CommentReply } from '@/lib/network';
import { Avatar } from '../../talent/ui';
import { timeAgo } from '@/lib/format';
import { Line, useRun } from '../updates-client';
import { commentOnPost, deletePostComment } from '../actions';

/*
 * Comments on an organization's post.
 *
 * A team member replies as themselves — their own name and photo, never the
 * organization's. The database lets the comment's author, the post's author
 * and the organization's owners and admins remove a comment; the button is
 * only offered where that is true, and a refusal still comes back as one
 * sentence.
 */

function Who({ author, createdAt }: { author: CommentReply['author']; createdAt: string | null }) {
  const name = author?.name ?? 'Someone on Omelo';
  return (
    <div className="flex items-center gap-2 min-w-0">
      <Avatar name={name} url={author?.avatarUrl ?? null} size={28} />
      <p className="text-sm font-semibold break-words min-w-0">
        {name}
        <span className="muted font-normal"> · {createdAt ? timeAgo(createdAt) : '—'}</span>
      </p>
    </div>
  );
}

function DeleteButton({
  postId,
  commentId,
  label,
}: {
  postId: string;
  commentId: string;
  label: string;
}) {
  const [confirming, setConfirming] = useState(false);
  const { run, result, pending } = useRun();
  if (!confirming)
    return (
      <button
        type="button"
        className="btn btn-ghost !h-7 !px-2 text-xs"
        style={{ color: 'var(--color-danger)' }}
        onClick={() => setConfirming(true)}
      >
        {label}
      </button>
    );
  return (
    <span className="inline-flex items-center gap-1.5 flex-wrap">
      <button
        type="button"
        className="btn btn-ghost !h-7 !px-2 text-xs"
        style={{ color: 'var(--color-danger)' }}
        disabled={pending}
        onClick={() => run(() => deletePostComment(postId, commentId), () => setConfirming(false))}
      >
        {pending ? 'Removing…' : 'Confirm'}
      </button>
      <button type="button" className="btn btn-ghost !h-7 !px-2 text-xs" onClick={() => setConfirming(false)}>
        Keep
      </button>
      {result && !result.ok && <Line text={result.text} />}
    </span>
  );
}

function CommentBox({
  postId,
  parentId,
  placeholder,
  cta,
  onDone,
}: {
  postId: string;
  parentId?: string;
  placeholder: string;
  cta: string;
  onDone?: () => void;
}) {
  const uid = useId();
  const [body, setBody] = useState('');
  const { run, result, pending } = useRun();
  const tooLong = body.length > COMMENT_MAX;

  return (
    <div className="space-y-2">
      <label className="sr-only" htmlFor={`${uid}c`}>
        {placeholder}
      </label>
      <textarea
        id={`${uid}c`}
        className="input"
        rows={parentId ? 2 : 3}
        value={body}
        onChange={(e) => setBody(e.target.value)}
        placeholder={placeholder}
      />
      <div className="flex items-center gap-2 flex-wrap">
        <button
          type="button"
          className="btn btn-primary !h-9 !px-3 text-sm"
          disabled={pending || body.trim().length === 0 || tooLong}
          onClick={() =>
            run(
              () => commentOnPost(postId, body, parentId ?? null),
              () => {
                setBody('');
                onDone?.();
              }
            )
          }
        >
          {pending ? 'Posting…' : cta}
        </button>
        <span
          className="text-xs tabular-nums"
          style={{ color: tooLong ? 'var(--color-danger)' : 'var(--muted)' }}
        >
          {body.length} / {COMMENT_MAX}
        </span>
        {!parentId && <span className="text-xs muted">You reply as yourself, with your own name.</span>}
        <Line text={result?.text ?? null} ok={result?.ok} />
      </div>
    </div>
  );
}

function Reply({
  postId,
  reply,
  canModerate,
}: {
  postId: string;
  reply: CommentReply;
  canModerate: boolean;
}) {
  return (
    <li className="pl-4 border-l hairline space-y-1.5 min-w-0">
      <Who author={reply.author} createdAt={reply.createdAt} />
      <p className="text-sm leading-relaxed whitespace-pre-wrap break-words">{reply.body}</p>
      <div className="flex items-center gap-2 flex-wrap text-xs muted">
        {reply.reactions > 0 && <span className="tabular-nums">{plural(reply.reactions, 'reaction')}</span>}
        {(reply.mine || canModerate) && (
          <DeleteButton postId={postId} commentId={reply.id} label="Remove reply" />
        )}
      </div>
    </li>
  );
}

function Comment({
  postId,
  comment,
  canModerate,
}: {
  postId: string;
  comment: CommentCard;
  canModerate: boolean;
}) {
  const [replying, setReplying] = useState(false);
  return (
    <li className="card p-3 sm:p-4 space-y-2 min-w-0">
      <Who author={comment.author} createdAt={comment.createdAt} />
      <p className="text-sm leading-relaxed whitespace-pre-wrap break-words">{comment.body}</p>
      <div className="flex items-center gap-2 flex-wrap text-xs muted">
        {comment.reactions > 0 && <span className="tabular-nums">{plural(comment.reactions, 'reaction')}</span>}
        {comment.editedAt && <span>edited</span>}
        <button
          type="button"
          className="btn btn-ghost !h-7 !px-2 text-xs"
          onClick={() => setReplying((v) => !v)}
        >
          {replying ? 'Cancel reply' : 'Reply'}
        </button>
        {(comment.mine || canModerate) && (
          <DeleteButton postId={postId} commentId={comment.id} label="Remove comment" />
        )}
      </div>
      {comment.thread.length > 0 && (
        <ul className="space-y-3 pt-1">
          {comment.thread.map((r) => (
            <Reply key={r.id} postId={postId} reply={r} canModerate={canModerate} />
          ))}
        </ul>
      )}
      {replying && (
        <div className="pt-1">
          <CommentBox
            postId={postId}
            parentId={comment.id}
            placeholder={`Reply to ${comment.author?.name ?? 'this comment'}…`}
            cta="Reply"
            onDone={() => setReplying(false)}
          />
        </div>
      )}
    </li>
  );
}

export default function Comments({
  postId,
  comments,
  canModerate,
}: {
  postId: string;
  comments: CommentCard[];
  /** True when this person may remove other people's comments on this post. */
  canModerate: boolean;
}) {
  return (
    <div className="space-y-4">
      <CommentBox
        postId={postId}
        placeholder="Answer a question, thank someone, add what the post left out…"
        cta="Comment"
      />
      {comments.length === 0 ? (
        <p className="text-sm muted">
          No comments yet. When someone asks about this post, answering quickly is the whole point of posting.
        </p>
      ) : (
        <ul className="space-y-3">
          {comments.map((c) => (
            <Comment key={c.id} postId={postId} comment={c} canModerate={canModerate} />
          ))}
        </ul>
      )}
    </div>
  );
}
