/**
 * Renders exactly what a consent allows: identity always, and each other
 * section only when it was shared. Used for the consented profile a
 * recruiter opens. No hooks: server-rendered.
 */
import { SCOPE_LABEL, type ScopedProfile } from '@/lib/agency';
import { PROFICIENCY_LABEL, calendarDate, monthYear, monthsLabel } from '@/lib/hiring';
import { ProfileAnswers } from '@/components/identity/evidence';
import { Avatar } from '../talent/ui';

const VERIFIED = 'var(--color-verified)';

function NotShared({ what }: { what: string }) {
  return <p className="text-sm muted">Not shared — the candidate did not include {what.toLowerCase()} in this consent.</p>;
}

function Block({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="card p-4 sm:p-5 space-y-3 min-w-0">
      <h2 className="font-bold">{title}</h2>
      {children}
    </section>
  );
}

export default function ScopedProfileView({ p }: { p: ScopedProfile }) {
  const i = p.identity;
  const has = (s: string) => p.scope.includes(s);
  return (
    <div className="space-y-5">
      <section className="card p-4 sm:p-5 flex items-start gap-4 flex-wrap">
        <Avatar name={i.name} url={i.avatarUrl} size={56} />
        <div className="flex-1 min-w-[12rem] space-y-1">
          <h2 className="text-lg font-bold break-words">{i.name}</h2>
          {(i.label || i.profession) && (
            <p className="text-sm break-words">
              <span className="muted">as</span> <strong>{i.label ?? i.profession}</strong>
              {i.label && i.profession && i.label !== i.profession ? <span className="muted"> · {i.profession}</span> : null}
            </p>
          )}
          {i.headline && <p className="text-sm break-words">{i.headline}</p>}
          <p className="text-sm muted break-words">
            {[i.experienceMonths ? `${monthsLabel(i.experienceMonths)} experience` : null, i.location].filter(Boolean).join(' · ')}
          </p>
          {i.about && <p className="text-sm whitespace-pre-line break-words pt-1">{i.about}</p>}
        </div>
      </section>

      <Block title={SCOPE_LABEL.skills}>
        {!has('skills') || !p.skills ? (
          <NotShared what={SCOPE_LABEL.skills} />
        ) : p.skills.length === 0 ? (
          <p className="text-sm muted">No skills listed.</p>
        ) : (
          <ul className="flex flex-wrap gap-1.5">
            {p.skills.map((s) => (
              <li
                key={s.name}
                className="pill"
                style={s.verified ? { color: VERIFIED, borderColor: VERIFIED } : undefined}
                title={s.verified ? 'Confirmed by an employer' : 'Self-declared'}
              >
                {s.verified ? '✓ ' : ''}
                {s.name}
                {s.proficiency ? ` · ${PROFICIENCY_LABEL[s.proficiency] ?? s.proficiency}` : ''}
              </li>
            ))}
          </ul>
        )}
      </Block>

      <Block title={SCOPE_LABEL.experience}>
        {!has('experience') || !p.experience ? (
          <NotShared what={SCOPE_LABEL.experience} />
        ) : p.experience.length === 0 ? (
          <p className="text-sm muted">No work history listed.</p>
        ) : (
          <ul className="space-y-3">
            {p.experience.map((x, idx) => (
              <li key={`${x.title}-${idx}`} className="min-w-0">
                <p className="text-sm font-semibold break-words">
                  {x.title}
                  {x.verified ? (
                    <span className="pill ml-2 text-[0.7rem]" style={{ color: VERIFIED, borderColor: VERIFIED }}>
                      ✓ Verified
                    </span>
                  ) : (
                    <span className="pill ml-2 text-[0.7rem]">Self-declared</span>
                  )}
                </p>
                <p className="text-sm muted break-words">{x.employer}</p>
                <p className="text-xs muted">
                  {monthYear(x.startedOn) || 'Start not given'} – {x.isCurrent ? 'Present' : monthYear(x.endedOn) || 'end not given'}
                </p>
                {x.description && <p className="text-sm mt-1 whitespace-pre-line break-words">{x.description}</p>}
              </li>
            ))}
          </ul>
        )}
      </Block>

      <Block title={SCOPE_LABEL.evidence}>
        {!has('evidence') || !p.evidence ? (
          <NotShared what={SCOPE_LABEL.evidence} />
        ) : (
          <div className="space-y-3 text-sm">
            <div>
              <p className="label">Verified employment</p>
              {p.evidence.verifiedEmployment.length === 0 ? (
                <p className="muted">None yet.</p>
              ) : (
                <ul className="space-y-1">
                  {p.evidence.verifiedEmployment.map((e, idx) => (
                    <li key={idx} className="break-words">
                      <span style={{ color: VERIFIED }}>✓</span> {e.title ?? 'Role'} at {e.employer ?? 'an employer'}{' '}
                      <span className="muted">
                        ({monthYear(e.startedOn) || '?'} – {monthYear(e.endedOn) || 'present'})
                      </span>
                    </li>
                  ))}
                </ul>
              )}
            </div>
            <div>
              <p className="label">Skills confirmed by employers</p>
              <p className="break-words">{p.evidence.verifiedSkills.join(', ') || <span className="muted">None yet.</span>}</p>
            </div>
            <div>
              <p className="label">Licences</p>
              {p.evidence.licences.length === 0 ? (
                <p className="muted">None listed.</p>
              ) : (
                <ul className="space-y-1">
                  {p.evidence.licences.map((l, idx) => (
                    <li key={idx} className="break-words">
                      {l.verified ? <span style={{ color: VERIFIED }}>✓ </span> : null}
                      {l.name}
                      {l.expiresOn ? <span className="muted"> · expires {calendarDate(l.expiresOn)}</span> : null}
                    </li>
                  ))}
                </ul>
              )}
            </div>
            <p>
              Email {p.evidence.emailVerified ? <span style={{ color: VERIFIED }}>verified ✓</span> : <span className="muted">not verified</span>}
            </p>
          </div>
        )}
      </Block>

      <Block title={SCOPE_LABEL.answers}>
        {!has('answers') || !p.answers ? <NotShared what={SCOPE_LABEL.answers} /> : <ProfileAnswers answers={p.answers} />}
      </Block>

      <Block title={SCOPE_LABEL.contact}>
        {!has('contact') ? (
          <NotShared what={SCOPE_LABEL.contact} />
        ) : !p.contact ? (
          <p className="text-sm muted">Contact details are shown to owners, admins and recruiters only.</p>
        ) : (
          <dl className="text-sm grid grid-cols-[auto_1fr] gap-x-3 gap-y-1">
            <dt className="muted">Email</dt>
            <dd className="break-all">{p.contact.email ? <a className="underline" href={`mailto:${p.contact.email}`}>{p.contact.email}</a> : '—'}</dd>
            <dt className="muted">Phone</dt>
            <dd className="break-all">{p.contact.phone ? <a className="underline" href={`tel:${p.contact.phone}`}>{p.contact.phone}</a> : '—'}</dd>
          </dl>
        )}
      </Block>
    </div>
  );
}
