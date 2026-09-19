import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { loadGlobalOptions } from '@/lib/global-data';
import JobForm from './job-form';

export default async function NewJobPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  const [{ data: categories }, { data: professions }, { data: areas }, { data: cities }, global] =
    await Promise.all([
      supabase
        .from('job_categories')
        .select('id, slug, name')
        .eq('status', 'active')
        .order('position'),
      supabase
        .from('professions')
        .select('id, name, category_id, is_entry_level_friendly, requires_license')
        .eq('status', 'active')
        .order('name'),
      supabase.from('locations').select('id, name, parent_id').eq('kind', 'area').order('name'),
      supabase.from('locations').select('id, name').eq('kind', 'city'),
      loadGlobalOptions(supabase, ctx.companyId),
    ]);

  const cityById = new Map((cities ?? []).map((c) => [c.id, c.name]));
  const areaOptions = (areas ?? []).map((a) => ({
    id: a.id,
    label: `${a.name}${a.parent_id && cityById.get(a.parent_id) ? `, ${cityById.get(a.parent_id)}` : ''}`,
  }));

  return (
    <div className="max-w-3xl">
      <h1 className="text-xl sm:text-2xl font-bold mb-1">Post a job</h1>
      <p className="muted text-sm mb-8">
        Saved as a draft first. Nothing is visible to workers until you publish.
      </p>

      {global.error && (
        <p className="text-sm mb-4" style={{ color: 'var(--color-warn)' }}>
          Some global-hiring options could not be loaded: {global.error}
        </p>
      )}

      <JobForm
        categories={categories ?? []}
        professions={professions ?? []}
        areas={areaOptions}
        companyName={ctx.companyName}
        countries={global.countries}
        entities={global.entities}
        currencies={global.currencies}
        defaultCurrency={global.defaultCurrency}
      />
    </div>
  );
}
