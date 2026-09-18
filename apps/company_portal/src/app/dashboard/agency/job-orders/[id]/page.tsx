import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import {
  AGENCY_ACTION_ROLES,
  CONSENT_STATUS,
  agencyCan,
  consentTone,
  onlyRoles,
  parseConsents,
  parseSubmissions,
  type ConsentStatus,
} from '@/lib/agency';
import { SHIFT_LABEL, WORKPLACE_LABEL, WORK_TYPE_LABEL, formatPay, timeAgo } from '@/lib/format';
import { calendarDate, monthsLabel, requestNow } from '@/lib/hiring';
import { UUID_RE } from '@/lib/talent';
import { loadTeam } from '@/lib/team';
import ConsentRowItem from '../../candidates/consent-row';
import {
  ErrorNote,
  FilterChips,
  NotVerifiedAgency,
  OrderStatusPill,
  PageHeader,
  PriorityPill,
  Section,
  SubmissionPill,
  Why,
  qs,
} from '../../ui';
import { Recruiters, StatusChanger, type Assigned } from './order-parts';

export const metadata: Metadata = { title: 'Job order · Omelo' };

const CONSENT_ORDER: ConsentStatus[] = ['accepted', 'requested', 'active', 'declined', 'expired', 'revoked', 'withdrawn'];

export default async function JobOrderPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { id } = await params;
  if (!UUID_RE.test(id)) notFound();
  const sp = await searchParams;
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: o, error } = await supabase
    .from('job_orders')
    .select(
      'id, reference, title, client_id, status, priority, openings, profession_id, location_text, workplace_type, work_type, shift_types, pay_min, pay_max, pay_period, pay_currency, min_experience_months, required_skill_ids, hard_requirements, description, start_date, closing_date, notes, client_job_id, created_at, updated_at, agency_clients ( id, name, link_status ), professions ( name )'
    )
    .eq('id', id)
    .eq('agency_id', ctx.companyId)
    .maybeSingle();
  const back = { href: '/dashboard/agency/job-orders', label: 'Job orders' };
  if (error)
    return (
      <div className="space-y-4">
        <PageHeader title="Job order" back={back} />
        <ErrorNote label="this job order" message={error.message} />
      </div>
    );
  if (!o) notFound();

  const [recRes, skillsRes, consentsRes, subsRes, clientJobRes, team] = await Promise.all([
    supabase.from('job_order_recruiters').select('person_id, role').eq('job_order_id', id),
    o.required_skill_ids.length
      ? supabase.from('skills').select('id, name').in('id', o.required_skill_ids)
      : Promise.resolve({ data: [] as { id: string; name: string }[] }),
    supabase.rpc('omelo_agency_candidates', { p_agency: ctx.companyId, p_job_order: id }),
    supabase.rpc('omelo_agency_submissions', { p_agency: ctx.companyId, p_job_order: id }),
    o.client_job_id
      ? supabase.from('jobs').select('title').eq('id', o.client_job_id).maybeSingle()
      : Promise.resolve({ data: null }),
    loadTeam(supabase, ctx.companyId, user?.id ?? null, user?.email ?? null),
  ]);

  const client = o.agency_clients as unknown as { id: string; name: string; link_status: string } | null;
  const profession = (o.professions as unknown as { name: string } | null)?.name ?? null;
  const nameOf = new Map<string, string>();
  for (const m of team.members) if (!nameOf.has(m.personId)) nameOf.set(m.personId, m.name ?? m.email ?? (m.isYou ? 'You' : 'Teammate'));
  const assigned: Assigned[] = (recRes.data ?? [])
    .map((r) => ({
      personId: r.person_id,
      label: `${nameOf.get(r.person_id) ?? 'Teammate'}${r.person_id === user?.id ? ' (you)' : ''}`,
      role: (r.role === 'lead' ? 'lead' : 'support') as 'lead' | 'support',
    }))
    .sort((a, b) => Number(b.role === 'lead') - Number(a.role === 'lead'));
  const assignable = new Set<string>(AGENCY_ACTION_ROLES.request_consent);
  const assignCandidates = [
    ...new Map(
      team.members
        .filter((m) => m.isActive && assignable.has(m.role))
        .map((m) => [m.personId, { personId: m.personId, label: `${m.name ?? m.email ?? 'Teammate'}${m.isYou ? ' (you)' : ''}` }])
    ).values(),
  ];
  const isAdmin = agencyCan(ctx, 'manage_agency');
  const iAmLead = assigned.some((a) => a.personId === user?.id && a.role === 'lead');
  const assignedToMe = assigned.some((a) => a.personId === user?.id);
  const canEdit = agencyCan(ctx, 'create_job_order') && (isAdmin || assignedToMe);

  const consents = parseConsents(consentsRes.data ?? null);
  const submissions = parseSubmissions(subsRes.data ?? null);
  const statusParam = typeof sp.consent === 'string' ? sp.consent : 'all';
  const consentFilter = statusParam === 'all' || (CONSENT_ORDER as string[]).includes(statusParam) ? statusParam : 'all';
  const shownConsents = (consentFilter === 'all' ? consents : consents.filter((c) => c.status === consentFilter)).sort(
    (a, b) => CONSENT_ORDER.indexOf(a.status as ConsentStatus) - CONSENT_ORDER.indexOf(b.status as ConsentStatus)
  );
  const nowMs = requestNow();
  const searchable = ['draft', 'open', 'on_hold'].includes(o.status);
  const canSearch = agencyCan(ctx, 'search_talent');

  const facts: [string, React.ReactNode][] = [
    ['Client', client ? <Link href={`/dashboard/agency/clients/${client.id}`} className="underline">{client.name}</Link> : '—'],
    ['Openings', o.openings],
    ['Profession', profession ?? '—'],
    ['Location', o.location_text ?? '—'],
    ['Workplace', WORKPLACE_LABEL[o.workplace_type] ?? o.workplace_type],
    ['Type', WORK_TYPE_LABEL[o.work_type] ?? o.work_type],
    ['Shifts', o.shift_types.map((s) => SHIFT_LABEL[s] ?? s).join(', ') || '—'],
    ['Pay', formatPay({ min: o.pay_min, max: o.pay_max, period: o.pay_period, currency: o.pay_currency })],
    ['Experience', o.min_experience_months ? `${monthsLabel(o.min_experience_months)}+` : 'None required'],
    ['Start', o.start_date ? calendarDate(o.start_date) : '—'],
    ['Closes', o.closing_date ? calendarDate(o.closing_date) : '—'],
  ];

  return (
    <div className="space-y-6 max-w-5xl">
      <PageHeader
        back={back}
        title={o.title}
        subtitle={
          <span className="inline-flex flex-wrap gap-2 items-center">
            <span>
              {o.reference} · {client?.name ?? 'Client'} · updated {timeAgo(o.updated_at)}
            </span>
            <OrderStatusPill status={o.status} />
            <PriorityPill priority={o.priority} />
          </span>
        }
        action={
          <>
            {canSearch && searchable && (
              <Link href={`/dashboard/agency/talent?order=${o.id}`} className="btn btn-primary w-full sm:w-auto">
                Find candidates
              </Link>
            )}
            {canEdit && (
              <Link href={`/dashboard/agency/job-orders/${o.id}/edit`} className="btn btn-ghost w-full sm:w-auto">
                Edit
              </Link>
            )}
          </>
        }
      />
      {!canSearch && <Why>{onlyRoles('search_talent', 'search for candidates')}</Why>}
      {canSearch && !searchable && <Why>This job order is {o.status.replace('_', ' ')}: reopen it to search for candidates.</Why>}
      {canSearch && searchable && !ctx.isVerified && <NotVerifiedAgency compact />}

      <div className="grid gap-6 lg:grid-cols-3 items-start">
        <div className="space-y-6 lg:col-span-2 min-w-0">
          <Section
            title={`Candidates · ${consents.length}`}
            aside={
              <Link href={`/dashboard/agency/candidates?order=${o.id}`} className="text-sm underline muted">
                Open in Candidates
              </Link>
            }
          >
            {consentsRes.error ? (
              <ErrorNote label="candidates" message={consentsRes.error.message} />
            ) : consents.length === 0 ? (
              <p className="text-sm muted">
                Nobody asked yet. Find candidates and ask for their consent — you can only submit people who say yes.
              </p>
            ) : (
              <>
                <FilterChips
                  label="Filter by consent"
                  active={consentFilter}
                  hrefFor={(v) => `/dashboard/agency/job-orders/${o.id}${qs({ consent: v })}`}
                  options={[
                    { value: 'all', label: 'All', count: consents.length },
                    ...CONSENT_ORDER.filter((s) => consents.some((c) => c.status === s)).map((s) => ({
                      value: s,
                      label: CONSENT_STATUS[s].label,
                      count: consents.filter((c) => c.status === s).length,
                    })),
                  ]}
                />
                <ul className="space-y-3">
                  {shownConsents.map((c) => (
                    <ConsentRowItem
                      key={c.consentId}
                      row={c}
                      nowMs={nowMs}
                      canSubmit={agencyCan(ctx, 'submit')}
                      canWithdraw={agencyCan(ctx, 'request_consent')}
                      canViewDetails={agencyCan(ctx, 'view_candidate_details')}
                      isAdmin={isAdmin}
                      order={{ status: o.status, clientJobId: o.client_job_id, assignedToMe }}
                      showOrder={false}
                    />
                  ))}
                </ul>
              </>
            )}
          </Section>

          <Section title={`Submissions · ${submissions.length}`}>
            {subsRes.error ? (
              <ErrorNote label="submissions" message={subsRes.error.message} />
            ) : submissions.length === 0 ? (
              <p className="text-sm muted">Nobody submitted to this order yet.</p>
            ) : (
              <ul className="divide-y" style={{ borderColor: 'var(--line)' }}>
                {submissions.map((s) => (
                  <li key={s.id} className="py-2.5 flex items-center gap-2 flex-wrap">
                    <div className="flex-1 min-w-[10rem]">
                      <Link href={`/dashboard/agency/submissions/${s.id}`} className="font-semibold text-sm hover:underline break-words">
                        {s.candidate.name}
                      </Link>
                      <p className="text-xs muted break-words">
                        {s.candidate.label ? `as ${s.candidate.label} · ` : ''}submitted {timeAgo(s.submittedAt)}
                        {s.recruiter ? ` by ${s.recruiter}` : ''}
                      </p>
                    </div>
                    <SubmissionPill status={s.status} />
                  </li>
                ))}
              </ul>
            )}
          </Section>

          <Section title="Requirements">
            {o.hard_requirements.length > 0 ? (
              <ul className="list-disc pl-5 text-sm space-y-1">
                {o.hard_requirements.map((r) => (
                  <li key={r} className="break-words">
                    {r}
                  </li>
                ))}
              </ul>
            ) : (
              <p className="text-sm muted">No must-haves listed.</p>
            )}
            {(skillsRes.data ?? []).length > 0 && (
              <div className="flex flex-wrap gap-1.5">
                {(skillsRes.data ?? []).map((s) => (
                  <span key={s.id} className="pill">
                    {s.name}
                  </span>
                ))}
              </div>
            )}
            {o.description && <p className="text-sm whitespace-pre-line break-words">{o.description}</p>}
          </Section>
        </div>

        <div className="space-y-6 min-w-0">
          <Section title="Details">
            {canEdit && <StatusChanger orderId={o.id} status={o.status} />}
            <dl className="text-sm grid grid-cols-[auto_1fr] gap-x-3 gap-y-1.5">
              {facts.map(([k, v]) => (
                <div key={k} className="contents">
                  <dt className="muted">{k}</dt>
                  <dd className="break-words min-w-0">{v}</dd>
                </div>
              ))}
            </dl>
            {o.notes && <p className="text-sm whitespace-pre-line break-words surface rounded-lg p-3">{o.notes}</p>}
          </Section>

          <Section title="Client pipeline">
            {o.client_job_id ? (
              <p className="text-sm">
                The client connected this order to their job
                {clientJobRes.data?.title ? (
                  <>
                    {' '}
                    <strong>{clientJobRes.data.title}</strong>
                  </>
                ) : (
                  ''
                )}
                . Submissions go straight into their hiring pipeline and statuses update here automatically.
              </p>
            ) : client?.link_status === 'confirmed' ? (
              <p className="text-sm muted">
                {client.name} is linked on Omelo but has not connected one of their jobs to this order yet. Until they
                do, share submissions with them yourself and record their answers.
              </p>
            ) : (
              <p className="text-sm muted">
                {client?.name ?? 'This client'} is not linked on Omelo. Share submissions with them yourself and record
                their answers on each submission.
              </p>
            )}
          </Section>

          <Section title="Recruiters">
            <Recruiters orderId={o.id} assigned={assigned} candidates={assignCandidates} canManage={isAdmin || iAmLead} />
            {!(isAdmin || iAmLead) && <Why>Only admins and the lead recruiter can assign people.</Why>}
            <Why>Only assigned recruiters (and admins) can submit candidates to this order.</Why>
          </Section>

          <Section title="Consent at a glance">
            <ul className="text-sm space-y-1">
              {CONSENT_ORDER.map((s) => {
                const n = consents.filter((c) => c.status === s).length;
                if (!n) return null;
                const t = consentTone(s);
                return (
                  <li key={s} className="flex justify-between gap-3">
                    <span style={{ color: t.color }}>{t.label}</span>
                    <span className="tabular-nums font-semibold">{n}</span>
                  </li>
                );
              })}
              {consents.length === 0 && <li className="muted">No requests yet.</li>}
            </ul>
          </Section>
        </div>
      </div>
    </div>
  );
}
