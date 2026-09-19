'use client';

import { useId, useState, useTransition } from 'react';
import { formatMoney } from '@/lib/format';
import type { Conversion } from '@/lib/global';
import { convertCurrency } from './actions';

/**
 * Small currency converter. Shows the rate, when it took effect and where it
 * came from; seed or unofficial rates are labelled "indicative". Converted
 * figures are for comparison only — pay stays in its original currency.
 */
export default function CurrencyConverter({
  currencies,
  defaultFrom,
  defaultTo,
}: {
  currencies: { code: string; name: string }[];
  defaultFrom: string;
  defaultTo: string;
}) {
  const uid = useId();
  const [amount, setAmount] = useState('1000');
  const [from, setFrom] = useState(defaultFrom);
  const [to, setTo] = useState(defaultTo);
  const [result, setResult] = useState<Conversion | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  function run() {
    const n = Number(amount);
    if (!amount.trim() || !Number.isFinite(n) || n < 0) {
      setError('Enter an amount.');
      return;
    }
    setError(null);
    start(async () => {
      const res = await convertCurrency(n, from, to);
      if (!res.ok) {
        setResult(null);
        setError(res.error);
      } else setResult(res.data);
    });
  }

  const select = (id: string, value: string, onChange: (v: string) => void) => (
    <select id={id} className="input" value={value} onChange={(e) => onChange(e.target.value)}>
      {currencies.map((c) => (
        <option key={c.code} value={c.code}>
          {c.code} · {c.name}
        </option>
      ))}
    </select>
  );

  return (
    <section className="card p-5 space-y-4" aria-label="Currency converter">
      <div>
        <h2 className="font-bold">Currency converter</h2>
        <p className="text-sm muted mt-1">For comparing pay only. Offers and pay stay in their original currency.</p>
      </div>
      <form
        className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_minmax(0,1.3fr)_auto_minmax(0,1.3fr)_auto] items-end"
        onSubmit={(e) => {
          e.preventDefault();
          run();
        }}
      >
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}amt`}>
            Amount
          </label>
          <input
            id={`${uid}amt`}
            className="input"
            type="number"
            min={0}
            step="any"
            inputMode="decimal"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
          />
        </div>
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}from`}>
            From
          </label>
          {select(`${uid}from`, from, setFrom)}
        </div>
        <button
          type="button"
          className="btn btn-ghost !h-10 !px-3"
          aria-label="Swap currencies"
          title="Swap"
          onClick={() => {
            setFrom(to);
            setTo(from);
            setResult(null);
          }}
        >
          ⇄
        </button>
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}to`}>
            To
          </label>
          {select(`${uid}to`, to, setTo)}
        </div>
        <button className="btn btn-primary w-full sm:w-auto" disabled={pending}>
          {pending ? 'Converting…' : 'Convert'}
        </button>
      </form>

      {error && (
        <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
          {error}
        </p>
      )}
      {result && (
        <div className="surface rounded-xl p-4 space-y-1.5" role="status">
          {result.converted == null ? (
            <p className="text-sm">{result.note ?? 'No exchange rate available for this pair.'}</p>
          ) : (
            <>
              <p className="text-lg font-bold break-words">
                {formatMoney(result.amount ?? 0, result.from)} ≈ {formatMoney(result.converted, result.to, { fractionDigits: 2 })}
                {result.indicative && (
                  <span className="pill ml-2 align-middle" style={{ color: 'var(--color-warn)' }}>
                    Indicative
                  </span>
                )}
              </p>
              <p className="text-xs muted break-words">
                1 {result.from} = {result.rate != null ? result.rate.toLocaleString('en-US', { maximumFractionDigits: 6 }) : '—'}{' '}
                {result.to}
                {result.effectiveAt
                  ? ` · effective ${new Date(result.effectiveAt).toLocaleString('en-GB', {
                      day: 'numeric',
                      month: 'short',
                      year: 'numeric',
                      hour: '2-digit',
                      minute: '2-digit',
                      timeZone: 'UTC',
                    })} UTC`
                  : ''}
              </p>
              {result.source && <p className="text-xs muted break-words">Source: {result.source}</p>}
              {result.note && <p className="text-xs muted break-words">{result.note}</p>}
            </>
          )}
        </div>
      )}
    </section>
  );
}
