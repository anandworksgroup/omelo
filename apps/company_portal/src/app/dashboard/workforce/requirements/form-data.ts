import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/lib/supabase/database.types';
import { loadTeam, peopleOf } from '@/lib/team';

export type Option = { id: string; label: string };

/**
 * Where a requirement comes from.
 *
 * It used to be one list or the other, chosen by company kind: job orders for
 * an agency, jobs for an employer. An organization that hires for itself AND
 * recruits for clients does both, so it gets both, and what the user picks
 * decides which field the requirement carries.
 */
export type SourceOption = Option & { type: 'job' | 'job_order' };

/** Every IANA zone the server knows (falls back to a short list). */
export function timeZones(): string[] {
  const intl = Intl as unknown as { supportedValuesOf?: (k: string) => string[] };
  try {
    const all = intl.supportedValuesOf?.('timeZone');
    if (all?.length) return all.includes('UTC') ? all : ['UTC', ...all];
  } catch {
    /* older runtimes */
  }
  return ['UTC', 'Asia/Kolkata', 'Asia/Dubai', 'Asia/Singapore', 'Europe/London', 'America/New_York'];
}

/** Lists the requirement form needs. */
export async function loadRequirementOptions(
  supabase: SupabaseClient<Database>,
  ctx: { companyId: string; kind: 'employer' | 'agency' },
  user: { id: string; email: string | null } | null
) {
  const [jobOrders, jobs, professions, areas, cities, policies, team] = await Promise.all([
    supabase
      .from('job_orders')
      .select('id, reference, title, status, agency_clients ( name )')
      .eq('agency_id', ctx.companyId)
      .in('status', ['draft', 'open', 'on_hold', 'filled'])
      .order('updated_at', { ascending: false })
      .limit(300),
    supabase
      .from('jobs')
      .select('id, title, status')
      .eq('company_id', ctx.companyId)
      .order('created_at', { ascending: false })
      .limit(300),
    supabase.from('professions').select('id, name').eq('status', 'active').order('name'),
    supabase.from('locations').select('id, name, parent_id').eq('kind', 'area').order('name'),
    supabase.from('locations').select('id, name').eq('kind', 'city'),
    supabase.from('overtime_policies').select('id, name').eq('company_id', ctx.companyId).order('name'),
    loadTeam(supabase, ctx.companyId, user?.id ?? null, user?.email ?? null),
  ]);
  const cityById = new Map((cities.data ?? []).map((c) => [c.id, c.name]));
  const orders = (jobOrders.data ?? []) as unknown as {
    id: string;
    title: string;
    reference?: string;
    agency_clients?: { name: string } | null;
  }[];
  const ownJobs = (jobs.data ?? []) as unknown as { id: string; title: string; status: string }[];

  // A client job order carries consent obligations, so it is listed first and
  // named with its client. Reading an empty list is not an error: an
  // organization that has not turned client recruitment on simply has none.
  const sources: SourceOption[] = [
    ...orders.map((o) => ({
      id: o.id,
      type: 'job_order' as const,
      label: `${o.reference ? `${o.reference} · ` : ''}${o.title}${o.agency_clients?.name ? ` · ${o.agency_clients.name}` : ''}`,
    })),
    ...ownJobs.map((j) => ({
      id: j.id,
      type: 'job' as const,
      label: `${j.title}${j.status !== 'published' ? ` (${j.status.replace(/_/g, ' ')})` : ''}`,
    })),
  ];
  return {
    error: jobs.error?.message ?? null,
    sources,
    professions: (professions.data ?? []).map((p) => ({ id: p.id, label: p.name })),
    areas: (areas.data ?? []).map((a) => ({
      id: a.id,
      label: `${a.name}${a.parent_id && cityById.get(a.parent_id) ? `, ${cityById.get(a.parent_id)}` : ''}`,
    })),
    policies: (policies.data ?? []).map((p) => ({ id: p.id, label: p.name })),
    supervisors: peopleOf(team.members).map((p) => ({ id: p.personId, label: p.label })),
    timeZones: timeZones(),
  };
}
