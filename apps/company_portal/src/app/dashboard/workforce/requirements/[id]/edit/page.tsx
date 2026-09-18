import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { createClient, getCompanyContext, getUser } from '@/lib/supabase/server';
import { UUID_RE } from '@/lib/talent';
import { onlyWf, wfCan } from '@/lib/workforce';
import { Notice, PageHeader } from '../../../ui';
import { loadRequirementOptions } from '../../form-data';
import RequirementForm from '../../requirement-form';

export const metadata: Metadata = { title: 'Edit requirement · Workforce · Omelo' };

const s = (v: string | number | null | undefined) => (v == null ? '' : String(v));

export default async function EditRequirementPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID_RE.test(id)) notFound();
  const ctx = (await getCompanyContext())!;
  const [supabase, user] = await Promise.all([createClient(), getUser()]);
  const { data: r } = await supabase.from('workforce_requirements').select('*').eq('id', id).eq('company_id', ctx.companyId).maybeSingle();
  if (!r) notFound();
  const back = { href: `/dashboard/workforce/requirements/${id}`, label: r.title };
  if (!wfCan(ctx, 'manage_workforce')) {
    return (
      <div className="space-y-5">
        <PageHeader title="Edit requirement" back={back} />
        <Notice title="Not available to your role">{onlyWf(ctx.kind, 'manage_workforce', 'edit requirements')}</Notice>
      </div>
    );
  }
  const o = await loadRequirementOptions(supabase, ctx, user ? { id: user.id, email: user.email ?? null } : null);
  return (
    <div className="space-y-5 max-w-4xl">
      <PageHeader title="Edit requirement" back={back} />
      <RequirementForm
        kind={ctx.kind}
        sources={o.sources}
        professions={o.professions}
        areas={o.areas}
        policies={o.policies}
        supervisors={o.supervisors}
        timeZones={o.timeZones}
        editId={id}
        initial={{
          job_id: r.job_id,
          job_order_id: r.job_order_id,
          title: r.title,
          profession_id: r.profession_id,
          openings: r.openings,
          location_id: r.location_id,
          location_text: s(r.location_text),
          site_name: s(r.site_name),
          country_code: s(r.country_code),
          currency: s(r.currency),
          timezone: r.timezone,
          employment_type: r.employment_type,
          work_type: r.work_type,
          pay_rate: s(r.pay_rate),
          pay_period: s(r.pay_period),
          pay_frequency: r.pay_frequency,
          hours_per_week: s(r.hours_per_week),
          start_date: s(r.start_date),
          end_date: s(r.end_date),
          check_in_method: r.check_in_method,
          geofence_radius_m: s(r.geofence_radius_m),
          late_grace_minutes: s(r.late_grace_minutes),
          overtime_policy_id: r.overtime_policy_id,
          supervisor_id: r.supervisor_id,
          status: r.status,
          notes: s(r.notes),
        }}
      />
    </div>
  );
}
