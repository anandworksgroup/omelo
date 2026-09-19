/**
 * Hiring difficulty as a half-circle gauge. The score (0-100) and the label
 * are always printed, so nothing depends on reading the arc or its colour.
 * No hooks: renders on the server.
 */
import { DIFFICULTY_COLOR, DIFFICULTY_LABEL, type Difficulty } from '@/lib/intelligence';

const R = 40;
const HALF = Math.PI * R;

export function DifficultyGauge({
  score,
  label,
  size = 'lg',
}: {
  score: number | null;
  label: Difficulty | null;
  size?: 'lg' | 'sm';
}) {
  const color = label ? DIFFICULTY_COLOR[label] : 'var(--muted)';
  const text = label ? DIFFICULTY_LABEL[label] : 'Unknown';
  const value = score ?? 0;
  const width = size === 'lg' ? 'w-40 sm:w-48' : 'w-24';
  return (
    <div
      role="meter"
      aria-label="Hiring difficulty"
      aria-valuemin={0}
      aria-valuemax={100}
      aria-valuenow={score ?? undefined}
      aria-valuetext={score == null ? 'Unknown' : `${text}, ${score} out of 100`}
      className={`${width} shrink-0`}
    >
      <svg viewBox="0 0 100 58" className="w-full h-auto" aria-hidden>
        <path
          d={`M 10 50 A ${R} ${R} 0 0 1 90 50`}
          fill="none"
          stroke="var(--line)"
          strokeWidth="10"
          strokeLinecap="round"
        />
        {score != null && value > 0 && (
          <path
            d={`M 10 50 A ${R} ${R} 0 0 1 90 50`}
            fill="none"
            stroke={color}
            strokeWidth="10"
            strokeLinecap="round"
            strokeDasharray={`${(value / 100) * HALF} ${HALF}`}
          />
        )}
        <text
          x="50"
          y="48"
          textAnchor="middle"
          fontSize={size === 'lg' ? 20 : 22}
          fontWeight="900"
          fill="var(--fg)"
          style={{ fontVariantNumeric: 'tabular-nums' }}
        >
          {score ?? '—'}
        </text>
      </svg>
      <p className={`text-center font-bold ${size === 'lg' ? 'text-base' : 'text-xs'}`} style={{ color }}>
        {text}
      </p>
    </div>
  );
}

/** A small coloured chip for tables. */
export function DifficultyChip({ label, score }: { label: Difficulty | null; score?: number | null }) {
  const color = label ? DIFFICULTY_COLOR[label] : 'var(--muted)';
  return (
    <span className="pill whitespace-nowrap" style={{ color, borderColor: color }}>
      {label ? DIFFICULTY_LABEL[label] : 'Unknown'}
      {score != null ? <span className="tabular-nums opacity-80"> · {score}</span> : null}
    </span>
  );
}
