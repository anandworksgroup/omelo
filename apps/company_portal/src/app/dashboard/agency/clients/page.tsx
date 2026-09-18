import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { LINK_STATUS, RELATIONSHIP, RELATIONSHIP_STATUSES, agencyCan, onlyRoles } from '@/lib/agency';
import { loadTeam, peopleOf } from '@/lib/team';
import { ErrorNote, FilterChips, Notice, PageHeader, Pill, Why, qs } from '../ui';
import { NewClientToggle } from './client-form';

export const metadata: Metadata = { title: 'Clients · Omelo' };

export default async function ClientsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const status = typeof sp.status === 'string' && (RELATIONSHIP_STATUSES as readonly string[]).includes(sp.status) ? sp.status : 'all';
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const [clientsRes, ordersRes, team] = await Promise.all([
    supabase
      .from('agency_clients')
      .select('id, name, relationship_status, link_status, industry, locations, owner_id, updated_at')
      .eq('agency_id', ctx.companyId)
      .order('name'),
    supabase.from('job_orders').select('client_id, status').eq('agency_id', ctx.companyId),
    loadTeam(supabase, ctx.companyId, user?.id ?? null, user?.email ?? null),
  ]);

  const people = peopleOf(team.members);
  const nameOf = new Map(people.map((p) => [p.personId, p.label]));
  const all = clientsRes.data ?? [];
  const openByClient = new Map<string, number>();
  for (const o of ordersRes.data ?? [])
    if (o.status === 'open' || o.status === 'on_hold') openByClient.set(o.client_id, (openByClient.get(o.client_id) ?? 0) + 1);
  const rows = status === 'all' ? all : all.filter((c) => c.relationship_status === status);
  const canManage = agencyCan(ctx, 'manage_clients');

  return (
    <div className="space-y-6 max-w-5xl">
      <PageHeader
        title="Clients"
        subtitle="The companies you recruit for. A client already on Omelo can confirm a link, so your submissions go straight into their hiring pipeline."
        action={canManage ? <NewClientToggle people={people} /> : undefined}
      />
      {!canManage && <Why>{onlyRoles('manage_clients', 'add or edit clients')}</Why>}

      <FilterChips
        label="Filter by relationship"
        active={status}
        hrefFor={(v) => `/dashboard/agency/clients${qs({ status: v })}`}
        options={[
          { value: 'all', label: 'All', count: all.length },
          ...RELATIONSHIP_STATUSES.map((s) => ({
            value: s,
            label: RELATIONSHIP[s].label,
            count: all.filter((c) => c.relationship_status === s).length,
          })),
        ]}
      />

      {clientsRes.error ? (
        <ErrorNote label="clients" message={clientsRes.error.message} />
      ) : rows.length === 0 ? (
        <Notice title={all.length ? 'No clients with this status' : 'No clients yet'}>
          {all.length
            ? 'Try another filter.'
            : 'Add the companies you recruit for. Each job order belongs to a client.'}
        </Notice>
      ) : (
        <ul className="grid gap-3 md:grid-cols-2">
          {rows.map((c) => {
            const rel = RELATIONSHIP[c.relationship_status] ?? { label: c.relationship_status, color: 'var(--muted)' };
            const link = LINK_STATUS[c.link_status] ?? LINK_STATUS.unlinked;
            const open = openByClient.get(c.id) ?? 0;
            return (
              <li key={c.id}>
                <Link href={`/dashboard/agency/clients/${c.id}`} className="card p-4 block hover:opacity-90 space-y-2 h-full">
                  <div className="flex items-start gap-2 flex-wrap">
                    <p className="font-bold break-words flex-1 min-w-0">{c.name}</p>
                    <Pill label={rel.label} color={rel.color} />
                  </div>
                  <p className="text-sm muted break-words">
                    {[c.industry, c.locations.slice(0, 3).join(', ') || null].filter(Boolean).join(' · ') || 'No details yet'}
                  </p>
                  <div className="flex flex-wrap gap-2 items-center text-xs">
                    <Pill label={link.label} color={link.color} />
                    <span className="muted">
                      {open} open job order{open === 1 ? '' : 's'}
                      {c.owner_id ? ` · owner: ${nameOf.get(c.owner_id) ?? 'teammate'}` : ''}
                    </span>
                  </div>
                </Link>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
