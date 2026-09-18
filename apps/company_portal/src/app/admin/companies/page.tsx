import type { Metadata } from 'next';
import { createClient } from '@/lib/supabase/server';
import { UUID_RE } from '@/lib/talent';
import LocalTime from '../../dashboard/local-time';
import { EntitlementsTool, VerificationTool } from './company-tools';

export const metadata: Metadata = { title: 'Companies · Omelo Admin', robots: { index: false, follow: false } };

const METHOD_LABEL: Record<string, string> = {
  manual_admin: 'manual review',
  document_review: 'document review',
  domain_email: 'domain email',
  otp: 'one-time code',
  employer_confirmation: 'employer confirmation',
  issuer_api: 'issuer API',
  institution_partner: 'institution partner',
  government_api: 'government API',
  third_party_provider: 'third-party provider',
};

export default async function CompaniesPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const sp = await searchParams;
  const raw = (typeof sp.q === 'string' ? sp.q : '').trim().slice(0, 80);
  const supabase = await createClient();

  let companies: {
    id: string;
    display_name: string;
    slug: string;
    is_verified: boolean;
    verified_at: string | null;
    verification_method: string | null;
    company_kind: string;
    created_at: string;
  }[] = [];
  let error: string | null = null;

  if (raw) {
    const select = 'id, display_name, slug, is_verified, verified_at, verification_method, company_kind, created_at';
    // Companies are publicly readable (not deleted), verified or not.
    let q = supabase.from('companies').select(select).is('deleted_at', null).limit(20);
    if (UUID_RE.test(raw)) {
      q = q.eq('id', raw);
    } else {
      // Keep only characters that are safe inside a PostgREST or() filter.
      const term = raw.replace(/[^\p{L}\p{N} _-]/gu, '').trim();
      if (!term) {
        error = 'Search by company name, slug or id.';
      } else {
        // Double-quoted so spaces survive the or() syntax; `_` is a harmless wildcard here.
        q = q.or(`slug.ilike."%${term}%",display_name.ilike."%${term}%"`).order('display_name');
      }
    }
    if (!error) {
      const res = await q;
      if (res.error) error = res.error.message;
      companies = res.data ?? [];
    }
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Companies</h1>
        <p className="text-sm muted mt-1">
          Verify a company and set its plan. Every change is written to the audit log.
        </p>
      </div>

      <form className="card p-4 flex flex-wrap gap-2 items-end" action="/admin/companies">
        <div className="flex-1 min-w-[12rem]">
          <label className="label" htmlFor="company-q">
            Find a company
          </label>
          <input
            id="company-q"
            name="q"
            className="input"
            defaultValue={raw}
            maxLength={80}
            placeholder="Name, slug, or paste a company id"
          />
        </div>
        <button className="btn btn-primary w-full sm:w-auto">Search</button>
      </form>

      {error && (
        <p className="text-sm" role="alert" style={{ color: 'var(--color-danger)' }}>
          {error}
        </p>
      )}

      {raw && !error && companies.length === 0 && (
        <p className="text-sm muted">No company matches “{raw}”. Try the exact slug or paste its id.</p>
      )}

      <ul className="space-y-4">
        {companies.map((c) => (
          <li key={c.id} className="card p-4 sm:p-5 space-y-5">
            <div className="flex items-start gap-3 flex-wrap">
              <div className="flex-1 min-w-0">
                <p className="font-bold break-words">{c.display_name}</p>
                <p className="text-xs muted break-all">
                  {c.slug} · {c.company_kind} · <span className="font-mono">{c.id}</span>
                </p>
              </div>
              {c.is_verified ? (
                <span className="pill" style={{ color: 'var(--color-verified)', borderColor: 'var(--color-verified)' }}>
                  ✓ Verified
                  {c.verification_method ? ` · ${METHOD_LABEL[c.verification_method] ?? c.verification_method}` : ''}
                </span>
              ) : (
                <span className="pill" style={{ color: 'var(--color-warn)' }}>
                  Unverified
                </span>
              )}
            </div>
            {c.is_verified && c.verified_at && (
              <p className="text-xs muted -mt-3">
                Verified <LocalTime iso={c.verified_at} />
              </p>
            )}

            <section className="space-y-2">
              <h2 className="text-sm font-bold uppercase tracking-wide muted">Verification</h2>
              <VerificationTool companyId={c.id} companyName={c.display_name} isVerified={c.is_verified} />
              <p className="hint !mt-1">Trust &amp; Safety or superadmins only.</p>
            </section>

            <section className="space-y-2 border-t hairline pt-4">
              <h2 className="text-sm font-bold uppercase tracking-wide muted">Plan &amp; talent search</h2>
              <EntitlementsTool companyId={c.id} companyName={c.display_name} />
              <p className="hint !mt-1">Superadmins only.</p>
            </section>
          </li>
        ))}
      </ul>
    </div>
  );
}
