import { INTERVIEW_STATUS_LABEL, type InterviewStatus } from '@/lib/hiring';
import {
  ASSESSMENT_OPTIONS,
  asCompetencies,
  asSkills,
  meetingModeLabel,
  recommendationLabel,
  roundKindLabel,
} from '@/lib/meet';
import LocalTime from '../../local-time';
import JoinButton from '@/components/interview/join-button';
import { FeedbackEditor } from '@/components/interview/feedback-forms';
import { CancelInterviewForm, CompleteInterviewForm, RescheduleForm } from '../forms';

export type RoundInterview = {
  id: string;
  status: InterviewStatus;
  round: number;
  round_name: string | null;
  round_kind: string | null;
  meeting_mode: string;
  scheduled_at: string | null;
  duration_minutes: number | null;
  location_text: string | null;
  instructions: string | null;
  candidate_confirmed_at: string | null;
  cancel_reason: string | null;
  room: {
    room_name: string;
    status: string;
    opens_at: string;
    closes_at: string;
    started_at: string | null;
    ended_at: string | null;
  } | null;
};

export type RoundFeedback = {
  id: string;
  interview_id: string;
  interviewer_id: string;
  recommendation: string | null;
  overall_rating: number | null;
  strengths: string | null;
  concerns: string | null;
  notes: string | null;
  competencies: unknown;
  skills_assessed: unknown;
  status: string;
  submitted_at: string | null;
  updated_at: string;
};

const LIVE: InterviewStatus[] = ['scheduled', 'rescheduled'];

function statusColor(s: InterviewStatus) {
  if (LIVE.includes(s)) return 'var(--fg)';
  if (s === 'completed') return 'var(--color-verified)';
  return 'var(--color-danger)';
}

function FeedbackCard({ fb, name }: { fb: RoundFeedback; name: string }) {
  const rec = recommendationLabel(fb.recommendation);
  const comps = asCompetencies(fb.competencies).filter((c) => c.assessment !== 'not_assessed');
  const skills = asSkills(fb.skills_assessed);
  const shown = skills.filter((s) => s.demonstrated);
  const notShown = skills.filter((s) => !s.demonstrated);
  return (
    <li className="surface rounded-lg p-3 space-y-2">
      <div className="flex items-center gap-2 flex-wrap">
        <span className="font-semibold text-sm">{name}</span>
        {rec ? (
          <span className="pill" style={{ color: rec.tone, borderColor: rec.tone }}>
            {rec.label}
          </span>
        ) : (
          <span className="pill">No recommendation yet</span>
        )}
        {fb.overall_rating != null && <span className="pill">{fb.overall_rating}/5</span>}
        <span
          className="text-xs ml-auto"
          style={{ color: fb.status === 'submitted' ? 'var(--color-verified)' : 'var(--color-warn)' }}
        >
          {fb.status === 'submitted' ? '✓ Submitted' : 'Draft'}
        </span>
      </div>
      {fb.strengths && (
        <p className="text-sm break-words whitespace-pre-line">
          <span className="font-medium">Strengths: </span>
          {fb.strengths}
        </p>
      )}
      {fb.concerns && (
        <p className="text-sm break-words whitespace-pre-line">
          <span className="font-medium">Concerns: </span>
          {fb.concerns}
        </p>
      )}
      {comps.length > 0 && (
        <ul className="text-sm space-y-0.5">
          {comps.map((c) => {
            const a = ASSESSMENT_OPTIONS.find((o) => o.value === c.assessment)!;
            return (
              <li key={c.name} className="break-words">
                {c.name}: <span style={{ color: a.tone }} className="font-semibold">{a.label}</span>
              </li>
            );
          })}
        </ul>
      )}
      {skills.length > 0 && (
        <div className="flex flex-wrap gap-1.5">
          {shown.map((s) => (
            <span key={s.name} className="pill" style={{ color: 'var(--color-verified)' }}>
              ✓ {s.name}
            </span>
          ))}
          {notShown.map((s) => (
            <span key={s.name} className="pill">
              {s.name} · not shown
            </span>
          ))}
        </div>
      )}
      {fb.notes && <p className="text-sm muted break-words whitespace-pre-line">{fb.notes}</p>}
    </li>
  );
}

/**
 * "Interview rounds" on the candidate page: every round, its Omelo Meet
 * room, logistics, and the panel's private feedback.
 */
export default function InterviewRounds({
  interviews,
  feedback,
  panels,
  names,
  userId,
  isHiringTeam,
  jobId,
  canManage,
}: {
  interviews: RoundInterview[];
  feedback: RoundFeedback[];
  panels: Record<string, string[]>;
  names: Record<string, string>;
  userId: string | null;
  isHiringTeam: boolean;
  jobId: string;
  canManage: boolean;
}) {
  const nameOf = (id: string) => (id === userId ? 'You' : (names[id] ?? 'Teammate'));

  return (
    <ol className="space-y-4">
      {interviews.map((iv) => {
        const live = LIVE.includes(iv.status);
        const panel = panels[iv.id] ?? [];
        const fbs = feedback.filter((f) => f.interview_id === iv.id);
        const awaiting = panel.filter((p) => !fbs.some((f) => f.interviewer_id === p && f.status === 'submitted'));
        const mine = fbs.find((f) => f.interviewer_id === userId) ?? null;
        const canGiveFeedback = (isHiringTeam || (userId != null && panel.includes(userId))) && iv.status !== 'cancelled';
        const showFeedback = iv.status === 'completed' || fbs.length > 0;
        const meet = iv.meeting_mode === 'omelo_meet';

        return (
          <li
            key={iv.id}
            id={`interview-${iv.id}`}
            className="rounded-xl border hairline p-4 space-y-3 scroll-mt-6"
          >
            <div className="flex items-start gap-2 flex-wrap">
              <div className="flex-1 min-w-[12rem]">
                <p className="font-semibold text-sm break-words">
                  Interview #{iv.round} · {iv.round_name ?? 'Interview'}
                </p>
                <p className="text-xs muted mt-0.5">
                  {roundKindLabel(iv.round_kind)} · {meetingModeLabel(iv.meeting_mode)}
                  {iv.duration_minutes ? ` · ${iv.duration_minutes} min` : ''}
                </p>
              </div>
              <span className="pill" style={{ color: statusColor(iv.status) }}>
                {iv.room?.status === 'live' && live ? '● Live now' : INTERVIEW_STATUS_LABEL[iv.status]}
              </span>
            </div>

            <div className="text-sm">
              <LocalTime iso={iv.scheduled_at} />
            </div>

            {live && (
              <p
                className="text-xs font-semibold"
                style={{ color: iv.candidate_confirmed_at ? 'var(--color-verified)' : 'var(--color-warn)' }}
              >
                {iv.candidate_confirmed_at ? '✓ Confirmed by candidate' : 'Awaiting confirmation from the candidate'}
              </p>
            )}
            {!meet && iv.location_text && <p className="text-sm muted break-words">{iv.location_text}</p>}
            {iv.instructions && (
              <p className="text-sm muted whitespace-pre-line break-words">{iv.instructions}</p>
            )}
            {iv.status === 'cancelled' && iv.cancel_reason && (
              <p className="text-sm muted break-words">Cancelled: “{iv.cancel_reason}”</p>
            )}
            {panel.length > 0 && (
              <p className="text-xs muted break-words">Panel: {panel.map(nameOf).join(', ')}</p>
            )}

            {live && (
              <div className="flex flex-wrap gap-2 items-start">
                {meet && iv.room && (
                  <JoinButton
                    roomName={iv.room.room_name}
                    opensAt={iv.room.opens_at}
                    closesAt={iv.room.closes_at}
                    roomStatus={iv.room.status}
                  />
                )}
                {canManage && (
                  <>
                    <RescheduleForm interviewId={iv.id} />
                    <CancelInterviewForm interviewId={iv.id} />
                    <CompleteInterviewForm interviewId={iv.id} />
                  </>
                )}
              </div>
            )}

            {showFeedback && (
              <div className="border-t hairline pt-3 space-y-3">
                <p className="label !mb-0">Feedback</p>
                {fbs.length === 0 ? (
                  <p className="text-sm muted">No feedback recorded yet.</p>
                ) : (
                  <ul className="space-y-2">
                    {fbs.map((f) => (
                      <FeedbackCard key={f.id} fb={f} name={nameOf(f.interviewer_id)} />
                    ))}
                  </ul>
                )}
                {!isHiringTeam && (
                  <p className="text-xs muted">You can see your own feedback. The hiring team sees everyone&apos;s.</p>
                )}
                {awaiting.length > 0 && iv.status === 'completed' && (
                  <p className="text-sm" style={{ color: 'var(--color-warn)' }}>
                    Awaiting feedback from {awaiting.map(nameOf).join(', ')}
                  </p>
                )}
                {canGiveFeedback && (
                  <details
                    className="rounded-lg border hairline"
                    open={iv.status === 'completed' && mine?.status !== 'submitted'}
                  >
                    <summary className="cursor-pointer select-none px-3 py-2.5 text-sm font-semibold">
                      {mine?.status === 'submitted'
                        ? 'Edit your feedback'
                        : mine
                          ? 'Finish your feedback (draft)'
                          : 'Add your feedback'}
                    </summary>
                    <div className="p-3 pt-0">
                      <FeedbackEditor interviewId={iv.id} jobId={jobId} canAddQuestions={isHiringTeam} />
                    </div>
                  </details>
                )}
              </div>
            )}
          </li>
        );
      })}
    </ol>
  );
}
