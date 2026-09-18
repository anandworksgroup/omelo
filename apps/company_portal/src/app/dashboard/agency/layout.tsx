import { redirect } from 'next/navigation';
import { getCompanyContext, getMemberships } from '@/lib/supabase/server';
import SwitchPrompt from './switch-prompt';

/**
 * Agency pages only make sense in an agency workspace. Convenience routing
 * only: every read below goes through RLS / agency-scoped RPCs that refuse
 * non-members anyway.
 *
 * A notification can deep-link here while the user is working in another
 * company; if they belong to an agency, offer to switch instead of bouncing.
 */
export default async function AgencyLayout({ children }: { children: React.ReactNode }) {
  const ctx = await getCompanyContext();
  if (!ctx) redirect('/onboarding');
  if (ctx.kind !== 'agency') {
    const agencies = (await getMemberships()).filter((m) => m.kind === 'agency');
    if (agencies.length === 0) redirect('/dashboard');
    return <SwitchPrompt agencies={agencies.map((a) => ({ id: a.companyId, name: a.companyName }))} current={ctx.companyName} />;
  }
  return children;
}
