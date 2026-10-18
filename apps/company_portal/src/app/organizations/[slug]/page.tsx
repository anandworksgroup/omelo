import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { loadPublicOrganization, type PublicJob } from './public-data';

/**
 * The public organization page.
 *
 * One organization, two visibility contexts. A stranger sees the published
 * profile, its open jobs and its posts. A member opening the same URL sees the
 * same page with the controls they are allowed to use — not a second copy of
 * the organization.
 *
 * Everything on it comes from loadPublicOrganization, which names every field
 * it fetches. Nothing private is read here, so nothing private can leak here.
 */

const SIZE_LABEL: Record<string, string> = {
  '1-10': '1–10 people',
  '11-50': '11–50 people',
  '51-200': '51–200 people',
  '201-500': '201–500 people',
  '501-1000': '501–1,000 people',
  '1001-5000': '1,001–5,000 people',
  '5001-10000': '5,001–10,000 people',
  '10000+': '10,000+ people',
};

const WORKPLACE_LABEL: Record<string, string> = {
  onsite: 'On site',
  hybrid: 'Hybrid',
  remote: 'Remote',
  field_based: 'Field based',
  client_site: 'Client site',
  multiple_sites: 'Multiple sites',
};

function payLabel(j: PublicJob): string | null {
  if (j.payMin == null && j.payMax == null) return null;
  const cur = j.payCurrency ?? '';
  const fmt = (n: number) => n.toLocaleString();
  const amount =
    j.payMin != null && j.payMax != null && j.payMin !== j.payMax
      ? `${fmt(j.payMin)}–${fmt(j.payMax)}`
      : fmt((j.payMin ?? j.payMax)!);
  return `${cur} ${amount}${j.payPeriod ? ` / ${j.payPeriod}` : ''}`.trim();
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const data = await loadPublicOrganization(slug);
  if (!data) return { title: 'Organization not found · Omelo' };
  const { organization: o } = data;
  return {
    title: `${o.name} · Omelo`,
    description: o.about?.slice(0, 160) ?? `${o.name} on Omelo.`,
    openGraph: {
      title: o.name,
      description: o.about?.slice(0, 160) ?? undefined,
      images: o.coverUrl ? [o.coverUrl] : undefined,
    },
  };
}

export default async function PublicOrganizationPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const data = await loadPublicOrganization(slug);
  if (!data) notFound();

  const { organization: o, jobs, locations, posts, followers, viewerIsMember } = data;
  const initial = (o.name || '?').trim().charAt(0).toUpperCase();

  return (
    <main className="min-h-screen">
      {/* Cover */}
      <div
        className="w-full"
        style={{
          height: 180,
          background: o.coverUrl
            ? `center/cover no-repeat url(${JSON.stringify(o.coverUrl)})`
            : 'linear-gradient(135deg, var(--color-brand-700), var(--color-brand-400))',
        }}
      />

      <div className="max-w-5xl mx-auto px-4 sm:px-6">
        {/* Identity */}
        {/* Stacked on a phone: side by side, the wrapped name climbs over the
            cover. From sm up there is room for the avatar and the name on one
            line. */}
        <header
          className="flex flex-col sm:flex-row sm:items-end gap-3 sm:gap-4"
          style={{ marginTop: -36 }}
        >
          <span
            className="avatar avatar-lg"
            aria-hidden
            style={{
              width: 88,
              height: 88,
              fontSize: '2rem',
              border: '4px solid var(--bg)',
              background: o.logoUrl ? `center/cover no-repeat url(${JSON.stringify(o.logoUrl)})` : undefined,
            }}
          >
            {o.logoUrl ? '' : initial}
          </span>
          <div className="flex-1 min-w-0 pb-1">
            <h1 className="flex items-center gap-2 flex-wrap break-words">
              {o.name}
              {o.isVerified && (
                <span className="pill pill-success" title="Omelo has verified this organization">
                  <span className="dot" /> Verified
                </span>
              )}
            </h1>
            <p className="muted text-sm mt-1">
              {[
                o.sizeBand ? SIZE_LABEL[o.sizeBand] ?? o.sizeBand : null,
                o.foundedYear ? `Founded ${o.foundedYear}` : null,
                followers > 0 ? `${followers.toLocaleString()} follower${followers === 1 ? '' : 's'}` : null,
              ]
                .filter(Boolean)
                .join(' · ')}
            </p>
          </div>

          <div className="flex gap-2 pb-1 flex-wrap">
            {o.website && (
              <a
                href={o.website}
                className="btn btn-ghost btn-sm"
                target="_blank"
                rel="noopener noreferrer nofollow"
              >
                Website
              </a>
            )}
            {/* The same page, with what this viewer may do on it. */}
            {viewerIsMember ? (
              <>
                <Link href="/dashboard/company" className="btn btn-ghost btn-sm">
                  Edit page
                </Link>
                <Link href="/dashboard/jobs" className="btn btn-primary btn-sm">
                  Manage jobs
                </Link>
              </>
            ) : (
              <Link href={`/sign-in?next=/organizations/${o.slug}`} className="btn btn-primary btn-sm">
                Follow
              </Link>
            )}
          </div>
        </header>

        <div className="grid lg:grid-cols-[1fr_18rem] gap-8 mt-8 pb-16">
          <div className="min-w-0 space-y-8">
            {o.about && (
              <section>
                <h2>About</h2>
                <p className="mt-2 leading-relaxed whitespace-pre-line">{o.about}</p>
              </section>
            )}

            <section>
              <div className="flex items-center justify-between mb-3">
                <h2>Open jobs</h2>
                {jobs.length > 0 && <span className="pill">{jobs.length}</span>}
              </div>
              {jobs.length === 0 ? (
                <div className="empty">
                  <p className="empty-title">No open jobs right now</p>
                  <p className="empty-body">
                    When {o.name} publishes a job it appears here, and workers nearby see it in
                    their feed.
                  </p>
                </div>
              ) : (
                <ul className="card divide-y hairline overflow-hidden">
                  {jobs.map((j) => {
                    const pay = payLabel(j);
                    return (
                      <li key={j.id}>
                        <div className="p-4">
                          <p className="font-semibold">{j.title}</p>
                          <p className="text-xs muted mt-1 flex items-center gap-2 flex-wrap">
                            {j.workplaceType && (
                              <span className="pill">
                                {WORKPLACE_LABEL[j.workplaceType] ?? j.workplaceType}
                              </span>
                            )}
                            {j.locationText && <span>{j.locationText}</span>}
                            {pay && <span className="tnum">{pay}</span>}
                          </p>
                        </div>
                      </li>
                    );
                  })}
                </ul>
              )}
            </section>

            {posts.length > 0 && (
              <section>
                <h2 className="mb-3">Updates</h2>
                <ul className="space-y-3">
                  {posts.map((p) => (
                    <li key={p.id} className="card p-4">
                      {p.body && <p className="leading-relaxed whitespace-pre-line">{p.body}</p>}
                      <p className="hint !mt-2">
                        {p.reactions} reaction{p.reactions === 1 ? '' : 's'} · {p.comments} comment
                        {p.comments === 1 ? '' : 's'}
                      </p>
                    </li>
                  ))}
                </ul>
              </section>
            )}
          </div>

          <aside className="space-y-6">
            {(o.responseRatePct != null || o.totalHires != null) && (
              <section className="panel p-4">
                <p className="section-title mb-2">How they hire</p>
                <dl className="space-y-2 text-sm">
                  {o.responseRatePct != null && (
                    <div className="flex justify-between gap-3">
                      <dt className="muted">Replies to applicants</dt>
                      <dd className="font-semibold tnum">{Math.round(o.responseRatePct)}%</dd>
                    </div>
                  )}
                  {o.medianResponseHours != null && (
                    <div className="flex justify-between gap-3">
                      <dt className="muted">Usually within</dt>
                      <dd className="font-semibold tnum">{o.medianResponseHours}h</dd>
                    </div>
                  )}
                  {o.totalHires != null && o.totalHires > 0 && (
                    <div className="flex justify-between gap-3">
                      <dt className="muted">People hired</dt>
                      <dd className="font-semibold tnum">{o.totalHires}</dd>
                    </div>
                  )}
                </dl>
                <p className="hint">Computed by Omelo from what actually happens, not set here.</p>
              </section>
            )}

            {locations.length > 0 && (
              <section className="panel p-4">
                <p className="section-title mb-2">Where they are</p>
                <ul className="space-y-2 text-sm">
                  {locations.map((l) => (
                    <li key={l.id}>
                      <span className="font-semibold">{l.name ?? 'Office'}</span>
                      {/* Most head offices are already called one; don't say it twice. */}
                      {l.isHq && !/head office/i.test(l.name ?? '') && (
                        <span className="pill ml-2">Head office</span>
                      )}
                      {l.address && <span className="muted block">{l.address}</span>}
                    </li>
                  ))}
                </ul>
              </section>
            )}
          </aside>
        </div>
      </div>
    </main>
  );
}
