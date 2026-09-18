import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { agencyCan, consentTone, onlyRoles, parseScopedProfile, submissionTone } from '@/lib/agency';
import { STATE_LABEL, timeAgo } from '@/lib/format';
import { UUID_RE } from '@/lib/talent';
import LocalTime from '../../../local-time';
import { ConsentPill, ErrorNote, PageHeader, PlacementPill, ScopeChips, Section, SubmissionPill, Why, dateText } from '../../ui';
import { BASE, CLOSED_SUBMISSION, WITHDRAWABLE, loadSubmissions, money, offerLabel } from '../lib';
import { PlatformHint } from '../row';
import { RecordOutcome, WithdrawSubmission } from '../submission-actions';
import { SnapshotView } from './snapshot';

export const metadata: Metadata = { title: 'Submission · Omelo' };

export default async function SubmissionPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID_RE.test(id)) notFound();
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  const { data: sub, error } = await supabase
    .from('candidate_submissions')
    .select(
      'id, consent_id, snapshot, status, recruiter_note, client_response, rejection_reason, submitted_at, updated_at, application_id, job_order_id, client_id'
    )
    .eq('id', id)
    .eq('agency_id', ctx.companyId)
    .maybeSingle();
  if (error) {
    return (
      <div className="space-y-4 max-w-4xl">
        <PageHeader title="Submission" back={{ href: `${BASE}/submissions`, label: 'Submissions' }} />
        <ErrorNote label="this submission" message={error.message} />
      </div>
    );
  }
  if (!sub) notFound();

  const [list, eventsRes] = await Promise.all([
    loadSubmissions(supabase, ctx.companyId, sub.job_order_id),
    supabase
      .from('candidate_submission_events')
      .select('id, from_status, to_status, reason, occurred_at')
      .eq('submission_id', id)
      .order('occurred_at', { ascending: true }),
  ]);
  const row = list.rows.find((r) => r.id === id) ?? null;
  const snap = parseScopedProfile(sub.snapshot);
  const events = eventsRes.data ?? [];

  const name = snap?.identity.name ?? row?.candidate.name ?? 'Candidate';
  const label = snap?.identity.label ?? row?.candidate.label ?? null;
  const onOmelo = sub.application_id != null;
  const status = sub.status;
  const closed = CLOSED_SUBMISSION.includes(status);
  const consent = row?.consentStatus ?? null;

  const canSubmit = agencyCan(ctx, 'submit');
  const canOutcome = canSubmit || agencyCan(ctx, 'manage_placements');
  const limited = !agencyCan(ctx, 'view_candidate_details');
  const offer = offerLabel(row?.offerStatus ?? null);

  let withdrawBlock: React.ReactNode;
  if (status === 'withdrawn') withdrawBlock = <Why>This submission was withdrawn.</Why>;
  else if (!WITHDRAWABLE.includes(status))
    withdrawBlock = (
      <Why>
        {closed
          ? 'This submission is closed.'
          : 'You cannot withdraw now: the client is already considering them. Ask the client directly if something changed.'}
      </Why>
    );
  else if (!canSubmit) withdrawBlock = <Why>{onlyRoles('submit', 'withdraw a submission')}</Why>;
  else withdrawBlock = <WithdrawSubmission submissionId={id} candidate={name} />;

  return (
    <div className="space-y-5 max-w-4xl">
      <PageHeader
        back={{ href: `${BASE}/submissions`, label: 'Submissions' }}
        title={
          <>
            {name}
            {label && <span className="font-normal muted text-base sm:text-lg"> as {label}</span>}
          </>
        }
        subtitle={
          <span className="flex flex-wrap gap-x-2 gap-y-1 items-center">
            <span className="break-words">
              {row?.position ?? 'Position'}
              {row?.jobOrder && (
                <>
                  {' · '}
                  <Link href={`${BASE}/job-orders/${sub.job_order_id}`} className="underline">
                    {row.jobOrder}
                  </Link>
                </>
              )}
              {row?.client && ` · ${row.client}`}
            </span>
            <PlatformHint onOmelo={onOmelo} />
          </span>
        }
        action={
          <span className="flex flex-wrap gap-1.5">
            <SubmissionPill status={status} />
            {row?.placement && <PlacementPill status={row.placement.status} />}
          </span>
        }
      />

      {consent === 'revoked' && (
        <div className="card p-4" style={{ borderTop: '3px solid var(--color-danger)' }}>
          <p className="font-semibold">The candidate withdrew their consent</p>
          <p className="text-sm muted mt-1 leading-relaxed">
            You no longer represent {name} for this job order. If the client had not progressed them yet, the
            submission was withdrawn automatically. Do not share their details further or put them forward again
            without asking for new consent.
          </p>
        </div>
      )}

      <div className="grid gap-5 lg:grid-cols-[minmax(0,1fr)_18rem]">
        <div className="space-y-5 min-w-0">
          <Section
            title="What was shared"
            aside={snap ? <ScopeChips scope={snap.scope} /> : undefined}
          >
            <p className="text-xs muted">
              Exactly what the client received, frozen when you submitted. It cannot be changed afterwards.
            </p>
            {snap ? (
              <SnapshotView p={snap} limited={limited} />
            ) : (
              <p className="text-sm muted">The snapshot could not be read.</p>
            )}
          </Section>

          {(sub.recruiter_note || sub.client_response || sub.rejection_reason) && (
            <Section title="Notes">
              {sub.recruiter_note && (
                <div className="text-sm">
                  <p className="font-semibold">Your note to the client</p>
                  <p className="whitespace-pre-line break-words mt-0.5">{sub.recruiter_note}</p>
                </div>
              )}
              {sub.client_response && (
                <div className="text-sm">
                  <p className="font-semibold">{status === 'withdrawn' ? 'Why it was withdrawn' : 'Client’s response'}</p>
                  <p className="whitespace-pre-line break-words mt-0.5">{sub.client_response}</p>
                </div>
              )}
              {sub.rejection_reason && (
                <div className="text-sm">
                  <p className="font-semibold">Why they were not selected</p>
                  <p className="whitespace-pre-line break-words mt-0.5">{sub.rejection_reason}</p>
                </div>
              )}
            </Section>
          )}

          <Section title="Timeline">
            {eventsRes.error ? (
              <ErrorNote label="the timeline" message={eventsRes.error.message} />
            ) : events.length === 0 ? (
              <p className="text-sm muted">Submitted {timeAgo(sub.submitted_at)}. No changes since.</p>
            ) : (
              <ol className="space-y-3 border-l hairline pl-4">
                {events.map((e) => (
                  <li key={e.id} className="text-sm min-w-0">
                    <p className="font-medium break-words">
                      {e.from_status
                        ? `${submissionTone(e.from_status).label} → ${submissionTone(e.to_status).label}`
                        : submissionTone(e.to_status).label}
                    </p>
                    <p className="text-xs muted">
                      <LocalTime iso={e.occurred_at} />
                    </p>
                    {e.reason && <p className="text-sm mt-0.5 break-words whitespace-pre-line">{e.reason}</p>}
                  </li>
                ))}
              </ol>
            )}
          </Section>
        </div>

        <div className="space-y-5 min-w-0">
          <Section title="Where it stands">
            <dl className="text-sm space-y-2">
              <div>
                <dt className="muted text-xs">Submitted</dt>
                <dd>
                  <LocalTime iso={sub.submitted_at} withTime={false} />
                  {row?.recruiter && <span className="muted"> by {row.recruiter}</span>}
                </dd>
              </div>
              {onOmelo && row?.applicationState && (
                <div>
                  <dt className="muted text-xs">Client’s pipeline</dt>
                  <dd>{STATE_LABEL[row.applicationState] ?? row.applicationState}</dd>
                </div>
              )}
              <div>
                <dt className="muted text-xs">Next interview</dt>
                <dd>{row?.nextInterview ? <LocalTime iso={row.nextInterview} /> : <span className="muted">None scheduled</span>}</dd>
              </div>
              {offer && (
                <div>
                  <dt className="muted text-xs">Offer</dt>
                  <dd>{offer}</dd>
                </div>
              )}
              <div>
                <dt className="muted text-xs">Consent</dt>
                <dd className="flex flex-wrap gap-2 items-center">
                  {consent ? <ConsentPill status={consent} /> : <span className="muted">Unknown</span>}
                  <Link href={`${BASE}/candidates/${sub.consent_id}`} className="text-xs underline muted">
                    View consent
                  </Link>
                </dd>
                {consent && consent !== 'revoked' && (
                  <p className="text-xs muted mt-1">{consentTone(consent).label}. The candidate can withdraw it at any time.</p>
                )}
              </div>
            </dl>
          </Section>

          {row?.placement && (
            <Section title="Placement">
              <div className="text-sm space-y-1">
                <PlacementPill status={row.placement.status} />
                <p>Starts {dateText(row.placement.startDate)}</p>
                <p className="muted">Fee: {money(row.placement.feeAmount, row.placement.feeCurrency)}</p>
                <Link href={`${BASE}/placements#p-${row.placement.id}`} className="underline text-sm">
                  Open placement
                </Link>
              </div>
            </Section>
          )}

          <Section title="Actions">
            <div className="space-y-2">{withdrawBlock}</div>
          </Section>
        </div>
      </div>

      <Section title="Client outcome">
        {onOmelo ? (
          <p className="text-sm muted">
            This client is on Omelo: the status follows their hiring pipeline automatically.
          </p>
        ) : closed ? (
          <Why>This submission is closed ({submissionTone(status).label.toLowerCase()}), so its outcome cannot change.</Why>
        ) : !canOutcome ? (
          <Why>{onlyRoles('manage_placements', 'record a client’s decision')}</Why>
        ) : (
          <>
            <p className="text-sm muted">
              This client is not on Omelo, so you record what they decided. The candidate can see the status in their app.
            </p>
            <RecordOutcome submissionId={id} current={status} />
          </>
        )}
      </Section>
    </div>
  );
}
