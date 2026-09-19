'use client';

import Link from 'next/link';
import { useId, useState, useTransition } from 'react';
import {
  AVAILABILITY,
  AVAILABILITY_LABEL,
  CONSENT_FILTERS,
  CONSENT_FILTER_LABEL,
  type AgencyCard,
  type SearchFilters,
} from '@/lib/agency';
import { WORK_TYPE_LABEL, formatPay } from '@/lib/format';
import { RADII, quotaText, type Pool, type SearchQuota } from '@/lib/talent';
import { PoolDialog } from '../../talent/talent-actions';
import { CardHeader, GlobalChips, Notice, ReasonList, SkillChips } from '../../talent/ui';
import { searchForOrder } from '../actions';
import GlobalFilterFields, {
  EMPTY_GLOBAL_FILTERS,
  activeGlobalFilters,
  globalFilterKeys,
  type GlobalFilterValues,
} from '@/components/global/global-filters';
import { AskConsent, type AgencySummary, type OrderSummary } from '../consent-ui';

export type OrderOption = OrderSummary & { status: string; professionId: string | null };
type Option = { id: string; label: string };
type Failure = { message: string; code?: string };

const isVerificationBlock = (f: Failure) => f.code === '42501' && /verified/i.test(f.message);
const isPlanBlock = (f: Failure) => f.code === '42501' && /plan/i.test(f.message);

function CardExtras({ card }: { card: AgencyCard }) {
  const facts = [
    card.availability ? AVAILABILITY_LABEL[card.availability] ?? card.availability : null,
    card.expectedPay
      ? `Expects ${formatPay({ min: card.expectedPay.amount, period: card.expectedPay.period, currency: card.expectedPay.currency })}`
      : null,
  ].filter(Boolean);
  const trust = [
    card.verifiedEmployers ? `${card.verifiedEmployers} verified employer${card.verifiedEmployers === 1 ? '' : 's'}` : null,
    card.employerConfirmedSkills
      ? `${card.employerConfirmedSkills} skill${card.employerConfirmedSkills === 1 ? '' : 's'} confirmed by employers`
      : null,
  ].filter(Boolean);
  return (
    <div className="space-y-1 text-xs">
      {facts.length > 0 && <p className="break-words">{facts.join(' · ')}</p>}
      {trust.length > 0 && (
        <p className="break-words" style={{ color: 'var(--color-verified)' }}>
          ✓ {trust.join(' · ')}
        </p>
      )}
      {card.previousRelationship && <p className="muted">You have asked this person before.</p>}
    </div>
  );
}

function ResultCard({
  card,
  order,
  agency,
  recruiterName,
  pools,
  onPoolCreated,
  consentBlocked,
  canSave,
}: {
  card: AgencyCard;
  order: OrderOption;
  agency: AgencySummary;
  recruiterName: string | null;
  pools: Pool[];
  onPoolCreated: (p: Pool) => void;
  consentBlocked: string | null;
  canSave: boolean;
}) {
  const [savedIn, setSavedIn] = useState(card.pools);
  const [poolOpen, setPoolOpen] = useState(false);
  const [flash, setFlash] = useState<string | null>(null);
  const savedNames = pools.filter((p) => savedIn.includes(p.id)).map((p) => p.name);

  return (
    <li className="card p-4 space-y-3 min-w-0">
      <CardHeader card={card} />
      <GlobalChips card={card} />
      <SkillChips card={card} />
      <CardExtras card={card} />
      {(card.strengths.length > 0 || card.gaps.length > 0) && (
        <div className="space-y-1">
          <ReasonList items={card.strengths.slice(0, 2)} tone="good" />
          {card.gaps[0] && <ReasonList items={[card.gaps[0]]} tone="gap" />}
        </div>
      )}
      <div className="border-t hairline pt-3 space-y-2">
        <div className="flex flex-wrap gap-2 items-start">
          <AskConsent
            candidate={{ identityId: card.workIdentityId, name: card.name, label: card.label }}
            order={order}
            agency={agency}
            recruiterName={recruiterName}
            existing={card.consent}
            acceptsRequests={card.acceptsRecruiterRequests}
            blockedReason={consentBlocked}
          />
          {canSave && (
            <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setPoolOpen(true)}>
              {savedIn.length ? `Saved · ${savedIn.length === 1 ? '1 pool' : `${savedIn.length} pools`}` : 'Save to pool'}
            </button>
          )}
        </div>
        {savedNames.length > 0 && <p className="text-xs muted break-words">In: {savedNames.join(', ')}</p>}
        {flash && (
          <p className="text-sm" role="status" style={{ color: 'var(--color-verified)' }}>
            {flash}
          </p>
        )}
      </div>
      {poolOpen && (
        <PoolDialog
          open
          onClose={() => setPoolOpen(false)}
          card={card}
          pools={pools}
          savedIn={savedIn}
          onSaved={(pool, created) => {
            setSavedIn((s) => [...s, pool.id]);
            if (created) onPoolCreated(pool);
            setFlash(`Saved to “${pool.name}”. Saving doesn’t let you submit them — ask for their consent.`);
          }}
        />
      )}
    </li>
  );
}

type Form = {
  query: string;
  radius: number;
  professionId: string;
  skillIds: string[];
  minExp: string;
  maxExp: string;
  availability: string[];
  workTypes: string[];
  maxPay: string;
  verifiedOnly: boolean;
  global: GlobalFilterValues;
  consent: string;
  previous: '' | 'yes' | 'no';
  poolId: string;
};

const EMPTY_FORM: Form = {
  query: '',
  radius: 50,
  professionId: '',
  skillIds: [],
  minExp: '',
  maxExp: '',
  availability: [],
  workTypes: [],
  maxPay: '',
  verifiedOnly: false,
  global: EMPTY_GLOBAL_FILTERS,
  consent: 'any',
  previous: '',
  poolId: '',
};

function toFilters(f: Form): SearchFilters {
  const n = (s: string) => (s.trim() && Number.isFinite(Number(s)) ? Number(s) : undefined);
  return {
    query: f.query.trim() || undefined,
    radius_km: f.radius,
    profession_id: f.professionId || undefined,
    skill_ids: f.skillIds.length ? f.skillIds : undefined,
    min_experience_months: n(f.minExp),
    max_experience_months: n(f.maxExp),
    availability: f.availability.length ? f.availability : undefined,
    work_types: f.workTypes.length ? f.workTypes : undefined,
    max_expected_pay_monthly: n(f.maxPay),
    verified_only: f.verifiedOnly || undefined,
    ...globalFilterKeys(f.global),
    consent_status: f.consent !== 'any' ? f.consent : undefined,
    previous_relationship: f.previous === '' ? undefined : f.previous === 'yes',
    pool_id: f.poolId || undefined,
  };
}

/**
 * Recruiter talent search for one job order, with the full filter set.
 * Only people who chose to be visible to recruiters appear (enforced in the
 * database). Every search counts toward the agency's monthly quota.
 */
export default function AgencyTalentSearch({
  orders,
  initialOrderId,
  pools: initialPools,
  professions,
  skills,
  countries,
  languages,
  agency,
  recruiterName,
  canRequest,
  canSave,
}: {
  orders: OrderOption[];
  initialOrderId: string;
  pools: Pool[];
  professions: Option[];
  skills: Option[];
  countries: Option[];
  languages: Option[];
  agency: AgencySummary;
  recruiterName: string | null;
  canRequest: boolean;
  canSave: boolean;
}) {
  const uid = useId();
  const [orderId, setOrderId] = useState(initialOrderId);
  const [form, setForm] = useState<Form>(EMPTY_FORM);
  const [more, setMore] = useState(false);
  const [skillFilter, setSkillFilter] = useState('');
  const [pools, setPools] = useState(initialPools);
  const [shown, setShown] = useState<{ orderId: string; filters: SearchFilters } | null>(null);
  const [results, setResults] = useState<AgencyCard[]>([]);
  const [total, setTotal] = useState(0);
  const [quota, setQuota] = useState<SearchQuota | null>(null);
  const [failure, setFailure] = useState<Failure | null>(null);
  const [pending, start] = useTransition();
  const [loadingMore, setLoadingMore] = useState(false);

  const order = orders.find((o) => o.id === (shown?.orderId ?? orderId)) ?? orders[0];
  const set = <K extends keyof Form>(k: K, v: Form[K]) => setForm((f) => ({ ...f, [k]: v }));
  const toggleIn = (k: 'skillIds' | 'availability' | 'workTypes', v: string) =>
    setForm((f) => ({ ...f, [k]: f[k].includes(v) ? f[k].filter((x) => x !== v) : [...f[k], v] }));

  function run(loadMore: boolean) {
    const params = loadMore && shown ? shown : { orderId, filters: toFilters(form) };
    const offset = loadMore ? results.length : 0;
    setFailure(null);
    setLoadingMore(loadMore);
    start(async () => {
      const res = await searchForOrder({ orderId: params.orderId, filters: params.filters, offset });
      setLoadingMore(false);
      if (!res.ok) return setFailure({ message: res.error, code: res.code });
      setShown(params);
      setTotal(res.data.total);
      setQuota(res.data.quota);
      setResults((prev) => {
        if (!loadMore) return res.data.results;
        const seen = new Set(prev.map((c) => c.workIdentityId));
        return [...prev, ...res.data.results.filter((c) => !seen.has(c.workIdentityId))];
      });
    });
  }

  const blocked = failure && (isVerificationBlock(failure) || isPlanBlock(failure));
  const consentBlocked = !canRequest
    ? 'Only owners, admins, recruiters and sourcers can ask for consent.'
    : order && !['open', 'on_hold'].includes(order.status)
      ? 'Open the job order to ask for consent.'
      : null;
  const shownSkills = skills.filter(
    (s) => form.skillIds.includes(s.id) || !skillFilter.trim() || s.label.toLowerCase().includes(skillFilter.trim().toLowerCase())
  );
  const activeCount =
    [form.professionId, form.minExp, form.maxExp, form.maxPay, form.poolId, form.previous].filter(Boolean).length +
    (form.skillIds.length ? 1 : 0) +
    (form.availability.length ? 1 : 0) +
    (form.workTypes.length ? 1 : 0) +
    (form.verifiedOnly ? 1 : 0) +
    activeGlobalFilters(form.global) +
    (form.consent !== 'any' ? 1 : 0);

  return (
    <div className="space-y-5">
      <form
        className="card p-4 sm:p-5 space-y-4"
        onSubmit={(e) => {
          e.preventDefault();
          run(false);
        }}
      >
        <div className="grid gap-3 sm:grid-cols-[minmax(0,2fr)_minmax(0,2fr)_minmax(0,1fr)] items-end">
          <div className="min-w-0">
            <label className="label" htmlFor={`${uid}order`}>
              For job order
            </label>
            <select
              id={`${uid}order`}
              className="input"
              value={orderId}
              onChange={(e) => {
                setOrderId(e.target.value);
                setResults([]);
                setShown(null);
                setTotal(0);
                setFailure(null);
              }}
            >
              {orders.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.reference} · {o.title} · {o.client}
                </option>
              ))}
            </select>
          </div>
          <div className="min-w-0">
            <label className="label" htmlFor={`${uid}q`}>
              Keywords <span className="muted font-normal">(optional)</span>
            </label>
            <input
              id={`${uid}q`}
              className="input"
              type="search"
              maxLength={80}
              value={form.query}
              placeholder="Skill or title"
              onChange={(e) => set('query', e.target.value)}
            />
          </div>
          <div className="min-w-0">
            <label className="label" htmlFor={`${uid}r`}>
              Within
            </label>
            <select id={`${uid}r`} className="input" value={form.radius} onChange={(e) => set('radius', Number(e.target.value))}>
              {RADII.map((r) => (
                <option key={r} value={r}>
                  {r} km
                </option>
              ))}
            </select>
          </div>
        </div>

        <button type="button" className="text-sm underline muted" aria-expanded={more} onClick={() => setMore((m) => !m)}>
          {more ? 'Hide filters' : `More filters${activeCount ? ` (${activeCount} on)` : ''}`}
        </button>

        {more && (
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3 border-t hairline pt-4">
            <div className="min-w-0">
              <label className="label" htmlFor={`${uid}prof`}>
                Profession
              </label>
              <select id={`${uid}prof`} className="input" value={form.professionId} onChange={(e) => set('professionId', e.target.value)}>
                <option value="">The job order&apos;s</option>
                {professions.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.label}
                  </option>
                ))}
              </select>
            </div>
            <div className="min-w-0 grid grid-cols-2 gap-2">
              <div>
                <label className="label" htmlFor={`${uid}minx`}>
                  Min. experience
                </label>
                <input
                  id={`${uid}minx`}
                  className="input"
                  type="number"
                  min={0}
                  placeholder="months"
                  value={form.minExp}
                  onChange={(e) => set('minExp', e.target.value)}
                />
              </div>
              <div>
                <label className="label" htmlFor={`${uid}maxx`}>
                  Max.
                </label>
                <input
                  id={`${uid}maxx`}
                  className="input"
                  type="number"
                  min={0}
                  placeholder="months"
                  value={form.maxExp}
                  onChange={(e) => set('maxExp', e.target.value)}
                />
              </div>
            </div>
            <div className="min-w-0">
              <label className="label" htmlFor={`${uid}pay`}>
                Expects at most (per month)
              </label>
              <input
                id={`${uid}pay`}
                className="input"
                type="number"
                min={0}
                value={form.maxPay}
                onChange={(e) => set('maxPay', e.target.value)}
              />
            </div>
            <GlobalFilterFields
              value={form.global}
              onChange={(g) => set('global', g)}
              countries={countries}
              languages={languages}
            />
            <div className="min-w-0">
              <label className="label" htmlFor={`${uid}consent`}>
                Consent for this order
              </label>
              <select id={`${uid}consent`} className="input" value={form.consent} onChange={(e) => set('consent', e.target.value)}>
                {CONSENT_FILTERS.map((c) => (
                  <option key={c} value={c}>
                    {CONSENT_FILTER_LABEL[c]}
                  </option>
                ))}
              </select>
            </div>
            <div className="min-w-0">
              <label className="label" htmlFor={`${uid}prev`}>
                Worked with you before
              </label>
              <select
                id={`${uid}prev`}
                className="input"
                value={form.previous}
                onChange={(e) => set('previous', e.target.value as Form['previous'])}
              >
                <option value="">Either</option>
                <option value="yes">Yes — asked before</option>
                <option value="no">No — new to us</option>
              </select>
            </div>
            <div className="min-w-0">
              <label className="label" htmlFor={`${uid}pool`}>
                Only people in pool
              </label>
              <select id={`${uid}pool`} className="input" value={form.poolId} onChange={(e) => set('poolId', e.target.value)}>
                <option value="">Any</option>
                {pools.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                  </option>
                ))}
              </select>
            </div>
            <label className="flex items-center gap-2 text-sm self-end min-h-10">
              <input type="checkbox" checked={form.verifiedOnly} onChange={(e) => set('verifiedOnly', e.target.checked)} />
              Only people with verified work or skills
            </label>
            <fieldset className="min-w-0 sm:col-span-2 lg:col-span-3">
              <legend className="label">Available</legend>
              <div className="flex flex-wrap gap-x-4 gap-y-2">
                {AVAILABILITY.map((a) => (
                  <label key={a} className="text-sm inline-flex items-center gap-1.5">
                    <input
                      type="checkbox"
                      checked={form.availability.includes(a)}
                      onChange={() => toggleIn('availability', a)}
                    />
                    {AVAILABILITY_LABEL[a]}
                  </label>
                ))}
              </div>
            </fieldset>
            <fieldset className="min-w-0 sm:col-span-2 lg:col-span-3">
              <legend className="label">Wants to work</legend>
              <div className="flex flex-wrap gap-x-4 gap-y-2">
                {Object.entries(WORK_TYPE_LABEL).map(([k, l]) => (
                  <label key={k} className="text-sm inline-flex items-center gap-1.5">
                    <input type="checkbox" checked={form.workTypes.includes(k)} onChange={() => toggleIn('workTypes', k)} />
                    {l}
                  </label>
                ))}
              </div>
            </fieldset>
            <fieldset className="min-w-0 sm:col-span-2 lg:col-span-3">
              <legend className="label">
                Must have all these skills{' '}
                {form.skillIds.length > 0 && <span className="muted font-normal">· {form.skillIds.length} chosen</span>}
              </legend>
              <input
                className="input mb-2"
                type="search"
                aria-label="Filter skills"
                placeholder="Filter skills"
                value={skillFilter}
                onChange={(e) => setSkillFilter(e.target.value)}
              />
              <div className="max-h-40 overflow-y-auto surface rounded-lg p-2 flex flex-wrap gap-x-4 gap-y-2">
                {shownSkills.map((s) => (
                  <label key={s.id} className="text-sm inline-flex items-center gap-1.5">
                    <input type="checkbox" checked={form.skillIds.includes(s.id)} onChange={() => toggleIn('skillIds', s.id)} />
                    {s.label}
                  </label>
                ))}
              </div>
            </fieldset>
            <div className="sm:col-span-2 lg:col-span-3">
              <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setForm({ ...EMPTY_FORM, query: form.query, radius: form.radius })}>
                Clear filters
              </button>
            </div>
          </div>
        )}

        <div className="flex flex-wrap items-center gap-3">
          <button className="btn btn-primary w-full sm:w-auto" disabled={pending}>
            {pending && !loadingMore ? 'Searching…' : 'Search'}
          </button>
          <p className="hint !mt-0 flex-1 min-w-[12rem]">
            Each search counts toward your agency&apos;s monthly talent searches. Only people who let recruiters find
            them appear, and names stay short until they consent.
          </p>
        </div>
      </form>

      {failure && isVerificationBlock(failure) && (
        <Notice tone="warn" title="Search opens once Omelo has verified your agency">
          {failure.message}. Until then you can add clients, create job orders and invite your team.
        </Notice>
      )}
      {failure && isPlanBlock(failure) && (
        <Notice tone="warn" title="Talent search is not included in your plan">
          {failure.message}
        </Notice>
      )}
      {failure && !blocked && (
        <div className="card p-4" role="alert" style={{ borderColor: 'var(--color-danger)' }}>
          <p className="text-sm" style={{ color: 'var(--color-danger)' }}>
            {failure.message}
          </p>
        </div>
      )}

      {shown && !blocked && (
        <div className="flex items-baseline gap-3 flex-wrap">
          <h2 className="font-bold flex-1 min-w-0 break-words">
            {total === 0 ? 'No matches' : `${total} candidate${total === 1 ? '' : 's'} for ${order?.title ?? 'this order'}`}
          </h2>
          {quotaText(quota) && <span className="text-xs muted">{quotaText(quota)}</span>}
        </div>
      )}
      {shown && !blocked && total === 0 && (
        <Notice title="Nobody matched">
          Only people who chose to be visible to recruiters appear. Try a wider radius, fewer filters, or another
          profession.
        </Notice>
      )}
      {!shown && !failure && (
        <Notice title="Find people for a job order">
          Search, then ask the people you like for their consent. You can only submit someone after they accept — for
          this job order, for the time and information they agree to.
        </Notice>
      )}

      {results.length > 0 && order && (
        <ul className="grid gap-3 md:grid-cols-2">
          {results.map((c) => (
            <ResultCard
              key={c.workIdentityId}
              card={c}
              order={order}
              agency={agency}
              recruiterName={recruiterName}
              pools={pools}
              onPoolCreated={(p) => setPools((ps) => (ps.some((x) => x.id === p.id) ? ps : [...ps, p]))}
              consentBlocked={consentBlocked}
              canSave={canSave}
            />
          ))}
        </ul>
      )}
      {shown && results.length < total && (
        <div className="flex flex-col items-center gap-1">
          <button type="button" className="btn btn-ghost" onClick={() => run(true)} disabled={pending}>
            {loadingMore ? 'Loading…' : `Show more (${total - results.length} left)`}
          </button>
          {quota?.limit != null && <p className="hint">Loading more uses one search.</p>}
        </div>
      )}

      <p className="text-sm muted">
        Candidates you already asked are on the{' '}
        <Link href={`/dashboard/agency/candidates${order ? `?order=${order.id}` : ''}`} className="underline">
          Candidates
        </Link>{' '}
        page.
      </p>
    </div>
  );
}
