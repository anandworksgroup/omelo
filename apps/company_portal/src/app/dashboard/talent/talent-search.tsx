'use client';

import Link from 'next/link';
import { useId, useState, useTransition } from 'react';
import { RADII, quotaText, type Pool, type SearchQuota, type TalentCard } from '@/lib/talent';
import { searchTalent } from './actions';
import GlobalFilterFields, {
  EMPTY_GLOBAL_FILTERS,
  activeGlobalFilters,
  globalFilterKeys,
  type GlobalFilterValues,
} from '@/components/global/global-filters';

type Option = { id: string; label: string };
import TalentActions, { type JobOption } from './talent-actions';
import { CardHeader, GlobalChips, Notice, ReasonList, SkillChips } from './ui';

type Failure = { message: string; code?: string };

function isVerificationBlock(f: Failure) {
  return f.code === '42501' && /verified/i.test(f.message);
}
function isPlanBlock(f: Failure) {
  return f.code === '42501' && /plan/i.test(f.message);
}

export function NotVerifiedNotice() {
  return (
    <Notice
      tone="warn"
      title="Talent search opens once Omelo has verified your company"
      action={
        <Link href="/dashboard/company" className="btn btn-ghost">
          Company profile
        </Link>
      }
    >
      Workers only let verified employers find them. Keep your company profile complete and contact Omelo to
      get verified; you can search as soon as verification is approved. Until then, post jobs and review
      applications as usual.
    </Notice>
  );
}

export function NotInPlanNotice({ message }: { message?: string }) {
  return (
    <Notice tone="warn" title="Talent search is not included in your plan">
      {message ?? 'Talent search is not included in your plan. Contact Omelo to enable it.'} You can still
      post jobs and receive applications as usual.
    </Notice>
  );
}

function ResultCard({
  card,
  job,
  companyName,
  pools,
  onPoolCreated,
}: {
  card: TalentCard;
  job: JobOption;
  companyName: string;
  pools: Pool[];
  onPoolCreated: (p: Pool) => void;
}) {
  const href = `/dashboard/talent/${card.workIdentityId}?job=${job.id}`;
  const strengths = card.strengths.slice(0, 2);
  const gap = card.gaps[0];
  return (
    <li className="card p-4 space-y-3 min-w-0">
      <CardHeader card={card} href={href} />
      <GlobalChips card={card} />
      <SkillChips card={card} />
      {(strengths.length > 0 || gap) && (
        <div className="space-y-1">
          <ReasonList items={strengths} tone="good" />
          {gap && <ReasonList items={[gap]} tone="gap" />}
        </div>
      )}
      <div className="border-t hairline pt-3">
        <TalentActions
          card={card}
          jobs={[job]}
          jobId={job.id}
          companyName={companyName}
          pools={pools}
          onPoolCreated={onPoolCreated}
          profileHref={href}
          canAct
        />
      </div>
    </li>
  );
}

export default function TalentSearch({
  jobs,
  initialJobId,
  companyName,
  pools: initialPools,
  countries,
  languages,
}: {
  jobs: JobOption[];
  initialJobId: string;
  companyName: string;
  pools: Pool[];
  countries: Option[];
  languages: Option[];
}) {
  const uid = useId();
  const [jobId, setJobId] = useState(initialJobId);
  const [query, setQuery] = useState('');
  const [radius, setRadius] = useState(50);
  const [pools, setPools] = useState(initialPools);
  const [global, setGlobal] = useState<GlobalFilterValues>(EMPTY_GLOBAL_FILTERS);
  const [more, setMore] = useState(false);

  // What is on screen was produced by this search (job + terms), so "Show
  // more" pages through the same one even if the form has been edited.
  const [shown, setShown] = useState<{
    jobId: string;
    query: string;
    radius: number;
    global: GlobalFilterValues;
  } | null>(null);
  const [results, setResults] = useState<TalentCard[]>([]);
  const [total, setTotal] = useState(0);
  const [quota, setQuota] = useState<SearchQuota | null>(null);
  const [failure, setFailure] = useState<Failure | null>(null);
  const [pending, start] = useTransition();
  const [loadingMore, setLoadingMore] = useState(false);

  const job = jobs.find((j) => j.id === (shown?.jobId ?? jobId)) ?? jobs[0];

  function run(more: boolean) {
    const params = more && shown ? shown : { jobId, query: query.trim(), radius, global };
    const offset = more ? results.length : 0;
    setFailure(null);
    setLoadingMore(more);
    start(async () => {
      const res = await searchTalent({
        jobId: params.jobId,
        query: params.query,
        radiusKm: params.radius,
        offset,
        filters: globalFilterKeys(params.global),
      });
      setLoadingMore(false);
      if (!res.ok) {
        setFailure({ message: res.error, code: res.code });
        return;
      }
      setShown(params);
      setTotal(res.data.total);
      setQuota(res.data.quota);
      setResults((prev) => {
        if (!more) return res.data.results;
        const seen = new Set(prev.map((c) => c.workIdentityId));
        return [...prev, ...res.data.results.filter((c) => !seen.has(c.workIdentityId))];
      });
    });
  }

  const blocked = failure && (isVerificationBlock(failure) || isPlanBlock(failure));
  const qText = quotaText(quota);
  const hasMore = shown && results.length < total;

  return (
    <div className="space-y-5">
      <form
        className="card p-4 sm:p-5 grid gap-3 sm:grid-cols-[minmax(0,2fr)_minmax(0,2fr)_minmax(0,1fr)_auto] items-end"
        onSubmit={(e) => {
          e.preventDefault();
          run(false);
        }}
      >
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}job`}>
            For job
          </label>
          <select
            id={`${uid}job`}
            className="input"
            value={jobId}
            onChange={(e) => {
              setJobId(e.target.value);
              setResults([]);
              setShown(null);
              setTotal(0);
              setFailure(null);
            }}
          >
            {jobs.map((j) => (
              <option key={j.id} value={j.id}>
                {j.title}
                {j.location ? ` · ${j.location}` : ''}
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
            value={query}
            maxLength={80}
            placeholder="Skill or title, e.g. tandoor"
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}r`}>
            Within
          </label>
          <select id={`${uid}r`} className="input" value={radius} onChange={(e) => setRadius(Number(e.target.value))}>
            {RADII.map((r) => (
              <option key={r} value={r}>
                {r} km
              </option>
            ))}
          </select>
        </div>
        <button className="btn btn-primary w-full sm:w-auto" disabled={pending}>
          {pending && !loadingMore ? 'Searching…' : 'Search'}
        </button>
        <div className="sm:col-span-4">
          <button type="button" className="text-sm underline muted" aria-expanded={more} onClick={() => setMore((m) => !m)}>
            {more
              ? 'Hide global filters'
              : `Eligibility, relocation and language filters${activeGlobalFilters(global) ? ` (${activeGlobalFilters(global)} on)` : ''}`}
          </button>
        </div>
        {more && (
          <div className="sm:col-span-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3 border-t hairline pt-3">
            <GlobalFilterFields value={global} onChange={setGlobal} countries={countries} languages={languages} />
            <div className="self-end">
              <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setGlobal(EMPTY_GLOBAL_FILTERS)}>
                Clear these filters
              </button>
            </div>
          </div>
        )}
        <p className="hint sm:col-span-4 !mt-0">
          Each search counts toward your company&apos;s monthly talent searches. Results are ranked by how well
          they match the job you pick.
        </p>
      </form>

      {failure && isVerificationBlock(failure) && <NotVerifiedNotice />}
      {failure && isPlanBlock(failure) && <NotInPlanNotice message={failure.message} />}
      {failure && !blocked && (
        <div className="card p-4" role="alert" style={{ borderColor: 'var(--color-danger)' }}>
          <p className="text-sm" style={{ color: 'var(--color-danger)' }}>
            {failure.message}
          </p>
        </div>
      )}

      {shown && !blocked && (
        <div className="flex items-baseline gap-3 flex-wrap">
          <h2 className="font-bold flex-1 min-w-0">
            {total === 0
              ? 'No matches'
              : `${total} candidate${total === 1 ? '' : 's'} for ${job?.title ?? 'this job'}`}
          </h2>
          {qText && <span className="text-xs muted">{qText}</span>}
        </div>
      )}

      {shown && !blocked && total === 0 && (
        <Notice title="Nobody matched this search">
          Only people who chose to be visible to employers appear here, and people who already applied are in
          your pipeline instead. Try a wider radius or fewer keywords.
        </Notice>
      )}

      {!shown && !failure && (
        <Notice title="Find people to invite">
          Pick a job and search. You will see workers whose profiles match it and who chose to be visible to
          employers like you. Names are shortened until they apply.
        </Notice>
      )}

      {results.length > 0 && job && (
        <ul className="grid gap-3 md:grid-cols-2">
          {results.map((c) => (
            <ResultCard
              key={c.workIdentityId}
              card={c}
              job={job}
              companyName={companyName}
              pools={pools}
              onPoolCreated={(p) => setPools((ps) => (ps.some((x) => x.id === p.id) ? ps : [...ps, p]))}
            />
          ))}
        </ul>
      )}

      {hasMore && (
        <div className="flex flex-col items-center gap-1">
          <button type="button" className="btn btn-ghost" onClick={() => run(true)} disabled={pending}>
            {loadingMore ? 'Loading…' : `Show more (${total - results.length} left)`}
          </button>
          {quota?.limit != null && <p className="hint">Loading more uses one search.</p>}
        </div>
      )}
    </div>
  );
}
