/**
 * Presentational pieces shared by the agency pages. No hooks, so server and
 * client components can both use them.
 */
import Link from 'next/link';
import type { ReactNode } from 'react';
import { calendarDate } from '@/lib/hiring';
import {
  JOB_ORDER_STATUS,
  PRIORITY,
  consentTone,
  placementTone,
  scopeLabel,
  submissionTone,
} from '@/lib/agency';

export { ErrorNote, Notice } from '../talent/ui';

export function Pill({ label, color, title }: { label: string; color: string; title?: string }) {
  return (
    <span className="pill whitespace-nowrap" style={{ color, borderColor: color }} title={title}>
      {label}
    </span>
  );
}

export function ConsentPill({ status }: { status: string }) {
  const t = consentTone(status);
  return <Pill label={t.label} color={t.color} />;
}

export function SubmissionPill({ status }: { status: string }) {
  const t = submissionTone(status);
  return <Pill label={t.label} color={t.color} />;
}

export function PlacementPill({ status }: { status: string }) {
  const t = placementTone(status);
  return <Pill label={t.label} color={t.color} />;
}

export function OrderStatusPill({ status }: { status: string }) {
  const t = JOB_ORDER_STATUS[status] ?? { label: status, color: 'var(--muted)' };
  return <Pill label={t.label} color={t.color} />;
}

export function PriorityPill({ priority }: { priority: string }) {
  if (priority === 'normal') return null;
  const t = PRIORITY[priority] ?? { label: priority, color: 'var(--muted)' };
  return <Pill label={`${t.label} priority`} color={t.color} />;
}

export function ScopeChips({ scope }: { scope: string[] }) {
  if (!scope.length) return null;
  return (
    <span className="inline-flex flex-wrap gap-1">
      {scope.map((s) => (
        <span key={s} className="pill text-[0.72rem]">
          {scopeLabel(s)}
        </span>
      ))}
    </span>
  );
}

export function PageHeader({
  title,
  subtitle,
  action,
  back,
}: {
  title: ReactNode;
  subtitle?: ReactNode;
  action?: ReactNode;
  back?: { href: string; label: string };
}) {
  return (
    <div className="space-y-3">
      {back && (
        <Link href={back.href} className="text-sm underline muted">
          ← {back.label}
        </Link>
      )}
      <div className="flex items-start gap-3 flex-wrap">
        <div className="flex-1 min-w-[14rem]">
          <h1 className="text-xl sm:text-2xl font-bold break-words">{title}</h1>
          {subtitle && <div className="text-sm muted mt-1 break-words">{subtitle}</div>}
        </div>
        {action && <div className="flex flex-wrap gap-2 w-full sm:w-auto">{action}</div>}
      </div>
    </div>
  );
}

export function Tile({ label, value, hint, href }: { label: string; value: ReactNode; hint?: string; href?: string }) {
  const body = (
    <>
      <div className="text-2xl sm:text-3xl font-black tabular-nums">{value}</div>
      <div className="text-sm font-semibold mt-1">{label}</div>
      {hint && <div className="text-xs muted mt-0.5">{hint}</div>}
    </>
  );
  return href ? (
    <Link href={href} className="card p-4 block hover:opacity-90 min-w-0">
      {body}
    </Link>
  ) : (
    <div className="card p-4 min-w-0">{body}</div>
  );
}

/** A one-line reason an action is unavailable (the DB would refuse anyway). */
export function Why({ children }: { children: ReactNode }) {
  return <p className="text-xs muted break-words">{children}</p>;
}

export function Section({
  title,
  aside,
  children,
  id,
}: {
  title: ReactNode;
  aside?: ReactNode;
  children: ReactNode;
  id?: string;
}) {
  return (
    <section className="card p-4 sm:p-5 space-y-3 min-w-0" id={id}>
      <div className="flex items-center gap-3 flex-wrap">
        <h2 className="font-bold flex-1 min-w-0">{title}</h2>
        {aside}
      </div>
      {children}
    </section>
  );
}

/** Filter chips driven by search params (server-rendered links). */
export function FilterChips({
  label,
  options,
  active,
  hrefFor,
}: {
  label: string;
  options: { value: string; label: string; count?: number }[];
  active: string;
  hrefFor: (value: string) => string;
}) {
  return (
    <nav aria-label={label} className="flex gap-1.5 overflow-x-auto pb-1 -mx-4 px-4 sm:mx-0 sm:px-0 sm:flex-wrap">
      {options.map((o) => {
        const on = o.value === active;
        return (
          <Link
            key={o.value}
            href={hrefFor(o.value)}
            aria-current={on ? 'page' : undefined}
            className="px-3 py-1.5 rounded-lg text-sm font-medium whitespace-nowrap border hairline"
            style={
              on
                ? { background: 'var(--color-brand-600)', color: '#fff', borderColor: 'transparent' }
                : { background: 'var(--surface)' }
            }
          >
            {o.label}
            {o.count != null && <span className={on ? 'opacity-80' : 'muted'}> {o.count}</span>}
          </Link>
        );
      })}
    </nav>
  );
}

export function dateText(d: string | null) {
  return d ? calendarDate(d) : '—';
}

/** Build a query string from defined, non-default values. */
export function qs(params: Record<string, string | null | undefined>) {
  const p = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v && v !== 'all') p.set(k, v);
  const s = p.toString();
  return s ? `?${s}` : '';
}

/** Shown when the agency is not verified yet (search and consent requests need it). */
export function NotVerifiedAgency({ compact = false }: { compact?: boolean }) {
  return (
    <div className="card p-4 sm:p-5" style={{ borderTop: '3px solid var(--color-warn)' }}>
      <p className="font-semibold">Omelo has not verified your agency yet</p>
      <p className="text-sm muted mt-1 leading-relaxed">
        Searching for candidates and asking them for consent open once Omelo verifies the agency and turns on
        talent search.
        {compact
          ? ''
          : ' Until then you can add clients, create job orders and invite your team. Contact Omelo to get verified.'}
      </p>
    </div>
  );
}
