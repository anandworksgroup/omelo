import { redirect } from 'next/navigation';
import { createClient, getCompanyContext, getUser } from '@/lib/supabase/server';
import CompanyForm from './company-form';

export default async function OnboardingPage() {
  const user = await getUser();
  if (!user) redirect('/sign-in');

  const ctx = await getCompanyContext();
  if (ctx) redirect('/dashboard');

  const supabase = await createClient();
  const [{ data: countries }, { data: areas }] = await Promise.all([
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
  ]);

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
    <main className="min-h-screen max-w-2xl mx-auto px-6 py-14">
      <span className="text-xl font-black tracking-tight text-brand-600">
        Omelo
      </span>
      <h1 className="text-3xl font-bold mt-8 mb-2">Set up your company</h1>
      <p className="muted mb-8 leading-relaxed">
        This is what workers see on your jobs. You can change all of it later.
      </p>

      <CompanyForm countries={countries ?? []} areas={areaOptions} />
    </main>
  );
}
