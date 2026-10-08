/**
 * Release 9 — the professional network, employer side.
 *
 * An organization's posts are public-facing: they appear in the worker app's
 * organization page and feed exactly as they are written here. Nothing in this
 * file decides who may read or write anything — `omelo_organization_feed`,
 * `omelo_create_post` and row-level security do that. These helpers only parse
 * the jsonb cards defensively (a missing field stays null, a missing object
 * never crashes a page) and turn the database's vocabulary into the words a
 * person reads on screen.
 *
 * The one rule worth repeating: a post carries text, media, a published job of
 * this organization's, or another public post — never an application, offer,
 * assignment, timesheet or payment (R9-003).
 */
import type { Json } from '@/lib/supabase/database.types';

type Obj = Record<string, unknown>;
const isObj = (v: unknown): v is Obj => !!v && typeof v === 'object' && !Array.isArray(v);
const arr = (v: unknown): unknown[] => (Array.isArray(v) ? v : []);
const str = (v: unknown): string | null => (typeof v === 'string' && v.trim() ? v : null);
const bool = (v: unknown): boolean => v === true;
const num = (v: unknown): number | null => {
  const n = typeof v === 'number' ? v : typeof v === 'string' && v.trim() ? Number(v) : NaN;
  return Number.isFinite(n) ? n : null;
};
const count = (v: unknown): number => num(v) ?? 0;

/* ------------------------------------------------------------------ */
/* Errors                                                              */
/* ------------------------------------------------------------------ */

/** What someone without a posting role is told, in plain words. */
export const CANNOT_POST =
  "You can't post for this organization. Only an owner, admin, recruiter or HR can.";

export const SIGNED_OUT = 'You are signed out or not part of an organization.';

/**
 * One sentence for anything the network functions refuse.
 *
 * The R9 functions raise their own plain-English messages ("Only a published
 * job can be shared", "Share the original post"), so those are shown as they
 * are. A bare 42501 — including the database's own "You cannot post as that
 * organization" — becomes the one sentence above.
 */
export function networkError(e: { code?: string; message?: string } | null | undefined): string {
  const m = (e?.message ?? '').trim();
  if (e?.code === '42501') {
    if (/sign in/i.test(m)) return 'You are signed out. Sign in again and try once more.';
    if (
      !m ||
      /row-level security|permission denied|violates|not allowed|post as that organization|cannot post/i.test(m)
    )
      return CANNOT_POST;
    return m;
  }
  if (e?.code === '22023') return m || 'Omelo could not do that here.';
  if (e?.code === '23505') return m || 'That already exists.';
  return m || 'Something went wrong.';
}

/* ------------------------------------------------------------------ */
/* Who may post as the organization                                    */
/* ------------------------------------------------------------------ */

/** Mirrors omelo_create_post: owner, admin, recruiter, HR. */
export const POSTING_ROLES = ['owner', 'admin', 'recruiter', 'hr'] as const;

export const canPostForOrganization = (roles: readonly string[]) =>
  roles.some((r) => (POSTING_ROLES as readonly string[]).includes(r));

/** Deleting an organization's post is narrower than writing one. */
export const canDeleteOrganizationPost = (roles: readonly string[]) =>
  roles.some((r) => r === 'owner' || r === 'admin');

/* ------------------------------------------------------------------ */
/* Visibility and reactions                                            */
/* ------------------------------------------------------------------ */

/** The three an organization may choose; 'connections' belongs to people. */
export const ORG_VISIBILITIES = ['public', 'followers', 'organization'] as const;
export type OrgVisibility = (typeof ORG_VISIBILITIES)[number];

export const VISIBILITY_LABEL: Record<string, string> = {
  public: 'Anyone',
  followers: 'Followers',
  connections: 'Connections',
  organization: 'Your team only',
};

export const VISIBILITY_HELP: Record<OrgVisibility, string> = {
  public:
    'Anyone on Omelo, signed in or not. It shows on your public organization page and can reach people who do not follow you yet.',
  followers: 'Only people who follow your organization see it in their feed.',
  organization: 'Only members of this organization. Nothing leaves the workspace.',
};

export const asOrgVisibility = (v: string | null | undefined): OrgVisibility =>
  (ORG_VISIBILITIES as readonly string[]).includes(v ?? '') ? (v as OrgVisibility) : 'public';

export const REACTION_KINDS = ['like', 'celebrate', 'support', 'insightful', 'curious'] as const;
export type ReactionKind = (typeof REACTION_KINDS)[number];

export const REACTION_LABEL: Record<string, string> = {
  like: 'Like',
  celebrate: 'Celebrate',
  support: 'Support',
  insightful: 'Insightful',
  curious: 'Curious',
};

export const POST_KIND_LABEL: Record<string, string> = {
  update: 'Update',
  job_share: 'Job',
  organization_update: 'Update',
  hiring: 'Hiring',
  achievement: 'Milestone',
  share: 'Shared post',
};

/** The longest a post body may be, as the database checks it. */
export const BODY_MAX = 3000;
export const COMMENT_MAX = 2000;
export const ALT_TEXT_MAX = 300;

/* ------------------------------------------------------------------ */
/* Media                                                               */
/* ------------------------------------------------------------------ */

export const MEDIA_BUCKET = 'post-media';
/** post_media.position is 0..9. */
export const MEDIA_MAX = 10;
/** The bucket's own limit. */
export const MEDIA_BYTES_MAX = 52_428_800;
/** duration_seconds is checked between 1 and 600. */
export const VIDEO_SECONDS_MAX = 600;

export const IMAGE_MIME = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'] as const;
export const VIDEO_MIME = ['video/mp4', 'video/webm'] as const;
export const MEDIA_MIME: readonly string[] = [...IMAGE_MIME, ...VIDEO_MIME];
export const MEDIA_ACCEPT = MEDIA_MIME.join(',');

/**
 * A public URL for something in the post-media bucket.
 *
 * The post card hands back the raw storage path; the bucket is public, so the
 * URL is a plain conversion with no round trip. Anything that already looks
 * like a URL is passed through untouched.
 */
export function mediaUrl(path: string | null): string | null {
  if (!path) return null;
  if (/^https?:\/\//i.test(path)) return path;
  const base = (process.env.NEXT_PUBLIC_SUPABASE_URL ?? '').replace(/\/+$/, '');
  if (!base) return null;
  const encoded = path.split('/').map(encodeURIComponent).join('/');
  return `${base}/storage/v1/object/public/${MEDIA_BUCKET}/${encoded}`;
}

export function mediaKindOf(mime: string): 'image' | 'video' | null {
  if ((IMAGE_MIME as readonly string[]).includes(mime)) return 'image';
  if ((VIDEO_MIME as readonly string[]).includes(mime)) return 'video';
  return null;
}

export function fileSizeText(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

/* ------------------------------------------------------------------ */
/* The cards                                                           */
/* ------------------------------------------------------------------ */

export type PostAuthor = {
  type: 'person' | 'organization';
  id: string | null;
  name: string;
  avatarUrl: string | null;
  slug: string | null;
  headline: string | null;
  verified: boolean;
  organizationType: string | null;
};

export type PostMedia = {
  kind: 'image' | 'video';
  /** The raw storage path, as post_media holds it. */
  path: string;
  /** The public URL, or null when the Supabase URL is not configured. */
  url: string | null;
  altText: string | null;
  width: number | null;
  height: number | null;
  durationSeconds: number | null;
};

export type PostPay = {
  min: number | null;
  max: number | null;
  period: string | null;
  currency: string | null;
};

export type PostJob = {
  id: string;
  title: string;
  company: string | null;
  locationText: string | null;
  country: string | null;
  workplaceType: string | null;
  workType: string | null;
  status: string | null;
  pay: PostPay | null;
};

export type SharedPost = {
  id: string;
  body: string | null;
  createdAt: string | null;
  author: PostAuthor | null;
  media: PostMedia[];
};

export type PostEngagement = { reactions: number; comments: number; shares: number; saves: number };

export type PostCard = {
  id: string;
  kind: string;
  body: string | null;
  visibility: string;
  createdAt: string | null;
  editedAt: string | null;
  author: PostAuthor | null;
  media: PostMedia[];
  job: PostJob | null;
  sharedPost: SharedPost | null;
  engagement: PostEngagement;
  my: { reaction: string | null; saved: boolean; mine: boolean };
};

export type OrganizationFeed = {
  organization: PostAuthor | null;
  followers: number;
  following: boolean;
  posts: PostCard[];
};

function parseAuthor(v: unknown): PostAuthor | null {
  if (!isObj(v)) return null;
  const name = str(v.name);
  if (!name) return null;
  return {
    type: v.type === 'organization' ? 'organization' : 'person',
    id: str(v.id),
    name,
    avatarUrl: str(v.avatar_url),
    slug: str(v.slug),
    headline: str(v.headline),
    verified: bool(v.verified),
    organizationType: str(v.organization_type),
  };
}

function parseMedia(v: unknown): PostMedia[] {
  return arr(v)
    .filter(isObj)
    .map((m) => {
      const path = str(m.url) ?? str(m.storage_path) ?? '';
      return {
        kind: m.kind === 'video' ? ('video' as const) : ('image' as const),
        path,
        url: mediaUrl(path),
        altText: str(m.alt_text),
        width: num(m.width),
        height: num(m.height),
        durationSeconds: num(m.duration_seconds),
      };
    })
    .filter((m) => !!m.path);
}

function parsePay(v: unknown): PostPay | null {
  if (!isObj(v)) return null;
  const min = num(v.min);
  const max = num(v.max);
  if (min == null && max == null) return null;
  return { min, max, period: str(v.period), currency: str(v.currency) };
}

function parseJob(v: unknown): PostJob | null {
  if (!isObj(v)) return null;
  const id = str(v.id);
  const title = str(v.title);
  if (!id || !title) return null;
  return {
    id,
    title,
    company: str(v.company),
    locationText: str(v.location_text),
    country: str(v.country),
    workplaceType: str(v.workplace_type),
    workType: str(v.work_type),
    status: str(v.status),
    pay: parsePay(v.pay),
  };
}

function parseShared(v: unknown): SharedPost | null {
  if (!isObj(v)) return null;
  const id = str(v.id);
  if (!id) return null;
  return {
    id,
    body: str(v.body),
    createdAt: str(v.created_at),
    author: parseAuthor(v.author),
    media: parseMedia(v.media),
  };
}

export function parsePostCard(v: unknown): PostCard | null {
  if (!isObj(v)) return null;
  const id = str(v.id);
  if (!id) return null;
  const engagement = isObj(v.engagement) ? v.engagement : {};
  const my = isObj(v.my) ? v.my : {};
  return {
    id,
    kind: str(v.kind) ?? 'update',
    body: str(v.body),
    visibility: str(v.visibility) ?? 'public',
    createdAt: str(v.created_at),
    editedAt: str(v.edited_at),
    author: parseAuthor(v.author),
    media: parseMedia(v.media),
    job: parseJob(v.job),
    sharedPost: parseShared(v.shared_post),
    engagement: {
      reactions: count(engagement.reactions),
      comments: count(engagement.comments),
      shares: count(engagement.shares),
      saves: count(engagement.saves),
    },
    my: {
      reaction: str(my.reaction),
      saved: bool(my.saved),
      mine: bool(my.mine),
    },
  };
}

export function parseOrganizationFeed(v: Json | null): OrganizationFeed | null {
  if (!isObj(v)) return null;
  return {
    organization: parseAuthor(v.organization),
    followers: count(v.followers),
    following: bool(v.following),
    posts: arr(v.posts)
      .map(parsePostCard)
      .filter((p): p is PostCard => !!p),
  };
}

/* ------------------------------------------------------------------ */
/* The organization's own posts, straight from the table               */
/* ------------------------------------------------------------------ */

/**
 * A row of `posts` as the Updates page selects it.
 *
 * The feed function only returns what a viewer could see in the worker app —
 * a followers-only post is invisible to a colleague who does not follow the
 * organization. The back office should still show the organization everything
 * it has published, so the page reads the table too (row-level security still
 * decides) and this turns one row into the same card shape.
 */
export type PostRow = {
  id: string;
  kind: string | null;
  body: string | null;
  visibility: string | null;
  created_at: string;
  edited_at: string | null;
  reaction_count: number | null;
  comment_count: number | null;
  share_count: number | null;
  save_count: number | null;
  post_media?: {
    position: number | null;
    kind: string | null;
    storage_path: string | null;
    alt_text: string | null;
    width: number | null;
    height: number | null;
    duration_seconds: number | null;
  }[] | null;
  jobs?: {
    id: string;
    title: string;
    location_text: string | null;
    country_code: string | null;
    workplace_type: string | null;
    work_type: string | null;
    status: string | null;
    pay_min: number | null;
    pay_max: number | null;
    pay_period: string | null;
    pay_currency: string | null;
    pay_disclosed: boolean | null;
  } | null;
};

/** The columns `cardFromRow` needs, so the page and this file cannot drift. */
export const POST_ROW_COLUMNS =
  `id, kind, body, visibility, created_at, edited_at,
   reaction_count, comment_count, share_count, save_count,
   post_media ( position, kind, storage_path, alt_text, width, height, duration_seconds ),
   jobs ( id, title, location_text, country_code, workplace_type, work_type, status,
          pay_min, pay_max, pay_period, pay_currency, pay_disclosed )`;

export function cardFromRow(row: PostRow, author: PostAuthor | null, mine: boolean): PostCard {
  const j = row.jobs ?? null;
  const payShown = !!j && j.pay_disclosed !== false && (j.pay_max ?? j.pay_min) != null;
  return {
    id: row.id,
    kind: row.kind ?? 'organization_update',
    body: row.body,
    visibility: row.visibility ?? 'public',
    createdAt: row.created_at,
    editedAt: row.edited_at,
    author,
    media: [...(row.post_media ?? [])]
      .sort((a, b) => (a.position ?? 0) - (b.position ?? 0))
      .filter((m) => !!m.storage_path)
      .map((m) => ({
        kind: m.kind === 'video' ? ('video' as const) : ('image' as const),
        path: m.storage_path!,
        url: mediaUrl(m.storage_path),
        altText: m.alt_text,
        width: m.width,
        height: m.height,
        durationSeconds: m.duration_seconds,
      })),
    job: j
      ? {
          id: j.id,
          title: j.title,
          company: author?.type === 'organization' ? author.name : null,
          locationText: j.location_text,
          country: j.country_code,
          workplaceType: j.workplace_type,
          workType: j.work_type,
          status: j.status,
          pay: payShown
            ? { min: j.pay_min, max: j.pay_max, period: j.pay_period, currency: j.pay_currency }
            : null,
        }
      : null,
    sharedPost: null,
    engagement: {
      reactions: row.reaction_count ?? 0,
      comments: row.comment_count ?? 0,
      shares: row.share_count ?? 0,
      saves: row.save_count ?? 0,
    },
    my: { reaction: null, saved: false, mine },
  };
}

/**
 * The organization's own posts, newest first.
 *
 * Table rows decide what exists and in what order; the feed's richer card
 * (which reaction the signed-in person left, whether they saved it) is used
 * wherever the feed also returned that post.
 */
export function mergeOwnPosts(rows: PostRow[], feed: PostCard[], author: PostAuthor | null, mine: boolean): PostCard[] {
  if (rows.length === 0) return feed;
  const byId = new Map(feed.map((p) => [p.id, p]));
  return rows.map((r) => byId.get(r.id) ?? cardFromRow(r, author, mine));
}

/* ------------------------------------------------------------------ */
/* Comments                                                            */
/* ------------------------------------------------------------------ */

export type CommentReply = {
  id: string;
  body: string;
  createdAt: string | null;
  author: PostAuthor | null;
  reactions: number;
  mine: boolean;
};

export type CommentCard = CommentReply & {
  editedAt: string | null;
  replies: number;
  myReaction: string | null;
  thread: CommentReply[];
};

function parseReply(v: unknown): CommentReply | null {
  if (!isObj(v)) return null;
  const id = str(v.id);
  if (!id) return null;
  return {
    id,
    body: str(v.body) ?? '',
    createdAt: str(v.created_at),
    author: parseAuthor(v.author),
    reactions: count(v.reactions),
    mine: bool(v.mine),
  };
}

export function parseComments(v: Json | null): CommentCard[] {
  return arr(v)
    .map((c) => {
      const base = parseReply(c);
      if (!base || !isObj(c)) return null;
      return {
        ...base,
        editedAt: str(c.edited_at),
        replies: count(c.replies),
        myReaction: str(c.my_reaction),
        thread: arr(c.thread)
          .map(parseReply)
          .filter((r): r is CommentReply => !!r),
      };
    })
    .filter((c): c is CommentCard => !!c);
}

/* ------------------------------------------------------------------ */
/* Summaries                                                           */
/* ------------------------------------------------------------------ */

export type EngagementTotals = PostEngagement & { posts: number };

export function engagementTotals(posts: PostCard[]): EngagementTotals {
  return posts.reduce<EngagementTotals>(
    (t, p) => ({
      posts: t.posts + 1,
      reactions: t.reactions + p.engagement.reactions,
      comments: t.comments + p.engagement.comments,
      shares: t.shares + p.engagement.shares,
      saves: t.saves + p.engagement.saves,
    }),
    { posts: 0, reactions: 0, comments: 0, shares: 0, saves: 0 }
  );
}

/** "3 posts" / "1 post" — used in a lot of small places. */
export const plural = (n: number, one: string, many = `${one}s`) => `${n} ${n === 1 ? one : many}`;

/**
 * The body Omelo suggests when an organization shares one of its jobs.
 * Editable before it is posted — it is read by people who do not work here.
 */
export function suggestedJobPost(job: {
  title: string;
  locationText?: string | null;
  workplaceLabel?: string | null;
  workTypeLabel?: string | null;
  payText?: string | null;
}): string {
  const facts = [job.locationText, job.workplaceLabel, job.workTypeLabel].filter(Boolean).join(' · ');
  const lines = [`We're hiring: ${job.title}`];
  if (facts) lines.push(facts);
  if (job.payText) lines.push(job.payText);
  lines.push('See the full role and apply on Omelo.');
  return lines.join('\n').slice(0, BODY_MAX);
}
