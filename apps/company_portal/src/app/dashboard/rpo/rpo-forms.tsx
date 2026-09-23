'use client';

import { useRouter } from 'next/navigation';
import { useId, useState, useTransition } from 'react';
import {
  RPO_PERMISSIONS,
  RPO_PERMISSION_HELP,
  RPO_PERMISSION_LABEL,
  RPO_RECRUITER_ROLES,
  RPO_RECRUITER_ROLE_LABEL,
  RPO_SCOPES,
  RPO_SCOPE_LABEL,
  rpoScopeText,
  type Engagement,
  type RpoPermission,
  type RpoScope,
  type RpoScopeType,
} from '@/lib/enterprise';
import {
  assignRecruiter,
  createEngagement,
  proposeEngagement,
  respondEngagement,
  searchCompanies,
  setEngagementScope,
  setEngagementStatus,
  type CompanyHit,
  type RpoResult,
} from './actions';

export type Person = { personId: string; label: string };
export type ScopePick = { id: string; name: string };
export type RpoScopeOptions = Record<Exclude<RpoScopeType, 'organization'>, ScopePick[]>;

function Line({ text, ok }: { text: string | null; ok?: boolean }) {
  if (!text) return null;
  return (
    <p
      className="text-sm basis-full break-words"
      role={ok ? 'status' : 'alert'}
      style={{ color: ok ? 'var(--color-verified)' : 'var(--color-danger)' }}
    >
      {text}
    </p>
  );
}

function useRun() {
  const router = useRouter();
  const [result, setResult] = useState<{ text: string; ok: boolean } | null>(null);
  const [pending, start] = useTransition();
  const run = (fn: () => Promise<RpoResult>, after?: () => void) => {
    setResult(null);
    start(async () => {
      const res = await fn();
      if (!res.ok) return setResult({ text: res.error, ok: false });
      setResult({ text: res.message ?? 'Done.', ok: true });
      after?.();
      router.refresh();
    });
  };
  return { run, result, pending };
}

/* ------------------------------------------------------------------ */
/* Setting one up                                                      */
/* ------------------------------------------------------------------ */

export function NewEngagementForm() {
  const uid = useId();
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [hits, setHits] = useState<CompanyHit[] | null>(null);
  const [client, setClient] = useState<CompanyHit | null>(null);
  const [title, setTitle] = useState('');
  const [reference, setReference] = useState('');
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [notes, setNotes] = useState('');
  const [permissions, setPermissions] = useState<string[]>(['view_jobs', 'view_candidates']);
  const [result, setResult] = useState<{ text: string; ok: boolean } | null>(null);
  const [searching, startSearch] = useTransition();
  const [saving, startSave] = useTransition();

  const toggle = (p: string) =>
    setPermissions((list) => (list.includes(p) ? list.filter((x) => x !== p) : [...list, p]));

  if (!open)
    return (
      <div className="flex items-center gap-3 flex-wrap">
        <button type="button" className="btn btn-primary" onClick={() => setOpen(true)}>
          Set up an engagement
        </button>
        {result?.ok && <Line text={result.text} ok />}
      </div>
    );

  return (
    <div className="space-y-4">
      <div>
        <label className="label" htmlFor={`${uid}q`}>
          Client organization *
        </label>
        {client ? (
          <div className="flex items-center gap-2 flex-wrap">
            <span className="pill">{client.name}</span>
            <button type="button" className="btn btn-ghost !h-8 !px-2.5 text-xs" onClick={() => setClient(null)}>
              Choose a different one
            </button>
          </div>
        ) : (
          <>
            <div className="flex gap-2 flex-wrap">
              <input
                id={`${uid}q`}
                className="input flex-1 min-w-[12rem]"
                value={query}
                maxLength={80}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Search by name"
              />
              <button
                type="button"
                className="btn btn-ghost"
                disabled={searching || query.trim().length < 2}
                onClick={() => startSearch(async () => setHits(await searchCompanies(query)))}
              >
                {searching ? 'Searching…' : 'Search'}
              </button>
            </div>
            {hits && hits.length === 0 && <p className="hint">No organization on Omelo matches that name.</p>}
            {hits && hits.length > 0 && (
              <ul className="mt-2 divide-y card" style={{ borderColor: 'var(--line)' }}>
                {hits.map((h) => (
                  <li key={h.id} className="p-3 flex items-center gap-3 flex-wrap">
                    <span className="flex-1 min-w-[10rem] text-sm font-semibold break-words">{h.name}</span>
                    <button
                      type="button"
                      className="btn btn-ghost !h-8 !px-2.5 text-xs"
                      onClick={() => {
                        setClient(h);
                        setHits(null);
                      }}
                    >
                      Choose
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </>
        )}
      </div>

      <div className="grid gap-3 sm:grid-cols-2">
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}t`}>
            Title *
          </label>
          <input
            id={`${uid}t`}
            className="input"
            maxLength={160}
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Warehouse hiring, 2026"
          />
        </div>
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}r`}>
            Your reference
          </label>
          <input
            id={`${uid}r`}
            className="input"
            maxLength={60}
            value={reference}
            onChange={(e) => setReference(e.target.value)}
          />
        </div>
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}s`}>
            Starts
          </label>
          <input id={`${uid}s`} type="date" className="input" value={startDate} onChange={(e) => setStartDate(e.target.value)} />
        </div>
        <div className="min-w-0">
          <label className="label" htmlFor={`${uid}e`}>
            Ends
          </label>
          <input id={`${uid}e`} type="date" className="input" value={endDate} onChange={(e) => setEndDate(e.target.value)} />
        </div>
      </div>

      <fieldset>
        <legend className="label">What your recruiters may do</legend>
        <div className="grid gap-2 sm:grid-cols-2">
          {RPO_PERMISSIONS.map((p) => (
            <label key={p} className="flex items-start gap-2 text-sm">
              <input
                type="checkbox"
                className="mt-1"
                checked={permissions.includes(p)}
                onChange={() => toggle(p)}
              />
              <span className="min-w-0">
                <span className="font-semibold">{RPO_PERMISSION_LABEL[p]}</span>
                <span className="block text-xs muted break-words">{RPO_PERMISSION_HELP[p]}</span>
              </span>
            </label>
          ))}
        </div>
      </fieldset>

      <div>
        <label className="label" htmlFor={`${uid}n`}>
          Notes
        </label>
        <textarea
          id={`${uid}n`}
          className="input"
          rows={3}
          maxLength={2000}
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
        />
      </div>

      <p className="hint">
        This creates a draft. The client decides what it covers and confirms it before anyone from your side can see
        anything.
      </p>
      <Line text={result?.text ?? null} ok={result?.ok} />
      <div className="flex gap-2 flex-wrap">
        <button
          type="button"
          className="btn btn-primary"
          disabled={saving || !client || title.trim().length < 2 || permissions.length === 0}
          onClick={() => {
            setResult(null);
            startSave(async () => {
              const res = await createEngagement({
                clientCompanyId: client!.id,
                title,
                reference,
                permissions,
                startDate,
                endDate,
                notes,
              });
              if (!res.ok) return setResult({ text: res.error, ok: false });
              setOpen(false);
              setResult({ text: res.message ?? 'Draft created.', ok: true });
              if (res.id) router.push(`/dashboard/rpo/${res.id}`);
              else router.refresh();
            });
          }}
        >
          {saving ? 'Creating…' : 'Create draft'}
        </button>
        <button type="button" className="btn btn-ghost" onClick={() => setOpen(false)}>
          Cancel
        </button>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Scope                                                               */
/* ------------------------------------------------------------------ */

export function ScopeEditor({
  engagementId,
  scopes,
  options,
  canEdit,
  allowedTypes,
  why,
}: {
  engagementId: string;
  scopes: RpoScope[];
  options: RpoScopeOptions;
  canEdit: boolean;
  /** A provider editing its own draft cannot read the client's structure, so it gets fewer. */
  allowedTypes?: readonly RpoScopeType[];
  why: string;
}) {
  const uid = useId();
  const types = allowedTypes && allowedTypes.length > 0 ? allowedTypes : RPO_SCOPES;
  const [scopeType, setScopeType] = useState<RpoScopeType>(types[0]);
  const [scopeId, setScopeId] = useState('');
  const { run, result, pending } = useRun();

  const list = scopeType === 'organization' ? [] : (options[scopeType] ?? []);

  return (
    <div className="space-y-3">
      {scopes.length === 0 ? (
        <p className="text-sm muted">Nothing yet. Until something is set here, the engagement reaches nothing.</p>
      ) : (
        <ul className="flex flex-wrap gap-2">
          {scopes.map((s) => (
            <li key={`${s.scopeType}-${s.scopeId ?? 'org'}`} className="flex items-center gap-1.5">
              <span className="pill">{rpoScopeText(s)}</span>
              {canEdit && (
                <button
                  type="button"
                  className="btn btn-ghost !h-8 !px-2.5 text-xs"
                  disabled={pending}
                  onClick={() => run(() => setEngagementScope(engagementId, s.scopeType, s.scopeId, false))}
                >
                  Remove
                </button>
              )}
            </li>
          ))}
        </ul>
      )}

      {canEdit && (
        <div className="flex flex-wrap items-end gap-2 border-t hairline pt-3">
          <div className="min-w-[10rem]">
            <label className="label" htmlFor={`${uid}t`}>
              Add
            </label>
            <select
              id={`${uid}t`}
              className="input !h-9 !py-0 text-sm"
              value={scopeType}
              onChange={(e) => {
                setScopeType(e.target.value as RpoScopeType);
                setScopeId('');
              }}
            >
              {types.map((t) => (
                <option key={t} value={t}>
                  {RPO_SCOPE_LABEL[t]}
                </option>
              ))}
            </select>
          </div>
          <div className="min-w-[12rem] flex-1">
            <label className="label" htmlFor={`${uid}i`}>
              Which one
            </label>
            <select
              id={`${uid}i`}
              className="input !h-9 !py-0 text-sm"
              value={scopeId}
              disabled={scopeType === 'organization'}
              onChange={(e) => setScopeId(e.target.value)}
            >
              <option value="">{scopeType === 'organization' ? 'Not needed' : 'Choose…'}</option>
              {list.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.name}
                </option>
              ))}
            </select>
          </div>
          <button
            type="button"
            className="btn btn-ghost !h-9 !px-3 text-sm"
            disabled={pending || (scopeType !== 'organization' && !scopeId)}
            onClick={() =>
              run(
                () =>
                  setEngagementScope(
                    engagementId,
                    scopeType,
                    scopeType === 'organization' ? null : scopeId,
                    true
                  ),
                () => setScopeId('')
              )
            }
          >
            {pending ? 'Saving…' : 'Add'}
          </button>
          <Line text={result?.text ?? null} ok={result?.ok} />
        </div>
      )}
      <p className="hint">{why}</p>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Recruiters                                                          */
/* ------------------------------------------------------------------ */

export function RecruiterControls({
  engagementId,
  people,
  assigned,
}: {
  engagementId: string;
  people: Person[];
  assigned: { personId: string; role: string; active: boolean }[];
}) {
  const uid = useId();
  const [personId, setPersonId] = useState('');
  const [role, setRole] = useState('recruiter');
  const { run, result, pending } = useRun();
  const free = people.filter((p) => !assigned.some((a) => a.personId === p.personId));

  return (
    <div className="space-y-3 border-t hairline pt-3">
      <div className="flex flex-wrap items-end gap-2">
        <div className="min-w-[12rem] flex-1">
          <label className="label" htmlFor={`${uid}p`}>
            Assign someone from your team
          </label>
          <select
            id={`${uid}p`}
            className="input !h-9 !py-0 text-sm"
            value={personId}
            onChange={(e) => setPersonId(e.target.value)}
          >
            <option value="">Choose…</option>
            {free.map((p) => (
              <option key={p.personId} value={p.personId}>
                {p.label}
              </option>
            ))}
          </select>
        </div>
        <div className="min-w-[9rem]">
          <label className="label" htmlFor={`${uid}r`}>
            As
          </label>
          <select
            id={`${uid}r`}
            className="input !h-9 !py-0 text-sm"
            value={role}
            onChange={(e) => setRole(e.target.value)}
          >
            {RPO_RECRUITER_ROLES.map((r) => (
              <option key={r} value={r}>
                {RPO_RECRUITER_ROLE_LABEL[r]}
              </option>
            ))}
          </select>
        </div>
        <button
          type="button"
          className="btn btn-ghost !h-9 !px-3 text-sm"
          disabled={pending || !personId}
          onClick={() => run(() => assignRecruiter(engagementId, personId, role, true), () => setPersonId(''))}
        >
          {pending ? 'Saving…' : 'Assign'}
        </button>
        <Line text={result?.text ?? null} ok={result?.ok} />
      </div>
    </div>
  );
}

export function ToggleRecruiter({
  engagementId,
  personId,
  role,
  active,
}: {
  engagementId: string;
  personId: string;
  role: string;
  active: boolean;
}) {
  const { run, result, pending } = useRun();
  return (
    <span className="inline-flex items-center gap-2 flex-wrap">
      <button
        type="button"
        className="btn btn-ghost !h-8 !px-2.5 text-xs"
        disabled={pending}
        onClick={() => run(() => assignRecruiter(engagementId, personId, role, !active))}
      >
        {pending ? 'Saving…' : active ? 'Take off' : 'Put back on'}
      </button>
      {result && !result.ok && <Line text={result.text} />}
    </span>
  );
}

/* ------------------------------------------------------------------ */
/* Moving an engagement along                                          */
/* ------------------------------------------------------------------ */

export function EngagementActions({
  engagement,
  canManage,
}: {
  engagement: Pick<Engagement, 'id' | 'status' | 'side' | 'scopes'>;
  canManage: boolean;
}) {
  const uid = useId();
  const { run, result, pending } = useRun();
  const [note, setNote] = useState('');
  const { id, status, side } = engagement;

  if (!canManage)
    return (
      <p className="text-sm muted">Only an owner or admin of your organization can change this engagement.</p>
    );

  const buttons: React.ReactNode[] = [];

  if (side === 'provider' && status === 'draft')
    buttons.push(
      <button
        key="propose"
        type="button"
        className="btn btn-primary"
        disabled={pending || engagement.scopes.length === 0}
        onClick={() => run(() => proposeEngagement(id))}
      >
        {pending ? 'Sending…' : 'Send to the client'}
      </button>
    );

  if (side === 'client' && status === 'pending_approval') {
    buttons.push(
      <button
        key="accept"
        type="button"
        className="btn btn-primary"
        disabled={pending}
        onClick={() => run(() => respondEngagement(id, true, note))}
      >
        {pending ? 'Saving…' : 'Accept'}
      </button>,
      <button
        key="decline"
        type="button"
        className="btn btn-ghost"
        style={{ color: 'var(--color-danger)' }}
        disabled={pending}
        onClick={() => run(() => respondEngagement(id, false, note))}
      >
        Decline
      </button>
    );
  }

  if (status === 'active')
    buttons.push(
      <button
        key="pause"
        type="button"
        className="btn btn-ghost"
        disabled={pending}
        onClick={() => run(() => setEngagementStatus(id, 'paused', note))}
      >
        Pause
      </button>
    );

  if (status === 'paused')
    buttons.push(
      <button
        key="resume"
        type="button"
        className="btn btn-primary"
        disabled={pending}
        onClick={() => run(() => setEngagementStatus(id, 'active', note))}
      >
        Resume
      </button>
    );

  if (status === 'active' || status === 'paused')
    buttons.push(
      <button
        key="complete"
        type="button"
        className="btn btn-ghost"
        disabled={pending}
        onClick={() => run(() => setEngagementStatus(id, 'completed', note))}
      >
        Mark completed
      </button>,
      <button
        key="end"
        type="button"
        className="btn btn-ghost"
        style={{ color: 'var(--color-danger)' }}
        disabled={pending}
        onClick={() => run(() => setEngagementStatus(id, 'terminated', note))}
      >
        End now
      </button>
    );

  if (buttons.length === 0)
    return (
      <p className="text-sm muted">
        Nothing to do here: this engagement is {status === 'draft' ? 'a draft on the provider’s side' : status.replace(/_/g, ' ')}.
      </p>
    );

  return (
    <div className="space-y-3">
      <div>
        <label className="label" htmlFor={`${uid}n`}>
          Note <span className="muted font-normal">· kept on the engagement</span>
        </label>
        <textarea
          id={`${uid}n`}
          className="input"
          rows={2}
          maxLength={2000}
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="Optional."
        />
      </div>
      <div className="flex gap-2 flex-wrap">{buttons}</div>
      {side === 'provider' && status === 'draft' && engagement.scopes.length === 0 && (
        <p className="text-sm" style={{ color: 'var(--color-warn)' }}>
          Set what this engagement covers before sending it.
        </p>
      )}
      <Line text={result?.text ?? null} ok={result?.ok} />
    </div>
  );
}

export function PermissionChips({ permissions }: { permissions: string[] }) {
  if (permissions.length === 0) return <span className="pill">Nothing granted</span>;
  return (
    <span className="inline-flex flex-wrap gap-1.5">
      {permissions.map((p) => (
        <span key={p} className="pill" title={RPO_PERMISSION_HELP[p as RpoPermission]}>
          {RPO_PERMISSION_LABEL[p as RpoPermission] ?? p.replace(/_/g, ' ')}
        </span>
      ))}
    </span>
  );
}
