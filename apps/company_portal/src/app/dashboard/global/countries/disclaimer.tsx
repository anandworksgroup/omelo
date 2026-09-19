/** The banner every country-guide page carries. */
export default function NotLegalAdvice({ text }: { text?: string | null }) {
  return (
    <div className="card p-4" role="note" style={{ borderLeft: '4px solid var(--color-warn)' }}>
      <p className="font-semibold text-sm" style={{ color: 'var(--color-warn)' }}>
        Information only — not legal advice
      </p>
      <p className="text-sm muted mt-1 leading-relaxed">
        {text ??
          'Summaries of official sources, linked so you can check them. Rules change; confirm with the official source or a licensed adviser before acting.'}
      </p>
    </div>
  );
}
