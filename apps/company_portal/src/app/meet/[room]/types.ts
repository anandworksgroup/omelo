/** Shapes returned by the meet-token Edge Function (supabase/functions/meet-token). */

export type InterviewPayload = {
  interview_id: string;
  application_id: string;
  job_title: string | null;
  company_name: string | null;
  candidate_name: string | null;
  round: number | null;
  round_name: string | null;
  meeting_mode: string | null;
  scheduled_at: string | null;
  duration_minutes: number | null;
  timezone: string | null;
  location_text: string | null;
  instructions: string | null;
  room_name: string;
};

export type JoinInfo = {
  role: 'candidate' | 'host' | 'interviewer' | 'observer' | string;
  identity: string;
  display_name: string;
  can_moderate: boolean;
  closes_at: string | null;
  interview: InterviewPayload;
};

export type Admitted = JoinInfo & {
  state: 'admitted';
  url: string;
  token: string;
  expires_at: string;
};

export type Unavailable = JoinInfo & {
  state: 'unavailable';
  code: string;
  error?: string;
};

export type Participant = {
  person_id: string;
  display_name: string | null;
  role: string;
  status: string;
  requested_at: string | null;
  admitted_at: string | null;
  joined_at: string | null;
  left_at: string | null;
};

export const ROLE_LABEL: Record<string, string> = {
  candidate: 'Candidate',
  host: 'Host',
  interviewer: 'Interviewer',
  observer: 'Observer',
};
