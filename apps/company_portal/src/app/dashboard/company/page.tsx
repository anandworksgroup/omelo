import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { roleLabel } from '@/lib/agency';
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

  // One row per (person, role): count people, not rows.
  const { data: members, error: membersError } = await supabase
    .from('company_members')
    .select('person_id')
    .eq('company_id', ctx.companyId)
    .eq('is_active', true);
  const memberCount = new Set((members ?? []).map((m) => m.person_id)).size;

  const canEdit = ['owner', 'admin'].includes(ctx.role);
  const isAgency = ctx.kind === 'agency';

  return (
    <div className="space-y-8 max-w-3xl">
      <div>
        <h1 className="text-xl sm:text-2xl font-bold">{isAgency ? 'Agency profile' : 'Company profile'}</h1>
        {isAgency && ctx.isIndependent && (
          <p className="mt-2">
            <span className="pill">Independent recruiter</span>
          </p>
        )}
        <p className="muted text-sm mt-1">
          {isAgency ? (
            <>
              This is what candidates see when you ask for their consent, and what your clients see on every
              candidate you submit. Public page:{' '}
            </>
          ) : (
            <>This is what workers see on every job you post, and on </>
          )}
          <code className="text-xs break-all">/company/{company?.slug}</code> in the app.
        </p>
      </div>

      {!company?.is_verified && (
        <div className="card p-4" style={{ borderColor: 'var(--color-warn)' }}>
          <p className="font-semibold text-sm mb-1" style={{ color: 'var(--color-warn)' }}>
            Not verified yet
          </p>
          {isAgency ? (
            <p className="text-sm muted leading-relaxed">
              Searching candidates and asking them for consent need Omelo verification, and talent search on your
              plan. Until then you can set up your profile, team, clients and job orders. Omelo reviews every agency
              before it can search.
            </p>
          ) : (
            <p className="text-sm muted leading-relaxed">
              Unverified companies show an “unverified” badge on every job, have
              reduced reach, and cannot use talent search. Verification needs
              domain control plus proof the company exists — that flow is not
              built yet.
            </p>
          )}
        </div>
      )}

      <CompanyEditForm company={company!} canEdit={canEdit} />

      {!isAgency && (
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
      )}

      <section className="card p-5 space-y-3">
        <div className="flex items-start gap-3 flex-wrap">
          <div className="flex-1 min-w-0">
            <h2 className="font-bold">Legal entities</h2>
            <p className="text-sm muted mt-1 leading-relaxed">
              The registered companies you hire through in each country, with their currency and time zone.
            </p>
          </div>
          <Link href="/dashboard/company/entities" className="btn btn-ghost w-full sm:w-auto">
            {canEdit ? 'Manage entities' : 'View entities'}
          </Link>
        </div>
      </section>

      <section className="card p-5 space-y-3">
        <div className="flex items-start gap-3 flex-wrap">
          <div className="flex-1 min-w-0">
            <h2 className="font-bold">Team</h2>
            <p className="text-sm muted mt-1">
              {membersError
                ? `Could not count your team: ${membersError.message}`
                : `${memberCount} active member${memberCount === 1 ? '' : 's'}`}
              {' · '}you are {ctx.roles.map(roleLabel).join(', ')}
            </p>
          </div>
          <Link href="/dashboard/team" className="btn btn-ghost w-full sm:w-auto">
            Manage team
          </Link>
        </div>
        <p className="hint !mt-0">
          Invite people by email and choose their role. Nobody joins without accepting the invitation.
        </p>
      </section>

      {!isAgency && (
        <section className="card p-5 space-y-3">
          <div className="flex items-start gap-3 flex-wrap">
            <div className="flex-1 min-w-0">
              <h2 className="font-bold">Create an agency</h2>
              <p className="text-sm muted mt-1 leading-relaxed">
                Recruit for other companies? Create an agency or work as an independent recruiter. Searching needs
                Omelo verification.
              </p>
            </div>
            <Link href="/onboarding/agency" className="btn btn-ghost w-full sm:w-auto">
              Create an agency
            </Link>
          </div>
        </section>
      )}
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
