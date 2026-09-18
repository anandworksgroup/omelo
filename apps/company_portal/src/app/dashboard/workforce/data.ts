import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/lib/supabase/database.types';
import { chunk, parseClientWorkforce, type ShiftRow } from '@/lib/workforce';
import { loadTeam, memberName } from '@/lib/team';
import type { HistoryEvent } from './ui';

type DB = SupabaseClient<Database>;

/** The time of this request (kept out of components so render stays pure). */
export function serverNow(): number {
  return Date.now();
}

export type ShiftListItem = ShiftRow & {
  requirementTitle: string | null;
  assigned: number;
  offered: number;
  present: number;
  absent: number;
  /** Run by an agency at this company's site (the viewer is the client). */
  atYourSite: boolean;
};

const SHIFT_COLS =
  'id, requirement_id, company_id, template_id, starts_at, ends_at, timezone, break_minutes, required_workers, shift_type, kind, status, cancel_reason, instructions, supervisor_id, location_text';

type ShiftDb = {
  id: string;
  requirement_id: string;
  company_id: string;
  template_id: string | null;
  starts_at: string;
  ends_at: string;
  timezone: string;
  break_minutes: number;
  required_workers: number;
  shift_type: string | null;
  kind: string;
  status: string;
  cancel_reason: string | null;
  instructions: string | null;
  supervisor_id: string | null;
  location_text: string | null;
};

function toRow(s: ShiftDb): ShiftRow {
  return {
    id: s.id,
    requirementId: s.requirement_id,
    companyId: s.company_id,
    templateId: s.template_id,
    startsAt: s.starts_at,
    endsAt: s.ends_at,
    timezone: s.timezone,
    breakMinutes: s.break_minutes,
    requiredWorkers: s.required_workers,
    shiftType: s.shift_type,
    kind: s.kind,
    status: s.status,
    cancelReason: s.cancel_reason,
    instructions: s.instructions,
    supervisorId: s.supervisor_id,
    locationText: s.location_text,
  };
}

/**
 * Shifts overlapping [from, to): the company's own, plus (for a client
 * company) agency shifts at its sites that have its agency workers on them.
 * RLS decides what is readable; this only narrows to the active workspace.
 */
export async function loadShifts(
  supabase: DB,
  ctx: { companyId: string; kind: 'employer' | 'agency' },
  fromIso: string,
  toIso: string,
  opts: { requirementId?: string | null; limit?: number } = {}
): Promise<{ shifts: ShiftListItem[]; error: string | null }> {
  const limit = opts.limit ?? 500;
  let q = supabase
    .from('shifts')
    .select(SHIFT_COLS)
    .eq('company_id', ctx.companyId)
    .lt('starts_at', toIso)
    .gt('ends_at', fromIso)
    .order('starts_at')
    .limit(limit);
  if (opts.requirementId) q = q.eq('requirement_id', opts.requirementId);
  const own = await q;
  if (own.error) return { shifts: [], error: own.error.message };
  let rows = (own.data ?? []) as ShiftDb[];
  const siteIds = new Set<string>();

  if (ctx.kind === 'employer' && !opts.requirementId) {
    const cw = await supabase.rpc('omelo_client_workforce', { p_company: ctx.companyId });
    const asg = parseClientWorkforce(cw.data ?? null).map((c) => c.assignmentId);
    if (asg.length) {
      const sw = await supabase
        .from('shift_workers')
        .select('shift_id')
        .in('assignment_id', asg.slice(0, 150))
        .lt('starts_at', toIso)
        .gt('ends_at', fromIso)
        .limit(1000);
      const ids = [...new Set((sw.data ?? []).map((x) => x.shift_id))].filter((id) => !rows.some((r) => r.id === id));
      if (ids.length) {
        const more = await supabase.from('shifts').select(SHIFT_COLS).in('id', ids.slice(0, 150));
        for (const m of (more.data ?? []) as ShiftDb[]) {
          siteIds.add(m.id);
          rows.push(m);
        }
        rows = rows.sort((a, b) => a.starts_at.localeCompare(b.starts_at));
      }
    }
  }

  const ids = rows.map((r) => r.id);
  const reqIds = [...new Set(rows.map((r) => r.requirement_id))];
  const idGroups = chunk(ids.slice(0, 500), 150);
  const [workerRes, attRes, reqs] = await Promise.all([
    Promise.all(idGroups.map((g) => supabase.from('shift_workers').select('shift_id, status').in('shift_id', g))),
    Promise.all(idGroups.map((g) => supabase.from('attendance_records').select('shift_id, status, check_in_at').in('shift_id', g))),
    reqIds.length
      ? supabase.from('workforce_requirements').select('id, title').in('id', reqIds.slice(0, 150))
      : Promise.resolve({ data: [] as { id: string; title: string }[] }),
  ]);
  const workers = { data: workerRes.flatMap((r) => r.data ?? []) };
  const att = { data: attRes.flatMap((r) => r.data ?? []) };
  const count = new Map<string, { assigned: number; offered: number; present: number; absent: number }>();
  const c = (id: string) => {
    let v = count.get(id);
    if (!v) count.set(id, (v = { assigned: 0, offered: 0, present: 0, absent: 0 }));
    return v;
  };
  for (const w of workers.data ?? []) {
    if (['assigned', 'completed', 'absent'].includes(w.status)) c(w.shift_id).assigned++;
    else if (w.status === 'offered') c(w.shift_id).offered++;
  }
  for (const a of att.data ?? []) {
    if (a.check_in_at) c(a.shift_id).present++;
    else if (a.status === 'absent' || a.status === 'unapproved_absence') c(a.shift_id).absent++;
  }
  const title = new Map((reqs.data ?? []).map((r) => [r.id, r.title]));
  return {
    error: null,
    shifts: rows.map((r) => ({
      ...toRow(r),
      requirementTitle: title.get(r.requirement_id) ?? null,
      ...(count.get(r.id) ?? { assigned: 0, offered: 0, present: 0, absent: 0 }),
      atYourSite: siteIds.has(r.id),
    })),
  };
}

/** workforce_events for one or more entities, with teammates' names where we may read them. */
export async function loadHistory(
  supabase: DB,
  ctx: { companyId: string },
  user: { id: string; email: string | null } | null,
  entityType: string,
  entityIds: string[]
): Promise<HistoryEvent[]> {
  if (entityIds.length === 0) return [];
  const [ev, team] = await Promise.all([
    supabase
      .from('workforce_events')
      .select('id, event, actor_id, reason, occurred_at, before, after')
      .eq('entity_type', entityType)
      .in('entity_id', entityIds)
      .order('occurred_at', { ascending: false })
      .limit(100),
    loadTeam(supabase, ctx.companyId, user?.id ?? null, user?.email ?? null),
  ]);
  const names = new Map(team.members.map((m) => [m.personId, memberName(m)]));
  return (ev.data ?? []).map((e) => ({
    id: e.id,
    event: e.event,
    actor: e.actor_id ? (names.get(e.actor_id) ?? 'Someone outside your team') : 'Omelo',
    reason: e.reason,
    occurredAt: e.occurred_at,
    before: e.before,
    after: e.after,
  }));
}
