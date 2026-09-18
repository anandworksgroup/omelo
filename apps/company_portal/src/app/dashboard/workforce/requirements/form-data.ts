import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/lib/supabase/database.types';
import { loadTeam, peopleOf } from '@/lib/team';

export type Option = { id: string; label: string };

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
  const [sources, professions, areas, cities, policies, team] = await Promise.all([
    ctx.kind === 'agency'
      ? supabase
          .from('job_orders')
          .select('id, reference, title, status, agency_clients ( name )')
          .eq('agency_id', ctx.companyId)
          .in('status', ['draft', 'open', 'on_hold', 'filled'])
          .order('updated_at', { ascending: false })
          .limit(300)
      : supabase
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
  const src = (sources.data ?? []) as unknown as {
    id: string;
    title: string;
    status: string;
    reference?: string;
    agency_clients?: { name: string } | null;
  }[];
  return {
    error: sources.error?.message ?? null,
    sources: src.map((s) => ({
      id: s.id,
      label:
        ctx.kind === 'agency'
          ? `${s.reference ? `${s.reference} · ` : ''}${s.title}${s.agency_clients?.name ? ` · ${s.agency_clients.name}` : ''}`
          : `${s.title}${s.status !== 'published' ? ` (${s.status.replace(/_/g, ' ')})` : ''}`,
    })),
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
