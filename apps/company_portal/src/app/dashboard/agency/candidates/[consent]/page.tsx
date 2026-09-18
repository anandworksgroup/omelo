import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { agencyCan, daysLeft, parseConsents, parseScopedProfile } from '@/lib/agency';
import { timeAgo } from '@/lib/format';
import { requestNow } from '@/lib/hiring';
import { UUID_RE } from '@/lib/talent';
import { SubmitCandidate, WithdrawRequest } from '../../consent-ui';
import ScopedProfileView from '../../scoped-profile';
import { ConsentPill, ErrorNote, Notice, PageHeader, ScopeChips, Section, SubmissionPill } from '../../ui';
import { whyCannotSubmit } from '../consent-row';

export const metadata: Metadata = { title: 'Consented profile · Omelo' };

export default async function ConsentedCandidatePage({ params }: { params: Promise<{ consent: string }> }) {
  const { consent } = await params;
  if (!UUID_RE.test(consent)) notFound();
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const back = { href: '/dashboard/agency/candidates', label: 'Candidates' };

  // The consent row (status, scope, order) comes from the agency read model.
  const { data: rawConsents, error: listError } = await supabase.rpc('omelo_agency_candidates', { p_agency: ctx.companyId });
  if (listError)
    return (
      <div className="space-y-4">
        <PageHeader title="Candidate" back={back} />
        <ErrorNote label="this candidate" message={listError.message} />
      </div>
    );
  const row = parseConsents(rawConsents ?? null).find((c) => c.consentId === consent);
  if (!row) notFound();

  const nowMs = requestNow();
  const inForce =
    row.status === 'active' || (row.status === 'accepted' && (!row.expiresAt || new Date(row.expiresAt).getTime() > nowMs));

  const [profileRes, orderRes, mineRes] = await Promise.all([
    inForce ? supabase.rpc('omelo_consent_candidate', { p_consent: consent }) : Promise.resolve({ data: null, error: null }),
    supabase.from('job_orders').select('id, status, client_job_id').eq('id', row.jobOrderId).maybeSingle(),
    user
      ? supabase.from('job_order_recruiters').select('person_id').eq('job_order_id', row.jobOrderId).eq('person_id', user.id)
      : Promise.resolve({ data: [] as { person_id: string }[] }),
  ]);
  const profile = parseScopedProfile(profileRes.data ?? null);
  const order = orderRes.data
    ? { status: orderRes.data.status, clientJobId: orderRes.data.client_job_id, assignedToMe: (mineRes.data ?? []).length > 0 }
    : undefined;
  const blocker = row.submission
    ? null
    : whyCannotSubmit(row, {
        canSubmit: agencyCan(ctx, 'submit'),
        isAdmin: agencyCan(ctx, 'manage_agency'),
        order,
        nowMs,
      });
  const left = inForce ? daysLeft(row.expiresAt, nowMs) : null;
  const limited = !agencyCan(ctx, 'view_candidate_details');

  return (
    <div className="space-y-6 max-w-4xl">
      <PageHeader
        back={back}
        title={profile?.identity.name ?? row.name}
        subtitle={
          <span className="inline-flex flex-wrap gap-2 items-center">
            <span>
              For{' '}
              <Link href={`/dashboard/agency/job-orders/${row.jobOrderId}`} className="underline">
                {row.position}
              </Link>{' '}
              ({row.jobOrder}) at {row.client}
            </span>
            <ConsentPill status={row.status} />
          </span>
        }
      />

      <Section title="Consent">
        <dl className="text-sm grid grid-cols-[auto_1fr] gap-x-3 gap-y-1.5">
          <dt className="muted">Asked</dt>
          <dd>
            {timeAgo(row.requestedAt)}
            {row.recruiter ? ` by ${row.recruiter}` : ''}
          </dd>
          {row.respondedAt && (
            <>
              <dt className="muted">Answered</dt>
              <dd>{timeAgo(row.respondedAt)}</dd>
            </>
          )}
          {left != null && (
            <>
              <dt className="muted">Ends</dt>
              <dd>
                in {left} day{left === 1 ? '' : 's'}
              </dd>
            </>
          )}
          <dt className="muted">Shared</dt>
          <dd>
            <ScopeChips scope={row.scope} />
          </dd>
        </dl>
        {row.declineReason && <p className="text-sm">Their reason: “{row.declineReason}”</p>}
        <div className="flex flex-wrap gap-2 items-start border-t hairline pt-3">
          {row.submission ? (
            <>
              <Link href={`/dashboard/agency/submissions/${row.submission.id}`} className="btn btn-ghost !h-9 !px-3 text-sm">
                View submission
              </Link>
              <SubmissionPill status={row.submission.status} />
            </>
          ) : (
            <SubmitCandidate
              consentId={row.consentId}
              candidateName={row.name}
              client={row.client ?? 'the client'}
              clientOnOmelo={!!order?.clientJobId}
              scope={row.scope}
              blocker={blocker}
            />
          )}
          {row.status === 'requested' && agencyCan(ctx, 'request_consent') && <WithdrawRequest consentId={row.consentId} />}
        </div>
      </Section>

      {!inForce ? (
        <Notice title="The profile is not available">
          {row.status === 'requested'
            ? 'The candidate has not answered yet. You will see what they agree to share once they accept.'
            : 'Consent is not in force, so the profile is closed to your agency. The candidate stays in control of their information.'}
        </Notice>
      ) : profileRes.error ? (
        <ErrorNote label="the consented profile" message={profileRes.error.message} />
      ) : !profile ? (
        <Notice title="The profile is not available">The candidate&apos;s profile could not be read.</Notice>
      ) : (
        <>
          {limited && (
            <p className="text-sm muted">
              Your role sees the professional identity and skills only. Owners, admins and recruiters see everything the
              candidate shared.
            </p>
          )}
          <ScopedProfileView p={profile} />
          <p className="hint">
            This is exactly what the candidate agreed to share with {ctx.companyName} and {row.client ?? 'the client'}{' '}
            for this job order. It is not yours to keep or reuse for other roles.
          </p>
        </>
      )}
    </div>
  );
}
