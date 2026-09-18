/**
 * "Recruiter submissions": candidates an agency put forward for this
 * company's jobs, each with the candidate's consent. Read through
 * omelo_client_submissions, which only returns rows for jobs the viewer can
 * access. Card rows (no wide table) so it works at 360px.
 */
import Link from 'next/link';
import { createClient } from '@/lib/supabase/server';
import { STATE_LABEL, timeAgo } from '@/lib/format';
import { TONE_COLOR, stateTone } from '@/lib/hiring';
import { CLIENT_CONSENT, parseClientSubmissions } from '@/lib/agency';
import { UUID_RE } from '@/lib/talent';
import { AgencyName, TonePill } from '../agencies/agency-badge';

export function ViewTabs({
  view,
  allHref,
  agencyHref,
  agencyCount,
}: {
  view: 'all' | 'agency';
  allHref: string;
  agencyHref: string;
  agencyCount: number;
}) {
  const tab = (href: string, label: React.ReactNode, on: boolean) => (
    <Link
      href={href}
      aria-current={on ? 'page' : undefined}
      className="px-3 py-1.5 rounded-md text-sm font-semibold whitespace-nowrap"
      style={
        on
          ? { background: 'var(--bg)', color: 'var(--color-brand-600)', boxShadow: '0 0 0 1px var(--line)' }
          : { color: 'var(--muted)' }
      }
    >
      {label}
    </Link>
  );
  return (
    <nav aria-label="Candidate source" className="inline-flex flex-wrap rounded-lg border hairline p-0.5 surface max-w-full">
      {tab(allHref, 'All applicants', view === 'all')}
      {tab(
        agencyHref,
        <>
          Recruiter submissions {agencyCount > 0 && <span className="opacity-80">{agencyCount}</span>}
        </>,
        view === 'agency'
      )}
    </nav>
  );
}

const consentTone = (s: string) => CLIENT_CONSENT[s] ?? { label: s, color: 'var(--muted)' };

export async function SubmissionList({ jobId, jobTitle }: { jobId: string | null; jobTitle: string | null }) {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(
    'omelo_client_submissions',
    jobId && UUID_RE.test(jobId) ? { p_job_id: jobId } : {}
  );

  if (error) {
    return (
      <div className="card p-5" style={{ borderColor: 'var(--color-danger)' }}>
        <p className="font-semibold mb-1" style={{ color: 'var(--color-danger)' }}>
          Could not load recruiter submissions
        </p>
        <p className="text-sm muted break-words">{error.message}</p>
      </div>
    );
  }

  const rows = parseClientSubmissions(data);

  if (rows.length === 0) {
    return (
      <div className="card p-8 sm:p-10 text-center">
        <p className="font-semibold mb-1">
          {jobTitle ? `No recruiter submissions for ${jobTitle}` : 'No recruiter submissions yet'}
        </p>
        <p className="text-sm muted mb-5 max-w-md mx-auto leading-relaxed">
          When an agency you work with connects one of its job orders to your job, the candidates it submits
          appear here and in the job&apos;s pipeline, each with their consent.
        </p>
        <Link href="/dashboard/agencies" className="btn btn-primary w-full sm:w-auto">
          Your agencies
        </Link>
      </div>
    );
  }

  return (
    <ul className="card divide-y" style={{ borderColor: 'var(--line)' }}>
      {rows.map((r) => {
        const body = (
          <div className="p-4 flex items-start gap-3 sm:gap-4">
            <div className="flex-1 min-w-0 space-y-1">
              <p className="font-semibold text-sm break-words">{r.candidateName}</p>
              <p className="text-xs muted break-words">
                {r.appliedAs ? (
                  <>
                    as <span className="font-medium" style={{ color: 'var(--fg)' }}>{r.appliedAs}</span>
                    {r.profession && r.profession !== r.appliedAs ? ` · ${r.profession}` : ''}
                  </>
                ) : (
                  (r.profession ?? '—')
                )}
                {r.jobTitle ? ` · for ${r.jobTitle}` : ''}
              </p>
              <p className="text-xs break-words">
                <span className="muted">By </span>
                {r.recruiter ? <span className="font-medium">{r.recruiter}</span> : <span className="muted">a recruiter</span>}
                <span className="muted"> at </span>
                <AgencyName agency={r.agency} strong={false} />
              </p>
              <div className="flex items-center gap-1.5 flex-wrap pt-0.5">
                <TonePill tone={consentTone(r.consentStatus)} />
                {r.submittedAt && <span className="text-xs muted">Submitted {timeAgo(r.submittedAt)}</span>}
              </div>
            </div>
            <div className="flex flex-col items-end gap-1.5 shrink-0">
              <span className="pill" title="Match score" style={r.matchScore != null ? { color: 'var(--fg)' } : undefined}>
                {r.matchScore != null ? `${r.matchScore}%` : '—'}
              </span>
              {r.stage && (
                <span className="pill" style={{ color: TONE_COLOR[stateTone(r.stage)] }}>
                  {STATE_LABEL[r.stage] ?? r.stage}
                </span>
              )}
            </div>
          </div>
        );
        return (
          <li key={r.submissionId}>
            {r.applicationId ? (
              <Link href={`/dashboard/candidates/${r.applicationId}`} className="block hover:bg-[var(--surface)]">
                {body}
              </Link>
            ) : (
              body
            )}
          </li>
        );
      })}
    </ul>
  );
}
