import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { LINK_STATUS, RELATIONSHIP, agencyCan, onlyRoles, parseSubmissions } from '@/lib/agency';
import { timeAgo } from '@/lib/format';
import { UUID_RE } from '@/lib/talent';
import { loadTeam, peopleOf } from '@/lib/team';
import { ErrorNote, OrderStatusPill, PageHeader, Pill, PriorityPill, Section, SubmissionPill, Why } from '../../ui';
import { DeleteClient, EditClientToggle } from '../client-form';
import { Contacts, LinkCompany } from './client-parts';

export const metadata: Metadata = { title: 'Client · Omelo' };

export default async function ClientPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID_RE.test(id)) notFound();
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: client, error } = await supabase
    .from('agency_clients')
    .select(
      'id, name, relationship_status, link_status, client_company_id, requested_company_id, owner_id, industry, website, locations, departments, notes, created_at'
    )
    .eq('id', id)
    .eq('agency_id', ctx.companyId)
    .maybeSingle();
  if (error)
    return (
      <div className="space-y-4">
        <PageHeader title="Client" back={{ href: '/dashboard/agency/clients', label: 'Clients' }} />
        <ErrorNote label="this client" message={error.message} />
      </div>
    );
  if (!client) notFound();

  const linkedId = client.client_company_id ?? client.requested_company_id;
  const [contactsRes, ordersRes, subsRes, companyRes, team] = await Promise.all([
    supabase
      .from('agency_client_contacts')
      .select('id, name, title, email, phone, is_primary, notes')
      .eq('client_id', id)
      .order('is_primary', { ascending: false })
      .order('name'),
    supabase
      .from('job_orders')
      .select('id, reference, title, status, priority, openings, client_job_id, created_at')
      .eq('client_id', id)
      .order('created_at', { ascending: false }),
    supabase.rpc('omelo_agency_submissions', { p_agency: ctx.companyId }),
    linkedId
      ? supabase.from('companies').select('display_name, is_verified').eq('id', linkedId).maybeSingle()
      : Promise.resolve({ data: null }),
    loadTeam(supabase, ctx.companyId, user?.id ?? null, user?.email ?? null),
  ]);

  const orders = ordersRes.data ?? [];
  const orderIds = new Set(orders.map((o) => o.id));
  const submissions = parseSubmissions(subsRes.data ?? null).filter((s) => orderIds.has(s.jobOrderId));
  const people = peopleOf(team.members);
  const owner = client.owner_id ? people.find((p) => p.personId === client.owner_id)?.label ?? 'A teammate' : null;
  const rel = RELATIONSHIP[client.relationship_status] ?? { label: client.relationship_status, color: 'var(--muted)' };
  const link = LINK_STATUS[client.link_status] ?? LINK_STATUS.unlinked;
  const canManage = agencyCan(ctx, 'manage_clients');
  const canAdmin = agencyCan(ctx, 'manage_agency');
  const canCreateOrder = agencyCan(ctx, 'create_job_order');

  return (
    <div className="space-y-6 max-w-5xl">
      <PageHeader
        back={{ href: '/dashboard/agency/clients', label: 'Clients' }}
        title={client.name}
        subtitle={
          <span className="inline-flex flex-wrap gap-2 items-center">
            <Pill label={rel.label} color={rel.color} />
            <Pill label={link.label} color={link.color} />
            {client.industry && <span>{client.industry}</span>}
          </span>
        }
        action={
          canManage ? (
            <EditClientToggle
              people={people}
              initial={{
                id: client.id,
                name: client.name,
                relationshipStatus: client.relationship_status,
                ownerId: client.owner_id,
                industry: client.industry,
                website: client.website,
                locations: client.locations,
                departments: client.departments,
                notes: client.notes,
              }}
            />
          ) : undefined
        }
      />
      {!canManage && <Why>{onlyRoles('manage_clients', 'edit clients')}</Why>}

      <div className="grid gap-6 lg:grid-cols-3 items-start">
        <div className="space-y-6 lg:col-span-2 min-w-0">
          <Section
            title="Job orders"
            aside={
              canCreateOrder && client.relationship_status !== 'ended' ? (
                <Link href={`/dashboard/agency/job-orders/new?client=${client.id}`} className="btn btn-primary !h-9 !px-3 text-sm">
                  New job order
                </Link>
              ) : undefined
            }
          >
            {client.relationship_status === 'ended' && (
              <Why>This relationship has ended, so no new job orders can be created for it.</Why>
            )}
            {ordersRes.error ? (
              <ErrorNote label="job orders" message={ordersRes.error.message} />
            ) : orders.length === 0 ? (
              <p className="text-sm muted">No job orders for this client yet.</p>
            ) : (
              <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
                {orders.map((o) => (
                  <li key={o.id} className="py-2.5 flex items-center gap-2 flex-wrap">
                    <div className="flex-1 min-w-[10rem]">
                      <Link href={`/dashboard/agency/job-orders/${o.id}`} className="font-semibold text-sm hover:underline break-words">
                        {o.title}
                      </Link>
                      <p className="text-xs muted">
                        {o.reference} · {o.openings} opening{o.openings === 1 ? '' : 's'} ·{' '}
                        {o.client_job_id ? 'connected to their job' : 'not connected'}
                      </p>
                    </div>
                    <PriorityPill priority={o.priority} />
                    <OrderStatusPill status={o.status} />
                  </li>
                ))}
              </ul>
            )}
          </Section>

          <Section title="Submission history">
            {subsRes.error ? (
              <ErrorNote label="submissions" message={subsRes.error.message} />
            ) : submissions.length === 0 ? (
              <p className="text-sm muted">You have not submitted anyone to this client yet.</p>
            ) : (
              <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
                {submissions.map((s) => (
                  <li key={s.id} className="py-2.5 flex items-center gap-2 flex-wrap">
                    <div className="flex-1 min-w-[10rem]">
                      <Link href={`/dashboard/agency/submissions/${s.id}`} className="font-semibold text-sm hover:underline break-words">
                        {s.candidate.name}
                      </Link>
                      <p className="text-xs muted break-words">
                        {s.position} · {s.jobOrder} · {timeAgo(s.submittedAt)}
                        {s.recruiter ? ` · by ${s.recruiter}` : ''}
                      </p>
                    </div>
                    <SubmissionPill status={s.status} />
                  </li>
                ))}
              </ul>
            )}
          </Section>
        </div>

        <div className="space-y-6 min-w-0">
          <Section title="On Omelo">
            <LinkCompany
              clientId={client.id}
              linkStatus={client.link_status}
              companyName={companyRes.data?.display_name ?? null}
              canRequest={canManage}
              canEnd={canAdmin}
            />
            {client.link_status === 'confirmed' && !canAdmin && (
              <Why>Only owners and admins (or the client) can end the link.</Why>
            )}
          </Section>

          <Section title="Contacts">
            {contactsRes.error ? (
              <ErrorNote label="contacts" message={contactsRes.error.message} />
            ) : (
              <Contacts
                clientId={client.id}
                canEdit={canManage}
                contacts={(contactsRes.data ?? []).map((c) => ({
                  id: c.id,
                  name: c.name,
                  title: c.title,
                  email: c.email,
                  phone: c.phone,
                  isPrimary: c.is_primary,
                  notes: c.notes,
                }))}
              />
            )}
          </Section>

          <Section title="Details">
            <dl className="text-sm grid grid-cols-[auto_1fr] gap-x-3 gap-y-1.5">
              <dt className="muted">Owner</dt>
              <dd className="break-words">{owner ?? 'Nobody yet'}</dd>
              <dt className="muted">Website</dt>
              <dd className="break-all">
                {client.website ? (
                  <a href={client.website} target="_blank" rel="noopener noreferrer" className="underline">
                    {client.website.replace(/^https?:\/\//, '')}
                  </a>
                ) : (
                  '—'
                )}
              </dd>
              <dt className="muted">Locations</dt>
              <dd className="break-words">{client.locations.join(', ') || '—'}</dd>
              <dt className="muted">Departments</dt>
              <dd className="break-words">{client.departments.join(', ') || '—'}</dd>
              <dt className="muted">Added</dt>
              <dd>{timeAgo(client.created_at)}</dd>
            </dl>
            {client.notes && <p className="text-sm whitespace-pre-line break-words surface rounded-lg p-3">{client.notes}</p>}
          </Section>

          {canAdmin && (
            <Section title="Delete">
              <p className="text-sm muted">
                Prefer setting the relationship to <strong>Ended</strong>: deleting removes the client, its job orders
                and the consent records attached to them.
              </p>
              <DeleteClient clientId={client.id} name={client.name} />
            </Section>
          )}
        </div>
      </div>
    </div>
  );
}
