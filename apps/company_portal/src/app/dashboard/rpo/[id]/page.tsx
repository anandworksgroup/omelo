import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { loadTeam, peopleOf } from '@/lib/team';
import { timeAgo } from '@/lib/format';
import {
  RPO_PERMISSION_HELP,
  RPO_PERMISSION_LABEL,
  RPO_RECRUITER_ROLE_LABEL,
  RPO_STATUS_COLOR,
  RPO_STATUS_LABEL,
  enterpriseError,
  parseEngagements,
  parseRpoWork,
  type RpoPermission,
  type RpoScopeType,
} from '@/lib/enterprise';
import { ErrorNote, Pill, Section } from '../../agency/ui';
import {
  EngagementActions,
  PermissionChips,
  RecruiterControls,
  ScopeEditor,
  ToggleRecruiter,
  type RpoScopeOptions,
} from '../rpo-forms';

export const metadata: Metadata = { title: 'RPO engagement · Omelo' };

const PROVIDER_DRAFT_SCOPES: readonly RpoScopeType[] = ['organization', 'profession'];

/**
 * One engagement, read from the same function the list uses, so both sides see
 * exactly what the database says they are part of. The client sets the scope;
 * the provider assigns its own recruiters; either side can pause or end it.
 */
export default async function EngagementPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data, error } = await supabase.rpc('omelo_rpo_engagements', { p_company: ctx.companyId });
  if (error) {
    const e = enterpriseError(error);
    return (
      <div className="space-y-4 max-w-3xl">
        <Link href="/dashboard/rpo" className="text-sm underline muted">
          ← RPO
        </Link>
        <ErrorNote label="this engagement" message={e.text} />
      </div>
    );
  }
  const engagement = parseEngagements(data ?? null).find((e) => e.id === id);
  if (!engagement) notFound();

  const isClientSide = engagement.side === 'client';
  const canManage = ctx.roles.some((r) => r === 'owner' || r === 'admin');
  // The client decides what an engagement reaches; a provider may only narrow its own draft.
  const canEditScope = canManage && (isClientSide || engagement.status === 'draft');
  const allowedScopeTypes = isClientSide ? undefined : PROVIDER_DRAFT_SCOPES;

  // The client can offer its own structure; the provider cannot read it.
  const [unitsRes, deptsRes, locsRes, jobsRes, profsRes, team, workRes] = await Promise.all([
    isClientSide
      ? supabase.from('business_units').select('id, name').eq('company_id', ctx.companyId).eq('is_active', true).order('name')
      : Promise.resolve({ data: [] as { id: string; name: string }[], error: null }),
    isClientSide
      ? supabase.from('departments').select('id, name').eq('company_id', ctx.companyId).order('name')
      : Promise.resolve({ data: [] as { id: string; name: string }[], error: null }),
    isClientSide
      ? supabase.from('company_locations').select('id, name').eq('company_id', ctx.companyId).order('name')
      : Promise.resolve({ data: [] as { id: string; name: string | null }[], error: null }),
    isClientSide
      ? supabase
          .from('jobs')
          .select('id, title')
          .eq('company_id', ctx.companyId)
          .order('created_at', { ascending: false })
          .limit(200)
      : Promise.resolve({ data: [] as { id: string; title: string }[], error: null }),
    canEditScope
      ? supabase.from('professions').select('id, name').eq('status', 'active').order('name')
      : Promise.resolve({ data: [] as { id: string; name: string }[], error: null }),
    loadTeam(supabase, ctx.companyId, user?.id ?? null, user?.email ?? null),
    supabase.rpc('omelo_rpo_my_work', { p_engagement: id }),
  ]);

  const options: RpoScopeOptions = {
    business_unit: (unitsRes.data ?? []).map((u) => ({ id: u.id, name: u.name })),
    department: (deptsRes.data ?? []).map((d) => ({ id: d.id, name: d.name })),
    location: (locsRes.data ?? []).map((l) => ({ id: l.id, name: l.name ?? 'Unnamed location' })),
    job: (jobsRes.data ?? []).map((j) => ({ id: j.id, name: j.title })),
    profession: (profsRes.data ?? []).map((p) => ({ id: p.id, name: p.name })),
  };

  const people = peopleOf(team.members);
  const personLabel = new Map(people.map((p) => [p.personId, p.label]));
  const work = parseRpoWork(workRes.data ?? null);
  const other = isClientSide ? engagement.provider : engagement.client;
  const color = RPO_STATUS_COLOR[engagement.status] ?? 'var(--muted)';

  return (
    <div className="space-y-6 max-w-3xl">
      <div>
        <Link href="/dashboard/rpo" className="text-sm underline muted">
          ← RPO
        </Link>
        <div className="flex items-start gap-3 mt-3 flex-wrap">
          <h1 className="text-xl sm:text-2xl font-bold flex-1 min-w-0 break-words">{engagement.title}</h1>
          <Pill label={RPO_STATUS_LABEL[engagement.status] ?? engagement.status} color={color} />
        </div>
        <p className="muted text-sm mt-1 break-words">
          {isClientSide ? 'Run for you by' : 'Run by you for'} <strong>{other ?? '—'}</strong>
          {engagement.reference ? ` · ${engagement.reference}` : ''}
          {engagement.startDate ? ` · from ${engagement.startDate}` : ''}
          {engagement.endDate ? ` to ${engagement.endDate}` : ''}
        </p>
      </div>

      {engagement.status === 'pending_approval' && isClientSide && (
        <div className="card p-4 sm:p-5" style={{ borderTop: '3px solid var(--color-warn)' }}>
          <p className="font-semibold">This is a proposal. Nothing of yours has been shared.</p>
          <p className="text-sm muted mt-1 leading-relaxed">
            If you accept, the recruiters listed below reach only what “What this covers” says, and only the things
            under “What they may do”. You can pause or end it at any time.
          </p>
        </div>
      )}

      <Section title="What they may do">
        <PermissionChips permissions={engagement.permissions} />
        <ul className="space-y-1 text-sm">
          {engagement.permissions.map((p) => (
            <li key={p} className="break-words">
              <span className="font-semibold">{RPO_PERMISSION_LABEL[p as RpoPermission] ?? p}</span>
              <span className="muted"> — {RPO_PERMISSION_HELP[p as RpoPermission] ?? 'as agreed'}</span>
            </li>
          ))}
        </ul>
        <p className="hint">
          Nothing outside this list is possible, whatever the screen shows. The database checks every action against
          the engagement.
        </p>
      </Section>

      <Section title="What this covers">
        <ScopeEditor
          engagementId={engagement.id}
          scopes={engagement.scopes}
          options={options}
          canEdit={canEditScope}
          allowedTypes={allowedScopeTypes}
          why={
            isClientSide
              ? 'You decide what an engagement reaches. Remove something and their access to it stops at once.'
              : engagement.status === 'draft'
                ? 'You can suggest the outline while this is a draft. The client sets the detail and confirms it.'
                : 'The client organization sets this. Ask them to change it if it is wrong.'
          }
        />
      </Section>

      <Section
        title={isClientSide ? 'Their recruiters' : 'Your recruiters on this'}
        aside={<span className="text-sm muted">{engagement.recruiters.filter((r) => r.active).length} active</span>}
      >
        {engagement.recruiters.length === 0 ? (
          <p className="text-sm muted">Nobody assigned yet.</p>
        ) : (
          <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
            {engagement.recruiters.map((r) => (
              <li key={r.personId} className={`py-2.5 flex flex-wrap items-center gap-3 ${r.active ? '' : 'opacity-60'}`}>
                <span className="flex-1 min-w-[10rem] text-sm font-semibold break-words">
                  {r.name ?? personLabel.get(r.personId) ?? 'Recruiter'}
                </span>
                <span className="pill">{RPO_RECRUITER_ROLE_LABEL[r.role] ?? r.role}</span>
                {!r.active && <span className="pill">Not on it</span>}
                {!isClientSide && canManage && (
                  <ToggleRecruiter
                    engagementId={engagement.id}
                    personId={r.personId}
                    role={r.role}
                    active={r.active}
                  />
                )}
              </li>
            ))}
          </ul>
        )}
        {!isClientSide && canManage && (
          <RecruiterControls
            engagementId={engagement.id}
            people={people}
            assigned={engagement.recruiters.map((r) => ({ personId: r.personId, role: r.role, active: r.active }))}
          />
        )}
        {isClientSide && (
          <p className="hint">The provider assigns its own people. You decide what the engagement reaches.</p>
        )}
      </Section>

      <Section title="This engagement">
        <EngagementActions engagement={engagement} canManage={canManage} />
      </Section>

      {work.length > 0 && (
        <Section title="Jobs you may work on" aside={<span className="text-sm muted">{work.length}</span>}>
          <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
            {work.map((j) => (
              <li key={j.jobId} className="py-3 flex flex-wrap items-start gap-3">
                <div className="flex-1 min-w-[12rem]">
                  <p className="font-semibold text-sm break-words">
                    <Link href={`/dashboard/rpo/${engagement.id}/jobs/${j.jobId}`} className="hover:underline">
                      {j.title}
                    </Link>
                  </p>
                  <p className="text-xs muted break-words">
                    {j.status}
                    {j.department ? ` · ${j.department}` : ''}
                    {j.locationText ? ` · ${j.locationText}` : ''}
                    {j.publishedAt ? ` · live ${timeAgo(j.publishedAt)}` : ''}
                  </p>
                </div>
                <span className="pill">{j.applicants} applicants</span>
                {j.newApplicants > 0 && <Pill label={`${j.newApplicants} new`} color="var(--color-brand-600)" />}
              </li>
            ))}
          </ul>
        </Section>
      )}

      {workRes.error && <ErrorNote label="your assigned work" message={enterpriseError(workRes.error).text} />}
      {isClientSide && engagement.status === 'active' && (
        <p className="text-sm muted">
          Their work happens in your own pipeline. See it on{' '}
          <Link href="/dashboard/jobs" className="underline">
            Jobs
          </Link>{' '}
          and{' '}
          <Link href="/dashboard/candidates" className="underline">
            Candidates
          </Link>{' '}
          like any other activity.
        </p>
      )}
    </div>
  );
}
