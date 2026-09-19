/**
 * Presentational pieces for talent search, profiles and pools. No hooks, so
 * server and client components share them.
 */
import Link from 'next/link';
import { monthsLabel } from '@/lib/hiring';
import { countryName } from '@/lib/global';
import { EligibilityBadge } from '@/components/global/eligibility';
import {
  ACTIVE_LABEL,
  INVITATION_COLOR,
  INVITATION_LABEL,
  distanceText,
  type InvitationStatus,
  type TalentCard,
} from '@/lib/talent';

const VERIFIED = 'var(--color-verified)';

export function ScoreBadge({ score, eligible }: { score: number | null; eligible: boolean | null }) {
  if (score == null) return <span className="pill">Not scored</span>;
  const ok = eligible !== false;
  return (
    <span
      className="inline-flex flex-col items-center justify-center rounded-xl px-2.5 py-1.5 shrink-0 min-w-[4.25rem]"
      style={{
        background: ok ? 'var(--color-brand-50)' : 'var(--surface)',
        border: `1px solid ${ok ? 'var(--color-brand-200)' : 'var(--line)'}`,
        color: ok ? 'var(--color-brand-700)' : 'var(--muted)',
      }}
      title={ok ? 'Match score. Meets every must-have.' : 'Match score. Misses at least one must-have.'}
    >
      <span className="text-xl font-black leading-none tabular-nums">{score}%</span>
      <span className="text-[0.68rem] font-semibold mt-0.5 whitespace-nowrap">
        {ok ? 'match' : 'misses a must-have'}
      </span>
    </span>
  );
}

export function InvitationChip({ status, sentAt }: { status: InvitationStatus; sentAt?: string | null }) {
  const color = INVITATION_COLOR[status] ?? 'var(--muted)';
  return (
    <span className="pill" style={{ color, borderColor: color }} title={sentAt ? `Invited ${sentAt.slice(0, 10)}` : undefined}>
      {INVITATION_LABEL[status] ?? status}
    </span>
  );
}

export function Avatar({ name, url, size = 44 }: { name: string; url: string | null; size?: number }) {
  const initial = name.trim().charAt(0).toUpperCase() || '?';
  if (url)
    // Avatars come from Supabase storage on arbitrary hosts; next/image would
    // need every host configured, and these are tiny.
    // eslint-disable-next-line @next/next/no-img-element
    return <img src={url} alt="" width={size} height={size} className="rounded-full object-cover shrink-0" style={{ width: size, height: size }} />;
  return (
    <span
      aria-hidden
      className="rounded-full grid place-items-center font-bold shrink-0"
      style={{ width: size, height: size, background: 'var(--color-brand-100)', color: 'var(--color-brand-700)' }}
    >
      {initial}
    </span>
  );
}

/** "as Cook · Line cook" */
export function IdentityLine({ card }: { card: Pick<TalentCard, 'label' | 'profession'> }) {
  if (!card.label && !card.profession) return null;
  return (
    <p className="text-sm break-words">
      <span className="muted">as</span> <span className="font-semibold">{card.label ?? card.profession}</span>
      {card.profession && card.label && card.profession !== card.label ? (
        <span className="muted"> · {card.profession}</span>
      ) : null}
    </p>
  );
}

export function CardFacts({ card }: { card: TalentCard }) {
  const facts = [
    distanceText(card.distanceKm) ?? card.location,
    card.experienceMonths ? `${monthsLabel(card.experienceMonths)} experience` : 'No experience listed',
    card.active ? ACTIVE_LABEL[card.active] : null,
  ].filter(Boolean);
  return <p className="text-xs muted break-words">{facts.join(' · ')}</p>;
}

/** R6: eligibility for the searched job, relocation and where they live. */
export function GlobalChips({ card }: { card: TalentCard }) {
  if (!card.eligibility && !card.openToRelocation && !card.currentCountry) return null;
  return (
    <div className="flex flex-wrap gap-1.5 items-start">
      {card.eligibility && <EligibilityBadge e={card.eligibility} />}
      {card.openToRelocation && (
        <span className="pill" style={{ color: 'var(--color-brand-600)' }}>
          Open to relocation
        </span>
      )}
      {card.currentCountry && <span className="pill">Lives in {countryName(card.currentCountry)}</span>}
    </div>
  );
}

export function SkillChips({ card, max = 5 }: { card: TalentCard; max?: number }) {
  if (card.topSkills.length === 0 && card.verifiedSkills === 0) return null;
  return (
    <div className="flex flex-wrap gap-1.5 items-center">
      {card.topSkills.slice(0, max).map((s) => (
        <span key={s} className="pill">
          {s}
        </span>
      ))}
      {card.verifiedSkills > 0 && (
        <span className="pill" style={{ color: VERIFIED, borderColor: VERIFIED }}>
          ✓ {card.verifiedSkills} verified
        </span>
      )}
    </div>
  );
}

export function ReasonList({
  items,
  tone,
}: {
  items: string[];
  tone: 'good' | 'gap';
}) {
  if (items.length === 0) return null;
  const color = tone === 'good' ? VERIFIED : 'var(--color-warn)';
  return (
    <ul className="space-y-1">
      {items.map((t, i) => (
        <li key={`${t}-${i}`} className="flex items-start gap-2 text-sm">
          <span aria-hidden className="font-bold shrink-0 w-4 text-center" style={{ color }}>
            {tone === 'good' ? '✓' : '!'}
          </span>
          <span className="break-words min-w-0">{t}</span>
        </li>
      ))}
    </ul>
  );
}

/** Header block of a candidate card: avatar, name, identity, facts, score. */
export function CardHeader({
  card,
  href,
  showScore = true,
}: {
  card: TalentCard;
  href?: string;
  showScore?: boolean;
}) {
  return (
    <div className="flex items-start gap-3">
      <Avatar name={card.name} url={card.avatarUrl} />
      <div className="flex-1 min-w-0 space-y-0.5">
        <p className="font-bold break-words">
          {href ? (
            <Link href={href} className="hover:underline">
              {card.name}
            </Link>
          ) : (
            card.name
          )}
        </p>
        <IdentityLine card={card} />
        {card.headline && card.headline !== card.label && (
          <p className="text-sm muted break-words line-clamp-2">{card.headline}</p>
        )}
        <CardFacts card={card} />
      </div>
      {showScore && card.score != null && <ScoreBadge score={card.score} eligible={card.eligible} />}
    </div>
  );
}

export function ErrorNote({ label, message }: { label: string; message: string }) {
  return (
    <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
      Could not load {label}: <span className="muted">{message}</span>
    </p>
  );
}

/** Large explanatory empty / blocked state. */
export function Notice({
  title,
  children,
  tone = 'neutral',
  action,
}: {
  title: string;
  children: React.ReactNode;
  tone?: 'neutral' | 'warn';
  action?: React.ReactNode;
}) {
  return (
    <div
      className="card p-6 sm:p-8 text-center"
      style={tone === 'warn' ? { borderTop: '3px solid var(--color-warn)' } : undefined}
    >
      <p className="font-semibold mb-1">{title}</p>
      <div className="text-sm muted max-w-md mx-auto leading-relaxed">{children}</div>
      {action && <div className="mt-5 flex justify-center gap-2 flex-wrap">{action}</div>}
    </div>
  );
}

/** Page title plus the Search / Talent pools switch. */
export function TalentHeader({ active }: { active: 'search' | 'pools' }) {
  const tab = (href: string, label: string, on: boolean) => (
    <Link
      href={href}
      aria-current={on ? 'page' : undefined}
      className="px-3 py-1.5 rounded-md text-sm font-semibold"
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
    <div className="flex items-end justify-between gap-3 flex-wrap">
      <div className="min-w-0">
        <h1 className="text-xl sm:text-2xl font-bold">Find candidates</h1>
        <p className="text-sm muted mt-1">
          People who chose to be visible to employers, ranked against your job.
        </p>
      </div>
      <nav aria-label="Talent" className="inline-flex rounded-lg border hairline p-0.5 surface">
        {tab('/dashboard/talent', 'Search', active === 'search')}
        {tab('/dashboard/talent/pools', 'Talent pools', active === 'pools')}
      </nav>
    </div>
  );
}
