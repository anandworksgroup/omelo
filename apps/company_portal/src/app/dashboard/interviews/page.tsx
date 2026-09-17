import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { INTERVIEW_STATUS_LABEL, INTERVIEW_TYPE_LABEL, requestNow } from '@/lib/hiring';
import LocalTime from '../local-time';

export default async function InterviewsPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  // interviews → persons is ambiguous (person_id and created_by), so hint it.
  const { data, error } = await supabase
    .from('interviews')
    .select(
      `id, application_id, type, status, round, scheduled_at, duration_minutes,
       location_text, candidate_confirmed_at, cancel_reason,
       jobs ( id, title ),
       persons!interviews_person_id_fkey ( display_name )`
    )
    .eq('company_id', ctx.companyId)
    .order('scheduled_at', { ascending: true });

  if (error) {
    return (
      <div className="max-w-3xl space-y-4">
        <h1 className="text-2xl font-bold">Interviews</h1>
        <div className="card p-5" style={{ borderColor: 'var(--color-danger)' }}>
          <p className="font-semibold mb-1" style={{ color: 'var(--color-danger)' }}>
            Could not load interviews
          </p>
          <p className="text-sm muted">{error.message}</p>
        </div>
      </div>
    );
  }

  const all = data ?? [];
  const upcoming = all.filter((i) => i.status === 'scheduled' || i.status === 'rescheduled');
  const past = all
    .filter((i) => i.status !== 'scheduled' && i.status !== 'rescheduled')
    .sort(
      (a, b) =>
        new Date(b.scheduled_at ?? 0).getTime() - new Date(a.scheduled_at ?? 0).getTime()
    );
  const now = requestNow();

  const row = (iv: (typeof all)[number]) => {
    const person = iv.persons as unknown as { display_name: string | null } | null;
    const job = iv.jobs as unknown as { id: string; title: string } | null;
    const live = iv.status === 'scheduled' || iv.status === 'rescheduled';
    const overdue = live && iv.scheduled_at && new Date(iv.scheduled_at).getTime() < now;

    return (
      <Link
        key={iv.id}
        href={`/dashboard/candidates/${iv.application_id}`}
        className="p-4 flex items-start gap-3 sm:gap-4 flex-wrap hover:bg-[var(--surface)]"
      >
        <div className="flex-1 min-w-[12rem]">
          <div className="font-semibold text-sm break-words">
            {person?.display_name ?? 'Candidate'}
          </div>
          <div className="text-xs muted mt-0.5 break-words">
            {job?.title ?? 'A job'} · {INTERVIEW_TYPE_LABEL[iv.type] ?? iv.type} · round {iv.round}
          </div>
          <div className="text-sm mt-1">
            <LocalTime iso={iv.scheduled_at} />
            {iv.duration_minutes ? <span className="muted"> · {iv.duration_minutes} min</span> : null}
          </div>
          {iv.location_text && (
            <div className="text-xs muted mt-0.5 break-words">{iv.location_text}</div>
          )}
          {iv.status === 'cancelled' && iv.cancel_reason && (
            <div className="text-xs muted mt-0.5 break-words">“{iv.cancel_reason}”</div>
          )}
        </div>
        <div className="flex flex-col items-end gap-1.5">
          {live ? (
            overdue ? (
              <span className="pill" style={{ color: 'var(--color-warn)' }}>
                Record outcome
              </span>
            ) : iv.candidate_confirmed_at ? (
              <span className="pill" style={{ color: 'var(--color-verified)' }}>
                ✓ Confirmed
              </span>
            ) : (
              <span className="pill" style={{ color: 'var(--color-warn)' }}>
                Awaiting confirmation
              </span>
            )
          ) : (
            <span
              className="pill"
              style={{
                color: iv.status === 'completed' ? 'var(--color-verified)' : 'var(--color-danger)',
              }}
            >
              {INTERVIEW_STATUS_LABEL[iv.status]}
            </span>
          )}
          {iv.status === 'rescheduled' && <span className="text-xs muted">Rescheduled</span>}
        </div>
      </Link>
    );
  };

  return (
    <div className="space-y-8 max-w-4xl">
      <div>
        <h1 className="text-xl sm:text-2xl font-bold">Interviews</h1>
        <p className="muted text-sm mt-1">
          Schedule interviews from a candidate&apos;s page. Candidates confirm in the Omelo app.
        </p>
      </div>

      <section>
        <h2 className="font-bold text-lg mb-3">Upcoming ({upcoming.length})</h2>
        {upcoming.length === 0 ? (
          <div className="card p-8 text-center text-sm muted">
            No interviews scheduled.{' '}
            <Link href="/dashboard/candidates?tab=shortlisted" className="underline">
              See shortlisted candidates
            </Link>
          </div>
        ) : (
          <div className="card divide-y" style={{ borderColor: 'var(--line)' }}>
            {upcoming.map(row)}
          </div>
        )}
      </section>

      {past.length > 0 && (
        <section>
          <h2 className="font-bold text-lg mb-3">Past ({past.length})</h2>
          <div className="card divide-y" style={{ borderColor: 'var(--line)' }}>
            {past.map(row)}
          </div>
        </section>
      )}
    </div>
  );
}
