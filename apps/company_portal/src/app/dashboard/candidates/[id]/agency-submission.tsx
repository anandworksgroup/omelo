/**
 * Pieces of the candidate page for applications an agency submitted.
 *
 * The client sees exactly what the candidate consented to share with the
 * agency. When the consented scope is narrower than the full profile, the
 * database hides the live profile rows from the client, and these components
 * render the submission snapshot instead. Anything outside the scope reads
 * "Not shared by the candidate" rather than looking empty.
 */
import { ProfileAnswers } from '@/components/identity/evidence';
import { PROFICIENCY_LABEL, calendarDate, monthYear, monthsLabel } from '@/lib/hiring';
import { timeAgo } from '@/lib/format';
import { CLIENT_CONSENT, scopeLabel, scopeList, type Scope, type ScopedProfile } from '@/lib/agency';
import { AgencyName, TonePill } from '../../agencies/agency-badge';

const VERIFIED = 'var(--color-verified)';

/** Every scope except contact: anything less keeps the client on the snapshot. */
export const FULL_PROFILE_SCOPE: Scope[] = ['identity', 'skills', 'experience', 'evidence', 'answers'];

export function isNarrowed(scoped: ScopedProfile): boolean {
  return !FULL_PROFILE_SCOPE.every((s) => scoped.scope.includes(s));
}

export function NotShared({ what }: { what?: string }) {
  return (
    <p className="text-sm muted surface rounded-lg p-3" role="note">
      {what ? `${what}: n` : 'N'}ot shared by the candidate.
    </p>
  );
}

function VerifiedPill({ label = '✓ Verified' }: { label?: string }) {
  return (
    <span className="pill" style={{ color: VERIFIED, borderColor: VERIFIED }}>
      {label}
    </span>
  );
}

export type SubmissionAgency = { name: string; verified: boolean | null; independent: boolean };

/** Short header badge: "Submitted by Acme ✓ (Priya)". */
export function SubmittedByBadge({ agency, recruiter }: { agency: SubmissionAgency; recruiter: string | null }) {
  return (
    <span
      className="pill max-w-full whitespace-normal break-words"
      style={{ color: 'var(--color-brand-600)', borderColor: 'var(--color-brand-600)' }}
    >
      Submitted by {agency.name}
      {agency.verified ? ' ✓' : ''}
      {recruiter ? ` (${recruiter})` : ''}
    </span>
  );
}

export function SubmissionCard({
  agency,
  recruiter,
  note,
  consentStatus,
  scope,
  submittedAt,
  jobOrder,
  error,
}: {
  agency: SubmissionAgency;
  recruiter: string | null;
  note: string | null;
  consentStatus: string | null;
  scope: string[];
  submittedAt: string | null;
  jobOrder: string | null;
  error: string | null;
}) {
  const tone = consentStatus ? (CLIENT_CONSENT[consentStatus] ?? { label: consentStatus, color: 'var(--muted)' }) : null;
  return (
    <section
      className="card p-4 sm:p-5 space-y-3"
      style={{ borderTop: '3px solid var(--color-brand-600)' }}
      aria-label="Recruiter submission"
    >
      <div className="flex items-start gap-3 flex-wrap">
        <div className="flex-1 min-w-0">
          <p className="text-sm break-words">
            <span className="muted">Submitted by</span> <AgencyName agency={agency} />
            {recruiter && (
              <>
                {' '}
                <span className="muted">· recruiter</span> <span className="font-medium">{recruiter}</span>
              </>
            )}
          </p>
          <p className="text-xs muted mt-0.5 break-words">
            {[submittedAt ? `Submitted ${timeAgo(submittedAt)}` : null, jobOrder ? `Job order ${jobOrder}` : null]
              .filter(Boolean)
              .join(' · ')}
          </p>
        </div>
        {tone && <TonePill tone={tone} />}
      </div>

      {consentStatus === 'withdrawn' && (
        <p
          className="text-sm rounded-lg p-3"
          role="alert"
          style={{ color: 'var(--color-danger)', border: '1px solid var(--color-danger)' }}
        >
          The candidate withdrew consent from the agency. The agency can no longer act for them on this
          application; contact the candidate directly through Omelo if you want to continue.
        </p>
      )}

      <p className="text-sm break-words">
        <span className="muted">Shared by {agency.name} with the candidate&apos;s consent:</span>{' '}
        {scope.length > 0 ? scopeList(scope) : 'Professional identity'}
      </p>

      {note && (
        <div className="surface rounded-lg p-3">
          <p className="label">Note from the recruiter</p>
          <p className="text-sm whitespace-pre-line break-words">{note}</p>
        </div>
      )}

      {error && (
        <p className="text-xs" style={{ color: 'var(--color-warn)' }}>
          Some submission details could not be loaded: {error}
        </p>
      )}
    </section>
  );
}

/** Skills and verified evidence from the snapshot. */
export function SnapshotEvidence({ scoped }: { scoped: ScopedProfile }) {
  const has = (s: Scope) => scoped.scope.includes(s);
  const ev = scoped.evidence;
  return (
    <div className="space-y-5">
      <div>
        <p className="label">Skills</p>
        {!has('skills') ? (
          <NotShared />
        ) : (scoped.skills ?? []).length === 0 ? (
          <p className="text-sm muted">No skills listed.</p>
        ) : (
          <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
            {(scoped.skills ?? []).map((s, i) => (
              <li key={`${s.name}-${i}`} className="py-2 flex items-center gap-2 flex-wrap">
                <span className="text-sm font-medium break-words min-w-0">{s.name}</span>
                {s.proficiency && <span className="pill">{PROFICIENCY_LABEL[s.proficiency] ?? s.proficiency}</span>}
                {s.monthsUsed ? <span className="text-xs muted">{monthsLabel(s.monthsUsed)}</span> : null}
                {s.verified && <VerifiedPill />}
              </li>
            ))}
          </ul>
        )}
      </div>

      <div>
        <p className="label">Verified evidence</p>
        {!has('evidence') || !ev ? (
          <NotShared />
        ) : (
          <div className="space-y-3 text-sm">
            <div>
              <p className="text-xs muted mb-1">Verified employment</p>
              {ev.verifiedEmployment.length === 0 ? (
                <p className="muted">None.</p>
              ) : (
                <ul className="space-y-1.5">
                  {ev.verifiedEmployment.map((x, i) => (
                    <li key={i} className="flex items-start gap-2">
                      <span aria-hidden className="font-bold shrink-0 w-4 text-center" style={{ color: VERIFIED }}>
                        ✓
                      </span>
                      <span className="break-words min-w-0">
                        {[x.title, x.employer].filter(Boolean).join(' at ') || 'Employment'}
                        <span className="muted">
                          {' · '}
                          {monthYear(x.startedOn) || 'start not given'} – {monthYear(x.endedOn) || 'present'}
                        </span>
                      </span>
                    </li>
                  ))}
                </ul>
              )}
            </div>
            <div>
              <p className="text-xs muted mb-1">Verified skills</p>
              {ev.verifiedSkills.length === 0 ? (
                <p className="muted">None.</p>
              ) : (
                <div className="flex flex-wrap gap-1.5">
                  {ev.verifiedSkills.map((s) => (
                    <VerifiedPill key={s} label={`✓ ${s}`} />
                  ))}
                </div>
              )}
            </div>
            <div>
              <p className="text-xs muted mb-1">Licences</p>
              {ev.licences.length === 0 ? (
                <p className="muted">None.</p>
              ) : (
                <ul className="space-y-1">
                  {ev.licences.map((l, i) => (
                    <li key={`${l.name}-${i}`} className="flex items-center gap-2 flex-wrap">
                      <span className="break-words">{l.name}</span>
                      {l.verified ? <VerifiedPill /> : <span className="pill">Self-declared</span>}
                      {l.expiresOn && <span className="text-xs muted">expires {calendarDate(l.expiresOn)}</span>}
                    </li>
                  ))}
                </ul>
              )}
            </div>
            <p>
              {ev.emailVerified ? (
                <span style={{ color: VERIFIED }}>✓ Email verified</span>
              ) : (
                <span className="muted">Email not verified</span>
              )}
            </p>
          </div>
        )}
      </div>
    </div>
  );
}

export function SnapshotAnswers({ scoped }: { scoped: ScopedProfile }) {
  if (!scoped.scope.includes('answers')) return <NotShared />;
  return <ProfileAnswers answers={scoped.answers ?? []} />;
}

export function SnapshotExperience({ scoped }: { scoped: ScopedProfile }) {
  if (!scoped.scope.includes('experience')) return <NotShared />;
  const items = scoped.experience ?? [];
  if (items.length === 0) return <p className="text-sm muted">No work history shared.</p>;
  const ordered = [...items.filter((e) => e.verified), ...items.filter((e) => !e.verified)];
  return (
    <ul className="space-y-4">
      {ordered.map((e, i) => (
        <li key={`${e.title}-${i}`} className="min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-semibold text-sm break-words">{e.title}</span>
            {e.verified ? <VerifiedPill label="✓ Verified by Omelo" /> : <span className="pill">Self-declared</span>}
          </div>
          {e.employer && <div className="text-sm muted break-words">{e.employer}</div>}
          <div className="text-xs muted mt-0.5">
            {monthYear(e.startedOn) || 'Start not given'} –{' '}
            {e.isCurrent ? 'Present' : monthYear(e.endedOn) || 'end not given'}
          </div>
          {e.description && <p className="text-sm mt-1 whitespace-pre-line break-words">{e.description}</p>}
        </li>
      ))}
    </ul>
  );
}

export function SnapshotContact({ scoped }: { scoped: ScopedProfile }) {
  if (!scoped.scope.includes('contact') || !scoped.contact || (!scoped.contact.email && !scoped.contact.phone)) {
    return (
      <p className="text-sm muted">
        {scopeLabel('contact')} not shared by the candidate. Message them through Omelo.
      </p>
    );
  }
  return (
    <dl className="text-sm grid grid-cols-[auto_1fr] gap-x-3 gap-y-1">
      {scoped.contact.email && (
        <>
          <dt className="muted">Email</dt>
          <dd className="break-all">
            <a href={`mailto:${scoped.contact.email}`} className="underline">
              {scoped.contact.email}
            </a>
          </dd>
        </>
      )}
      {scoped.contact.phone && (
        <>
          <dt className="muted">Phone</dt>
          <dd className="break-all">
            <a href={`tel:${scoped.contact.phone}`} className="underline">
              {scoped.contact.phone}
            </a>
          </dd>
        </>
      )}
    </dl>
  );
}

/** "As shared when submitted, 3 days ago" — shown wherever the snapshot stands in for live data. */
export function SnapshotNote({ submittedAt }: { submittedAt: string | null }) {
  return (
    <p className="hint">
      As the candidate shared it through the agency{submittedAt ? `, ${timeAgo(submittedAt)}` : ''}.
    </p>
  );
}
