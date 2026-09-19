/**
 * Eligibility, as the hiring side sees it. No hooks, so server and client
 * components share these. "Potentially eligible" is shown as something to
 * check — never as a rejection.
 */
import {
  AUTH_VISIBILITY_LABEL,
  ELIGIBILITY_COLOR,
  ELIGIBILITY_LABEL,
  SPONSORSHIP_LABEL,
  countryName,
  eligibilityText,
  type CandidateEligibility,
  type CardEligibility,
  type Sponsorship,
} from '@/lib/global';

const MARK: Record<CardEligibility['status'], string> = {
  eligible: '✓',
  potentially_eligible: '?',
  not_eligible: '–',
};

/** One-line badge for search cards. */
export function EligibilityBadge({ e }: { e: CardEligibility }) {
  const color = ELIGIBILITY_COLOR[e.status];
  const text = eligibilityText(e);
  return (
    <span
      className="inline-flex items-start gap-1.5 rounded-lg border px-2 py-1 text-xs font-medium max-w-full"
      style={{ color, borderColor: color }}
      title={text}
    >
      <span aria-hidden className="font-bold">
        {MARK[e.status]}
      </span>
      <span className="break-words min-w-0">{text}</span>
    </span>
  );
}

const dateText = (d: string | null) =>
  d
    ? new Date(d.slice(0, 10) + 'T00:00:00Z').toLocaleDateString('en-GB', {
        day: 'numeric',
        month: 'short',
        year: 'numeric',
        timeZone: 'UTC',
      })
    : null;

/** Full panel for an applicant / candidate page. */
export function EligibilityPanel({
  eligibility: e,
  error,
  jobTitle,
}: {
  eligibility: CandidateEligibility | null;
  error?: string | null;
  jobTitle?: string | null;
}) {
  return (
    <section className="card p-5 space-y-3" aria-label="Eligibility">
      <div className="flex items-center gap-3 flex-wrap">
        <h2 className="font-bold flex-1 min-w-0">Eligibility</h2>
        {jobTitle && <span className="text-xs muted">for {jobTitle}</span>}
      </div>
      {error ? (
        <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
          Could not check eligibility: <span className="muted">{error}</span>
        </p>
      ) : !e ? (
        <p className="text-sm muted">No eligibility result for this job.</p>
      ) : (
        <>
          <p className="font-semibold" style={{ color: ELIGIBILITY_COLOR[e.status] }}>
            {MARK[e.status]} {ELIGIBILITY_LABEL[e.status]}
            {e.country ? <span className="muted font-normal"> · to work in {countryName(e.country)}</span> : null}
          </p>
          {e.status === 'potentially_eligible' && (
            <p className="text-sm muted">
              Something is missing or not on the profile yet. This is not a rejection — ask the candidate about it.
            </p>
          )}
          {e.missing.length > 0 && (
            <div>
              <p className="label">{e.status === 'not_eligible' ? 'Blocking' : 'Missing or to confirm'}</p>
              <ul className="space-y-1">
                {e.missing.map((m, i) => (
                  <li key={`${m.kind}-${i}`} className="flex items-start gap-2 text-sm">
                    <span aria-hidden className="font-bold shrink-0 w-4 text-center" style={{ color: 'var(--color-warn)' }}>
                      !
                    </span>
                    <span className="break-words min-w-0">{m.text}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}
          {e.notes.length > 0 && (
            <div>
              <p className="label">Notes</p>
              <ul className="space-y-1">
                {e.notes.map((n, i) => (
                  <li key={i} className="flex items-start gap-2 text-sm">
                    <span aria-hidden className="shrink-0 w-4 text-center muted">
                      •
                    </span>
                    <span className="break-words min-w-0">{n}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}
          {e.sponsorship && (
            <p className="text-xs muted">
              This job: {SPONSORSHIP_LABEL[e.sponsorship as Sponsorship] ?? e.sponsorship}
            </p>
          )}
          <div className="border-t hairline pt-3">
            <p className="label">Work authorization</p>
            {e.authorizations === null ? (
              <p className="text-sm muted">
                {e.authorizationVisibility === 'private'
                  ? AUTH_VISIBILITY_LABEL.private
                  : 'The candidate shares eligibility only'}
                .
              </p>
            ) : e.authorizations.length === 0 ? (
              <p className="text-sm muted">No authorization recorded for this country.</p>
            ) : (
              <ul className="space-y-2">
                {e.authorizations.map((a, i) => (
                  <li key={i} className="text-sm">
                    <span className="font-semibold">{countryName(a.country) ?? 'Country'}</span>
                    {a.status ? ` · ${a.status.replace(/_/g, ' ')}` : ''}
                    {a.isVerified ? (
                      <span className="pill ml-2" style={{ color: 'var(--color-verified)' }}>
                        ✓ Verified
                      </span>
                    ) : (
                      <span className="pill ml-2">Self-declared</span>
                    )}
                    <span className="block text-xs muted">
                      {[
                        a.validFrom ? `From ${dateText(a.validFrom)}` : null,
                        a.expiresOn ? `until ${dateText(a.expiresOn)}` : null,
                        a.requiresSponsorship === true
                          ? 'needs sponsorship'
                          : a.requiresSponsorship === false
                            ? 'no sponsorship needed'
                            : null,
                      ]
                        .filter(Boolean)
                        .join(' · ')}
                    </span>
                    {a.restrictions && <span className="block text-xs break-words">Restrictions: {a.restrictions}</span>}
                  </li>
                ))}
              </ul>
            )}
          </div>
          <p className="hint">
            {e.disclaimer ?? 'Based on what is on the profile and the job. Not legal advice; the official sources decide.'}
          </p>
        </>
      )}
    </section>
  );
}
