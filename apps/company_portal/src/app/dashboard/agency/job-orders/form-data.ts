import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/lib/supabase/database.types';

/** Lists the job order form needs: clients, professions, skills, areas. */
export async function loadOrderFormOptions(supabase: SupabaseClient<Database>, agencyId: string) {
  const [clients, professions, skills, areas, cities] = await Promise.all([
    supabase
      .from('agency_clients')
      .select('id, name, relationship_status')
      .eq('agency_id', agencyId)
      .neq('relationship_status', 'ended')
      .order('name'),
    supabase.from('professions').select('id, name').eq('status', 'active').order('name'),
    supabase.from('skills').select('id, name').eq('status', 'active').order('name'),
    supabase.from('locations').select('id, name, parent_id').eq('kind', 'area').order('name'),
    supabase.from('locations').select('id, name').eq('kind', 'city'),
  ]);
  const cityById = new Map((cities.data ?? []).map((c) => [c.id, c.name]));
  return {
    error: clients.error?.message ?? null,
    clients: (clients.data ?? []).map((c) => ({ id: c.id, label: c.name })),
    professions: (professions.data ?? []).map((p) => ({ id: p.id, label: p.name })),
    skills: (skills.data ?? []).map((s) => ({ id: s.id, label: s.name })),
    areas: (areas.data ?? []).map((a) => ({
      id: a.id,
      label: `${a.name}${a.parent_id && cityById.get(a.parent_id) ? `, ${cityById.get(a.parent_id)}` : ''}`,
    })),
  };
}
