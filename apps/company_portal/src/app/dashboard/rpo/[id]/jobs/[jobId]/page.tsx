import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { STATE_LABEL, timeAgo } from '@/lib/format';
import { NO_ACCESS, enterpriseError, parseRpoWork, rpoPermissionLabel } from '@/lib/enterprise';
import { ErrorNote, Notice, PageHeader, Pill } from '../../../../agency/ui';
import { PermissionChips } from '../../../rpo-forms';

export const metadata: Metadata = { title: 'Client job · Omelo' };

/**
 * One client job as an assigned RPO recruiter may see it.
 *
 * The job itself comes from omelo_rpo_my_work, which returns only the jobs the
 * engagement authorizes. The applicants are read straight from `applications`
 * — RLS decides, through the engagement's view_candidates permission. If the
 * engagement does not reach this job, nothing is shown and the page says so.
 */
export default async function RpoJobPage({
  params,
}: {
  params: Promise<{ id: string; jobId: string }>;
}) {
  const { id, jobId } = await params;
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  const { data, error } = await supabase.rpc('omelo_rpo_my_work', { p_engagement: id });
  const job = parseRpoWork(data ?? null).find((w) => w.jobId === jobId);

  const back = (
    <Link href={`/dashboard/rpo/${id}`} className="text-sm underline muted">
      ← Engagement
    </Link>
  );

  if (error)
    return (
      <div className="space-y-4 max-w-3xl">
        {back}
        <ErrorNote label="this job" message={enterpriseError(error).text} />
      </div>
    );

  if (!job)
    return (
      <div className="space-y-4 max-w-3xl">
        {back}
        <Notice title={NO_ACCESS} tone="warn">
          This job is not part of what the engagement covers, or the engagement is not active right now. Ask the client
          organization to widen the scope if you should be working on it.
        </Notice>
      </div>
    );

  const canSeeCandidates = job.permissions.includes('view_candidates');
  const { data: apps, error: appsError } = canSeeCandidates
    ? await supabase
        .from('applications')
        .select('id, state, applied_at, match_score, first_viewed_at')
        .eq('job_id', jobId)
        .order('applied_at', { ascending: false })
        .limit(200)
    : { data: null, error: null };

  // The client's own team reaches the full candidate screen; an RPO recruiter
  // reads what the engagement allows, here.
  const isClientTeam = ctx.companyId === job.clientCompanyId;

  return (
    <div className="space-y-6 max-w-3xl">
      {back}
      <PageHeader
        title={job.title}
        subtitle={
          <>
            {job.client ?? 'Client'} · {job.status}
            {job.department ? ` · ${job.department}` : ''}
            {job.locationText ? ` · ${job.locationText}` : ''}
            {job.openings ? ` · ${job.openings} opening${job.openings === 1 ? '' : 's'}` : ''}
            {job.publishedAt ? ` · live ${timeAgo(job.publishedAt)}` : ''}
          </>
        }
      />

      <div className="card p-4 sm:p-5 space-y-2">
        <p className="font-bold">What you may do on this job</p>
        <PermissionChips permissions={job.permissions} />
        <p className="text-sm muted leading-relaxed">
          These come from the engagement. Anything not listed is refused by the database, not just hidden here.
        </p>
      </div>

      <section className="card p-4 sm:p-5 space-y-3">
        <div className="flex items-start gap-3 flex-wrap">
          <h2 className="font-bold flex-1 min-w-0">Applicants</h2>
          <span className="pill">{job.applicants}</span>
          {job.newApplicants > 0 && <Pill label={`${job.newApplicants} new`} color="var(--color-brand-600)" />}
        </div>

        {!canSeeCandidates ? (
          <p className="text-sm muted">
            This engagement does not include “{rpoPermissionLabel('view_candidates')}”, so the applicants stay with the
            client.
          </p>
        ) : appsError ? (
          <ErrorNote label="the applicants" message={enterpriseError(appsError).text} />
        ) : (apps ?? []).length === 0 ? (
          <p className="text-sm muted">Nobody has applied yet.</p>
        ) : (
          <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
            {(apps ?? []).map((a) => (
              <li key={a.id} className="py-3 flex flex-wrap items-center gap-3">
                <div className="flex-1 min-w-[10rem]">
                  <p className="text-sm font-semibold">
                    Candidate · applied {timeAgo(a.applied_at)}
                    {a.first_viewed_at ? '' : ' · not opened yet'}
                  </p>
                  <p className="text-xs muted">{STATE_LABEL[a.state] ?? a.state}</p>
                </div>
                {a.match_score != null && <span className="pill">{a.match_score}% match</span>}
                {isClientTeam && (
                  <Link href={`/dashboard/candidates/${a.id}`} className="text-sm underline">
                    Review
                  </Link>
                )}
              </li>
            ))}
          </ul>
        )}
        {canSeeCandidates && !isClientTeam && (
          <p className="hint">
            Names and profiles stay with the client organization&apos;s own screens. What you can act on is set by the
            engagement.
          </p>
        )}
      </section>
    </div>
  );
}
