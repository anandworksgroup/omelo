import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { UUID_RE } from '@/lib/talent';
import { billingTone, earningTone, loadWorkerNames, money, nice, onlyWf, wfCan } from '@/lib/workforce';
import { ErrorNote, FilterChips, Notice, PageHeader, Section, Table, TonePill, dateText, qs } from '../ui';
import { BillingActions, EarningActions, OvertimePolicies, PaymentRow, type Policy } from './parts';

export const metadata: Metadata = { title: 'Pay · Workforce · Omelo' };

const W = '/dashboard/workforce';
const EARNING_FILTERS = [
  { value: 'calculated', label: 'To approve' },
  { value: 'topay', label: 'To pay' },
  { value: 'paid', label: 'Paid' },
  { value: 'all', label: 'All' },
];

export default async function PayPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const ctx = (await getCompanyContext())!;
  if (!wfCan(ctx, 'manage_pay')) {
    return (
      <div className="space-y-5">
        <PageHeader title="Pay" />
        <Notice title="Not available to your role">{onlyWf(ctx.kind, 'manage_pay', 'manage pay')}</Notice>
      </div>
    );
  }
  const isAgency = ctx.kind === 'agency';
  const tabs = ['earnings', 'overtime', ...(isAgency ? ['billing'] : ['bills'])];
  const tab = typeof sp.tab === 'string' && tabs.includes(sp.tab) ? sp.tab : 'earnings';
  const one = typeof sp.earning === 'string' && UUID_RE.test(sp.earning) ? sp.earning : null;
  const filter = one ? 'all' : typeof sp.status === 'string' && EARNING_FILTERS.some((f) => f.value === sp.status) ? sp.status : 'calculated';
  const supabase = await createClient();

  const tabLink = (value: string, label: string) => (
    <Link
      href={`${W}/pay${qs({ tab: value === 'earnings' ? null : value })}`}
      aria-current={tab === value ? 'page' : undefined}
      className="px-3 py-1.5 rounded-md text-sm font-semibold whitespace-nowrap"
      style={tab === value ? { background: 'var(--bg)', color: 'var(--color-brand-600)', boxShadow: '0 0 0 1px var(--line)' } : { color: 'var(--muted)' }}
    >
      {label}
    </Link>
  );

  return (
    <div className="space-y-5">
      <PageHeader
        title={isAgency ? 'Pay & billing' : 'Pay'}
        subtitle="Earnings come only from approved timesheets. Omelo records payments made through your bank or payroll; it does not move money — a payroll provider can be integrated later."
      />
      <nav aria-label="Pay" className="inline-flex rounded-lg border hairline p-0.5 surface max-w-full overflow-x-auto">
        {tabLink('earnings', 'Earnings & payments')}
        {tabLink('overtime', 'Overtime policies')}
        {isAgency ? tabLink('billing', 'Client billing') : tabLink('bills', 'Agency bills')}
      </nav>
      {tab === 'earnings' && <Earnings ctx={ctx} supabase={supabase} filter={filter} one={one} />}
      {tab === 'overtime' && <Overtime companyId={ctx.companyId} supabase={supabase} />}
      {tab === 'billing' && <Billing agencyId={ctx.companyId} supabase={supabase} />}
      {tab === 'bills' && <Bills companyId={ctx.companyId} supabase={supabase} />}
    </div>
  );
}

type DB = Awaited<ReturnType<typeof createClient>>;
type Ctx = NonNullable<Awaited<ReturnType<typeof getCompanyContext>>>;

async function Earnings({ ctx, supabase, filter, one }: { ctx: Ctx; supabase: DB; filter: string; one: string | null }) {
  let q = supabase
    .from('earnings')
    .select(
      'id, assignment_id, person_id, timesheet_id, period_start, period_end, currency, base_amount, overtime_amount, allowance_amount, bonus_amount, deduction_amount, adjustment_amount, gross_amount, status, approved_at, assignments ( title, work_identity_id )'
    )
    .eq('company_id', ctx.companyId)
    .order('period_start', { ascending: false })
    .limit(200);
  if (one) q = q.eq('id', one);
  else if (filter === 'calculated') q = q.eq('status', 'calculated');
  else if (filter === 'topay') q = q.in('status', ['approved', 'scheduled', 'processing', 'failed']);
  else if (filter === 'paid') q = q.eq('status', 'paid');
  const { data, error } = await q;
  const rows = data ?? [];
  const ids = rows.map((e) => e.id);
  const [lines, payments, names] = await Promise.all([
    ids.length
      ? supabase.from('earning_lines').select('id, earning_id, kind, description, quantity, unit, rate, amount, reason').in('earning_id', ids).order('created_at')
      : Promise.resolve({ data: [] as { id: string; earning_id: string; kind: string; description: string; quantity: number | null; unit: string | null; rate: number | null; amount: number; reason: string | null }[] }),
    ids.length
      ? supabase
          .from('payment_records')
          .select('id, earning_id, amount, currency, status, provider, provider_reference, scheduled_for, paid_at, failure_reason')
          .in('earning_id', ids)
          .order('created_at')
      : Promise.resolve({ data: [] as { id: string; earning_id: string; amount: number; currency: string; status: string; provider: string | null; provider_reference: string | null; scheduled_for: string | null; paid_at: string | null; failure_reason: string | null }[] }),
    loadWorkerNames(
      supabase,
      ctx,
      rows.map((e) => ({ personId: e.person_id, identityId: (e.assignments as unknown as { work_identity_id: string } | null)?.work_identity_id ?? null }))
    ),
  ]);

  return (
    <div className="space-y-4">
      {!one && (
        <FilterChips
          label="Earnings"
          active={filter}
          options={EARNING_FILTERS}
          hrefFor={(v) => `${W}/pay${qs({ status: v === 'calculated' ? null : v })}`}
        />
      )}
      {one && (
        <Link href={`${W}/pay`} className="text-sm underline muted">
          ← All earnings
        </Link>
      )}
      {error ? (
        <ErrorNote label="earnings" message={error.message} />
      ) : rows.length === 0 ? (
        <Notice title="Nothing here">Earnings appear when a timesheet is approved by the workplace.</Notice>
      ) : (
        <ul className="space-y-4">
          {rows.map((e) => {
            const ls = (lines.data ?? []).filter((l) => l.earning_id === e.id);
            const ps = (payments.data ?? []).filter((p) => p.earning_id === e.id);
            const committed = ps.filter((p) => ['scheduled', 'processing', 'paid'].includes(p.status)).reduce((s, p) => s + Number(p.amount), 0);
            const remaining = Math.max(0, Math.round((Number(e.gross_amount) - committed) * 100) / 100);
            const title = (e.assignments as unknown as { title: string } | null)?.title ?? '';
            return (
              <li key={e.id} id={`e-${e.id}`} className="card p-4 space-y-3 min-w-0">
                <div className="flex items-start gap-2 flex-wrap">
                  <div className="flex-1 min-w-[12rem]">
                    <p className="font-bold break-words">
                      <Link href={`${W}/assignments/${e.assignment_id}`} className="hover:underline">
                        {names.get(e.person_id) ?? 'Worker'}
                      </Link>
                      <span className="muted font-normal"> · {title}</span>
                    </p>
                    <p className="text-xs muted">
                      {dateText(e.period_start)} – {dateText(e.period_end)} ·{' '}
                      <Link href={`${W}/timesheets/${e.timesheet_id}`} className="underline">
                        timesheet
                      </Link>
                    </p>
                  </div>
                  <div className="text-right">
                    <p className="text-xl font-black tabular-nums">{money(e.gross_amount, e.currency)}</p>
                    <TonePill tone={earningTone(e.status)} />
                  </div>
                </div>
                <Table head={['Line', 'Quantity', 'Rate', 'Amount']}>
                  {ls.map((l) => (
                    <tr key={l.id}>
                      <td className="py-1.5 pr-3">
                        <span className="font-semibold">{l.description}</span> <span className="muted text-xs">· {nice(l.kind)}</span>
                        {l.reason && <span className="block text-xs muted break-words">“{l.reason}”</span>}
                      </td>
                      <td className="py-1.5 pr-3 tabular-nums whitespace-nowrap">
                        {l.quantity != null ? `${Number(l.quantity)} ${l.unit ?? ''}` : '—'}
                      </td>
                      <td className="py-1.5 pr-3 tabular-nums whitespace-nowrap">{l.rate != null ? money(l.rate, e.currency) : '—'}</td>
                      <td
                        className="py-1.5 pr-3 tabular-nums whitespace-nowrap"
                        style={l.kind === 'deduction' || Number(l.amount) < 0 ? { color: 'var(--color-danger)' } : undefined}
                      >
                        {money(l.kind === 'deduction' ? -Math.abs(Number(l.amount)) : Number(l.amount), e.currency)}
                      </td>
                    </tr>
                  ))}
                </Table>
                <p className="text-xs muted tabular-nums">
                  Base {money(e.base_amount, e.currency)} · overtime {money(e.overtime_amount, e.currency)} · allowances{' '}
                  {money(e.allowance_amount, e.currency)} · bonus {money(e.bonus_amount, e.currency)} · deductions −
                  {money(e.deduction_amount, e.currency)} · adjustments {money(e.adjustment_amount, e.currency)}
                </p>
                {ps.length > 0 && (
                  <div>
                    <p className="text-sm font-semibold">Payments</p>
                    <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
                      {ps.map((p) => (
                        <PaymentRow
                          key={p.id}
                          id={p.id}
                          status={p.status}
                          amount={Number(p.amount)}
                          currency={p.currency}
                          label={[
                            p.provider,
                            p.provider_reference ? `ref ${p.provider_reference}` : null,
                            p.scheduled_for ? `for ${dateText(p.scheduled_for)}` : null,
                            p.paid_at ? `paid ${dateText(p.paid_at.slice(0, 10))}` : null,
                            p.failure_reason,
                          ]
                            .filter(Boolean)
                            .join(' · ')}
                        />
                      ))}
                    </ul>
                  </div>
                )}
                <EarningActions id={e.id} status={e.status} currency={e.currency} remaining={remaining} />
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

async function Overtime({ companyId, supabase }: { companyId: string; supabase: DB }) {
  const { data, error } = await supabase.from('overtime_policies').select('*').eq('company_id', companyId).order('name');
  return (
    <Section title="Overtime policies">
      <p className="text-sm">
        <strong>Omelo does not assume a legal overtime rule — configure your jurisdiction’s.</strong>{' '}
        <span className="muted">
          Attach a policy to a requirement; its assignments inherit it. Overtime is the larger of daily and weekly excess,
          capped if you set a cap, and paid at the multiplier.
        </span>
      </p>
      {error ? <ErrorNote label="policies" message={error.message} /> : <OvertimePolicies policies={(data ?? []) as Policy[]} />}
    </Section>
  );
}

async function Billing({ agencyId, supabase }: { agencyId: string; supabase: DB }) {
  const { data, error } = await supabase
    .from('billing_records')
    .select('id, assignment_id, client_id, quantity, unit, bill_rate, amount, currency, status, created_at, timesheets ( period_start, period_end )')
    .eq('agency_id', agencyId)
    .order('created_at', { ascending: false })
    .limit(500);
  const rows = data ?? [];
  const clientIds = [...new Set(rows.map((b) => b.client_id).filter((x): x is string => !!x))];
  const { data: clients } = clientIds.length
    ? await supabase.from('agency_clients').select('id, name').in('id', clientIds)
    : { data: [] as { id: string; name: string }[] };
  const clientName = new Map((clients ?? []).map((c) => [c.id, c.name]));
  // Totals per client and currency, by status.
  const totals = new Map<string, { client: string; currency: string; draft: number; invoiced: number; paid: number }>();
  for (const b of rows) {
    if (b.status === 'void') continue;
    const key = `${b.client_id ?? '-'}|${b.currency}`;
    const t = totals.get(key) ?? { client: clientName.get(b.client_id ?? '') ?? 'Client', currency: b.currency, draft: 0, invoiced: 0, paid: 0 };
    t[b.status as 'draft' | 'invoiced' | 'paid'] += Number(b.amount);
    totals.set(key, t);
  }
  return (
    <div className="space-y-5">
      <Section title="Totals per client">
        <p className="text-xs muted">Billed at the bill rate set on each assignment — kept apart from the worker’s pay, which the client never sees.</p>
        {error ? (
          <ErrorNote label="billing" message={error.message} />
        ) : totals.size === 0 ? (
          <p className="text-sm muted">No billing yet. A bill is drafted when a timesheet with a bill rate is approved.</p>
        ) : (
          <Table head={['Client', 'Draft', 'Invoiced', 'Paid']}>
            {[...totals.values()].map((t) => (
              <tr key={`${t.client}${t.currency}`}>
                <td className="py-2 pr-3 font-semibold">{t.client}</td>
                <td className="py-2 pr-3 tabular-nums">{money(t.draft, t.currency)}</td>
                <td className="py-2 pr-3 tabular-nums">{money(t.invoiced, t.currency)}</td>
                <td className="py-2 pr-3 tabular-nums">{money(t.paid, t.currency)}</td>
              </tr>
            ))}
          </Table>
        )}
      </Section>
      {rows.length > 0 && (
        <Section title="Billing records">
          <Table head={['Client', 'Period', 'Quantity × rate', 'Amount', 'Status']}>
            {rows.map((b) => {
              const t = b.timesheets as unknown as { period_start: string; period_end: string } | null;
              return (
                <tr key={b.id}>
                  <td className="py-2 pr-3">
                    <Link href={`${W}/assignments/${b.assignment_id}`} className="hover:underline">
                      {clientName.get(b.client_id ?? '') ?? 'Client'}
                    </Link>
                  </td>
                  <td className="py-2 pr-3 whitespace-nowrap">{t ? `${dateText(t.period_start)} – ${dateText(t.period_end)}` : '—'}</td>
                  <td className="py-2 pr-3 tabular-nums whitespace-nowrap">
                    {Number(b.quantity)} {b.unit} × {money(b.bill_rate, b.currency)}
                  </td>
                  <td className="py-2 pr-3 tabular-nums">{money(b.amount, b.currency)}</td>
                  <td className="py-2 pr-3">
                    <BillingActions id={b.id} status={b.status} />
                  </td>
                </tr>
              );
            })}
          </Table>
        </Section>
      )}
    </div>
  );
}

async function Bills({ companyId, supabase }: { companyId: string; supabase: DB }) {
  const { data, error } = await supabase
    .from('billing_records')
    .select('id, agency_id, quantity, unit, bill_rate, amount, currency, status, created_at, timesheets ( period_start, period_end )')
    .eq('client_company_id', companyId)
    .order('created_at', { ascending: false })
    .limit(500);
  const rows = data ?? [];
  const agencyIds = [...new Set(rows.map((b) => b.agency_id))];
  const { data: agencies } = agencyIds.length
    ? await supabase.from('companies').select('id, display_name').in('id', agencyIds)
    : { data: [] as { id: string; display_name: string }[] };
  const agencyName = new Map((agencies ?? []).map((a) => [a.id, a.display_name]));
  return (
    <Section title="Bills from agencies">
      <p className="text-xs muted">What agencies bill you for their workers’ approved time at your sites. Agencies mark them invoiced and paid.</p>
      {error ? (
        <ErrorNote label="bills" message={error.message} />
      ) : rows.length === 0 ? (
        <p className="text-sm muted">No bills from agencies.</p>
      ) : (
        <Table head={['Agency', 'Period', 'Quantity × rate', 'Amount', 'Status']}>
          {rows.map((b) => {
            const t = b.timesheets as unknown as { period_start: string; period_end: string } | null;
            return (
              <tr key={b.id}>
                <td className="py-2 pr-3">{agencyName.get(b.agency_id) ?? 'Agency'}</td>
                <td className="py-2 pr-3 whitespace-nowrap">{t ? `${dateText(t.period_start)} – ${dateText(t.period_end)}` : '—'}</td>
                <td className="py-2 pr-3 tabular-nums whitespace-nowrap">
                  {Number(b.quantity)} {b.unit} × {money(b.bill_rate, b.currency)}
                </td>
                <td className="py-2 pr-3 tabular-nums">{money(b.amount, b.currency)}</td>
                <td className="py-2 pr-3">
                  <TonePill tone={billingTone(b.status)} />
                </td>
              </tr>
            );
          })}
        </Table>
      )}
    </Section>
  );
}
