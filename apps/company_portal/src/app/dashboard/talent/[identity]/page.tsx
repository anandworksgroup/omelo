import type { Metadata } from 'next';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { monthYear } from '@/lib/hiring';
import { reportError } from '@/lib/observability';
import { TALENT_ROLES, UUID_RE, parseProfile } from '@/lib/talent';
import { CompletenessMeter, EvidencePanel, ProfileAnswers } from '@/components/identity/evidence';
import TalentActions from '../talent-actions';
import { CardHeader, GlobalChips, Notice, ReasonList, ScoreBadge, SkillChips } from '../ui';
import { parseCandidateEligibility } from '@/lib/global';
import { EligibilityPanel } from '@/components/global/eligibility';

export const metadata: Metadata = { title: 'Candidate profile · Omelo' };

function Section({ title, aside, children }: { title: string; aside?: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="card p-5">
      <div className="flex items-center gap-3 flex-wrap mb-3">
        <h2 className="font-bold flex-1 min-w-0">{title}</h2>
        {aside}
      </div>
      {children}
    </section>
  );
}

export default async function TalentProfilePage({
  params,
  searchParams,
}: {
  params: Promise<{ identity: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { identity } = await params;
  if (!UUID_RE.test(identity)) notFound();
  const sp = await searchParams;
  const jobParam = typeof sp.job === 'string' && UUID_RE.test(sp.job) ? sp.job : null;

  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  const [profileRes, jobsRes, poolsRes, eligibilityRes] = await Promise.all([
    // Records a profile view: the worker sees that this company looked.
    supabase.rpc('omelo_talent_profile', { p_identity: identity, p_job_id: jobParam ?? undefined }),
    supabase
      .from('jobs')
      .select('id, title, location_text')
      .eq('company_id', ctx.companyId)
      .eq('status', 'published')
      .order('published_at', { ascending: false, nullsFirst: false }),
    supabase.from('talent_pools').select('id, name').eq('company_id', ctx.companyId).order('name'),
    jobParam
      ? supabase.rpc('omelo_candidate_eligibility', { p_job: jobParam, p_identity: identity })
      : Promise.resolve({ data: null, error: null }),
  ]);

  const jobs = (jobsRes.data ?? []).map((j) => ({ id: j.id, title: j.title, location: j.location_text }));
  const job = jobParam ? (jobs.find((j) => j.id === jobParam) ?? null) : null;
  const back = (
    <Link href={`/dashboard/talent${jobParam ? `?job=${jobParam}` : ''}`} className="text-sm underline muted">
      ← Find candidates
    </Link>
  );

  if (profileRes.error) {
    if (profileRes.error.code === '42501') {
      return (
        <div className="space-y-4 max-w-3xl">
          {back}
          <Notice title="This person is no longer visible to your company">
            They may have changed who can find them, or turned this work profile off. Anything you saved about
            them stays in your pools, greyed out. If they apply to one of your jobs you will see their profile
            again.
          </Notice>
        </div>
      );
    }
    reportError(profileRes.error, { action: 'talentProfile' });
    return (
      <div className="space-y-4 max-w-3xl">
        {back}
        <div className="card p-5" style={{ borderColor: 'var(--color-danger)' }}>
          <p className="font-semibold mb-1" style={{ color: 'var(--color-danger)' }}>
            Could not load this profile
          </p>
          <p className="text-sm muted">{profileRes.error.message}</p>
        </div>
      </div>
    );
  }

  const profile = parseProfile(profileRes.data);
  if (!profile?.card) notFound();
  const card = profile.card;
  const match = profile.match;
  const canAct = TALENT_ROLES.includes(ctx.role);
  const verifiedExp = profile.experiences.filter((e) => e.verified);
  const selfExp = profile.experiences.filter((e) => !e.verified);

  return (
    <div className="space-y-6 max-w-5xl">
      {back}

      <header className="card p-5 space-y-4">
        <CardHeader card={{ ...card, score: null }} showScore={false} />
        {card.completeness != null && (
          <div className="max-w-xs">
            <CompletenessMeter score={card.completeness} />
          </div>
        )}
        <GlobalChips card={card} />
        <SkillChips card={card} max={6} />
        <div className="border-t hairline pt-4">
          <TalentActions
            card={card}
            jobs={job ? [job] : jobs}
            jobId={job?.id ?? null}
            companyName={ctx.companyName}
            pools={poolsRes.data ?? []}
            canAct={canAct && ctx.isVerified}
          />
          {!job && canAct && (
            <p className="hint">
              Opened without a job, so the match below is not shown. Open this profile from a search to see how well
              they fit that job.
            </p>
          )}
        </div>
      </header>

      <div className="grid gap-6 lg:grid-cols-3 items-start">
        <div className="space-y-6 lg:col-span-2 min-w-0">
          {job && (
            <Section title="How they match" aside={<span className="text-xs muted">for {job.title}</span>}>
              {!match ? (
                <p className="text-sm muted">No match has been computed for this job yet. Search again to score them.</p>
              ) : (
                <div className="space-y-4">
                  <div className="flex items-center gap-3 flex-wrap">
                    <ScoreBadge score={match.score} eligible={match.eligible} />
                    <p className="text-sm flex-1 min-w-[12rem]">
                      {match.eligible === false
                        ? 'Misses at least one must-have for this job. Check the gaps before inviting.'
                        : 'Meets every must-have for this job.'}
                    </p>
                  </div>
                  {match.strengths.length > 0 && (
                    <div>
                      <p className="label">Strengths</p>
                      <ReasonList items={match.strengths} tone="good" />
                    </div>
                  )}
                  {match.gaps.length > 0 && (
                    <div>
                      <p className="label">Gaps</p>
                      <ReasonList items={match.gaps} tone="gap" />
                    </div>
                  )}
                  {match.missingSkills.length > 0 && (
                    <div>
                      <p className="label">Missing required skills</p>
                      <div className="flex flex-wrap gap-2">
                        {match.missingSkills.map((s) => (
                          <span key={s} className="pill" style={{ color: 'var(--color-warn)' }}>
                            {s}
                          </span>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              )}
            </Section>
          )}

          <Section
            title="Evidence"
            aside={card.label ? <span className="text-xs muted">for {card.label}</span> : undefined}
          >
            {profile.evidence ? (
              <EvidencePanel ev={profile.evidence} />
            ) : (
              <p className="text-sm muted">No evidence on this work profile yet.</p>
            )}
          </Section>

          <Section title="Work history">
            {profile.experiences.length === 0 ? (
              <p className="text-sm muted">No work history on this work profile yet.</p>
            ) : (
              <ul className="space-y-4">
                {[...verifiedExp, ...selfExp].map((e, i) => (
                  <li key={`${e.title}-${e.startedOn}-${i}`} className="min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="font-semibold text-sm break-words">{e.title}</span>
                      {e.verified ? (
                        <span
                          className="pill"
                          style={{ color: 'var(--color-verified)', borderColor: 'var(--color-verified)' }}
                        >
                          ✓ Verified by Omelo
                        </span>
                      ) : (
                        <span className="pill">Self-declared</span>
                      )}
                    </div>
                    {e.employer && <div className="text-sm muted break-words">{e.employer}</div>}
                    <div className="text-xs muted mt-0.5">
                      {monthYear(e.startedOn) || 'Start not given'} –{' '}
                      {e.isCurrent ? 'Present' : monthYear(e.endedOn) || 'end not given'}
                    </div>
                    {e.description && (
                      <p className="text-sm mt-1 whitespace-pre-line break-words">{e.description}</p>
                    )}
                  </li>
                ))}
              </ul>
            )}
          </Section>
        </div>

        <div className="space-y-6 min-w-0">
          {job && (
            <EligibilityPanel
              eligibility={parseCandidateEligibility(eligibilityRes.data ?? null)}
              error={eligibilityRes.error?.message ?? null}
              jobTitle={job.title}
            />
          )}
          {profile.about && (
            <Section title="About">
              <p className="text-sm whitespace-pre-line break-words">{profile.about}</p>
            </Section>
          )}
          <Section title="Profile answers">
            <ProfileAnswers answers={profile.answers} />
          </Section>
          <p className="hint">
            You are seeing the {card.label ? <strong>{card.label}</strong> : 'work'} profile this person made
            visible to employers, plus details they share across profiles. Their full name appears once they
            apply. They can see that {ctx.companyName} viewed this profile.
          </p>
        </div>
      </div>
    </div>
  );
}
