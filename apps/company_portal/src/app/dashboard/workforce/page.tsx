import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { fmtIn, parseWorkforceDashboard, shiftTone, wfCan, zonedDate } from '@/lib/workforce';
import { loadShifts, serverNow } from './data';
import { ErrorNote, PageHeader, Section, Tile, TonePill } from './ui';

export const metadata: Metadata = { title: 'Workforce · Omelo' };

const W = '/dashboard/workforce';

export default async function WorkforceDashboardPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const now = serverNow();
  const [dashRes, shiftsRes] = await Promise.all([
    supabase.rpc('omelo_workforce_dashboard', { p_company: ctx.companyId }),
    loadShifts(
      supabase,
      ctx,
      new Date(now - 14 * 3_600_000).toISOString(),
      new Date(now + 38 * 3_600_000).toISOString()
    ),
  ]);
  const d = parseWorkforceDashboard(dashRes.data ?? null);
  const today = shiftsRes.shifts.filter(
    (s) => s.status !== 'cancelled' && zonedDate(s.startsAt, s.timezone) === zonedDate(now, s.timezone)
  );
  const canManage = wfCan(ctx, 'manage_workforce');
  const isAgency = ctx.kind === 'agency';
  const A = '/dashboard/agency';

  return (
    <div className="space-y-6">
      <PageHeader
        title="Workforce"
        subtitle={
          isAgency
            ? 'Workers you place with clients: requirements, assignments, shifts, time and pay.'
            : 'Your workforce: requirements, assignments, shifts, attendance, timesheets and pay.'
        }
        action={
          canManage ? (
            <Link href={`${W}/requirements/new`} className="btn btn-primary w-full sm:w-auto">
              New requirement
            </Link>
          ) : undefined
        }
      />

      {dashRes.error ? (
        <ErrorNote label="the workforce dashboard" message={dashRes.error.message} />
      ) : (
        <>
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-3">
            <Tile label="Active workers" value={d.activeWorkers} href={`${W}/assignments?status=active`} />
            <Tile label="Today’s shifts" value={d.todaysShifts} hint={`${d.present} present · ${d.absent} absent`} href={`${W}/shifts`} />
            <Tile label="Open positions" value={d.openPositions} href={`${W}/requirements`} />
            <Tile label="Offers pending" value={d.offersPending} href={`${W}/assignments?status=offered`} />
            <Tile
              label="Approvals"
              value={d.pendingApprovals}
              hint="exceptions and leave"
              href={wfCan(ctx, 'approve_time') ? `${W}/approvals` : undefined}
            />
            <Tile
              label="Timesheets to review"
              value={d.timesheets}
              href={wfCan(ctx, 'approve_time') ? `${W}/approvals#timesheets` : undefined}
            />
            <Tile
              label="Earnings to approve"
              value={d.earningsToApprove}
              href={wfCan(ctx, 'manage_pay') ? `${W}/pay` : undefined}
            />
          </div>
          {d.agency && (
            <div className="space-y-2">
              <h2 className="text-sm font-bold muted uppercase tracking-wide">Recruiting</h2>
              <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-7 gap-3">
                <Tile label="Clients" value={d.agency.clients} href={`${A}/clients`} />
                <Tile label="Active job orders" value={d.agency.activeJobOrders} href={`${A}/job-orders`} />
                <Tile label="Awaiting consent" value={d.agency.pendingConsents} href={`${A}/candidates?status=requested`} />
                <Tile label="Submissions" value={d.agency.submissions} href={`${A}/submissions`} />
                <Tile label="Interviews" value={d.agency.interviews} href={`${A}/interviews`} />
                <Tile label="Offers" value={d.agency.offers} href={`${A}/offers`} />
                <Tile label="Placements" value={d.agency.placements} href={`${A}/placements`} />
              </div>
            </div>
          )}
        </>
      )}

      <Section
        title="Today’s shifts"
        aside={
          <Link href={`${W}/shifts`} className="text-sm underline muted">
            Full schedule
          </Link>
        }
      >
        {shiftsRes.error ? (
          <ErrorNote label="shifts" message={shiftsRes.error} />
        ) : today.length === 0 ? (
          <p className="text-sm muted">No shifts today. Create them from a requirement’s shift templates.</p>
        ) : (
          <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
            {today.map((s) => (
              <li key={s.id} className="py-2.5 flex items-center gap-3 flex-wrap">
                <div className="flex-1 min-w-[12rem]">
                  <Link href={`${W}/shifts/${s.id}`} className="font-semibold text-sm hover:underline break-words">
                    {fmtIn(s.startsAt, s.timezone, 'time')}–{fmtIn(s.endsAt, s.timezone, 'time')} ·{' '}
                    {s.requirementTitle ?? 'Shift'}
                  </Link>
                  <p className="text-xs muted break-words">
                    {s.locationText || s.timezone}
                    {s.atYourSite ? ' · agency workers at your site' : ''}
                  </p>
                </div>
                <span className="text-xs tabular-nums whitespace-nowrap">
                  <strong>{s.assigned}</strong>/{s.requiredWorkers} assigned
                </span>
                <span className="text-xs tabular-nums whitespace-nowrap" style={{ color: 'var(--color-verified)' }}>
                  {s.present} present
                </span>
                {s.absent > 0 && (
                  <span className="text-xs tabular-nums whitespace-nowrap" style={{ color: 'var(--color-danger)' }}>
                    {s.absent} absent
                  </span>
                )}
                <TonePill tone={shiftTone(s.status)} />
              </li>
            ))}
          </ul>
        )}
      </Section>
    </div>
  );
}
