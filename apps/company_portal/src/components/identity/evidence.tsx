/**
 * Evidence for one work identity. Pure presentational components (no hooks),
 * so both the server-rendered candidate page and the client Meet panel use
 * them.
 */
import { PROFICIENCY_LABEL, calendarDate, monthYear, monthsLabel } from '@/lib/hiring';
import {
  skillBadges,
  type EvidenceResult,
  type EvidenceSkill,
  type IdentityEvidence,
  type ProfileAnswer,
} from '@/lib/identity';

const VERIFIED = 'var(--color-verified)';

export function HiringTeamOnly() {
  return (
    <p className="text-sm muted surface rounded-lg p-3" role="note">
      Only the hiring team can see this.
    </p>
  );
}

function EvidenceError({ message }: { message: string }) {
  return (
    <p className="text-sm" style={{ color: 'var(--color-danger)' }}>
      Could not load evidence: <span className="muted">{message}</span>
    </p>
  );
}

/** Handles the forbidden / error branches; renders children only on success. */
export function EvidenceGate({
  result,
  children,
}: {
  result: EvidenceResult;
  children: (data: IdentityEvidence) => React.ReactNode;
}) {
  if (result.status === 'forbidden') return <HiringTeamOnly />;
  if (result.status === 'error') return <EvidenceError message={result.message} />;
  return <>{children(result.data)}</>;
}

export function CompletenessMeter({ score, compact }: { score: number | null; compact?: boolean }) {
  if (score == null) return null;
  const pct = Math.max(0, Math.min(100, Math.round(score)));
  const color = pct >= 80 ? VERIFIED : pct >= 50 ? 'var(--color-brand-600)' : 'var(--color-warn)';
  return (
    <div
      className={compact ? 'flex items-center gap-2' : 'flex items-center gap-2 min-w-[10rem]'}
      title="How complete this work identity's profile is. Computed by Omelo."
    >
      <div
        role="meter"
        aria-label="Profile completeness"
        aria-valuemin={0}
        aria-valuemax={100}
        aria-valuenow={pct}
        className="h-1.5 flex-1 rounded-full overflow-hidden min-w-[4rem]"
        style={{ background: 'var(--line)' }}
      >
        <div className="h-full rounded-full" style={{ width: `${pct}%`, background: color }} />
      </div>
      <span className="text-xs muted whitespace-nowrap">{pct}% complete</span>
    </div>
  );
}

export function TrustRow({ trust }: { trust: IdentityEvidence['trust'] }) {
  const items: [string, boolean][] = [
    ['Email', trust.email_verified],
    ['Phone', trust.phone_verified],
    ['Identity', trust.identity_verified],
  ];
  return (
    <div className="flex flex-wrap gap-1.5" aria-label="Verification">
      {items.map(([label, ok]) => (
        <span
          key={label}
          className="pill"
          style={ok ? { color: VERIFIED, borderColor: VERIFIED } : undefined}
        >
          {ok ? `✓ ${label} verified` : `${label} not verified`}
        </span>
      ))}
    </div>
  );
}

function SkillRow({ s, required }: { s: EvidenceSkill; required?: boolean }) {
  const badges = skillBadges(s);
  return (
    <li className="py-2.5 first:pt-0 last:pb-0">
      <div className="flex items-baseline gap-2 flex-wrap">
        <span className="font-semibold text-sm break-words" style={s.verified ? { color: VERIFIED } : undefined}>
          {s.verified ? '✓ ' : ''}
          {s.name}
        </span>
        {s.proficiency && (
          <span className="text-xs muted">{PROFICIENCY_LABEL[s.proficiency] ?? s.proficiency}</span>
        )}
        {s.months_used ? <span className="text-xs muted">· used {monthsLabel(s.months_used)}</span> : null}
        {required && (
          <span className="pill" style={{ borderColor: 'var(--color-brand-400)' }}>
            Job asks for this
          </span>
        )}
      </div>
      {badges.length > 0 && (
        <div className="flex flex-wrap gap-1.5 mt-1.5">
          {badges.map((b) => (
            <span
              key={b.key}
              className="pill text-xs"
              title={b.title}
              style={b.verified ? { color: VERIFIED, borderColor: VERIFIED } : undefined}
            >
              {b.text}
            </span>
          ))}
        </div>
      )}
    </li>
  );
}

function Licences({ ev }: { ev: IdentityEvidence }) {
  if (ev.licences.length === 0 && ev.credentials.length === 0) return null;
  return (
    <div className="grid sm:grid-cols-2 gap-5">
      {ev.licences.length > 0 && (
        <div>
          <p className="label">Licences</p>
          <ul className="text-sm space-y-1">
            {ev.licences.map((l, i) => (
              <li key={`${l.name}-${i}`} className="break-words">
                {l.name ?? 'Licence'}
                {l.class ? ` (${l.class})` : ''}{' '}
                {l.verified ? (
                  <span style={{ color: VERIFIED }}>· ✓ verified</span>
                ) : (
                  <span className="muted">· not verified</span>
                )}
                {l.expires_on && <span className="muted"> · expires {calendarDate(l.expires_on)}</span>}
              </li>
            ))}
          </ul>
        </div>
      )}
      {ev.credentials.length > 0 && (
        <div>
          <p className="label">Credentials</p>
          <ul className="text-sm space-y-1">
            {ev.credentials.map((c, i) => (
              <li key={`${c.name}-${i}`} className="break-words">
                {c.name}
                {c.issuer ? <span className="muted"> · {c.issuer}</span> : null}{' '}
                {c.verified ? (
                  <span style={{ color: VERIFIED }}>· ✓ verified</span>
                ) : (
                  <span className="muted">· not verified</span>
                )}
                {c.expires_on && <span className="muted"> · expires {calendarDate(c.expires_on)}</span>}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

/** Full evidence panel for the candidate review page. */
export function EvidencePanel({ ev }: { ev: IdentityEvidence }) {
  return (
    <div className="space-y-5">
      <div>
        <p className="label">Verification</p>
        <TrustRow trust={ev.trust} />
      </div>

      <div>
        <p className="label">Skills and what backs them</p>
        {ev.skills.length === 0 ? (
          <p className="text-sm muted">No skills on this work identity yet.</p>
        ) : (
          <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
            {ev.skills.map((s) => (
              <SkillRow key={s.skill_id} s={s} />
            ))}
          </ul>
        )}
      </div>

      <div>
        <p className="label">Verified employment</p>
        {ev.verified_employment.length === 0 ? (
          <p className="text-sm muted">No employment verified by Omelo yet.</p>
        ) : (
          <ul className="text-sm space-y-1.5">
            {ev.verified_employment.map((e, i) => (
              <li key={`${e.employer}-${e.started_on}-${i}`} className="break-words">
                <span style={{ color: VERIFIED }}>✓ </span>
                <span className="font-medium">{e.title}</span> at {e.employer}
                <span className="muted">
                  {' '}
                  · {monthYear(e.started_on) || 'start not given'} –{' '}
                  {e.is_current ? 'Present' : monthYear(e.ended_on) || 'end not given'}
                </span>
              </li>
            ))}
          </ul>
        )}
      </div>

      <Licences ev={ev} />
    </div>
  );
}

/** Compact summary for the Meet side panel's Candidate tab. */
export function EvidenceSummary({ ev }: { ev: IdentityEvidence }) {
  const verifiedSkills = ev.skills.filter((s) => s.verified).length;
  return (
    <div className="space-y-3">
      <TrustRow trust={ev.trust} />
      <p className="text-sm">
        <span className="font-semibold">{ev.skills.length}</span>{' '}
        <span className="muted">skill{ev.skills.length === 1 ? '' : 's'}</span>
        {' · '}
        <span className="font-semibold" style={verifiedSkills ? { color: VERIFIED } : undefined}>
          {verifiedSkills}
        </span>{' '}
        <span className="muted">verified</span>
        {' · '}
        <span className="font-semibold">{ev.verified_employment.length}</span>{' '}
        <span className="muted">verified job{ev.verified_employment.length === 1 ? '' : 's'}</span>
      </p>
      <Licences ev={ev} />
    </div>
  );
}

/** Skills with evidence badges; `required` names are highlighted. */
export function EvidenceSkills({ ev, required }: { ev: IdentityEvidence; required?: Set<string> }) {
  if (ev.skills.length === 0) return <p className="text-sm muted">No skills on this work identity yet.</p>;
  return (
    <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
      {ev.skills.map((s) => (
        <SkillRow key={s.skill_id} s={s} required={required?.has(s.name.toLowerCase())} />
      ))}
    </ul>
  );
}

export function ProfileAnswers({ answers }: { answers: ProfileAnswer[] }) {
  if (answers.length === 0) return <p className="text-sm muted">No profile answers for this work identity yet.</p>;
  return (
    <dl className="grid sm:grid-cols-2 gap-x-6 gap-y-3">
      {answers.map((a) => (
        <div key={a.id} className="min-w-0">
          <dt className="text-xs muted break-words">{a.label}</dt>
          <dd className="text-sm break-words">
            {Array.isArray(a.value) ? (
              <ul className="flex flex-wrap gap-1.5 mt-0.5">
                {a.value.map((v) => (
                  <li key={v} className="pill">
                    {v}
                  </li>
                ))}
              </ul>
            ) : (
              <span className="whitespace-pre-line">{a.value}</span>
            )}
          </dd>
        </div>
      ))}
    </dl>
  );
}
