import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { agencyCan, onlyRoles } from '@/lib/agency';
import { UUID_RE } from '@/lib/talent';
import { ErrorNote, Notice, PageHeader } from '../../ui';
import { loadOrderFormOptions } from '../form-data';
import JobOrderForm from '../job-order-form';

export const metadata: Metadata = { title: 'New job order · Omelo' };

export default async function NewJobOrderPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const wanted = typeof sp.client === 'string' && UUID_RE.test(sp.client) ? sp.client : null;
  const ctx = (await getCompanyContext())!;
  const back = { href: '/dashboard/agency/job-orders', label: 'Job orders' };

  if (!agencyCan(ctx, 'create_job_order'))
    return (
      <div className="space-y-6 max-w-3xl">
        <PageHeader title="New job order" back={back} />
        <Notice title="You cannot create job orders">{onlyRoles('create_job_order', 'create job orders')}</Notice>
      </div>
    );

  const supabase = await createClient();
  const opts = await loadOrderFormOptions(supabase, ctx.companyId);

  return (
    <div className="space-y-6 max-w-3xl">
      <PageHeader
        title="New job order"
        subtitle="A role you are recruiting for on behalf of a client. You become its lead recruiter."
        back={back}
      />
      {opts.error ? (
        <ErrorNote label="your clients" message={opts.error} />
      ) : opts.clients.length === 0 ? (
        <Notice
          title="Add a client first"
          action={
            <Link href="/dashboard/agency/clients" className="btn btn-primary">
              Go to clients
            </Link>
          }
        >
          Every job order belongs to a client with an active relationship.
        </Notice>
      ) : (
        <JobOrderForm
          clients={opts.clients}
          defaultClientId={wanted && opts.clients.some((c) => c.id === wanted) ? wanted : null}
          professions={opts.professions}
          skills={opts.skills}
          areas={opts.areas}
        />
      )}
    </div>
  );
}
