import type { Metadata } from 'next';
import { createClient, getCompanyContext, getUser } from '@/lib/supabase/server';
import { UUID_RE } from '@/lib/talent';
import { onlyWf, wfCan } from '@/lib/workforce';
import { ErrorNote, Notice, PageHeader } from '../../ui';
import { loadRequirementOptions } from '../form-data';
import RequirementForm, { EMPTY_REQUIREMENT } from '../requirement-form';

export const metadata: Metadata = { title: 'New requirement · Workforce · Omelo' };

export default async function NewRequirementPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const ctx = (await getCompanyContext())!;
  const back = { href: '/dashboard/workforce/requirements', label: 'Requirements' };
  if (!wfCan(ctx, 'manage_workforce')) {
    return (
      <div className="space-y-5">
        <PageHeader title="New requirement" back={back} />
        <Notice title="Not available to your role">{onlyWf('manage_workforce', 'create requirements')}</Notice>
      </div>
    );
  }
  const [supabase, user] = await Promise.all([createClient(), getUser()]);
  const o = await loadRequirementOptions(supabase, ctx, user ? { id: user.id, email: user.email ?? null } : null);
  const pre = (k: string) => (typeof sp[k] === 'string' && UUID_RE.test(sp[k] as string) ? (sp[k] as string) : null);
  const initial = {
    ...EMPTY_REQUIREMENT,
    // Either deep link works for any organization now.
    job_id: pre('job'),
    job_order_id: pre('order'),
  };

  return (
    <div className="space-y-5 max-w-4xl">
      <PageHeader
        title="New requirement"
        back={back}
        subtitle="Optionally from one of your jobs or a client job order. Title, place, openings and pay are copied from it unless you change them." 
      />
      {o.error && <ErrorNote label="jobs and job orders" message={o.error} />}
      <RequirementForm
        sources={o.sources}
        professions={o.professions}
        areas={o.areas}
        policies={o.policies}
        supervisors={o.supervisors}
        timeZones={o.timeZones}
        initial={initial}
      />
    </div>
  );
}
