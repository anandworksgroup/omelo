import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { SHIFT_LABEL } from '@/lib/format';
import { UUID_RE } from '@/lib/talent';
import { DATE_RE, addDays, fmtIn, loadWorkerNames, mondayOf, nice, shiftTone, wfCan, zonedDate } from '@/lib/workforce';
import { loadShifts, serverNow } from '../data';
import { ErrorNote, PageHeader, TonePill, qs } from '../ui';
import BulkAssign from './bulk-assign';

export const metadata: Metadata = { title: 'Schedule · Workforce · Omelo' };

const W = '/dashboard/workforce';

export default async function SchedulePage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const now = serverNow();
  const req = typeof sp.req === 'string' && UUID_RE.test(sp.req) ? sp.req : null;
  const week = mondayOf(typeof sp.week === 'string' && DATE_RE.test(sp.week) ? sp.week : zonedDate(now, 'UTC'));
  const days = Array.from({ length: 7 }, (_, i) => addDays(week, i));

  const [res, reqs] = await Promise.all([
    loadShifts(supabase, ctx, `${addDays(week, -1)}T00:00:00Z`, `${addDays(week, 8)}T00:00:00Z`, { requirementId: req }),
    supabase.from('workforce_requirements').select('id, title, status').eq('company_id', ctx.companyId).order('created_at', { ascending: false }).limit(100),
  ]);
  const byDay = new Map<string, typeof res.shifts>();
  for (const s of res.shifts) {
    const d = zonedDate(s.startsAt, s.timezone);
    if (!days.includes(d)) continue;
    byDay.set(d, [...(byDay.get(d) ?? []), s]);
  }
  const weekShifts = days.flatMap((d) => byDay.get(d) ?? []);
  const today = zonedDate(now, 'UTC');
  const canManage = wfCan(ctx, 'manage_workforce');

  // Bulk assignment needs one requirement's workers.
  let workers: { id: string; label: string }[] = [];
  if (req && canManage) {
    const { data } = await supabase
      .from('assignments')
      .select('id, person_id, work_identity_id')
      .eq('requirement_id', req)
      .eq('company_id', ctx.companyId)
      .in('status', ['accepted', 'active'])
      .limit(1000);
    const names = await loadWorkerNames(supabase, ctx, (data ?? []).map((a) => ({ personId: a.person_id, identityId: a.work_identity_id })));
    workers = (data ?? []).map((a) => ({ id: a.id, label: names.get(a.person_id) ?? 'Worker' }));
  }

  return (
    <div className="space-y-5">
      <PageHeader
        title="Schedule"
        subtitle="Shifts by day, in each site’s local time. Required versus assigned workers at a glance."
      />
      <div className="flex gap-2 flex-wrap items-center">
        <Link href={`${W}/shifts${qs({ week: addDays(week, -7), req })}`} className="btn btn-ghost" aria-label="Previous week">
          ←
        </Link>
        <span className="font-semibold text-sm">
          {fmtIn(`${week}T12:00:00Z`, 'UTC', 'date')} – {fmtIn(`${addDays(week, 6)}T12:00:00Z`, 'UTC', 'date')}
        </span>
        <Link href={`${W}/shifts${qs({ week: addDays(week, 7), req })}`} className="btn btn-ghost" aria-label="Next week">
          →
        </Link>
        <Link href={`${W}/shifts${qs({ req })}`} className="text-sm underline muted">
          This week
        </Link>
        <form action={`${W}/shifts`} className="flex gap-2 flex-wrap ml-auto w-full sm:w-auto">
          <input type="hidden" name="week" value={week} />
          <select name="req" defaultValue={req ?? ''} className="input flex-1 sm:w-64" aria-label="Requirement">
            <option value="">All requirements</option>
            {(reqs.data ?? []).map((r) => (
              <option key={r.id} value={r.id}>
                {r.title}
              </option>
            ))}
          </select>
          <button className="btn btn-ghost">Show</button>
        </form>
      </div>

      {req && canManage && (
        <BulkAssign
          shifts={weekShifts
            .filter((s) => s.status === 'scheduled')
            .map((s) => ({ id: s.id, label: `${fmtIn(s.startsAt, s.timezone, 'datetime')}–${fmtIn(s.endsAt, s.timezone, 'time')}` }))}
          workers={workers}
        />
      )}

      {res.error ? (
        <ErrorNote label="shifts" message={res.error} />
      ) : (
        <div className="space-y-3">
          {days.map((d) => {
            const list = byDay.get(d) ?? [];
            return (
              <section key={d} className="card p-3 sm:p-4" aria-label={d}>
                <h2 className="font-bold text-sm mb-2 flex items-center gap-2">
                  {fmtIn(`${d}T12:00:00Z`, 'UTC', 'day')}
                  {d === today && <span className="pill">Today</span>}
                  <span className="muted font-normal">· {list.length} shift{list.length === 1 ? '' : 's'}</span>
                </h2>
                {list.length === 0 ? (
                  <p className="text-sm muted">No shifts.</p>
                ) : (
                  <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
                    {list.map((s) => {
                      const short = s.status !== 'cancelled' && s.assigned < s.requiredWorkers;
                      return (
                        <li key={s.id} className="py-2 flex items-center gap-x-3 gap-y-1 flex-wrap">
                          <Link href={`${W}/shifts/${s.id}`} className="font-semibold text-sm hover:underline tabular-nums whitespace-nowrap">
                            {fmtIn(s.startsAt, s.timezone, 'time')}–{fmtIn(s.endsAt, s.timezone, 'time')}
                          </Link>
                          <span className="text-sm flex-1 min-w-[10rem] break-words">
                            {s.requirementTitle ?? 'Shift'}
                            <span className="muted text-xs">
                              {s.shiftType ? ` · ${SHIFT_LABEL[s.shiftType] ?? s.shiftType}` : ''}
                              {s.kind !== 'regular' ? ` · ${nice(s.kind)}` : ''}
                              {s.atYourSite ? ' · agency' : ''}
                            </span>
                          </span>
                          <span
                            className="text-xs tabular-nums whitespace-nowrap font-semibold"
                            style={{ color: short ? 'var(--color-warn)' : 'var(--color-verified)' }}
                            title="Assigned / required"
                          >
                            {s.assigned}/{s.requiredWorkers}
                            {s.offered ? ` +${s.offered} offered` : ''}
                          </span>
                          <TonePill tone={shiftTone(s.status)} />
                        </li>
                      );
                    })}
                  </ul>
                )}
              </section>
            );
          })}
        </div>
      )}
      {!req && (
        <p className="text-xs muted">
          Create shifts from a requirement (templates or single shifts). Choose one requirement above to assign workers to
          several shifts at once.
        </p>
      )}
    </div>
  );
}
