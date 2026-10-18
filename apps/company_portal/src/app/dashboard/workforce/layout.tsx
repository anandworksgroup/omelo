import { redirect } from 'next/navigation';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { onlyWf, parseClientWorkforce, wfCan } from '@/lib/workforce';
import WorkforceTabs from './tabs';
import { Notice } from './ui';

/**
 * Workforce section, shared by employers and agencies. Convenience routing
 * only: every read goes through RLS and every write through a function that
 * checks the role again.
 */
export default async function WorkforceLayout({ children }: { children: React.ReactNode }) {
  const ctx = await getCompanyContext();
  if (!ctx) redirect('/onboarding');
  const canView = wfCan(ctx, 'view');
  // "At your sites" appears for any organization that actually hosts workers
  // placed by someone else — the RPC answers that, not the business type.
  let hostsAgencyWorkers = false;
  if (canView) {
    const supabase = await createClient();
    const { data } = await supabase.rpc('omelo_client_workforce', { p_company: ctx.companyId });
    hostsAgencyWorkers = parseClientWorkforce(data ?? null).length > 0;
  }
  return (
    <div className="space-y-5">
      <WorkforceTabs
        kind={ctx.kind}
        canPay={wfCan(ctx, 'manage_pay')}
        canApprove={wfCan(ctx, 'approve_time')}
        showSites={hostsAgencyWorkers}
      />
      {canView ? (
        children
      ) : (
        <Notice title="Workforce is not available to your role">{onlyWf('view', 'see the workforce')}</Notice>
      )}
    </div>
  );
}
