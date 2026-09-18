import Link from 'next/link';

/** Segmented control made of links, so the window lives in the URL. */
export function WindowSelector({
  param,
  options,
  current,
  basePath,
  label,
}: {
  param: string;
  options: { value: number; label: string }[];
  current: number;
  basePath: string;
  label: string;
}) {
  return (
    <div role="group" aria-label={label} className="inline-flex rounded-lg border hairline p-0.5 surface">
      {options.map((o) => {
        const active = o.value === current;
        return (
          <Link
            key={o.value}
            href={`${basePath}?${param}=${o.value}`}
            aria-current={active ? 'true' : undefined}
            scroll={false}
            className="px-3 py-1.5 rounded-md text-sm font-semibold"
            style={
              active
                ? { background: 'var(--bg)', color: 'var(--color-brand-600)', boxShadow: '0 0 0 1px var(--line)' }
                : { color: 'var(--muted)' }
            }
          >
            {o.label}
          </Link>
        );
      })}
    </div>
  );
}

export function Card({
  title,
  children,
  tone,
}: {
  title: string;
  children: React.ReactNode;
  tone?: 'ok' | 'warn' | 'bad';
}) {
  const color =
    tone === 'bad' ? 'var(--color-danger)' : tone === 'warn' ? 'var(--color-warn)' : tone === 'ok' ? 'var(--color-verified)' : undefined;
  return (
    <section className="card p-4 sm:p-5" style={color ? { borderTop: `3px solid ${color}` } : undefined}>
      <h2 className="text-sm font-bold uppercase tracking-wide muted">{title}</h2>
      <div className="mt-3">{children}</div>
    </section>
  );
}

export function Stat({
  label,
  value,
  tone,
  hint,
}: {
  label: string;
  value: string;
  tone?: 'warn' | 'bad';
  hint?: string;
}) {
  return (
    <div>
      <p
        className="text-2xl font-black tabular-nums"
        style={tone ? { color: tone === 'bad' ? 'var(--color-danger)' : 'var(--color-warn)' } : undefined}
      >
        {value}
      </p>
      <p className="text-xs muted mt-0.5">{label}</p>
      {hint && <p className="text-xs muted">{hint}</p>}
    </div>
  );
}

export function parseChoice(raw: string | string[] | undefined, allowed: number[], fallback: number) {
  const n = Number(Array.isArray(raw) ? raw[0] : raw);
  return allowed.includes(n) ? n : fallback;
}
