import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { createClient, getCompanyContext, getUser } from '@/lib/supabase/server';
import AgencyForm from './agency-form';

export const metadata: Metadata = { title: 'Create an agency · Omelo' };

export default async function CreateAgencyPage() {
  const user = await getUser();
  if (!user) redirect('/sign-in?next=/onboarding/agency');
  const ctx = await getCompanyContext();
  const supabase = await createClient();
  const [{ data: countries }, { data: me }] = await Promise.all([
    supabase.from('country_policies').select('country_code, name').eq('supported', true).order('name'),
    supabase.from('persons').select('country_code').eq('id', user.id).maybeSingle(),
  ]);
  const list = countries?.length ? countries : [{ country_code: 'IN', name: 'India' }];
  const preferred = me?.country_code && list.some((c) => c.country_code === me.country_code) ? me.country_code : 'IN';

  return (
    <main className="min-h-screen max-w-2xl mx-auto px-4 sm:px-6 py-10 sm:py-14">
      <Link href={ctx ? '/dashboard' : '/onboarding'} className="text-xl font-black tracking-tight text-brand-600">
        Omelo
      </Link>
      <h1 className="text-2xl sm:text-3xl font-bold mt-8 mb-2">Create an agency</h1>
      <p className="muted mb-8 leading-relaxed">
        Recruit for your clients on Omelo. {ctx ? 'You keep your current workspace and can switch between them.' : ''}
      </p>
      <AgencyForm countries={list} defaultCountry={preferred} />
      <p className="text-sm muted mt-8">
        <Link href={ctx ? '/dashboard' : '/onboarding'} className="underline">
          {ctx ? 'Back to the dashboard' : 'Set up an employer company instead'}
        </Link>
      </p>
    </main>
  );
}
