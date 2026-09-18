'use client';

import { useRouter } from 'next/navigation';
import { useId, useState, useTransition } from 'react';
import type { Database } from '@/lib/supabase/database.types';
import { setCompanyEntitlements, setCompanyVerification } from './actions';

type Method = Database['public']['Enums']['verification_method'];

const METHODS: { value: Method; label: string }[] = [
  { value: 'manual_admin', label: 'Manual review by Omelo' },
  { value: 'document_review', label: 'Document review' },
  { value: 'domain_email', label: 'Domain email' },
  { value: 'otp', label: 'One-time code' },
  { value: 'employer_confirmation', label: 'Employer confirmation' },
  { value: 'issuer_api', label: 'Issuer API' },
  { value: 'institution_partner', label: 'Institution partner' },
  { value: 'government_api', label: 'Government API' },
  { value: 'third_party_provider', label: 'Third-party provider' },
];

function Feedback({ result }: { result: { ok: boolean; text: string } | null }) {
  if (!result) return null;
  return (
    <p
      className="text-sm basis-full"
      role={result.ok ? 'status' : 'alert'}
      style={{ color: result.ok ? 'var(--color-verified)' : 'var(--color-danger)' }}
    >
      {result.text}
    </p>
  );
}

function Confirm({
  summary,
  onConfirm,
  onCancel,
  pending,
  danger,
}: {
  summary: React.ReactNode;
  onConfirm: () => void;
  onCancel: () => void;
  pending: boolean;
  danger?: boolean;
}) {
  return (
    <div className="card surface p-3 space-y-3 basis-full">
      <div className="text-sm">{summary}</div>
      <div className="flex gap-2 flex-wrap">
        <button
          type="button"
          className="btn btn-primary !h-9 !px-3 text-sm"
          style={danger ? { background: 'var(--color-danger)' } : undefined}
          onClick={onConfirm}
          disabled={pending}
        >
          {pending ? 'Saving…' : 'Confirm'}
        </button>
        <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={onCancel} disabled={pending}>
          Cancel
        </button>
      </div>
    </div>
  );
}

export function VerificationTool({
  companyId,
  companyName,
  isVerified,
}: {
  companyId: string;
  companyName: string;
  isVerified: boolean;
}) {
  const uid = useId();
  const router = useRouter();
  const [method, setMethod] = useState<Method>('manual_admin');
  const [confirming, setConfirming] = useState<boolean | null>(null);
  const [result, setResult] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, start] = useTransition();

  function save(verified: boolean) {
    start(async () => {
      const res = await setCompanyVerification({ companyId, verified, method });
      setConfirming(null);
      setResult(res.ok ? { ok: true, text: res.message } : { ok: false, text: res.error });
      if (res.ok) router.refresh();
    });
  }

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap gap-2 items-end">
        {!isVerified && (
          <div className="flex-1 min-w-[12rem]">
            <label className="label" htmlFor={`${uid}method`}>
              How was it verified?
            </label>
            <select
              id={`${uid}method`}
              className="input"
              value={method}
              onChange={(e) => setMethod(e.target.value as Method)}
            >
              {METHODS.map((m) => (
                <option key={m.value} value={m.value}>
                  {m.label}
                </option>
              ))}
            </select>
          </div>
        )}
        {confirming == null &&
          (isVerified ? (
            <button
              type="button"
              className="btn btn-ghost"
              style={{ color: 'var(--color-danger)' }}
              onClick={() => {
                setResult(null);
                setConfirming(false);
              }}
            >
              Remove verification
            </button>
          ) : (
            <button
              type="button"
              className="btn btn-primary"
              onClick={() => {
                setResult(null);
                setConfirming(true);
              }}
            >
              Verify company
            </button>
          ))}
      </div>
      {confirming != null && (
        <Confirm
          danger={!confirming}
          pending={pending}
          onCancel={() => setConfirming(null)}
          onConfirm={() => save(confirming)}
          summary={
            confirming ? (
              <>
                Mark <strong>{companyName}</strong> as verified by{' '}
                <strong>{METHODS.find((m) => m.value === method)?.label}</strong>? Workers will see the verified
                badge and, with talent search in its plan, the company can search and invite them.
              </>
            ) : (
              <>
                Remove verification from <strong>{companyName}</strong>? Its jobs show “unverified” and talent
                search stops immediately.
              </>
            )
          }
        />
      )}
      <Feedback result={result} />
    </div>
  );
}

export function EntitlementsTool({ companyId, companyName }: { companyId: string; companyName: string }) {
  const uid = useId();
  const [plan, setPlan] = useState('free');
  const [talentSearch, setTalentSearch] = useState(false);
  const [searchQuota, setSearchQuota] = useState('50');
  const [outreachQuota, setOutreachQuota] = useState('20');
  const [validUntil, setValidUntil] = useState('');
  const [confirming, setConfirming] = useState(false);
  const [result, setResult] = useState<{ ok: boolean; text: string } | null>(null);
  const [pending, start] = useTransition();

  const quota = (v: string, unit: string) => (Number(v) > 0 ? `${Number(v)} ${unit}` : 'unlimited');

  function save() {
    start(async () => {
      const res = await setCompanyEntitlements({
        companyId,
        plan,
        talentSearch,
        searchQuotaMonthly: Number(searchQuota || 0),
        outreachQuotaDaily: Number(outreachQuota || 0),
        validUntil: validUntil || null,
      });
      setConfirming(false);
      setResult(res.ok ? { ok: true, text: res.message } : { ok: false, text: res.error });
    });
  }

  return (
    <form
      className="space-y-3"
      onSubmit={(e) => {
        e.preventDefault();
        setResult(null);
        setConfirming(true);
      }}
    >
      <div className="grid gap-3 grid-cols-1 sm:grid-cols-2">
        <div>
          <label className="label" htmlFor={`${uid}plan`}>
            Plan
          </label>
          <input
            id={`${uid}plan`}
            className="input"
            value={plan}
            maxLength={40}
            required
            onChange={(e) => setPlan(e.target.value)}
            placeholder="free, pro, enterprise…"
          />
        </div>
        <div>
          <label className="label" htmlFor={`${uid}until`}>
            Valid until <span className="muted font-normal">(empty = no end)</span>
          </label>
          <input
            id={`${uid}until`}
            className="input"
            type="date"
            value={validUntil}
            onChange={(e) => setValidUntil(e.target.value)}
          />
        </div>
        <div>
          <label className="label" htmlFor={`${uid}sq`}>
            Talent searches per month <span className="muted font-normal">(0 = unlimited)</span>
          </label>
          <input
            id={`${uid}sq`}
            className="input"
            type="number"
            min={0}
            step={1}
            inputMode="numeric"
            value={searchQuota}
            onChange={(e) => setSearchQuota(e.target.value)}
          />
        </div>
        <div>
          <label className="label" htmlFor={`${uid}oq`}>
            Invitations per day <span className="muted font-normal">(0 = unlimited)</span>
          </label>
          <input
            id={`${uid}oq`}
            className="input"
            type="number"
            min={0}
            step={1}
            inputMode="numeric"
            value={outreachQuota}
            onChange={(e) => setOutreachQuota(e.target.value)}
          />
        </div>
      </div>
      <label className="flex items-center gap-2 text-sm">
        <input type="checkbox" checked={talentSearch} onChange={(e) => setTalentSearch(e.target.checked)} />
        Talent search and invitations included
      </label>
      <p className="hint !mt-0">
        Saving replaces the company&apos;s whole plan. Current values are not shown here: only the company&apos;s
        owners and admins can read them.
      </p>
      {confirming ? (
        <Confirm
          pending={pending}
          onCancel={() => setConfirming(false)}
          onConfirm={save}
          summary={
            <>
              Set <strong>{companyName}</strong> to plan <strong>{plan || '—'}</strong>: talent search{' '}
              <strong>{talentSearch ? 'on' : 'off'}</strong>
              {talentSearch && (
                <>
                  , {quota(searchQuota, 'searches / month')}, {quota(outreachQuota, 'invitations / day')}
                </>
              )}
              , {validUntil ? `valid until ${validUntil}` : 'no end date'}.
            </>
          }
        />
      ) : (
        <button className="btn btn-primary">Review and save plan</button>
      )}
      <Feedback result={result} />
    </form>
  );
}
