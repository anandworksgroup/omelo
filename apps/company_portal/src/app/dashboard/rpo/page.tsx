import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { timeAgo } from '@/lib/format';
import {
  RPO_PROVIDER_TYPES,
  RPO_STATUS_COLOR,
  RPO_STATUS_LABEL,
  asOrganizationType,
  enterpriseError,
  groupWorkByClient,
  parseEngagements,
  parseRpoWork,
  rpoScopeText,
  type Engagement,
} from '@/lib/enterprise';
import { ErrorNote, Notice, PageHeader, Pill, Section, Tile } from '../agency/ui';
import { NewEngagementForm, PermissionChips } from './rpo-forms';

export const metadata: Metadata = { title: 'RPO · Omelo' };

/**
 * Release 8 — RPO, both sides in one place.
 *
 * A client organization sees the providers running part of its recruiting and
 * answers their proposals. A provider sees its clients and, for the signed-in
 * recruiter, exactly which of the client's jobs they may work on. Everything
 * on this page comes from omelo_rpo_engagements and omelo_rpo_my_work, so it
 * shows only what the engagement actually authorizes.
 */
export default async function RpoPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const [engagementsRes, workRes, companyRes] = await Promise.all([
    supabase.rpc('omelo_rpo_engagements', { p_company: ctx.companyId }),
    supabase.rpc('omelo_rpo_my_work'),
    supabase.from('companies').select('organization_type').eq('id', ctx.companyId).maybeSingle(),
  ]);

  const engagements = parseEngagements(engagementsRes.data ?? null);
  const work = parseRpoWork(workRes.data ?? null);
  const groups = groupWorkByClient(work);
  const orgType = asOrganizationType(companyRes.data?.organization_type);
  const canProvide = RPO_PROVIDER_TYPES.includes(orgType);
  const canManage = ctx.roles.some((r) => r === 'owner' || r === 'admin');

  const asProvider = engagements.filter((e) => e.side === 'provider');
  const asClient = engagements.filter((e) => e.side === 'client');
  const waiting = asClient.filter((e) => e.status === 'pending_approval');
  const activeJobs = work.filter((w) => w.status === 'published').length;

  return (
    <div className="space-y-6 max-w-4xl">
      <PageHeader
        title="RPO"
        subtitle="Recruitment run by one organization inside another's pipeline — only as far as the engagement allows."
      />

      {engagementsRes.error && (
        <ErrorNote label="your engagements" message={enterpriseError(engagementsRes.error).text} />
      )}

      {waiting.length > 0 && (
        <div className="card p-4 sm:p-5" style={{ borderTop: '3px solid var(--color-warn)' }}>
          <p className="font-semibold">
            {waiting.length === 1 ? 'A provider is waiting for your answer' : `${waiting.length} proposals are waiting for you`}
          </p>
          <p className="text-sm muted mt-1 leading-relaxed">
            Nothing of yours is shared until you accept. Open the proposal to see exactly what it would cover and what
            they could do.
          </p>
          <div className="mt-3 flex flex-wrap gap-2">
            {waiting.map((e) => (
              <Link key={e.id} href={`/dashboard/rpo/${e.id}`} className="btn btn-primary" style={{ height: 36 }}>
                {e.title}
              </Link>
            ))}
          </div>
        </div>
      )}

      {work.length > 0 && (
        <div className="grid gap-3 grid-cols-2 sm:grid-cols-3">
          <Tile label="Clients you work for" value={groups.length} />
          <Tile label="Jobs you may work on" value={work.length} />
          <Tile label="Live right now" value={activeJobs} />
        </div>
      )}

      {/* The provider's own clients ---------------------------------- */}
      {(canProvide || asProvider.length > 0) && (
        <Section
          title="My RPO clients"
          aside={<span className="text-sm muted">{asProvider.length}</span>}
        >
          {asProvider.length === 0 ? (
            <p className="text-sm muted">
              No engagements yet. Set one up, decide what it should cover, and send it to the client to confirm.
            </p>
          ) : (
            <ul className="space-y-3">
              {asProvider.map((e) => (
                <EngagementRow key={e.id} engagement={e} other={e.client} />
              ))}
            </ul>
          )}
          {canManage && canProvide && (
            <div className="border-t hairline pt-3">
              <NewEngagementForm />
            </div>
          )}
          {canProvide && !canManage && (
            <p className="text-xs muted">Only an owner or admin sets up a new engagement.</p>
          )}
        </Section>
      )}

      {/* The client's providers -------------------------------------- */}
      {(asClient.length > 0 || !canProvide) && (
        <Section title="Providers working for you" aside={<span className="text-sm muted">{asClient.length}</span>}>
          {asClient.length === 0 ? (
            <p className="text-sm muted">
              Nobody runs recruiting for you on Omelo. A provider sets an engagement up and sends it to you; nothing
              of yours is shared until an owner or admin here accepts it.
            </p>
          ) : (
            <ul className="space-y-3">
              {asClient.map((e) => (
                <EngagementRow key={e.id} engagement={e} other={e.provider} />
              ))}
            </ul>
          )}
        </Section>
      )}

      {/* What the signed-in recruiter may work on --------------------- */}
      <Section title="My work" aside={<span className="text-sm muted">{work.length} jobs</span>}>
        {workRes.error ? (
          <ErrorNote label="your assigned work" message={enterpriseError(workRes.error).text} />
        ) : groups.length === 0 ? (
          <Notice title="Nothing assigned to you">
            When a provider you belong to assigns you to an active engagement, the client jobs it covers appear here —
            and only those.
          </Notice>
        ) : (
          <div className="space-y-5">
            {groups.map((g) => (
              <div key={g.engagementId || g.client} className="space-y-2">
                <div className="flex items-start gap-3 flex-wrap">
                  <p className="font-bold flex-1 min-w-[10rem] break-words">{g.client}</p>
                  <PermissionChips permissions={g.permissions} />
                </div>
                <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
                  {g.jobs.map((j) => (
                    <li key={j.jobId} className="py-3 flex flex-wrap items-start gap-3">
                      <div className="flex-1 min-w-[12rem]">
                        <p className="font-semibold text-sm break-words">
                          <Link href={`/dashboard/rpo/${j.engagementId}/jobs/${j.jobId}`} className="hover:underline">
                            {j.title}
                          </Link>
                        </p>
                        <p className="text-xs muted break-words">
                          {j.status}
                          {j.department ? ` · ${j.department}` : ''}
                          {j.locationText ? ` · ${j.locationText}` : ''}
                          {j.openings ? ` · ${j.openings} opening${j.openings === 1 ? '' : 's'}` : ''}
                          {j.publishedAt ? ` · live ${timeAgo(j.publishedAt)}` : ''}
                        </p>
                      </div>
                      <span className="pill">{j.applicants} applicants</span>
                      {j.newApplicants > 0 && (
                        <Pill label={`${j.newApplicants} new`} color="var(--color-brand-600)" />
                      )}
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        )}
      </Section>
    </div>
  );
}

function EngagementRow({ engagement: e, other }: { engagement: Engagement; other: string | null }) {
  const color = RPO_STATUS_COLOR[e.status] ?? 'var(--muted)';
  return (
    <li className="card p-4 space-y-2">
      <div className="flex flex-wrap items-start gap-3">
        <div className="flex-1 min-w-[12rem]">
          <p className="font-bold break-words">
            <Link href={`/dashboard/rpo/${e.id}`} className="hover:underline">
              {e.title}
            </Link>
          </p>
          <p className="text-xs muted break-words">
            {e.side === 'provider' ? 'Client' : 'Provider'}: {other ?? '—'}
            {e.reference ? ` · ${e.reference}` : ''}
            {e.startDate ? ` · from ${e.startDate}` : ''}
            {e.endDate ? ` to ${e.endDate}` : ''}
          </p>
        </div>
        <Pill label={RPO_STATUS_LABEL[e.status] ?? e.status} color={color} />
      </div>
      <PermissionChips permissions={e.permissions} />
      <p className="text-xs muted break-words">
        Covers: {e.scopes.length === 0 ? 'nothing yet' : e.scopes.map(rpoScopeText).join(' · ')}
      </p>
      <p className="text-xs muted">
        {e.recruiters.filter((r) => r.active).length} assigned recruiter
        {e.recruiters.filter((r) => r.active).length === 1 ? '' : 's'}
        {e.side === 'provider' ? ` · ${e.openJobs} live jobs at the client` : ''}
      </p>
    </li>
  );
}
