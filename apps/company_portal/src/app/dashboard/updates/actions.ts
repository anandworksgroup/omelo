'use server';

import { revalidatePath } from 'next/cache';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import type { Json } from '@/lib/supabase/database.types';
import { reportError } from '@/lib/observability';
import { UUID_RE } from '@/lib/talent';
import {
  ALT_TEXT_MAX,
  BODY_MAX,
  COMMENT_MAX,
  MEDIA_MAX,
  MEDIA_MIME,
  ORG_VISIBILITIES,
  REACTION_KINDS,
  SIGNED_OUT,
  VIDEO_SECONDS_MAX,
  canPostForOrganization,
  networkError,
} from '@/lib/network';

/*
 * Release 9 — posting as the organization.
 *
 * Every write is a SECURITY DEFINER function that checks the role itself
 * (owner, admin, recruiter or HR to write; owner or admin to delete) and the
 * R9-003 rule that a post may only carry this organization's own published
 * job. Nothing here widens that: these actions shape the input, keep the
 * company id on the post, and hand the database's sentence back.
 *
 * These posts are read by people who do not work here, so the words matter.
 */

export type PostResult = { ok: true; message?: string; id?: string } | { ok: false; error: string };

/** Codes the database raises on purpose; anything else is worth reporting. */
const EXPECTED = new Set(['42501', '22023', '23505', '23503', '23514', '22001']);
const PATH = '/dashboard/updates';

function fail(e: { code?: string; message: string }, action: string): PostResult {
  if (!EXPECTED.has(e.code ?? '')) reportError(e, { action });
  return { ok: false, error: networkError(e) };
}

async function session() {
  const ctx = await getCompanyContext();
  if (!ctx) return null;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;
  return { ctx, supabase, userId: user.id };
}

function refresh(postId?: string) {
  revalidatePath(PATH);
  if (postId) revalidatePath(`${PATH}/${postId}`);
}

/** The id an RPC hands back inside the whole card. */
function idOf(data: unknown): string | undefined {
  if (data && typeof data === 'object' && !Array.isArray(data)) {
    const v = (data as Record<string, unknown>).id;
    if (typeof v === 'string') return v;
  }
  return undefined;
}

/* ------------------------------------------------------------------ */
/* Composing                                                           */
/* ------------------------------------------------------------------ */

export type MediaInput = {
  kind: 'image' | 'video';
  storagePath: string;
  mimeType: string;
  width?: number | null;
  height?: number | null;
  durationSeconds?: number | null;
  altText?: string | null;
};

export type ComposeInput = {
  body: string;
  visibility: string;
  /** One of this organization's published jobs, or null. */
  jobId?: string | null;
  media?: MediaInput[];
};

type Checked = {
  body: string | null;
  visibility: string;
  jobId: string | null;
  media: Json[];
};

/**
 * Everything the database would refuse anyway, checked here first so the
 * person reads a sentence about the thing they got wrong.
 *
 * `uploadedBy` is the signed-in person: Storage only lets them write inside
 * their own folder, so a path outside it could not be theirs.
 */
function check(input: ComposeInput, uploadedBy: string): Checked | string {
  const body = (input.body ?? '').trim();
  if (body.length > BODY_MAX) return `Keep the post under ${BODY_MAX} characters.`;

  const visibility = (ORG_VISIBILITIES as readonly string[]).includes(input.visibility)
    ? input.visibility
    : 'public';

  const jobId = (input.jobId ?? '').trim() || null;
  if (jobId && !UUID_RE.test(jobId)) return 'That job no longer exists.';

  const list = input.media ?? [];
  if (list.length > MEDIA_MAX) return `A post carries up to ${MEDIA_MAX} images or videos.`;

  const media: Json[] = [];
  for (const m of list) {
    const path = (m.storagePath ?? '').trim();
    if (!path) return 'One of the attachments did not finish uploading. Remove it and try again.';
    if (!path.startsWith(`${uploadedBy}/`))
      return 'Attachments have to be uploaded from this account. Remove them and add them again.';
    if (!MEDIA_MIME.includes(m.mimeType))
      return 'Omelo takes JPEG, PNG, WebP or GIF images and MP4 or WebM video.';
    const kind = m.kind === 'video' ? 'video' : 'image';
    const duration = m.durationSeconds ?? null;
    if (kind === 'video' && duration != null && (duration < 1 || duration > VIDEO_SECONDS_MAX))
      return `A video can be up to ${VIDEO_SECONDS_MAX / 60} minutes long.`;
    const alt = (m.altText ?? '').trim();
    if (alt.length > ALT_TEXT_MAX) return `Keep each description under ${ALT_TEXT_MAX} characters.`;
    media.push({
      kind,
      storage_path: path,
      mime_type: m.mimeType,
      width: m.width ?? null,
      height: m.height ?? null,
      duration_seconds: kind === 'video' ? duration : null,
      alt_text: alt || null,
    });
  }

  if (!body && !jobId && media.length === 0)
    return 'Write something, attach an image or video, or share one of your jobs.';

  return { body: body || null, visibility, jobId, media };
}

/**
 * Confirms the job is this organization's and is live.
 *
 * The trigger behind omelo_create_post checks the same thing; asking first
 * only buys a clearer sentence than "Only a published job can be shared".
 */
async function jobProblem(
  supabase: Awaited<ReturnType<typeof createClient>>,
  companyId: string,
  jobId: string
): Promise<string | null> {
  const { data, error } = await supabase
    .from('jobs')
    .select('id, status')
    .eq('id', jobId)
    .eq('company_id', companyId)
    .maybeSingle();
  if (error) {
    reportError(error, { action: 'updates.jobProblem' });
    return null; // let the database have the final word
  }
  if (!data) return 'You can only share one of your own jobs.';
  if (data.status !== 'published') return 'Publish the job first — only a live job can be shared.';
  return null;
}

export async function createOrganizationPost(input: ComposeInput): Promise<PostResult> {
  const s = await session();
  if (!s) return { ok: false, error: SIGNED_OUT };
  if (!canPostForOrganization(s.ctx.roles))
    return { ok: false, error: "You can't post for this organization." };

  const checked = check(input, s.userId);
  if (typeof checked === 'string') return { ok: false, error: checked };
  if (checked.jobId) {
    const problem = await jobProblem(s.supabase, s.ctx.companyId, checked.jobId);
    if (problem) return { ok: false, error: problem };
  }

  const { data, error } = await s.supabase.rpc('omelo_create_post', {
    p: {
      company_id: s.ctx.companyId,
      body: checked.body,
      visibility: checked.visibility,
      job_id: checked.jobId,
      media: checked.media,
      kind: checked.jobId ? 'job_share' : 'organization_update',
    },
  });
  if (error) return fail(error, 'createOrganizationPost');
  refresh();
  return {
    ok: true,
    id: idOf(data),
    message:
      checked.visibility === 'public'
        ? 'Posted. It is on your organization page now.'
        : 'Posted.',
  };
}

/** One click from the job page: the same post, with a body the person may edit. */
export async function shareJobToFeed(
  jobId: string,
  body: string,
  visibility: string
): Promise<PostResult> {
  const res = await createOrganizationPost({ body, visibility, jobId });
  if (res.ok) {
    revalidatePath(`/dashboard/jobs/${jobId}`);
    return { ...res, message: 'Shared to your organization feed.' };
  }
  return res;
}

export async function updateOrganizationPost(
  postId: string,
  body: string,
  visibility: string
): Promise<PostResult> {
  const s = await session();
  if (!s) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(postId)) return { ok: false, error: 'That post no longer exists.' };
  const trimmed = body.trim();
  if (trimmed.length > BODY_MAX) return { ok: false, error: `Keep the post under ${BODY_MAX} characters.` };
  const wanted = (ORG_VISIBILITIES as readonly string[]).includes(visibility) ? visibility : 'public';

  const { error } = await s.supabase.rpc('omelo_update_post', {
    p_post: postId,
    p: { body: trimmed, visibility: wanted },
  });
  if (error) return fail(error, 'updateOrganizationPost');
  refresh(postId);
  return { ok: true, message: 'Saved. The edit shows wherever the post appears.' };
}

export async function deleteOrganizationPost(postId: string): Promise<PostResult> {
  const s = await session();
  if (!s) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(postId)) return { ok: false, error: 'That post no longer exists.' };
  const { error } = await s.supabase.rpc('omelo_delete_post', { p_post: postId });
  if (error) return fail(error, 'deleteOrganizationPost');
  refresh(postId);
  return { ok: true, message: 'Deleted. It is gone from your organization page and from every feed.' };
}

/* ------------------------------------------------------------------ */
/* Engagement — always as the signed-in person, never as the company    */
/* ------------------------------------------------------------------ */

export async function reactToPost(postId: string, kind: string | null): Promise<PostResult> {
  const s = await session();
  if (!s) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(postId)) return { ok: false, error: 'That post no longer exists.' };
  if (kind !== null && !(REACTION_KINDS as readonly string[]).includes(kind))
    return { ok: false, error: 'That is not a reaction Omelo has.' };

  // p_kind is nullable in the database (null removes the reaction); the
  // generated types only describe the defaulted argument.
  const args = { p_post: postId, p_kind: kind } as unknown as { p_post: string; p_kind?: string };
  const { error } = await s.supabase.rpc('omelo_react_to_post', args);
  if (error) return fail(error, 'reactToPost');
  refresh(postId);
  return { ok: true, message: kind ? 'Reaction added.' : 'Reaction removed.' };
}

export async function commentOnPost(
  postId: string,
  body: string,
  parentId?: string | null
): Promise<PostResult> {
  const s = await session();
  if (!s) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(postId)) return { ok: false, error: 'That post no longer exists.' };
  const trimmed = body.trim();
  if (trimmed.length === 0) return { ok: false, error: 'Write the comment first.' };
  if (trimmed.length > COMMENT_MAX)
    return { ok: false, error: `Keep a comment under ${COMMENT_MAX} characters.` };
  const parent = (parentId ?? '').trim() || null;
  if (parent && !UUID_RE.test(parent)) return { ok: false, error: 'That comment no longer exists.' };

  const { error } = await s.supabase.rpc('omelo_comment_on_post', {
    p_post: postId,
    p_body: trimmed,
    ...(parent ? { p_parent: parent } : {}),
  });
  if (error) return fail(error, 'commentOnPost');
  refresh(postId);
  return { ok: true, message: parent ? 'Reply posted.' : 'Comment posted. It shows with your own name.' };
}

export async function deletePostComment(postId: string, commentId: string): Promise<PostResult> {
  const s = await session();
  if (!s) return { ok: false, error: SIGNED_OUT };
  if (!UUID_RE.test(commentId)) return { ok: false, error: 'That comment no longer exists.' };
  const { error } = await s.supabase.rpc('omelo_delete_comment', { p_comment: commentId });
  if (error) return fail(error, 'deletePostComment');
  refresh(UUID_RE.test(postId) ? postId : undefined);
  return { ok: true, message: 'Comment removed.' };
}
