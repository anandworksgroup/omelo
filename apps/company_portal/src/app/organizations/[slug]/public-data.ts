import { createClient, getMemberships } from '@/lib/supabase/server';

/**
 * The public organization page's data contract.
 *
 * One organization, two visibility contexts — not two products. Everything
 * here comes from the same records the workspace uses; what makes it public is
 * this file, which names every field a stranger may see and fetches nothing
 * else.
 *
 * The rule is an allowlist, never `select('*')`. Migration 83 took the
 * confidential columns off the client roles so a mistake here is refused by
 * the database rather than published, but the first line of defence is asking
 * only for what belongs on a public page.
 *
 * Deliberately absent, and it should stay that way: applications and the
 * candidate pipeline, interviews and their feedback, messages, offers and any
 * compensation agreed with a person, client relationships and their billing,
 * internal notes, and the organization's tax or registration identifiers.
 */

/** Every organization column a stranger may read. Add to this on purpose. */
const PUBLIC_ORGANIZATION_COLUMNS = [
  'id',
  'slug',
  'display_name',
  'about',
  'logo_url',
  'cover_url',
  'website',
  'size_band',
  'founded_year',
  'country_code',
  'is_verified',
  'organization_type',
  'response_rate_pct',
  'median_response_hours',
  'total_hires',
].join(', ');

/** Every job column a stranger may read. */
const PUBLIC_JOB_COLUMNS = [
  'id',
  'title',
  'workplace_type',
  'work_type',
  'pay_min',
  'pay_max',
  'pay_period',
  'pay_currency',
  'published_at',
  'location_text',
].join(', ');

export type PublicOrganization = {
  id: string;
  slug: string;
  name: string;
  about: string | null;
  logoUrl: string | null;
  coverUrl: string | null;
  website: string | null;
  sizeBand: string | null;
  foundedYear: number | null;
  countryCode: string | null;
  isVerified: boolean;
  organizationType: string | null;
  responseRatePct: number | null;
  medianResponseHours: number | null;
  totalHires: number | null;
};

export type PublicJob = {
  id: string;
  title: string;
  workplaceType: string | null;
  workType: string | null;
  payMin: number | null;
  payMax: number | null;
  payPeriod: string | null;
  payCurrency: string | null;
  publishedAt: string | null;
  locationText: string | null;
};

export type PublicLocation = { id: string; name: string | null; address: string | null; isHq: boolean };

export type PublicPost = {
  id: string;
  body: string | null;
  createdAt: string | null;
  reactions: number;
  comments: number;
};

export type PublicOrganizationPage = {
  organization: PublicOrganization;
  jobs: PublicJob[];
  locations: PublicLocation[];
  posts: PublicPost[];
  followers: number;
  /** True when the signed-in viewer belongs to this organization. */
  viewerIsMember: boolean;
};

function num(v: unknown): number | null {
  return typeof v === 'number' ? v : null;
}
function str(v: unknown): string | null {
  return typeof v === 'string' ? v : null;
}

/** Reads the posts out of omelo_organization_feed without trusting its shape. */
function parsePosts(feed: unknown): { posts: PublicPost[]; followers: number } {
  if (!feed || typeof feed !== 'object') return { posts: [], followers: 0 };
  const f = feed as Record<string, unknown>;
  const rows = Array.isArray(f.posts) ? f.posts : [];
  const posts: PublicPost[] = [];
  for (const r of rows) {
    if (!r || typeof r !== 'object') continue;
    const o = r as Record<string, unknown>;
    const id = str(o.id);
    if (!id) continue;
    posts.push({
      id,
      body: str(o.body),
      createdAt: str(o.created_at),
      reactions: num(o.reaction_count) ?? 0,
      comments: num(o.comment_count) ?? 0,
    });
  }
  return { posts, followers: num(f.followers) ?? 0 };
}

export async function loadPublicOrganization(slug: string): Promise<PublicOrganizationPage | null> {
  const supabase = await createClient();

  const { data: row } = await supabase
    .from('companies')
    .select(PUBLIC_ORGANIZATION_COLUMNS)
    .eq('slug', slug)
    .is('deleted_at', null)
    .maybeSingle();
  if (!row) return null;

  const c = row as unknown as Record<string, unknown>;
  const id = String(c.id);

  const [jobsRes, locationsRes, feedRes, memberships] = await Promise.all([
    supabase
      .from('jobs')
      .select(PUBLIC_JOB_COLUMNS)
      .eq('company_id', id)
      .eq('status', 'published')
      .order('published_at', { ascending: false })
      .limit(20),
    supabase
      .from('company_locations')
      .select('id, name, address, is_hq')
      .eq('company_id', id)
      .order('is_hq', { ascending: false })
      .limit(10),
    supabase.rpc('omelo_organization_feed', { p_company: id, p_limit: 5, p_before: undefined }),
    // Membership decides whether the page also offers the controls. It never
    // changes what the page fetches: a member sees the same public record.
    // omelo_is_company_member is deliberately off the public API (invariant 2),
    // so this asks the viewer's own memberships instead.
    getMemberships(),
  ]);

  const { posts, followers } = parsePosts(feedRes.data);

  return {
    organization: {
      id,
      slug: String(c.slug),
      name: String(c.display_name ?? ''),
      about: str(c.about),
      logoUrl: str(c.logo_url),
      coverUrl: str(c.cover_url),
      website: str(c.website),
      sizeBand: str(c.size_band),
      foundedYear: num(c.founded_year),
      countryCode: str(c.country_code),
      isVerified: c.is_verified === true,
      organizationType: str(c.organization_type),
      responseRatePct: num(c.response_rate_pct),
      medianResponseHours: num(c.median_response_hours),
      totalHires: num(c.total_hires),
    },
    jobs: ((jobsRes.data ?? []) as unknown as Record<string, unknown>[]).map((j) => ({
      id: String(j.id),
      title: String(j.title ?? ''),
      workplaceType: str(j.workplace_type),
      workType: str(j.work_type),
      payMin: num(j.pay_min),
      payMax: num(j.pay_max),
      payPeriod: str(j.pay_period),
      payCurrency: str(j.pay_currency),
      publishedAt: str(j.published_at),
      locationText: str(j.location_text),
    })),
    locations: ((locationsRes.data ?? []) as unknown as Record<string, unknown>[]).map((l) => ({
      id: String(l.id),
      name: str(l.name),
      address: str(l.address),
      isHq: l.is_hq === true,
    })),
    posts,
    followers,
    viewerIsMember: memberships.some((m) => m.companyId === id),
  };
}
