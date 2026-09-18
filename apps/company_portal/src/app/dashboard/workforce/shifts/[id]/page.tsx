import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { SHIFT_LABEL } from '@/lib/format';
import { UUID_RE } from '@/lib/talent';
import {
  EXCEPTION_LABEL,
  attendanceTone,
  fmtIn,
  hours,
  loadWorkerNames,
  nice,
  onlyWf,
  parseReplacements,
  parseRoster,
  reviewTone,
  shiftTone,
  shiftWorkerTone,
  tzShort,
  utcToZonedInput,
  wfCan,
} from '@/lib/workforce';
import { ErrorNote, ExceptionsAreForReview, Notice, PageHeader, Section, TonePill, Why } from '../../ui';
import { AssignPanel, ReplacementList, ShiftEditor, WorkerActions } from './parts';

export const metadata: Metadata = { title: 'Shift · Workforce · Omelo' };

const W = '/dashboard/workforce';

export default async function ShiftPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID_RE.test(id)) notFound();
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const rosterRes = await supabase.rpc('omelo_shift_roster', { p_shift: id });
  const back = { href: `${W}/shifts`, label: 'Schedule' };
  if (rosterRes.error) {
    return (
      <div className="space-y-5">
        <PageHeader title="Shift" back={back} />
        <Notice title="This shift is not available">{rosterRes.error.message}</Notice>
      </div>
    );
  }
  const roster = parseRoster(rosterRes.data);
  const s = roster.shift;
  if (!s) notFound();
  const tz = s.timezone;
  const own = s.companyId === ctx.companyId;

  // Who approves time here: the client company for agency workers at a
  // client confirmed on Omelo, otherwise the managing company.
  const { data: req } = own
    ? await supabase.from('workforce_requirements').select('id, title, client_id, job_id, job_order_id').eq('id', s.requirementId).maybeSingle()
    : { data: null };
  const { data: client } = req?.client_id
    ? await supabase.from('agency_clients').select('name, link_status, client_company_id').eq('id', req.client_id).maybeSingle()
    : { data: null };
  const clientApproves = own && !!client && client.link_status === 'confirmed' && !!client.client_company_id;
  const canManage = own && wfCan(ctx, 'manage_workforce');
  const canRecord = wfCan(ctx, 'approve_time') && !clientApproves;
  const live = s.status === 'scheduled' || s.status === 'in_progress';

  const assigned = roster.workers.filter((w) => ['assigned', 'completed', 'absent'].includes(w.status)).length;
  const open = Math.max(0, s.requiredWorkers - assigned);

  const [asgRes, replRes] = await Promise.all([
    canManage && live
      ? supabase
          .from('assignments')
          .select('id, person_id, work_identity_id, title, status, start_date, end_date')
          .eq('requirement_id', s.requirementId)
          .in('status', ['accepted', 'active'])
          .limit(1000)
      : Promise.resolve({
          data: [] as { id: string; person_id: string; work_identity_id: string; title: string; status: string; start_date: string; end_date: string | null }[],
          error: null,
        }),
    canManage && live ? supabase.rpc('omelo_shift_replacements', { p_shift: id }) : Promise.resolve({ data: null, error: null }),
  ]);
  const onShift = new Set(roster.workers.filter((w) => ['assigned', 'offered', 'completed'].includes(w.status)).map((w) => w.assignmentId));
  const pool = (asgRes.data ?? []).filter((a) => !onShift.has(a.id));
  const names = await loadWorkerNames(supabase, ctx, pool.map((a) => ({ personId: a.person_id, identityId: a.work_identity_id })));
  const repl = parseReplacements(replRes.data ?? null);
  const externalHref = repl.external?.jobOrderId
    ? `/dashboard/agency/talent?order=${repl.external.jobOrderId}`
    : repl.external?.jobId
      ? `/dashboard/talent?job=${repl.external.jobId}`
      : null;

  return (
    <div className="space-y-6">
      <PageHeader
        back={back}
        title={`${fmtIn(s.startsAt, tz, 'datetime')}–${fmtIn(s.endsAt, tz, 'time')}`}
        subtitle={
          <span className="inline-flex gap-2 items-center flex-wrap">
            <TonePill tone={shiftTone(s.status)} />
            {req ? (
              <Link href={`${W}/requirements/${req.id}`} className="underline">
                {req.title}
              </Link>
            ) : (
              <span>Agency workers at your site</span>
            )}
            <span>
              {tzShort(tz)}
              {s.shiftType ? ` · ${SHIFT_LABEL[s.shiftType] ?? s.shiftType}` : ''}
              {s.kind !== 'regular' ? ` · ${nice(s.kind)}` : ''}
              {client ? ` · at ${client.name}` : ''}
            </span>
          </span>
        }
      />

      <div className="grid gap-6 lg:grid-cols-3 items-start">
        <Section title="Check-in code">
          {roster.code ? (
            <div className="text-center space-y-2">
              <p
                className="font-black tabular-nums tracking-[0.2em] break-all"
                style={{ fontSize: 'clamp(2.25rem, 12vw, 3.75rem)', color: 'var(--color-brand-700)' }}
                aria-label={`Check-in code ${roster.code.split('').join(' ')}`}
              >
                {roster.code}
              </p>
              <p className="text-xs muted">
                Show this to workers at the start of the shift; they enter it in the app when check-in is by code. Keep it
                private — anyone with it can check in to this shift.
              </p>
            </div>
          ) : (
            <Why>{onlyWf(ctx.kind, 'approve_time', 'see check-in codes')}</Why>
          )}
        </Section>

        <Section title="Shift">
          <dl className="text-sm space-y-1.5">
            <div className="flex gap-2">
              <dt className="muted w-28 shrink-0">Workers</dt>
              <dd>
                <strong>{assigned}</strong> of {s.requiredWorkers} assigned{open ? ` · ${open} open` : ''}
              </dd>
            </div>
            <div className="flex gap-2">
              <dt className="muted w-28 shrink-0">Break</dt>
              <dd>{s.breakMinutes} min</dd>
            </div>
            <div className="flex gap-2">
              <dt className="muted w-28 shrink-0">Where</dt>
              <dd className="break-words min-w-0">{s.locationText || '—'}</dd>
            </div>
            {s.instructions && (
              <div className="flex gap-2">
                <dt className="muted w-28 shrink-0">Instructions</dt>
                <dd className="break-words min-w-0">{s.instructions}</dd>
              </div>
            )}
            {s.cancelReason && (
              <div className="flex gap-2">
                <dt className="muted w-28 shrink-0">Cancelled</dt>
                <dd className="break-words min-w-0">{s.cancelReason}</dd>
              </div>
            )}
          </dl>
        </Section>

        <Section title="Manage">
          {canManage && live ? (
            <ShiftEditor
              id={id}
              tz={tz}
              startsAt={utcToZonedInput(s.startsAt, tz)}
              endsAt={utcToZonedInput(s.endsAt, tz)}
              breakMinutes={s.breakMinutes}
              requiredWorkers={s.requiredWorkers}
              instructions={s.instructions ?? ''}
            />
          ) : (
            <Why>
              {!own
                ? 'The agency manages this shift. You see its roster and approve time for its workers at your site.'
                : !live
                  ? `This shift is ${shiftTone(s.status).label.toLowerCase()}.`
                  : onlyWf(ctx.kind, 'manage_workforce', 'change shifts')}
            </Why>
          )}
        </Section>
      </div>

      <Section title={`Roster (${roster.workers.length})`}>
        {clientApproves && (
          <p className="text-xs muted">
            {client?.name ?? 'The client'} approves attendance at its site; you see it here as it happens.
          </p>
        )}
        <ExceptionsAreForReview />
        {roster.workers.length === 0 ? (
          <p className="text-sm muted">Nobody is on this shift yet.</p>
        ) : (
          <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
            {roster.workers.map((w) => {
              const a = w.attendance;
              const onIt = ['assigned', 'completed', 'absent'].includes(w.status);
              return (
                <li key={w.shiftWorkerId} className="py-3 flex items-center gap-x-3 gap-y-1.5 flex-wrap">
                  <div className="flex-1 min-w-[10rem]">
                    <p className="font-semibold text-sm break-words">
                      {own ? (
                        <Link href={`${W}/assignments/${w.assignmentId}`} className="hover:underline">
                          {w.name}
                        </Link>
                      ) : (
                        w.name
                      )}
                    </p>
                    <p className="text-xs muted">
                      {a?.checkInAt ? `In ${fmtIn(a.checkInAt, tz, 'time')}` : 'Not checked in'}
                      {a?.checkOutAt ? ` · out ${fmtIn(a.checkOutAt, tz, 'time')}` : ''}
                      {a?.workedMinutes != null ? ` · ${hours(a.workedMinutes)}` : ''}
                    </p>
                  </div>
                  <TonePill tone={shiftWorkerTone(w.status)} />
                  {a && <TonePill tone={attendanceTone(a.status)} />}
                  {a && a.reviewStatus !== 'none' && <TonePill tone={reviewTone(a.reviewStatus)} />}
                  {a?.exceptions
                    .filter((x) => x.status === 'pending')
                    .map((x) => (
                      <span key={x.id} className="pill" style={{ color: 'var(--color-warn)', borderColor: 'var(--color-warn)' }}>
                        {EXCEPTION_LABEL[x.kind] ?? x.kind}
                        {x.minutes ? ` ${x.minutes} min` : ''}
                      </span>
                    ))}
                  {a && (
                    <Link href={`${W}/attendance/${a.id}`} className="text-xs underline muted">
                      Attendance
                    </Link>
                  )}
                  <WorkerActions
                    shiftWorkerId={w.shiftWorkerId}
                    tz={tz}
                    defaultIn={utcToZonedInput(a?.checkInAt ?? s.startsAt, tz)}
                    defaultOut={utcToZonedInput(a?.checkOutAt ?? s.endsAt, tz)}
                    canRecord={
                      canRecord &&
                      onIt &&
                      s.status !== 'cancelled' &&
                      !(a && ['approved', 'adjusted', 'rejected'].includes(a.reviewStatus))
                    }
                    canUnassign={canManage && live && ['assigned', 'offered'].includes(w.status) && !a?.checkInAt}
                    recorded={!!a}
                  />
                </li>
              );
            })}
          </ul>
        )}
      </Section>

      {canManage && live && (
        <div className="grid gap-6 lg:grid-cols-2 items-start">
          <Section title="Assign workers">
            {asgRes.error ? (
              <ErrorNote label="workers" message={asgRes.error.message} />
            ) : (
              <AssignPanel
                shiftId={id}
                open={open}
                workers={pool.map((a) => ({
                  id: a.id,
                  label: names.get(a.person_id) ?? 'Worker',
                  detail: `${a.title} · ${a.status}`,
                }))}
              />
            )}
          </Section>
          <Section
            title={`Replacements${repl.open ? ` · ${repl.open} open` : ''}`}
            aside={
              externalHref ? (
                <Link href={externalHref} className="text-sm underline muted">
                  Search outside
                </Link>
              ) : undefined
            }
          >
            {replRes.error ? (
              <ErrorNote label="replacements" message={replRes.error.message} />
            ) : (
              <>
                <p className="text-xs muted">
                  Workers on this requirement who are free at this time, not on leave and within their assignment dates.
                </p>
                <ReplacementList shiftId={id} candidates={repl.candidates} />
              </>
            )}
          </Section>
        </div>
      )}
    </div>
  );
}
