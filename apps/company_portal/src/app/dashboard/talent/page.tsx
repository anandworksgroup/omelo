import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { TALENT_ROLES, UUID_RE } from '@/lib/talent';
import TalentSearch, { NotInPlanNotice, NotVerifiedNotice } from './talent-search';
import { ErrorNote, Notice, TalentHeader } from './ui';

export const metadata: Metadata = { title: 'Find candidates · Omelo' };

export default async function TalentPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const wanted = typeof sp.job === 'string' && UUID_RE.test(sp.job) ? sp.job : null;
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  if (!TALENT_ROLES.includes(ctx.role)) {
    return (
      <div className="space-y-6">
        <TalentHeader active="search" />
        <Notice title="Talent search is for owners, admins and recruiters">
          Ask an owner or admin of {ctx.companyName} to change your role if you need to search for candidates.
          You can still open your company&apos;s talent pools.
        </Notice>
      </div>
    );
  }

  const [jobsRes, poolsRes, entRes, countriesRes, languagesRes] = await Promise.all([
    supabase
      .from('jobs')
      .select('id, title, location_text, published_at')
      .eq('company_id', ctx.companyId)
      .eq('status', 'published')
      .order('published_at', { ascending: false, nullsFirst: false }),
    supabase.from('talent_pools').select('id, name').eq('company_id', ctx.companyId).order('name'),
    // Readable to owners/admins/finance only; for others it is simply null.
    supabase
      .from('company_entitlements')
      .select('talent_search_enabled')
      .eq('company_id', ctx.companyId)
      .maybeSingle(),
    supabase.from('country_policies').select('country_code, name').order('name'),
    supabase.from('languages').select('code, name').order('name'),
  ]);

  const jobs = (jobsRes.data ?? []).map((j) => ({ id: j.id, title: j.title, location: j.location_text }));
  const canReadPlan = ['owner', 'admin'].includes(ctx.role) && !entRes.error;
  // For owners/admins a missing row means the same as disabled (the DB treats it so).
  const planKnownOff = canReadPlan && !entRes.data?.talent_search_enabled;

  let body: React.ReactNode;
  if (!ctx.isVerified) {
    body = <NotVerifiedNotice />;
  } else if (planKnownOff) {
    body = <NotInPlanNotice />;
  } else if (jobsRes.error) {
    body = <ErrorNote label="your jobs" message={jobsRes.error.message} />;
  } else if (jobs.length === 0) {
    body = (
      <Notice
        title="Publish a job to search for candidates"
        action={
          <Link href="/dashboard/jobs" className="btn btn-primary">
            Go to jobs
          </Link>
        }
      >
        Talent search ranks people against one of your published jobs, and invitations are always to a specific
        job.
      </Notice>
    );
  } else {
    const initial = jobs.find((j) => j.id === wanted)?.id ?? jobs[0].id;
    body = (
      <TalentSearch
        key={initial}
        jobs={jobs}
        initialJobId={initial}
        companyName={ctx.companyName}
        pools={poolsRes.data ?? []}
        countries={(countriesRes.data ?? []).map((c) => ({ id: c.country_code.trim(), label: c.name }))}
        languages={(languagesRes.data ?? []).map((l) => ({ id: l.code.trim(), label: l.name }))}
      />
    );
  }

  return (
    <div className="space-y-6">
      <TalentHeader active="search" />
      {wanted && !jobs.some((j) => j.id === wanted) && jobs.length > 0 && (
        <p className="text-sm" style={{ color: 'var(--color-warn)' }}>
          That job is not published, so it cannot be searched for. Showing your most recent published job.
        </p>
      )}
      {body}
    </div>
  );
}
