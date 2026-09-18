import Link from 'next/link';
import { redirect } from 'next/navigation';
import { parseTeamInvitations } from '@/lib/agency';
import { createClient, getCompanyContext, getUser } from '@/lib/supabase/server';
import CompanyForm from './company-form';

export default async function OnboardingPage() {
  const user = await getUser();
  if (!user) redirect('/sign-in');

  const ctx = await getCompanyContext();
  if (ctx) redirect('/dashboard');

  const supabase = await createClient();
  const [{ data: countries }, { data: areas }, { data: invitesRaw }] = await Promise.all([
    supabase
      .from('country_policies')
      .select('country_code, name')
      .eq('supported', true)
      .order('name'),
    supabase
      .from('locations')
      .select('id, name, parent_id')
      .eq('kind', 'area')
      .order('name'),
    supabase.rpc('omelo_my_team_invitations'),
  ]);
  const invitations = parseTeamInvitations(invitesRaw ?? null);

  // Label areas with their city so "Sector 18" is unambiguous.
  const { data: cities } = await supabase
    .from('locations')
    .select('id, name')
    .eq('kind', 'city');
  const cityById = new Map((cities ?? []).map((c) => [c.id, c.name]));
  const areaOptions = (areas ?? []).map((a) => ({
    id: a.id,
    label: `${a.name}${a.parent_id && cityById.get(a.parent_id) ? `, ${cityById.get(a.parent_id)}` : ''}`,
  }));

  return (
    <main className="min-h-screen max-w-2xl mx-auto px-5 sm:px-6 py-10 sm:py-14">
      <span className="text-xl font-black tracking-tight text-brand-600">
        Omelo
      </span>
      {invitations.length > 0 && (
        <section className="mt-8 space-y-3" aria-label="Team invitations">
          <h2 className="font-bold text-lg">You have been invited</h2>
          <ul className="space-y-2">
            {invitations.map((i) => (
              <li key={i.id} className="card p-4 flex items-center gap-3 flex-wrap">
                <div className="flex-1 min-w-0">
                  <p className="font-semibold break-words">{i.company.name}</p>
                  <p className="text-sm muted">
                    {i.company.kind === 'agency' ? 'Agency' : 'Employer'} · as {i.role.replace(/_/g, ' ')}
                    {i.invitedBy ? ` · invited by ${i.invitedBy}` : ''}
                  </p>
                </div>
                <Link href={`/join/${i.id}`} className="btn btn-primary w-full sm:w-auto">
                  Review
                </Link>
              </li>
            ))}
          </ul>
          <p className="text-sm muted">Or set up your own company below.</p>
        </section>
      )}

      <div className="card p-4 mt-8 flex items-center gap-3 flex-wrap">
        <p className="text-sm flex-1 min-w-[12rem]">
          <strong>Recruiting for clients?</strong> Set up a recruitment agency or work as an independent recruiter.
        </p>
        <Link href="/onboarding/agency" className="btn btn-ghost w-full sm:w-auto">
          Create an agency
        </Link>
      </div>

      <h1 className="text-2xl sm:text-3xl font-bold mt-8 mb-2">Set up your company</h1>
      <p className="muted mb-8 leading-relaxed">
        This is what workers see on your jobs. You can change all of it later.
      </p>

      <CompanyForm countries={countries ?? []} areas={areaOptions} />
    </main>
  );
}
