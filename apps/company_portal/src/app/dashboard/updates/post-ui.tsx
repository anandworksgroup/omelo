/**
 * Presentational pieces for an organization's posts. No hooks, so the server
 * page and the client components both use them.
 *
 * What is drawn here is what the worker app draws on the public organization
 * page: the same body, the same media, the same job card. If it looks wrong
 * here, it looks wrong to everyone.
 */
import Link from 'next/link';
import { WORKPLACE_LABEL, WORK_TYPE_LABEL, formatPay, timeAgo } from '@/lib/format';
import { countryName } from '@/lib/global';
import {
  POST_KIND_LABEL,
  VISIBILITY_LABEL,
  plural,
  type PostAuthor,
  type PostCard,
  type PostJob,
  type PostMedia,
  type SharedPost,
} from '@/lib/network';
import { Avatar } from '../talent/ui';

export function VisibilityPill({ visibility }: { visibility: string }) {
  const label = VISIBILITY_LABEL[visibility] ?? visibility;
  const limited = visibility !== 'public';
  return (
    <span
      className="pill whitespace-nowrap"
      title={limited ? 'Not everyone can see this post.' : 'Anyone on Omelo can see this post.'}
      style={limited ? { color: 'var(--color-warn)', borderColor: 'var(--color-warn)' } : undefined}
    >
      {label}
    </span>
  );
}

export function AuthorLine({
  author,
  createdAt,
  editedAt,
  visibility,
  kind,
  fallbackName,
}: {
  author: PostAuthor | null;
  createdAt: string | null;
  editedAt?: string | null;
  visibility?: string;
  kind?: string;
  fallbackName?: string;
}) {
  const name = author?.name ?? fallbackName ?? 'Your organization';
  return (
    <div className="flex items-start gap-3 min-w-0">
      <Avatar name={name} url={author?.avatarUrl ?? null} size={40} />
      <div className="flex-1 min-w-0">
        <p className="font-bold text-sm break-words">
          {name}
          {author?.verified && (
            <span className="ml-1.5 text-xs font-semibold" style={{ color: 'var(--color-verified)' }}>
              ✓ verified
            </span>
          )}
        </p>
        <p className="text-xs muted break-words">
          {createdAt ? timeAgo(createdAt) : '—'}
          {editedAt ? ' · edited' : ''}
          {author?.headline ? ` · ${author.headline}` : ''}
        </p>
      </div>
      <div className="flex items-center gap-1.5 flex-wrap justify-end">
        {kind && kind !== 'organization_update' && kind !== 'update' && (
          <span className="pill whitespace-nowrap">{POST_KIND_LABEL[kind] ?? kind}</span>
        )}
        {visibility && <VisibilityPill visibility={visibility} />}
      </div>
    </div>
  );
}

export function PostBody({ body }: { body: string | null }) {
  if (!body) return null;
  return (
    <p className="text-sm leading-relaxed whitespace-pre-wrap break-words">{body}</p>
  );
}

export function MediaGrid({ media }: { media: PostMedia[] }) {
  if (media.length === 0) return null;
  return (
    <ul
      className={`grid gap-2 ${media.length === 1 ? 'grid-cols-1' : 'grid-cols-2'}`}
      aria-label={plural(media.length, 'attachment')}
    >
      {media.map((m, i) => (
        <li key={`${m.path}-${i}`} className="min-w-0 overflow-hidden rounded-xl border hairline surface">
          {m.url == null ? (
            <p className="p-3 text-xs muted break-words">This attachment could not be loaded.</p>
          ) : m.kind === 'video' ? (
            <video
              src={m.url}
              controls
              preload="metadata"
              className="w-full h-auto max-h-96 object-contain bg-black"
              aria-label={m.altText ?? 'Video in this post'}
            />
          ) : (
            // Media lives in a public Supabase bucket on a per-project host;
            // next/image would need every host configured for no gain here.
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={m.url}
              alt={m.altText ?? ''}
              className="w-full h-auto max-h-96 object-cover block"
              loading="lazy"
            />
          )}
          {m.altText && <p className="px-3 py-2 text-xs muted break-words">{m.altText}</p>}
        </li>
      ))}
    </ul>
  );
}

export function JobAttachment({ job }: { job: PostJob }) {
  const facts = [
    job.locationText,
    job.country ? countryName(job.country) : null,
    job.workplaceType ? (WORKPLACE_LABEL[job.workplaceType] ?? job.workplaceType) : null,
    job.workType ? (WORK_TYPE_LABEL[job.workType] ?? job.workType) : null,
  ].filter(Boolean);
  return (
    <div className="rounded-xl border hairline surface p-3 space-y-1 min-w-0">
      <p className="text-xs muted font-semibold uppercase tracking-wide">Job in this post</p>
      <p className="font-bold text-sm break-words">
        <Link href={`/dashboard/jobs/${job.id}`} className="hover:underline">
          {job.title}
        </Link>
      </p>
      {facts.length > 0 && <p className="text-xs muted break-words">{facts.join(' · ')}</p>}
      {job.pay && (
        <p className="text-sm font-semibold">
          {formatPay({
            min: job.pay.min,
            max: job.pay.max,
            currency: job.pay.currency,
            period: job.pay.period,
          })}
        </p>
      )}
      {job.status && job.status !== 'published' && (
        <p className="text-xs" style={{ color: 'var(--color-warn)' }}>
          This job is {job.status} — people who open the post will not be able to apply.
        </p>
      )}
    </div>
  );
}

export function SharedQuote({ shared }: { shared: SharedPost }) {
  return (
    <div className="rounded-xl border hairline p-3 space-y-2 min-w-0">
      <AuthorLine author={shared.author} createdAt={shared.createdAt} />
      <PostBody body={shared.body} />
      <MediaGrid media={shared.media} />
    </div>
  );
}

export function EngagementLine({ post, href }: { post: PostCard; href?: string }) {
  const e = post.engagement;
  const parts = [
    plural(e.reactions, 'reaction'),
    plural(e.comments, 'comment'),
    plural(e.shares, 'share'),
    plural(e.saves, 'save'),
  ];
  return (
    <div className="flex items-center gap-3 flex-wrap text-xs muted">
      <span className="tabular-nums">{parts.join(' · ')}</span>
      {href && (
        <Link href={href} className="underline font-semibold">
          {e.comments > 0 ? `Read ${e.comments === 1 ? 'the comment' : 'the comments'}` : 'Open and comment'}
        </Link>
      )}
    </div>
  );
}

/** The post itself, without any of the controls. */
export function PostContent({ post, fallbackName }: { post: PostCard; fallbackName?: string }) {
  return (
    <div className="space-y-3 min-w-0">
      <AuthorLine
        author={post.author}
        createdAt={post.createdAt}
        editedAt={post.editedAt}
        visibility={post.visibility}
        kind={post.kind}
        fallbackName={fallbackName}
      />
      <PostBody body={post.body} />
      <MediaGrid media={post.media} />
      {post.job && <JobAttachment job={post.job} />}
      {post.sharedPost && <SharedQuote shared={post.sharedPost} />}
    </div>
  );
}
