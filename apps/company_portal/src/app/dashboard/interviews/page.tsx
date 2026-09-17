import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { INTERVIEW_STATUS_LABEL, requestNow } from '@/lib/hiring';
import { meetingModeLabel } from '@/lib/meet';
import JoinButton from '@/components/interview/join-button';
import LocalTime from '../local-time';

type Room = { room_name: string; status: string; opens_at: string; closes_at: string } | null;

export default async function InterviewsPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // interviews → persons is ambiguous (person_id and created_by), so hint it.
  const [{ data, error }, panelRes, feedbackRes] = await Promise.all([
    supabase
      .from('interviews')
      .select(
        `id, application_id, status, round, round_name, meeting_mode, scheduled_at, duration_minutes,
         location_text, candidate_confirmed_at, cancel_reason,
         jobs ( id, title ),
         persons!interviews_person_id_fkey ( display_name ),
         interview_rooms ( room_name, status, opens_at, closes_at )`
      )
      .eq('company_id', ctx.companyId)
      .order('scheduled_at', { ascending: true }),
    // Rounds I sit on, and the feedback I have already submitted.
    user
      ? supabase.from('interview_interviewers').select('interview_id').eq('person_id', user.id)
      : Promise.resolve({ data: [] as { interview_id: string }[] }),
    user
      ? supabase
          .from('interview_feedback')
          .select('interview_id, status')
          .eq('interviewer_id', user.id)
      : Promise.resolve({ data: [] as { interview_id: string; status: string }[] }),
  ]);

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

  const mine = new Set((panelRes.data ?? []).map((p) => p.interview_id));
  const submitted = new Set(
    (feedbackRes.data ?? []).filter((f) => f.status === 'submitted').map((f) => f.interview_id)
  );

  const all = data ?? [];
  const upcoming = all.filter((i) => i.status === 'scheduled' || i.status === 'rescheduled');
  const past = all
    .filter((i) => i.status !== 'scheduled' && i.status !== 'rescheduled')
    .sort(
      (a, b) =>
        new Date(b.scheduled_at ?? 0).getTime() - new Date(a.scheduled_at ?? 0).getTime()
    );
  const feedbackDue = past.filter((i) => i.status === 'completed' && mine.has(i.id) && !submitted.has(i.id));
  const now = requestNow();

  const row = (iv: (typeof all)[number]) => {
    const person = iv.persons as unknown as { display_name: string | null } | null;
    const job = iv.jobs as unknown as { id: string; title: string } | null;
    const room = iv.interview_rooms as unknown as Room;
    const live = iv.status === 'scheduled' || iv.status === 'rescheduled';
    const meet = iv.meeting_mode === 'omelo_meet';
    const endMs = iv.scheduled_at
      ? new Date(iv.scheduled_at).getTime() + (iv.duration_minutes ?? 30) * 60_000
      : null;
    const overdue = live && endMs != null && endMs < now && (!meet || !room || new Date(room.closes_at).getTime() < now);
    const due = feedbackDue.includes(iv);
    const href = `/dashboard/candidates/${iv.application_id}`;

    return (
      <li key={iv.id} className="p-4 flex items-start gap-3 sm:gap-4 flex-wrap">
        <Link href={href} className="flex-1 min-w-[12rem] hover:opacity-80">
          <div className="font-semibold text-sm break-words">
            {person?.display_name ?? 'Candidate'}
            <span className="font-normal muted"> · {iv.round_name ?? 'Interview'}</span>
          </div>
          <div className="text-xs muted mt-0.5 break-words">
            {job?.title ?? 'A job'} · Interview #{iv.round} · {meetingModeLabel(iv.meeting_mode)}
          </div>
          <div className="text-sm mt-1">
            <LocalTime iso={iv.scheduled_at} />
            {iv.duration_minutes ? <span className="muted"> · {iv.duration_minutes} min</span> : null}
          </div>
          {!meet && iv.location_text && (
            <div className="text-xs muted mt-0.5 break-words">{iv.location_text}</div>
          )}
          {iv.status === 'cancelled' && iv.cancel_reason && (
            <div className="text-xs muted mt-0.5 break-words">“{iv.cancel_reason}”</div>
          )}
        </Link>
        <div className="flex flex-col items-end gap-1.5 ml-auto">
          {live ? (
            <>
              {meet && room && (
                <JoinButton
                  roomName={room.room_name}
                  opensAt={room.opens_at}
                  closesAt={room.closes_at}
                  roomStatus={room.status}
                  compact
                />
              )}
              {overdue ? (
                <Link href={href} className="pill" style={{ color: 'var(--color-warn)' }}>
                  Record outcome
                </Link>
              ) : iv.candidate_confirmed_at ? (
                <span className="pill" style={{ color: 'var(--color-verified)' }}>
                  ✓ Confirmed
                </span>
              ) : (
                <span className="pill" style={{ color: 'var(--color-warn)' }}>
                  Awaiting confirmation
                </span>
              )}
              {iv.status === 'rescheduled' && <span className="text-xs muted">Rescheduled</span>}
            </>
          ) : (
            <>
              <span
                className="pill"
                style={{
                  color: iv.status === 'completed' ? 'var(--color-verified)' : 'var(--color-danger)',
                }}
              >
                {INTERVIEW_STATUS_LABEL[iv.status]}
              </span>
              {due && (
                <Link
                  href={`${href}#interview-${iv.id}`}
                  className="pill"
                  style={{ color: 'var(--color-warn)', borderColor: 'var(--color-warn)' }}
                >
                  Feedback due
                </Link>
              )}
            </>
          )}
        </div>
      </li>
    );
  };

  return (
    <div className="space-y-8 max-w-4xl">
      <div>
        <h1 className="text-xl sm:text-2xl font-bold">Interviews</h1>
        <p className="muted text-sm mt-1">
          Schedule interviews from a candidate&apos;s page. Omelo Meet rounds happen inside
          Omelo — the room opens 15 minutes before the start.
        </p>
      </div>

      {feedbackDue.length > 0 && (
        <section className="card p-4" style={{ borderColor: 'var(--color-warn)' }}>
          <p className="font-semibold text-sm">
            Feedback due for {feedbackDue.length} interview{feedbackDue.length === 1 ? '' : 's'}
          </p>
          <p className="text-sm muted mt-0.5">Record it while it is fresh — your team is waiting on it to decide.</p>
        </section>
      )}

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
          <ul className="card divide-y" style={{ borderColor: 'var(--line)' }}>
            {upcoming.map(row)}
          </ul>
        )}
      </section>

      {past.length > 0 && (
        <section>
          <h2 className="font-bold text-lg mb-3">Past ({past.length})</h2>
          <ul className="card divide-y" style={{ borderColor: 'var(--line)' }}>
            {past.map(row)}
          </ul>
        </section>
      )}
    </div>
  );
}
