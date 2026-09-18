import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { agencyCan, onlyRoles } from '@/lib/agency';
import { UUID_RE } from '@/lib/talent';
import { ErrorNote, Notice, PageHeader } from '../../../ui';
import { loadOrderFormOptions } from '../../form-data';
import JobOrderForm from '../../job-order-form';

export const metadata: Metadata = { title: 'Edit job order · Omelo' };

export default async function EditJobOrderPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID_RE.test(id)) notFound();
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const back = { href: `/dashboard/agency/job-orders/${id}`, label: 'Job order' };

  const { data: o, error } = await supabase
    .from('job_orders')
    .select(
      'id, client_id, reference, title, profession_id, openings, location_id, location_text, workplace_type, work_type, shift_types, pay_min, pay_max, pay_period, pay_currency, min_experience_months, required_skill_ids, hard_requirements, description, start_date, closing_date, priority, status, notes, agency_clients ( name )'
    )
    .eq('id', id)
    .eq('agency_id', ctx.companyId)
    .maybeSingle();
  if (error)
    return (
      <div className="space-y-6">
        <PageHeader title="Edit job order" back={back} />
        <ErrorNote label="this job order" message={error.message} />
      </div>
    );
  if (!o) notFound();

  if (!agencyCan(ctx, 'create_job_order'))
    return (
      <div className="space-y-6 max-w-3xl">
        <PageHeader title={`Edit ${o.reference}`} back={back} />
        <Notice title="You cannot edit job orders">{onlyRoles('create_job_order', 'edit job orders')}</Notice>
      </div>
    );

  const opts = await loadOrderFormOptions(supabase, ctx.companyId);
  const clientName = (o.agency_clients as unknown as { name: string } | null)?.name ?? 'Client';
  // The order's own client stays selectable even if the relationship has since ended.
  const clients = opts.clients.some((c) => c.id === o.client_id)
    ? opts.clients
    : [{ id: o.client_id, label: clientName }, ...opts.clients];

  return (
    <div className="space-y-6 max-w-3xl">
      <PageHeader
        title={`Edit ${o.reference}`}
        subtitle="Only owners, admins and the recruiters on this order can save changes."
        back={back}
      />
      <JobOrderForm
        clients={clients}
        defaultClientId={o.client_id}
        professions={opts.professions}
        skills={opts.skills}
        areas={opts.areas}
        initial={{
          id: o.id,
          clientId: o.client_id,
          title: o.title,
          reference: o.reference,
          profession_id: o.profession_id,
          openings: o.openings,
          location_id: o.location_id,
          location_text: o.location_text ?? '',
          workplace_type: o.workplace_type,
          work_type: o.work_type,
          shift_types: o.shift_types,
          pay_min: o.pay_min,
          pay_max: o.pay_max,
          pay_period: o.pay_period,
          pay_currency: o.pay_currency ?? 'INR',
          min_experience_months: o.min_experience_months,
          required_skill_ids: o.required_skill_ids,
          hard_requirements: o.hard_requirements,
          description: o.description ?? '',
          start_date: o.start_date,
          closing_date: o.closing_date,
          priority: o.priority,
          status: o.status,
          notes: o.notes ?? '',
        }}
      />
    </div>
  );
}
