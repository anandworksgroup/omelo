import type { Metadata } from 'next';
import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import type { SubmissionRow } from '@/lib/agency';
import { ErrorNote, Notice, PageHeader } from '../ui';
import { BASE, loadSubmissions } from '../submissions/lib';
import { SubmissionCard, WorkTabs } from '../submissions/row';

export const metadata: Metadata = { title: 'Offers · Omelo' };

const OPEN_OFFER = ['draft', 'sent', 'viewed', 'negotiating'];

function group(r: SubmissionRow): 'open' | 'accepted' | 'closed' {
  if (r.status === 'hired' || r.offerStatus === 'accepted') return 'accepted';
  if (r.status === 'offer' && (!r.offerStatus || OPEN_OFFER.includes(r.offerStatus))) return 'open';
  if (r.offerStatus && OPEN_OFFER.includes(r.offerStatus) && !['rejected', 'withdrawn'].includes(r.status)) return 'open';
  return 'closed';
}

export default async function OffersPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();
  const { rows, error } = await loadSubmissions(supabase, ctx.companyId);

  const withOffers = rows
    .filter((r) => r.status === 'offer' || r.status === 'hired' || r.offerStatus)
    .sort((a, b) => (b.updatedAt ?? '').localeCompare(a.updatedAt ?? ''));
  const groups = {
    open: withOffers.filter((r) => group(r) === 'open'),
    accepted: withOffers.filter((r) => group(r) === 'accepted'),
    closed: withOffers.filter((r) => group(r) === 'closed'),
  };

  const sections: { key: keyof typeof groups; title: string; hint: string }[] = [
    { key: 'open', title: 'Waiting on the candidate', hint: 'Offers made and not answered yet.' },
    { key: 'accepted', title: 'Accepted', hint: 'Hired — track the start and your fee under Placements.' },
    { key: 'closed', title: 'Declined, withdrawn or expired', hint: 'Offers that did not go ahead.' },
  ];

  return (
    <div className="space-y-5 max-w-5xl">
      <PageHeader title="Offers" subtitle="Offers clients made to candidates you submitted." />
      <WorkTabs active="offers" />
      <p className="text-sm muted max-w-3xl">
        For clients on Omelo the offer status comes straight from their hiring team. For off-platform clients,
        record “The client made an offer” or “Hired” on the submission.
      </p>

      {error ? (
        <ErrorNote label="offers" message={error} />
      ) : withOffers.length === 0 ? (
        <Notice
          title="No offers yet"
          action={
            <Link href={`${BASE}/interviews`} className="btn btn-ghost">
              See interviews
            </Link>
          }
        >
          When a client makes an offer to one of your candidates, it appears here.
        </Notice>
      ) : (
        sections.map((s) =>
          groups[s.key].length ? (
            <section key={s.key} className="space-y-3">
              <div>
                <h2 className="font-bold">
                  {s.title} ({groups[s.key].length})
                </h2>
                <p className="text-sm muted">{s.hint}</p>
              </div>
              <ul className="grid gap-3">
                {groups[s.key].map((r) => (
                  <SubmissionCard
                    key={r.id}
                    row={r}
                    extra={
                      !r.onOmelo && !r.offerStatus ? (
                        <p className="text-xs muted mt-2">
                          {r.status === 'hired' ? 'Hire recorded by your agency.' : 'Offer recorded by your agency.'}
                        </p>
                      ) : undefined
                    }
                  />
                ))}
              </ul>
            </section>
          ) : null
        )
      )}
    </div>
  );
}
