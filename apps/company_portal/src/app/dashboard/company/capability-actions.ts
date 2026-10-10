'use server';

import { revalidatePath } from 'next/cache';
import { createClient } from '@/lib/supabase/server';

type Fail = { ok: false; error: string };
type Ok = { ok: true };

const KEYS = ['client_recruitment', 'workforce', 'rpo', 'billing'];

/**
 * Turn an optional module on or off for this organization.
 *
 * The database decides whether the caller may: omelo_set_capability wants an
 * owner or an admin and records who changed it. Nothing here grants access to
 * a client, a job order or a candidate — those are still the client's and the
 * worker's to give.
 */
export async function setCapability(
  companyId: string,
  capability: string,
  enabled: boolean
): Promise<Ok | Fail> {
  if (!KEYS.includes(capability)) return { ok: false, error: 'Unknown capability.' };

  const supabase = await createClient();
  const { error } = await supabase.rpc('omelo_set_capability', {
    p_company: companyId,
    p_capability: capability,
    p_enabled: enabled,
  });
  if (error) return { ok: false, error: error.message };

  // The navigation reads capabilities, so the whole shell needs refreshing.
  revalidatePath('/', 'layout');
  return { ok: true };
}
