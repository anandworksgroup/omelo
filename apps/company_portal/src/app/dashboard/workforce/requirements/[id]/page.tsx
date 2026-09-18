import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createClient, getCompanyContext, getUser } from '@/lib/supabase/server';
import { parseConsents } from '@/lib/agency';
import { STATE_LABEL, WORK_TYPE_LABEL } from '@/lib/format';
import { UUID_RE } from '@/lib/talent';
import { loadTeam, memberName } from '@/lib/team';
import {
  CHECK_IN_LABEL,
  PAY_FREQUENCY_LABEL,
  assignmentTone,
  fmtIn,
  loadWorkerNames,
  nice,
  onlyWf,
  rate,
  requirementTone,
  shiftTone,
  tzShort,
  wfCan,
} from '@/lib/workforce';
import { loadShifts, serverNow } from '../../data';
import { ErrorNote, Facts, PageHeader, Section, Table, TonePill, Why, dateText } from '../../ui';
import { NewShiftForm, OfferPanel, PayComponentsPanel, TemplatesPanel, type Candidate } from './parts';

export const metadata: Metadata = { title: 'Requirement · Workforce · Omelo' };

const W = '/dashboard/workforce';
const OPEN = ['offered', 'accepted', 'active', 'paused'];

export default async function RequirementPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  if (!UUID_RE.test(id)) notFound();
  const ctx = (await getCompanyContext())!;
  const [supabase, user] = await Promise.all([createClient(), getUser()]);
  const { data: r, error } = await supabase
    .from('workforce_requirements')
    .select('*')
    .eq('id', id)
    .eq('company_id', ctx.companyId)
    .maybeSingle();
  if (error) return <ErrorNote label="the requirement" message={error.message} />;
  if (!r) notFound();

  const isAgency = ctx.kind === 'agency';
  const canManage = wfCan(ctx, 'manage_workforce');
  const canPay = wfCan(ctx, 'manage_pay');
  const now = serverNow();

  const [asgRes, tplRes, compRes, policyRes, team, source, shifts] = await Promise.all([
    supabase
      .from('assignments')
      .select('id, person_id, work_identity_id, status, start_date, end_date, pay_rate, pay_period, currency, title, work_identities ( label )')
      .eq('requirement_id', id)
      .order('created_at', { ascending: false })
      .limit(1000),
    supabase.from('shift_templates').select('*').eq('requirement_id', id).order('created_at'),
    supabase.from('pay_components').select('id, kind, name, amount, basis, applies_to_shift_types').eq('requirement_id', id).order('created_at'),
    r.overtime_policy_id
      ? supabase.from('overtime_policies').select('name, multiplier').eq('id', r.overtime_policy_id).maybeSingle()
      : Promise.resolve({ data: null }),
    loadTeam(supabase, ctx.companyId, user?.id ?? null, user?.email ?? null),
    r.job_order_id
      ? supabase.from('job_orders').select('id, reference, title, agency_clients ( name )').eq('id', r.job_order_id).maybeSingle()
      : r.job_id
        ? supabase.from('jobs').select('id, title').eq('id', r.job_id).maybeSingle()
        : Promise.resolve({ data: null }),
    loadShifts(supabase, ctx, new Date(now - 3_600_000).toISOString(), new Date(now + 14 * 86_400_000).toISOString(), {
      requirementId: id,
      limit: 20,
    }),
  ]);

  const assignments = asgRes.data ?? [];
  const names = await loadWorkerNames(
    supabase,
    ctx,
    assignments.map((a) => ({ personId: a.person_id, identityId: a.work_identity_id }))
  );
  const filled = assignments.filter((a) => ['accepted', 'active', 'paused'].includes(a.status)).length;
  const offered = assignments.filter((a) => a.status === 'offered').length;
  const openByIdentity = new Map(assignments.filter((a) => OPEN.includes(a.status)).map((a) => [a.work_identity_id, a.status]));
  const openByPerson = new Map(assignments.filter((a) => OPEN.includes(a.status)).map((a) => [a.person_id, a.status]));

  // Who can be offered this work.
  let candidates: Candidate[] = [];
  let candidateError: string | null = null;
  if (canManage && ['open', 'filled', 'active'].includes(r.status)) {
    if (isAgency && r.job_order_id) {
      const res = await supabase.rpc('omelo_agency_candidates', { p_agency: ctx.companyId, p_job_order: r.job_order_id });
      candidateError = res.error?.message ?? null;
      candidates = parseConsents(res.data ?? null)
        .filter((c) => (c.status === 'accepted' || c.status === 'active' || c.submission?.status === 'hired') && c.card?.workIdentityId)
        .map((c) => ({
          identityId: c.card!.workIdentityId,
          name: c.name,
          detail: [c.card?.label ?? c.card?.profession, c.submission ? `submission: ${c.submission.status}` : 'consent given']
            .filter(Boolean)
            .join(' · '),
          existing: openByIdentity.get(c.card!.workIdentityId) ?? null,
        }));
    } else if (!isAgency) {
      let q = supabase
        .from('applications')
        .select('id, person_id, work_identity_id, state, jobs ( title ), persons!applications_person_id_fkey ( display_name ), work_identities ( label )')
        .eq('company_id', ctx.companyId)
        .not('state', 'in', '(rejected,withdrawn,expired,declined_by_candidate)')
        .order('applied_at', { ascending: false })
        .limit(500);
      if (r.job_id) q = q.eq('job_id', r.job_id);
      const res = await q;
      candidateError = res.error?.message ?? null;
      const seen = new Set<string>();
      for (const a of res.data ?? []) {
        if (seen.has(a.work_identity_id)) continue;
        seen.add(a.work_identity_id);
        const p = a.persons as unknown as { display_name: string | null } | null;
        const wi = a.work_identities as unknown as { label: string | null } | null;
        const job = a.jobs as unknown as { title: string } | null;
        candidates.push({
          identityId: a.work_identity_id,
          name: p?.display_name ?? 'Applicant',
          detail: [wi?.label, r.job_id ? null : job?.title, STATE_LABEL[a.state] ?? a.state].filter(Boolean).join(' · '),
          existing: openByIdentity.get(a.work_identity_id) ?? openByPerson.get(a.person_id) ?? null,
        });
      }
    }
  }

  const supervisor = team.members.find((m) => m.personId === r.supervisor_id);
  const policy = policyRes.data as { name: string; multiplier: number } | null;
  const src = source.data as { id: string; title: string; reference?: string; agency_clients?: { name: string } | null } | null;
  const talentHref = isAgency ? `/dashboard/agency/talent?order=${r.job_order_id}` : r.job_id ? `/dashboard/talent?job=${r.job_id}` : '/dashboard/talent';
  const liveReq = ['open', 'filled', 'active'].includes(r.status);

  return (
    <div className="space-y-6">
      <PageHeader
        back={{ href: `${W}/requirements`, label: 'Requirements' }}
        title={r.title}
        subtitle={
          <span className="inline-flex gap-2 items-center flex-wrap">
            <TonePill tone={requirementTone(r.status)} />
            {src &&
              (isAgency ? (
                <Link href={`/dashboard/agency/job-orders/${src.id}`} className="underline">
                  {src.reference ? `${src.reference} · ` : ''}
                  {src.title}
                  {src.agency_clients?.name ? ` · ${src.agency_clients.name}` : ''}
                </Link>
              ) : (
                <Link href={`/dashboard/jobs/${src.id}`} className="underline">
                  Job: {src.title}
                </Link>
              ))}
          </span>
        }
        action={
          canManage ? (
            <>
              <Link href={`${W}/requirements/${id}/edit`} className="btn btn-ghost w-full sm:w-auto">
                Edit
              </Link>
              <Link href={`${W}/shifts?req=${id}`} className="btn btn-ghost w-full sm:w-auto">
                Schedule
              </Link>
            </>
          ) : undefined
        }
      />

      <Section title="Details">
        <div className="space-y-1">
          <div className="flex items-baseline gap-2 flex-wrap">
            <span className="text-3xl font-black tabular-nums">{filled.toLocaleString('en-IN')}</span>
            <span className="muted">of {r.openings.toLocaleString('en-IN')} openings filled</span>
            {offered > 0 && <span className="muted">· {offered} offer{offered === 1 ? '' : 's'} waiting</span>}
          </div>
          <div className="h-2 rounded-full overflow-hidden" style={{ background: 'var(--surface)' }} aria-hidden>
            <div className="h-full" style={{ width: `${Math.min(100, (filled / Math.max(1, r.openings)) * 100)}%`, background: 'var(--color-brand-600)' }} />
          </div>
        </div>
        <Facts
          items={[
            ['Dates', `${dateText(r.start_date)}${r.end_date ? ` – ${dateText(r.end_date)}` : ' onwards'}`],
            ['Site', [r.site_name, r.location_text].filter(Boolean).join(', ') || '—'],
            ['Time zone', tzShort(r.timezone)],
            ['Employment', `${nice(r.employment_type)} · ${WORK_TYPE_LABEL[r.work_type] ?? r.work_type}`],
            ['Pay', rate(r.pay_rate, r.currency, r.pay_period)],
            ['Paid', PAY_FREQUENCY_LABEL[r.pay_frequency] ?? r.pay_frequency],
            ['Hours a week', r.hours_per_week != null ? String(r.hours_per_week) : '—'],
            ['Check-in', `${CHECK_IN_LABEL[r.check_in_method] ?? r.check_in_method}${r.geofence_radius_m ? ` (${r.geofence_radius_m} m)` : ''}`],
            ['Late grace', `${r.late_grace_minutes} min`],
            ['Overtime', policy ? `${policy.name} (×${policy.multiplier})` : 'No policy — extra hours at the normal rate'],
            ['Supervisor', supervisor ? memberName(supervisor) : r.supervisor_id ? 'Client’s supervisor' : '—'],
          ]}
        />
        {r.notes && <p className="text-sm whitespace-pre-wrap break-words">{r.notes}</p>}
      </Section>

      {canManage && (
        <Section
          title={isAgency ? 'Offer to consented candidates' : 'Offer to applicants'}
          aside={
            <Link href={talentHref} className="text-sm underline muted">
              Find more talent
            </Link>
          }
        >
          {!liveReq ? (
            <Why>The requirement is {requirementTone(r.status).label.toLowerCase()}; set it to open to offer work.</Why>
          ) : candidateError ? (
            <ErrorNote label="candidates" message={candidateError} />
          ) : (
            <OfferPanel
              requirementId={id}
              candidates={candidates}
              canBill={isAgency && canPay}
              isAgency={isAgency}
              canManageJobs={canManage}
            />
          )}
        </Section>
      )}

      <Section
        title={`Assignments (${assignments.length})`}
        aside={
          <Link href={`${W}/assignments?req=${id}`} className="text-sm underline muted">
            Filter list
          </Link>
        }
      >
        {asgRes.error ? (
          <ErrorNote label="assignments" message={asgRes.error.message} />
        ) : assignments.length === 0 ? (
          <p className="text-sm muted">No one has been offered this work yet.</p>
        ) : (
          <Table head={['Worker', 'Status', 'Dates', 'Pay']}>
            {assignments.slice(0, 200).map((a) => (
              <tr key={a.id}>
                <td className="py-2 pr-3">
                  <Link href={`${W}/assignments/${a.id}`} className="font-semibold hover:underline">
                    {names.get(a.person_id) ?? (a.work_identities as unknown as { label: string } | null)?.label ?? 'Worker'}
                  </Link>
                </td>
                <td className="py-2 pr-3">
                  <TonePill tone={assignmentTone(a.status)} />
                </td>
                <td className="py-2 pr-3 whitespace-nowrap">
                  {dateText(a.start_date)}
                  {a.end_date ? ` – ${dateText(a.end_date)}` : ''}
                </td>
                <td className="py-2 pr-3 whitespace-nowrap">{rate(a.pay_rate, a.currency, a.pay_period)}</td>
              </tr>
            ))}
          </Table>
        )}
      </Section>

      <div className="grid gap-6 lg:grid-cols-2 items-start">
        <Section title="Shift templates">
          <TemplatesPanel
            requirementId={id}
            canManage={canManage && liveReq}
            templates={(tplRes.data ?? []).map((t) => ({
              id: t.id,
              name: t.name,
              days: t.days_of_week,
              start: t.start_time.slice(0, 5),
              end: t.end_time.slice(0, 5),
              breakMinutes: t.break_minutes,
              requiredWorkers: t.required_workers,
              shiftType: t.shift_type,
              validFrom: t.valid_from,
              validUntil: t.valid_until,
              status: t.status,
            }))}
          />
        </Section>

        <Section
          title="Next shifts"
          aside={
            <Link href={`${W}/shifts?req=${id}`} className="text-sm underline muted">
              All
            </Link>
          }
        >
          {shifts.error ? (
            <ErrorNote label="shifts" message={shifts.error} />
          ) : shifts.shifts.length === 0 ? (
            <p className="text-sm muted">No shifts in the next two weeks.</p>
          ) : (
            <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
              {shifts.shifts.map((s) => (
                <li key={s.id} className="py-2 flex items-center gap-2 flex-wrap text-sm">
                  <Link href={`${W}/shifts/${s.id}`} className="flex-1 min-w-[10rem] hover:underline">
                    {fmtIn(s.startsAt, s.timezone, 'datetime')}–{fmtIn(s.endsAt, s.timezone, 'time')}
                  </Link>
                  <span className="tabular-nums text-xs">
                    {s.assigned}/{s.requiredWorkers}
                  </span>
                  <TonePill tone={shiftTone(s.status)} />
                </li>
              ))}
            </ul>
          )}
          {canManage && liveReq && <NewShiftForm requirementId={id} tz={r.timezone} />}
        </Section>
      </div>

      <Section title="Allowances, bonuses and deductions">
        <p className="text-xs muted">
          Added to earnings when a timesheet is approved, as separate lines.
          {!canPay ? ` ${onlyWf(ctx.kind, 'manage_pay', 'change them')}` : ''}
        </p>
        <PayComponentsPanel
          requirementId={id}
          assignmentId={null}
          currency={r.currency}
          canPay={canPay}
          components={(compRes.data ?? []).map((c) => ({
            id: c.id,
            kind: c.kind,
            name: c.name,
            amount: Number(c.amount),
            basis: c.basis,
            shiftTypes: c.applies_to_shift_types ?? [],
          }))}
        />
      </Section>
    </div>
  );
}
