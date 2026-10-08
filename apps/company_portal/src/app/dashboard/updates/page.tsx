import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { createClient, getCompanyContext, getUser } from '@/lib/supabase/server';
import { reportError } from '@/lib/observability';
import {
  CANNOT_POST,
  POST_ROW_COLUMNS,
  canDeleteOrganizationPost,
  canPostForOrganization,
  engagementTotals,
  mergeOwnPosts,
  networkError,
  parseOrganizationFeed,
  plural,
  type PostRow,
} from '@/lib/network';
import { ErrorNote, Notice, PageHeader, Section, Tile } from '../agency/ui';
import { Composer, PostControls, ReactionBar, type JobOption } from './updates-client';
import { EngagementLine, PostContent } from './post-ui';

export const metadata: Metadata = { title: 'Updates · Omelo' };

/** The feed function's own ceiling, and the window the summary covers. */
const WINDOW = 20;

/**
 * Release 9 — what the organization says in public.
 *
 * Everything written here lands on the organization's page in the worker app
 * and in the feeds of people who follow it. The page reads the same function
 * the worker app reads (`omelo_organization_feed`), so what a team member sees
 * is what a candidate sees; it also reads the `posts` table so the back office
 * still lists a post that was limited to followers.
 *
 * Who may write is the database's decision (owner, admin, recruiter, HR).
 * Everyone else gets the same list without a composer.
 */
export default async function UpdatesPage() {
  const user = await getUser();
  if (!user) redirect('/sign-in');
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  const canPost = canPostForOrganization(ctx.roles);
  const canDelete = canDeleteOrganizationPost(ctx.roles);

  const [feedRes, ownRes, jobsRes] = await Promise.all([
    supabase.rpc('omelo_organization_feed', { p_company: ctx.companyId, p_limit: WINDOW }),
    supabase
      .from('posts')
      .select(POST_ROW_COLUMNS)
      .eq('author_company_id', ctx.companyId)
      .is('deleted_at', null)
      .eq('status', 'published')
      .order('created_at', { ascending: false })
      .limit(WINDOW),
    canPost
      ? supabase
          .from('jobs')
          .select('id, title, location_text')
          .eq('company_id', ctx.companyId)
          .eq('status', 'published')
          .order('published_at', { ascending: false })
          .limit(100)
      : Promise.resolve({ data: [], error: null }),
  ]);

  if (feedRes.error) reportError(feedRes.error, { action: 'updatesPage.organizationFeed' });
  if (ownRes.error) reportError(ownRes.error, { action: 'updatesPage.ownPosts' });

  const feed = parseOrganizationFeed(feedRes.data ?? null);
  const author = feed?.organization ?? null;
  const rows = (ownRes.data ?? []) as unknown as PostRow[];
  const posts = mergeOwnPosts(rows, feed?.posts ?? [], author, canPost);
  const totals = engagementTotals(posts);

  const jobs: JobOption[] = (jobsRes.data ?? []).map((j) => ({
    id: j.id,
    title: j.title,
    locationText: j.location_text,
  }));

  const orgName = author?.name ?? ctx.companyName;
  const publicCount = posts.filter((p) => p.visibility === 'public').length;

  return (
    <div className="space-y-6 max-w-3xl">
      <PageHeader
        title="Updates"
        subtitle={`What ${orgName} says in public. These posts appear on your organization page and in the feeds of people who follow you — candidates read them before they apply.`}
      />

      {feedRes.error && <ErrorNote label="your organization feed" message={networkError(feedRes.error)} />}
      {ownRes.error && <ErrorNote label="your posts" message={networkError(ownRes.error)} />}

      {/* Followers and engagement -------------------------------------- */}
      <div className="grid gap-3 grid-cols-2 sm:grid-cols-4">
        <Tile
          label="Followers"
          value={feed ? feed.followers.toLocaleString() : '—'}
          hint={feed ? 'People following your organization' : 'Not available right now'}
        />
        <Tile
          label="Reactions"
          value={totals.reactions.toLocaleString()}
          hint={`Across your last ${plural(totals.posts, 'post')}`}
        />
        <Tile label="Comments" value={totals.comments.toLocaleString()} hint="Same posts" />
        <Tile label="Shares" value={totals.shares.toLocaleString()} hint="Same posts" />
      </div>
      {totals.posts > 0 && (
        <p className="text-xs muted -mt-3">
          {publicCount === totals.posts
            ? 'Every post below is visible to anyone.'
            : `${publicCount} of ${totals.posts} are visible to anyone; the rest are limited.`}{' '}
          Omelo counts followers only — individual followers are theirs to show, not yours to list.
        </p>
      )}

      {/* Composing ------------------------------------------------------ */}
      <Section title="Write an update">
        {canPost ? (
          <Composer personId={user.id} jobs={jobs} organizationName={orgName} />
        ) : (
          <p className="text-sm muted">
            {CANNOT_POST} You can still read everything your organization has posted below.
          </p>
        )}
      </Section>

      {/* The posts ------------------------------------------------------ */}
      <Section title="Posted" aside={<span className="text-sm muted">{plural(posts.length, 'post')}</span>}>
        {posts.length === 0 ? (
          <Notice title="Nothing posted yet">
            An organization that posts is an organization candidates recognise. Share a job you are hiring for,
            something your team did, or where the work happens. Write it for someone who has never heard of you.
          </Notice>
        ) : (
          <ul className="space-y-4">
            {posts.map((post) => (
              <li key={post.id} className="card p-4 space-y-3 min-w-0">
                <PostContent post={post} fallbackName={orgName} />
                <EngagementLine post={post} href={`/dashboard/updates/${post.id}`} />
                <div className="border-t hairline pt-3 space-y-2">
                  <ReactionBar postId={post.id} mine={post.my.reaction} />
                  <PostControls post={post} canEdit={canPost} canDelete={canDelete} />
                </div>
              </li>
            ))}
          </ul>
        )}
        {posts.length >= WINDOW && (
          <p className="text-xs muted">
            Showing the last {WINDOW} posts. Older ones stay on your organization page.
          </p>
        )}
      </Section>

      <p className="text-sm muted">
        Hiring for something?{' '}
        <Link href="/dashboard/jobs" className="underline">
          Open a job
        </Link>{' '}
        and share it from there in one click.
      </p>
    </div>
  );
}
