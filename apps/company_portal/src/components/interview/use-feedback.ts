'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import {
  DEFAULT_COMPETENCIES,
  asCompetencies,
  asSkills,
  type Competency,
  type Evaluation,
  type Recommendation,
  type SkillAssessed,
} from '@/lib/meet';

export type InterviewQuestion = {
  id: string;
  position: number;
  question: string;
  category: string;
  required: boolean;
  source: string;
};

export type AnswerDraft = { evaluation: Evaluation | null; notes: string };

export type FeedbackDraft = {
  recommendation: Recommendation | null;
  rating: number | null;
  strengths: string;
  concerns: string;
  notes: string;
  competencies: Competency[];
  skills: SkillAssessed[];
  answers: Record<string, AnswerDraft>;
};

export type SaveState =
  | { kind: 'idle' }
  | { kind: 'dirty' }
  | { kind: 'saving' }
  | { kind: 'saved'; at: number }
  | { kind: 'error'; message: string };

const EMPTY: FeedbackDraft = {
  recommendation: null,
  rating: null,
  strengths: '',
  concerns: '',
  notes: '',
  competencies: DEFAULT_COMPETENCIES.map((name) => ({ name, assessment: 'not_assessed' })),
  skills: [],
  answers: {},
};

const AUTOSAVE_MS = 1500;

/**
 * The signed-in interviewer's private feedback for one interview, plus the
 * interview's questions. Drafts autosave (debounced) through
 * omelo_save_interview_feedback; the candidate can never read any of it.
 */
export function useInterviewFeedback(interviewId: string, jobId: string | null) {
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [questions, setQuestions] = useState<InterviewQuestion[]>([]);
  const [questionsError, setQuestionsError] = useState<string | null>(null);
  const [draft, setDraft] = useState<FeedbackDraft>(EMPTY);
  const [status, setStatus] = useState<'draft' | 'submitted' | null>(null);
  const [save, setSave] = useState<SaveState>({ kind: 'idle' });

  const latest = useRef(draft);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const inflight = useRef<Promise<boolean> | null>(null);
  const again = useRef(false);

  useEffect(() => {
    latest.current = draft;
  }, [draft]);

  const loadQuestions = useCallback(async () => {
    const supabase = createClient();
    const { data, error } = await supabase
      .from('interview_questions')
      .select('id, position, question, category, required, source')
      .eq('interview_id', interviewId)
      .order('position');
    setQuestionsError(error ? error.message : null);
    setQuestions(data ?? []);
  }, [interviewId]);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const supabase = createClient();
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (!user) {
        if (!cancelled) {
          setLoadError('You are signed out.');
          setLoading(false);
        }
        return;
      }
      // Without a job id (inside the room), read it from the interview.
      let job = jobId;
      if (!job) {
        const { data: iv } = await supabase.from('interviews').select('job_id').eq('id', interviewId).maybeSingle();
        job = iv?.job_id ?? null;
      }
      const [qRes, fbRes, ansRes, skillRes] = await Promise.all([
        supabase
          .from('interview_questions')
          .select('id, position, question, category, required, source')
          .eq('interview_id', interviewId)
          .order('position'),
        supabase
          .from('interview_feedback')
          .select('recommendation, overall_rating, strengths, concerns, notes, competencies, skills_assessed, status')
          .eq('interview_id', interviewId)
          .eq('interviewer_id', user.id)
          .maybeSingle(),
        supabase
          .from('interview_answers')
          .select('question_id, evaluation, notes')
          .eq('interview_id', interviewId)
          .eq('interviewer_id', user.id),
        job
          ? supabase
              .from('job_skills')
              .select('skill_id, requirement_level, skills ( id, name )')
              .eq('job_id', job)
          : Promise.resolve({ data: [], error: null }),
      ]);
      if (cancelled) return;

      setQuestionsError(qRes.error ? qRes.error.message : null);
      setQuestions(qRes.data ?? []);
      if (fbRes.error) setLoadError(fbRes.error.message);

      const fb = fbRes.data;
      const saved = fb ? asSkills(fb.skills_assessed) : [];
      const jobSkills = ((skillRes.data ?? []) as { skill_id: string; skills: { id: string; name: string } | null }[])
        .filter((s) => s.skills?.name)
        .map((s) => ({ skill_id: s.skill_id, name: s.skills!.name }));
      const skills: SkillAssessed[] = [
        ...jobSkills.map((s) => ({
          ...s,
          demonstrated: saved.find((x) => x.name === s.name)?.demonstrated ?? false,
        })),
        ...saved.filter((x) => !jobSkills.some((s) => s.name === x.name)),
      ];
      const comps = fb ? asCompetencies(fb.competencies) : [];

      const answers: Record<string, AnswerDraft> = {};
      for (const a of ansRes.data ?? []) {
        answers[a.question_id] = { evaluation: (a.evaluation as Evaluation | null) ?? null, notes: a.notes ?? '' };
      }

      setDraft({
        recommendation: (fb?.recommendation as Recommendation | null) ?? null,
        rating: fb?.overall_rating ?? null,
        strengths: fb?.strengths ?? '',
        concerns: fb?.concerns ?? '',
        notes: fb?.notes ?? '',
        competencies: comps.length ? comps : EMPTY.competencies,
        skills,
        answers,
      });
      setStatus((fb?.status as 'draft' | 'submitted' | undefined) ?? null);
      setLoading(false);
    })();
    return () => {
      cancelled = true;
    };
  }, [interviewId, jobId]);

  const persist = useCallback(
    async (submit: boolean): Promise<boolean> => {
      const saveOnce = async (asSubmit: boolean) => {
        const d = latest.current;
        setSave({ kind: 'saving' });
        const supabase = createClient();
        const { error } = await supabase.rpc('omelo_save_interview_feedback', {
          p_interview_id: interviewId,
          p_recommendation: d.recommendation ?? undefined,
          p_rating: d.rating ?? undefined,
          p_strengths: d.strengths,
          p_concerns: d.concerns,
          p_notes: d.notes,
          p_competencies: d.competencies,
          p_skills: d.skills,
          p_answers: Object.entries(d.answers)
            .filter(([, a]) => a.evaluation || a.notes.trim())
            .map(([question_id, a]) => ({ question_id, evaluation: a.evaluation ?? '', notes: a.notes })),
          p_submit: asSubmit,
        });
        if (error) {
          setSave({ kind: 'error', message: error.message });
          return false;
        }
        setStatus((s) => (asSubmit || s === 'submitted' ? 'submitted' : 'draft'));
        setSave({ kind: 'saved', at: Date.now() });
        return true;
      };

      if (inflight.current) {
        if (!submit) {
          // A save is running; it will run once more with the newest draft.
          again.current = true;
          return inflight.current;
        }
        await inflight.current;
      }

      const loop = (async () => {
        let ok = await saveOnce(submit);
        while (again.current) {
          again.current = false;
          ok = await saveOnce(false);
        }
        return ok;
      })();
      inflight.current = loop;
      try {
        return await loop;
      } finally {
        inflight.current = null;
      }
    },
    [interviewId]
  );

  const change = useCallback(
    (patch: Partial<FeedbackDraft> | ((d: FeedbackDraft) => Partial<FeedbackDraft>)) => {
      setDraft((d) => ({ ...d, ...(typeof patch === 'function' ? patch(d) : patch) }));
      setSave({ kind: 'dirty' });
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(() => {
        timer.current = null;
        void persist(false);
      }, AUTOSAVE_MS);
    },
    [persist]
  );

  /** Save now if anything is pending (before leaving / ending). */
  const flush = useCallback(async () => {
    if (timer.current) {
      clearTimeout(timer.current);
      timer.current = null;
      return persist(false);
    }
    if (inflight.current) return inflight.current;
    return true;
  }, [persist]);

  const submit = useCallback(async () => {
    if (timer.current) {
      clearTimeout(timer.current);
      timer.current = null;
    }
    if (!latest.current.recommendation) {
      setSave({ kind: 'error', message: 'Choose a recommendation before submitting.' });
      return false;
    }
    return persist(true);
  }, [persist]);

  useEffect(
    () => () => {
      if (timer.current) clearTimeout(timer.current);
    },
    []
  );

  return {
    loading,
    loadError,
    questions,
    questionsError,
    reloadQuestions: loadQuestions,
    draft,
    change,
    status,
    save,
    saveNow: () => persist(false),
    flush,
    submit,
  };
}

export type FeedbackController = ReturnType<typeof useInterviewFeedback>;
