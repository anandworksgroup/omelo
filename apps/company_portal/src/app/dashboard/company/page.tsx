import { createClient, getCompanyContext } from '@/lib/supabase/server';
import CompanyEditForm from './edit-form';

export default async function CompanyPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  const { data: company } = await supabase
    .from('companies')
    .select(
      'id, slug, display_name, legal_name, website, about, size_band, founded_year, is_verified, response_rate_pct, median_response_hours, total_hires, country_code'
    )
    .eq('id', ctx.companyId)
    .single();

  const { data: members } = await supabase
    .from('company_members')
    .select('role, is_active, joined_at, persons ( display_name, email )')
    .eq('company_id', ctx.companyId);

  const canEdit = ['owner', 'admin'].includes(ctx.role);

  return (
    <div className="space-y-8 max-w-3xl">
      <div>
        <h1 className="text-xl sm:text-2xl font-bold">Company profile</h1>
        <p className="muted text-sm mt-1">
          This is what workers see on every job you post, and on{' '}
          <code className="text-xs">/company/{company?.slug}</code> in the app.
        </p>
      </div>

      {!company?.is_verified && (
        <div className="card p-4" style={{ borderColor: 'var(--color-warn)' }}>
          <p className="font-semibold text-sm mb-1" style={{ color: 'var(--color-warn)' }}>
            Not verified yet
          </p>
          <p className="text-sm muted leading-relaxed">
            Unverified companies show an “unverified” badge on every job, have
            reduced reach, and cannot use talent search. Verification needs
            domain control plus proof the company exists — that flow is not
            built yet.
          </p>
        </div>
      )}

      <CompanyEditForm company={company!} canEdit={canEdit} />

      <section className="card p-5">
        <h2 className="font-bold mb-1">Your hiring behaviour</h2>
        <p className="text-sm muted mb-4 leading-relaxed">
          Workers see these numbers on your job cards. They are computed from
          how you actually respond, not from anything you set here.
        </p>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 text-center">
          <Stat
            value={company?.response_rate_pct != null ? `${Math.round(Number(company.response_rate_pct))}%` : '—'}
            label="Response rate"
          />
          <Stat
            value={
              company?.median_response_hours != null
                ? `${Math.round(company.median_response_hours / 24)}d`
                : '—'
            }
            label="Median response"
          />
          <Stat value={String(company?.total_hires ?? 0)} label="Hires on Omelo" />
        </div>
      </section>

      <section>
        <h2 className="font-bold text-lg mb-3">Team</h2>
        <div className="card divide-y" style={{ borderColor: 'var(--line)' }}>
          {(members ?? []).map((m, i) => {
            const p = m.persons as unknown as { display_name: string | null; email: string | null };
            return (
              <div key={i} className="p-4 flex items-center gap-4">
                <div className="flex-1 min-w-0">
                  <div className="font-semibold text-sm truncate">
                    {p?.display_name || p?.email || 'Member'}
                  </div>
                  <div className="text-xs muted">{p?.email}</div>
                </div>
                <span className="pill">{m.role}</span>
              </div>
            );
          })}
        </div>
        <p className="hint">
          Inviting teammates is not built yet. Roles and their permissions are
          specified in architecture/A2 §12.
        </p>
      </section>
    </div>
  );
}

function Stat({ value, label }: { value: string; label: string }) {
  return (
    <div>
      <div className="text-2xl font-bold">{value}</div>
      <div className="text-xs muted mt-1">{label}</div>
    </div>
  );
}
