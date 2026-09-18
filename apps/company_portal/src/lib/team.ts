import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/lib/supabase/database.types';

/**
 * Team members of a company, with the best name we are allowed to read.
 *
 * Teammates' persons rows are not readable to each other (RLS). Owners and
 * admins can read their company's invitations, and accepting an invitation
 * inserts the membership in the same transaction that stamps accepted_at —
 * so an accepted invitation's (role, accepted_at) identifies the member's
 * (role, joined_at) and gives us the address they were invited at. Anyone
 * else sees "Teammate" plus role and join date. Nothing here widens access.
 */
export type TeamMember = {
  memberId: string;
  personId: string;
  role: Database['public']['Enums']['company_role'];
  isActive: boolean;
  joinedAt: string;
  title: string | null;
  name: string | null;
  email: string | null;
  isYou: boolean;
};

export type PendingInvitation = {
  id: string;
  email: string;
  role: string;
  createdAt: string;
  expiresAt: string;
};

export async function loadTeam(
  supabase: SupabaseClient<Database>,
  companyId: string,
  userId: string | null,
  userEmail: string | null
): Promise<{
  members: TeamMember[];
  pending: PendingInvitation[];
  error: string | null;
  invitesReadable: boolean;
}> {
  const [membersRes, invitesRes] = await Promise.all([
    supabase
      .from('company_members')
      .select('id, person_id, role, is_active, joined_at, title, persons!company_members_person_id_fkey ( display_name, email )')
      .eq('company_id', companyId)
      .order('joined_at', { ascending: true }),
    supabase
      .from('company_invitations')
      .select('id, email, role, created_at, expires_at, accepted_at')
      .eq('company_id', companyId)
      .order('created_at', { ascending: false }),
  ]);

  const invites = invitesRes.data ?? [];
  const accepted = new Map<string, string>();
  for (const i of invites) if (i.accepted_at) accepted.set(`${i.role}|${new Date(i.accepted_at).getTime()}`, i.email);

  const emailByPerson = new Map<string, string>();
  const rows = membersRes.data ?? [];
  for (const m of rows) {
    const e = accepted.get(`${m.role}|${new Date(m.joined_at).getTime()}`);
    if (e) emailByPerson.set(m.person_id, e);
  }

  const members: TeamMember[] = rows.map((m) => {
    const p = m.persons as unknown as { display_name: string | null; email: string | null } | null;
    const isYou = !!userId && m.person_id === userId;
    return {
      memberId: m.id,
      personId: m.person_id,
      role: m.role,
      isActive: m.is_active,
      joinedAt: m.joined_at,
      title: m.title,
      name: p?.display_name ?? null,
      email: p?.email ?? emailByPerson.get(m.person_id) ?? (isYou ? userEmail : null),
      isYou,
    };
  });

  const now = Date.now();
  return {
    members,
    pending: invites
      .filter((i) => !i.accepted_at && new Date(i.expires_at).getTime() > now)
      .map((i) => ({ id: i.id, email: i.email, role: i.role, createdAt: i.created_at, expiresAt: i.expires_at })),
    error: membersRes.error?.message ?? null,
    invitesReadable: !invitesRes.error,
  };
}

export function memberName(m: Pick<TeamMember, 'name' | 'email' | 'isYou'>): string {
  const base = m.name ?? m.email ?? 'Teammate';
  return m.isYou ? `${base} (you)` : base;
}

/** One entry per person (a person can hold several roles). */
export function peopleOf(members: TeamMember[]): { personId: string; label: string; roles: string[] }[] {
  const map = new Map<string, { personId: string; label: string; roles: string[] }>();
  for (const m of members) {
    if (!m.isActive) continue;
    const e = map.get(m.personId);
    if (e) e.roles.push(m.role);
    else map.set(m.personId, { personId: m.personId, label: memberName(m), roles: [m.role] });
  }
  return [...map.values()];
}
