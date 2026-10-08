import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { reportError } from '@/lib/observability';
import { UUID_RE } from '@/lib/talent';
import {
  canDeleteOrganizationPost,
  canPostForOrganization,
  networkError,
  parseComments,
  parsePostCard,
  plural,
  VISIBILITY_HELP,
  asOrgVisibility,
} from '@/lib/network';
import { ErrorNote, PageHeader, Section } from '../../agency/ui';
import { EngagementLine, PostContent } from '../post-ui';
import { PostControls, ReactionBar } from '../updates-client';
import Comments from './comments';

export const metadata: Metadata = { title: 'Post · Omelo' };

const PAGE = 50;

type SearchParams = Promise<{ after?: string }>;

/**
 * One post and its comments.
 *
 * Reading a post here reads it exactly as a candidate would: `omelo_post_detail`
 * refuses anything the signed-in person could not see anyway. Comments are
 * written as the person, not as the organization — a reply with a name on it
 * is worth more than one from a logo.
 */
export default async function PostPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: SearchParams;
}) {
  const { id } = await params;
  if (!UUID_RE.test(id)) notFound();
  const { after } = await searchParams;
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  const [detailRes, commentsRes] = await Promise.all([
    supabase.rpc('omelo_post_detail', { p_post: id }),
    supabase.rpc('omelo_post_comments', {
      p_post: id,
      p_limit: PAGE,
      ...(after ? { p_after: after } : {}),
    }),
  ]);

  if (detailRes.error) reportError(detailRes.error, { action: 'postPage.detail' });
  if (commentsRes.error) reportError(commentsRes.error, { action: 'postPage.comments' });

  const post = parsePostCard(detailRes.data ?? null);
  if (!post && !detailRes.error) notFound();

  const comments = parseComments(commentsRes.data ?? null);
  const ours = post?.author?.type === 'organization' && post.author.id === ctx.companyId;
  const canEdit = ours && canPostForOrganization(ctx.roles);
  const canDelete = ours && canDeleteOrganizationPost(ctx.roles);
  const last = comments.length === PAGE ? comments[comments.length - 1]?.createdAt : null;

  return (
    <div className="space-y-6 max-w-3xl">
      <PageHeader
        title="Post"
        subtitle={
          post
            ? VISIBILITY_HELP[asOrgVisibility(post.visibility)]
            : 'This post could not be loaded.'
        }
        back={{ href: '/dashboard/updates', label: 'All updates' }}
      />

      {detailRes.error && <ErrorNote label="this post" message={networkError(detailRes.error)} />}

      {post && (
        <section className="card p-4 sm:p-5 space-y-3 min-w-0">
          <PostContent post={post} fallbackName={ctx.companyName} />
          <EngagementLine post={post} />
          <div className="border-t hairline pt-3 space-y-2">
            <ReactionBar postId={post.id} mine={post.my.reaction} />
            <PostControls post={post} canEdit={canEdit} canDelete={canDelete} />
          </div>
        </section>
      )}

      <Section
        title="Comments"
        aside={
          post ? <span className="text-sm muted">{plural(post.engagement.comments, 'comment')}</span> : null
        }
      >
        {commentsRes.error ? (
          <ErrorNote label="the comments" message={networkError(commentsRes.error)} />
        ) : (
          <>
            {after && (
              <p className="text-sm">
                <Link href={`/dashboard/updates/${id}`} className="underline muted">
                  ← Back to the first comments
                </Link>
              </p>
            )}
            <Comments postId={id} comments={comments} canModerate={canDelete} />
            {last && (
              <p className="text-sm pt-1">
                <Link
                  href={`/dashboard/updates/${id}?after=${encodeURIComponent(last)}`}
                  className="underline"
                >
                  Later comments
                </Link>
              </p>
            )}
          </>
        )}
      </Section>
    </div>
  );
}
