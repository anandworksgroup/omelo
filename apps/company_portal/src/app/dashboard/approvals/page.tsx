import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { ROLE_HELP, roleLabel } from '@/lib/agency';
import { timeAgo } from '@/lib/format';
import {
  APPROVAL_ENTITIES,
  APPROVAL_ENTITY_LABEL,
  GRANT_SCOPE_LABEL,
  approvalHref,
  enterpriseError,
  parseApprovalStatus,
  parseMyApprovals,
  type ApprovalEntity,
  type GrantScope,
} from '@/lib/enterprise';
import { ApprovalChain, ApprovalStatusPill } from '@/components/approvals/chain';
import { DecideControls } from '@/components/approvals/controls';
import { ErrorNote, Notice, PageHeader, Section } from '../agency/ui';
import WorkflowEditor, { type WorkflowValue } from './workflow-editor';

export const metadata: Metadata = { title: 'Approvals · Omelo' };

const TABS = [
  { key: 'mine', label: 'Waiting for me' },
  { key: 'workflow', label: 'Workflow' },
] as const;

/** How many chains to draw next to the waiting list before we stop asking. */
const CHAIN_LIMIT = 12;

export default async function ApprovalsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const ctx = (await getCompanyContext())!;
  const canManage = ctx.roles.some((r) => r === 'owner' || r === 'admin');
  const wanted = typeof sp.tab === 'string' ? sp.tab : 'mine';
  const tab: 'mine' | 'workflow' = wanted === 'workflow' && canManage ? 'workflow' : 'mine';

  const supabase = await createClient();
  const [mineRes, workflowsRes, stepsRes] = await Promise.all([
    supabase.rpc('omelo_my_approvals', { p_company: ctx.companyId }),
    supabase
      .from('approval_workflows')
      .select('id, entity_type, name, is_active, updated_at')
      .eq('company_id', ctx.companyId)
      .order('entity_type'),
    supabase.from('approval_steps').select('id, workflow_id, position, name, approver_role, approver_scope, required_approvals'),
  ]);

  const tasks = parseMyApprovals(mineRes.data ?? null);
  const chains = await Promise.all(
    tasks.slice(0, CHAIN_LIMIT).map(async (t) => {
      const { data } = await supabase.rpc('omelo_approval_status', {
        p_entity_type: t.entityType,
        p_entity_id: t.entityId,
      });
      return [t.requestId, parseApprovalStatus(data ?? null)?.request ?? null] as const;
    })
  );
  const chainByRequest = new Map(chains);

  const workflows = workflowsRes.data ?? [];
  const allSteps = stepsRes.data ?? [];
  const workflowFor = (entity: ApprovalEntity): WorkflowValue | null => {
    // The active chain if there is one, otherwise the most recently touched.
    const rows = workflows.filter((w) => w.entity_type === entity);
    const w = rows.find((r) => r.is_active) ?? rows[0];
    if (!w) return null;
    return {
      id: w.id,
      name: w.name,
      isActive: w.is_active,
      steps: allSteps
        .filter((s) => s.workflow_id === w.id)
        .sort((a, b) => a.position - b.position)
        .map((s) => ({
          name: s.name,
          approverRole: s.approver_role,
          approverScope: s.approver_scope,
          requiredApprovals: s.required_approvals,
        })),
    };
  };

  const roles = ROLE_HELP.map((h) => h.role);
  const tabsToShow = canManage ? TABS : TABS.filter((t) => t.key === 'mine');

  return (
    <div className="space-y-6 max-w-3xl">
      <PageHeader
        title="Approvals"
        subtitle="What is waiting for your decision, and the chain this organization asks things to go through."
      />

      <nav aria-label="Approvals" className="flex gap-1 overflow-x-auto -mx-4 px-4 sm:mx-0 sm:px-0 border-b hairline">
        {tabsToShow.map((t) => {
          const on = t.key === tab;
          return (
            <Link
              key={t.key}
              href={`/dashboard/approvals?tab=${t.key}`}
              aria-current={on ? 'page' : undefined}
              className="px-3 py-2 text-sm font-semibold whitespace-nowrap border-b-2 -mb-px"
              style={
                on
                  ? { borderColor: 'var(--color-brand-600)', color: 'var(--color-brand-600)' }
                  : { borderColor: 'transparent', color: 'var(--muted)' }
              }
            >
              {t.label}
              {t.key === 'mine' && tasks.length > 0 ? (
                <span className="ml-1.5 pill" style={{ color: 'var(--color-warn)', borderColor: 'var(--color-warn)' }}>
                  {tasks.length}
                </span>
              ) : null}
            </Link>
          );
        })}
      </nav>

      {tab === 'mine' ? (
        <div className="space-y-4">
          {mineRes.error ? (
            <ErrorNote label="your approvals" message={enterpriseError(mineRes.error).text} />
          ) : tasks.length === 0 ? (
            <Notice title="Nothing is waiting for you">
              When a job, workforce requirement or offer reaches a step your role approves, it appears here. You never
              approve something you asked for yourself.
            </Notice>
          ) : (
            <ul className="space-y-3">
              {tasks.map((t) => {
                const href = approvalHref(t.entityType, t.entityId);
                const chain = chainByRequest.get(t.requestId) ?? null;
                return (
                  <li key={t.requestId} className="card p-4 sm:p-5 space-y-3">
                    <div className="flex flex-wrap items-start gap-3">
                      <div className="flex-1 min-w-[12rem]">
                        <p className="font-bold break-words">
                          {href ? (
                            <Link href={href} className="hover:underline">
                              {t.title ?? APPROVAL_ENTITY_LABEL[t.entityType as ApprovalEntity] ?? t.entityType}
                            </Link>
                          ) : (
                            (t.title ?? t.entityType)
                          )}
                        </p>
                        <p className="text-xs muted break-words">
                          {APPROVAL_ENTITY_LABEL[t.entityType as ApprovalEntity] ?? t.entityType} · step {t.position}:{' '}
                          {t.step} · approved by {roleLabel(t.role)} · asked {timeAgo(t.requestedAt)}
                        </p>
                      </div>
                      <ApprovalStatusPill status="pending" />
                    </div>

                    {t.note && <p className="text-sm break-words">“{t.note}”</p>}

                    {chain && (
                      <div className="border-t hairline pt-3">
                        <ApprovalChain request={chain} />
                      </div>
                    )}

                    <div className="border-t hairline pt-3">
                      <DecideControls requestId={t.requestId} />
                    </div>
                  </li>
                );
              })}
            </ul>
          )}
          {tasks.length > CHAIN_LIMIT && (
            <p className="hint">
              Showing the full chain for the first {CHAIN_LIMIT}. Open an item to see the rest of its steps.
            </p>
          )}
        </div>
      ) : (
        <div className="space-y-6">
          <p className="text-sm muted leading-relaxed">
            Describe your own process. Each step names the role that approves it and the part of the organization that
            role acts for — {Object.values(GRANT_SCOPE_LABEL).join(', ').toLowerCase()}. One chain can be switched on
            per kind of thing at a time.
          </p>
          {workflowsRes.error && (
            <ErrorNote label="your approval chains" message={enterpriseError(workflowsRes.error).text} />
          )}
          {stepsRes.error && <ErrorNote label="the steps" message={enterpriseError(stepsRes.error).text} />}
          {APPROVAL_ENTITIES.map((entity) => {
            const w = workflowFor(entity);
            return (
              <Section
                key={entity}
                title={APPROVAL_ENTITY_LABEL[entity]}
                aside={
                  <span
                    className="pill"
                    style={
                      w?.isActive
                        ? { color: 'var(--color-verified)', borderColor: 'var(--color-verified)' }
                        : undefined
                    }
                  >
                    {w ? (w.isActive ? 'On' : 'Off') : 'No chain yet'}
                  </span>
                }
              >
                <WorkflowEditor entityType={entity} workflow={w} roles={roles} />
              </Section>
            );
          })}
          <p className="hint">
            Scope words mean the same thing here as on People &amp; access:{' '}
            {(Object.keys(GRANT_SCOPE_LABEL) as GrantScope[]).map((g) => GRANT_SCOPE_LABEL[g]).join(' · ')}. A step
            approver must reach the part of the organization the thing belongs to, or the database refuses their
            decision.
          </p>
        </div>
      )}
    </div>
  );
}
