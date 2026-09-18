/**
 * Renders a submission snapshot: exactly what the candidate consented to
 * share, frozen at the moment of submission. Sections the candidate did not
 * include are absent from the snapshot, so they are not rendered.
 */
import type { ScopedProfile } from '@/lib/agency';
import { PROFICIENCY_LABEL, calendarDate, monthYear, monthsLabel } from '@/lib/hiring';

function Block({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="space-y-2 min-w-0">
      <h3 className="text-sm font-semibold">{title}</h3>
      {children}
    </div>
  );
}

const ym = (d: string | null) => (d ? monthYear(d.slice(0, 10)) : '');

export function SnapshotView({ p, limited }: { p: ScopedProfile; limited: boolean }) {
  const i = p.identity;
  const facts = [i.profession, monthsLabel(i.experienceMonths) && `${monthsLabel(i.experienceMonths)} experience`, i.location]
    .filter(Boolean)
    .join(' · ');

  return (
    <div className="space-y-5 min-w-0">
      <Block title="Professional identity">
        <div className="text-sm space-y-1 break-words">
          <p className="font-semibold">
            {i.name}
            {i.label && <span className="font-normal muted"> as {i.label}</span>}
          </p>
          {i.headline && <p>{i.headline}</p>}
          {facts && <p className="muted">{facts}</p>}
          {i.about && <p className="whitespace-pre-line leading-relaxed">{i.about}</p>}
        </div>
      </Block>

      {p.skills && (
        <Block title="Skills">
          {p.skills.length === 0 ? (
            <p className="text-sm muted">No skills listed.</p>
          ) : (
            <ul className="flex flex-wrap gap-1.5">
              {p.skills.map((s, k) => (
                <li key={k} className="pill text-[0.78rem] max-w-full break-words">
                  {s.name}
                  {s.proficiency && <span className="muted"> · {PROFICIENCY_LABEL[s.proficiency] ?? s.proficiency}</span>}
                  {s.verified && (
                    <span style={{ color: 'var(--color-verified)' }} title="Confirmed by an employer">
                      {' '}
                      ✓
                    </span>
                  )}
                </li>
              ))}
            </ul>
          )}
        </Block>
      )}

      {limited ? (
        <p className="text-xs muted">
          Your role shows identity and skills only. Owners, admins and recruiters see the rest of what was shared.
        </p>
      ) : (
        <>
          {p.experience && (
            <Block title="Work history">
              {p.experience.length === 0 ? (
                <p className="text-sm muted">No jobs listed.</p>
              ) : (
                <ul className="space-y-2">
                  {p.experience.map((x, k) => (
                    <li key={k} className="text-sm break-words">
                      <p className="font-medium">
                        {x.title}
                        {x.employer && <span className="muted font-normal"> · {x.employer}</span>}
                        {x.verified && (
                          <span className="text-xs" style={{ color: 'var(--color-verified)' }}>
                            {' '}
                            Verified
                          </span>
                        )}
                      </p>
                      <p className="text-xs muted">
                        {ym(x.startedOn) || '—'} – {x.isCurrent ? 'now' : ym(x.endedOn) || '—'}
                      </p>
                      {x.description && <p className="text-sm mt-0.5 whitespace-pre-line">{x.description}</p>}
                    </li>
                  ))}
                </ul>
              )}
            </Block>
          )}

          {p.evidence && (
            <Block title="Verified evidence">
              <ul className="text-sm space-y-1 break-words">
                {p.evidence.verifiedEmployment.map((v, k) => (
                  <li key={`e${k}`}>
                    Verified employment: {[v.title, v.employer].filter(Boolean).join(' at ') || 'Job'}
                    <span className="muted">
                      {' '}
                      ({ym(v.startedOn) || '—'} – {ym(v.endedOn) || 'now'})
                    </span>
                  </li>
                ))}
                {p.evidence.verifiedSkills.length > 0 && (
                  <li>Skills confirmed by employers: {p.evidence.verifiedSkills.join(', ')}</li>
                )}
                {p.evidence.licences.map((l, k) => (
                  <li key={`l${k}`}>
                    Licence: {l.name}
                    {l.verified ? ' (verified)' : ''}
                    {l.expiresOn && <span className="muted"> · expires {calendarDate(l.expiresOn)}</span>}
                  </li>
                ))}
                {p.evidence.emailVerified && <li>Email address verified</li>}
                {!p.evidence.verifiedEmployment.length &&
                  !p.evidence.verifiedSkills.length &&
                  !p.evidence.licences.length &&
                  !p.evidence.emailVerified && <li className="muted">No verified evidence yet.</li>}
              </ul>
            </Block>
          )}

          {p.answers && (
            <Block title={`Profile answers (${p.answers.length})`}>
              {p.answers.length === 0 ? (
                <p className="text-sm muted">No answers.</p>
              ) : (
                <dl className="grid gap-x-4 gap-y-1 text-sm sm:grid-cols-[minmax(0,14rem)_1fr]">
                  {p.answers.map((a) => (
                    <div key={a.id} className="contents">
                      <dt className="muted break-words">{a.label}</dt>
                      <dd className="break-words mb-1 sm:mb-0">{Array.isArray(a.value) ? a.value.join(', ') : a.value}</dd>
                    </div>
                  ))}
                </dl>
              )}
            </Block>
          )}

          {p.contact && (
            <Block title="Contact details">
              <p className="text-sm break-words">
                {[p.contact.email, p.contact.phone].filter(Boolean).join(' · ') || (
                  <span className="muted">None given.</span>
                )}
              </p>
            </Block>
          )}
        </>
      )}
    </div>
  );
}
