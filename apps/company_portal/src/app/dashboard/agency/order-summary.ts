import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/lib/supabase/database.types';
import type { CompanyContext } from '@/lib/supabase/server';
import { WORKPLACE_LABEL, WORK_TYPE_LABEL, formatPay } from '@/lib/format';
import { calendarDate } from '@/lib/hiring';
import type { AgencySummary, OrderSummary } from './consent-ui';

/** Columns needed to describe an order to a worker. */
export const ORDER_SUMMARY_SELECT =
  'id, reference, title, status, location_text, workplace_type, work_type, pay_min, pay_max, pay_period, pay_currency, start_date, client_job_id, agency_clients ( name, link_status, client_company_id )';

type Row = {
  id: string;
  reference: string;
  title: string;
  location_text: string | null;
  workplace_type: string;
  work_type: string;
  pay_min: number | null;
  pay_max: number | null;
  pay_period: string | null;
  pay_currency: string | null;
  start_date: string | null;
  agency_clients: unknown;
};

export function toOrderSummary(o: Row, clientCompanyName?: string | null): OrderSummary {
  const c = o.agency_clients as { name: string } | null;
  return {
    id: o.id,
    reference: o.reference,
    title: o.title,
    client: clientCompanyName ?? c?.name ?? 'the client',
    location: o.location_text,
    pay: o.pay_min != null || o.pay_max != null ? formatPay({ min: o.pay_min, max: o.pay_max, period: o.pay_period, currency: o.pay_currency }) : null,
    workType: WORK_TYPE_LABEL[o.work_type] ?? o.work_type,
    workplace: WORKPLACE_LABEL[o.workplace_type] ?? o.workplace_type,
    startDate: o.start_date ? calendarDate(o.start_date) : null,
  };
}

export function agencySummary(ctx: CompanyContext): AgencySummary {
  return { name: ctx.companyName, verified: ctx.isVerified, independent: ctx.isIndependent };
}

export async function myDisplayName(supabase: SupabaseClient<Database>): Promise<string | null> {
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;
  const { data } = await supabase.from('persons').select('display_name').eq('id', user.id).maybeSingle();
  return data?.display_name ?? user.email ?? null;
}
