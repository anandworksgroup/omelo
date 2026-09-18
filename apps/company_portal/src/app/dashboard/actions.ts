'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { reportError } from '@/lib/observability';

export type ActionState = { error?: string; ok?: boolean; message?: string };

/* ------------------------------------------------------------------ */
/* Company                                                             */
/* ------------------------------------------------------------------ */

export async function createCompany(
  _prev: ActionState,
  formData: FormData
): Promise<ActionState> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return { error: 'You are signed out. Sign in and try again.' };

  const name = String(formData.get('display_name') ?? '').trim();
  if (!name) return { error: 'Enter your company name.' };

  const { data: slug, error: slugErr } = await supabase.rpc(
    'omelo_company_slug',
    { p_name: name }
  );
  if (slugErr) return { error: slugErr.message };

  const { data, error } = await supabase
    .from('companies')
    .insert({
      slug: slug as string,
      display_name: name,
      legal_name: String(formData.get('legal_name') ?? '').trim() || null,
      country_code: String(formData.get('country_code') ?? 'IN'),
      size_band: (String(formData.get('size_band') ?? '1-10') ||
        null) as never,
      website: String(formData.get('website') ?? '').trim() || null,
      about: String(formData.get('about') ?? '').trim() || null,
      hq_location_id: String(formData.get('hq_location_id') ?? '') || null,
      created_by: user.id,
    })
    .select('id')
    .single();

  if (error) return { error: error.message };

  // Mirror the HQ into company_locations so jobs can inherit its geo.
  const hq = String(formData.get('hq_location_id') ?? '');
  if (hq) {
    const { data: loc } = await supabase
      .from('locations')
      .select('name, geo')
      .eq('id', hq)
      .single();
    const { error: hqError } = await supabase.from('company_locations').insert({
      company_id: data.id,
      location_id: hq,
      name: 'Head office',
      address: loc?.name ?? null,
      geo: loc?.geo ?? null,
      is_hq: true,
    });
    // The company exists; a missing HQ row only loses geo inheritance.
    if (hqError) reportError(hqError, { action: 'createCompany.hq_location', companyId: data.id });
  }

  revalidatePath('/', 'layout');
  redirect('/dashboard');
}

export async function updateCompany(
  _prev: ActionState,
  formData: FormData
): Promise<ActionState> {
  const ctx = await getCompanyContext();
  if (!ctx) return { error: 'No company found.' };
  if (!['owner', 'admin'].includes(ctx.role))
    return { error: 'Only an owner or admin can edit the company profile.' };

  const supabase = await createClient();
  const { error } = await supabase
    .from('companies')
    .update({
      display_name: String(formData.get('display_name') ?? '').trim(),
      legal_name: String(formData.get('legal_name') ?? '').trim() || null,
      website: String(formData.get('website') ?? '').trim() || null,
      about: String(formData.get('about') ?? '').trim() || null,
      size_band: (String(formData.get('size_band') ?? '') || null) as never,
      founded_year: Number(formData.get('founded_year')) || null,
    })
    .eq('id', ctx.companyId);

  if (error) return { error: error.message };
  revalidatePath('/dashboard/company');
  return { ok: true };
}

/* ------------------------------------------------------------------ */
/* Jobs                                                                */
/* ------------------------------------------------------------------ */

const DEFAULT_STAGES = [
  { name: 'New', position: 1, maps_to_state: 'applied', is_terminal: false },
  { name: 'Shortlisted', position: 2, maps_to_state: 'shortlisted', is_terminal: false },
  { name: 'Phone call', position: 3, maps_to_state: 'screening', is_terminal: false },
  { name: 'Interview', position: 4, maps_to_state: 'interview', is_terminal: false },
  { name: 'Offer', position: 5, maps_to_state: 'offer', is_terminal: false },
  { name: 'Hired', position: 6, maps_to_state: 'hired', is_terminal: true },
  { name: 'Not moving forward', position: 7, maps_to_state: 'rejected', is_terminal: true },
] as const;

export async function createJob(
  _prev: ActionState,
  formData: FormData
): Promise<ActionState> {
  const ctx = await getCompanyContext();
  if (!ctx) return { error: 'No company found.' };
  if (!['owner', 'admin', 'recruiter'].includes(ctx.role))
    return { error: 'Your role cannot create jobs.' };

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const title = String(formData.get('title') ?? '').trim();
  const professionId = String(formData.get('profession_id') ?? '');
  const locationId = String(formData.get('location_id') ?? '');
  const workplace = String(formData.get('workplace_type') ?? 'onsite');

  if (!title) return { error: 'Give the job a title.' };
  if (!professionId) return { error: 'Choose the kind of work.' };
  if (!locationId && workplace !== 'remote')
    return {
      error:
        'Choose a location. Workers find jobs by distance, so an on-site job without one reaches nobody.',
    };

  const { data: prof } = await supabase
    .from('professions')
    .select('category_id')
    .eq('id', professionId)
    .single();

  const payMin = Number(formData.get('pay_min')) || null;
  const payMax = Number(formData.get('pay_max')) || null;
  if (payMin && payMax && payMax < payMin)
    return { error: 'Maximum pay cannot be less than minimum pay.' };

  const shifts = formData.getAll('shift_types').map(String);

  // company_location lets the job inherit an exact site geo when present.
  const { data: cl } = await supabase
    .from('company_locations')
    .select('id')
    .eq('company_id', ctx.companyId)
    .eq('is_hq', true)
    .maybeSingle();

  const { data: job, error } = await supabase
    .from('jobs')
    .insert({
      company_id: ctx.companyId,
      created_by: user?.id ?? null,
      title,
      profession_id: professionId,
      category_id: prof?.category_id ?? null,
      description: String(formData.get('description') ?? '').trim() || null,
      location_id: locationId || null,
      location_text: String(formData.get('location_text') ?? '').trim() || null,
      company_location_id: locationId ? null : (cl?.id ?? null),
      workplace_type: workplace as never,
      work_type: String(formData.get('work_type') ?? 'full_time') as never,
      shift_types: shifts as never,
      hours_per_week: Number(formData.get('hours_per_week')) || null,
      working_days: Number(formData.get('working_days')) || null,
      is_immediate_start: formData.get('is_immediate_start') === 'on',
      pay_min: payMin,
      pay_max: payMax,
      pay_period: (String(formData.get('pay_period') ?? 'month') ||
        null) as never,
      pay_currency: String(formData.get('pay_currency') ?? 'INR'),
      pay_negotiable: formData.get('pay_negotiable') === 'on',
      min_experience_months: Number(formData.get('min_experience_months')) || null,
      accepts_no_experience: formData.get('accepts_no_experience') === 'on',
      openings: Number(formData.get('openings')) || 1,
      requires_resume: formData.get('requires_resume') === 'on',
      quick_apply_enabled: formData.get('requires_resume') !== 'on',
      application_method: 'omelo',
      status: 'draft',
    })
    .select('id')
    .single();

  if (error) return { error: error.message };

  const { error: stagesError } = await supabase.from('job_stages').insert(
    DEFAULT_STAGES.map((s) => ({ ...s, job_id: job.id })) as never
  );
  if (stagesError) reportError(stagesError, { action: 'createJob.stages', jobId: job.id });

  const benefits = formData.getAll('benefits').map(String);
  if (benefits.length) {
    const { error: benefitsError } = await supabase.from('job_benefits').insert(
      benefits.map((b) => ({ job_id: job.id, benefit_type: b })) as never
    );
    if (benefitsError) reportError(benefitsError, { action: 'createJob.benefits', jobId: job.id });
  }

  // Requirements seeded from the profession taxonomy so an employer who
  // skips this step still gets a matchable job.
  const { data: profSkills } = await supabase
    .from('profession_skills')
    .select('skill_id, importance')
    .eq('profession_id', professionId)
    .gte('importance', 0.65);

  if (profSkills?.length) {
    const { error: skillsError } = await supabase.from('job_skills').insert(
      profSkills.map((s) => ({
        job_id: job.id,
        skill_id: s.skill_id,
        requirement_level: s.importance >= 0.85 ? 'required' : 'preferred',
        weight: s.importance,
      })) as never
    );
    if (skillsError) reportError(skillsError, { action: 'createJob.skills', jobId: job.id });
  }

  const question = String(formData.get('question') ?? '').trim();
  if (question) {
    const { error: questionError } = await supabase.from('job_questions').insert({
      job_id: job.id,
      position: 1,
      prompt: question,
      answer_type: 'boolean',
      is_required: true,
      is_knockout: false,
    } as never);
    if (questionError) reportError(questionError, { action: 'createJob.question', jobId: job.id });
  }

  revalidatePath('/dashboard/jobs');
  redirect(`/dashboard/jobs/${job.id}`);
}

export async function setJobStatus(jobId: string, status: string) {
  const ctx = await getCompanyContext();
  if (!ctx) return;
  const supabase = await createClient();
  const { error } = await supabase
    .from('jobs')
    .update({ status: status as never })
    .eq('id', jobId)
    .eq('company_id', ctx.companyId);
  if (error) reportError(error, { action: 'setJobStatus', jobId, status });
  revalidatePath('/dashboard/jobs');
  revalidatePath(`/dashboard/jobs/${jobId}`);
}

export async function publishJob(formData: FormData) {
  'use server';
  const id = String(formData.get('job_id'));
  await setJobStatus(id, 'published');
}

export async function pauseJob(formData: FormData) {
  'use server';
  const id = String(formData.get('job_id'));
  await setJobStatus(id, 'paused');
}

export async function closeJob(formData: FormData) {
  'use server';
  const id = String(formData.get('job_id'));
  await setJobStatus(id, 'closed');
}
