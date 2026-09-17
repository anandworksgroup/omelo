import Link from 'next/link';
import { createClient, getCompanyContext } from '@/lib/supabase/server';
import { formatPay, timeAgo } from '@/lib/format';
import { OFFER_STATUS_LABEL, OPEN_OFFER_STATUSES, calendarDate } from '@/lib/hiring';
import LocalTime from '../local-time';

export default async function OffersPage() {
  const ctx = (await getCompanyContext())!;
  const supabase = await createClient();

  // offers → persons is ambiguous (person_id and created_by), so hint it.
  const { data, error } = await supabase
    .from('offers')
    .select(
      `id, application_id, status, title, pay_amount, pay_period, pay_currency,
       start_date, expires_at, sent_at, viewed_at, responded_at, decline_reason, created_at,
       persons!offers_person_id_fkey ( display_name )`
    )
    .eq('company_id', ctx.companyId)
    .neq('status', 'draft')
    .order('created_at', { ascending: false });

  if (error) {
    return (
      <div className="max-w-3xl space-y-4">
        <h1 className="text-2xl font-bold">Offers</h1>
        <div className="card p-5" style={{ borderColor: 'var(--color-danger)' }}>
          <p className="font-semibold mb-1" style={{ color: 'var(--color-danger)' }}>
            Could not load offers
          </p>
          <p className="text-sm muted">{error.message}</p>
        </div>
      </div>
    );
  }

  const all = data ?? [];
  const open = all.filter((o) => OPEN_OFFER_STATUSES.includes(o.status));
  const closed = all.filter((o) => !OPEN_OFFER_STATUSES.includes(o.status));

  const row = (o: (typeof all)[number]) => {
    const person = o.persons as unknown as { display_name: string | null } | null;
    const isOpen = OPEN_OFFER_STATUSES.includes(o.status);
    const color =
      o.status === 'accepted'
        ? 'var(--color-verified)'
        : isOpen
          ? 'var(--fg)'
          : 'var(--color-danger)';

    return (
      <Link
        key={o.id}
        href={`/dashboard/candidates/${o.application_id}`}
        className="p-4 flex items-start gap-3 sm:gap-4 flex-wrap hover:bg-[var(--surface)]"
      >
        <div className="flex-1 min-w-[12rem]">
          <div className="font-semibold text-sm break-words">
            {person?.display_name ?? 'Candidate'}
          </div>
          <div className="text-xs muted mt-0.5 break-words">
            {o.title} · starts {calendarDate(o.start_date)}
          </div>
          <div className="text-sm font-semibold mt-1">
            {formatPay({ min: o.pay_amount, currency: o.pay_currency, period: o.pay_period })}
          </div>
          <div className="text-xs muted mt-0.5">
            {isOpen ? (
              <>
                Sent {timeAgo(o.sent_at)}
                {o.expires_at && (
                  <>
                    {' '}
                    · expires <LocalTime iso={o.expires_at} withTime={false} />
                  </>
                )}
              </>
            ) : (
              <>Closed {timeAgo(o.responded_at ?? o.created_at)}</>
            )}
          </div>
          {o.decline_reason && (
            <div className="text-xs muted mt-0.5 break-words">“{o.decline_reason}”</div>
          )}
        </div>
        <span className="pill" style={{ color }}>
          {OFFER_STATUS_LABEL[o.status]}
        </span>
      </Link>
    );
  };

  return (
    <div className="space-y-8 max-w-4xl">
      <div>
        <h1 className="text-xl sm:text-2xl font-bold">Offers</h1>
        <p className="muted text-sm mt-1">
          Send an offer from a candidate&apos;s page. When a candidate accepts, they
          are marked hired and the job becomes verified work history on their profile.
        </p>
      </div>

      <section>
        <h2 className="font-bold text-lg mb-3">Open ({open.length})</h2>
        {open.length === 0 ? (
          <div className="card p-8 text-center text-sm muted">No offers awaiting a reply.</div>
        ) : (
          <div className="card divide-y" style={{ borderColor: 'var(--line)' }}>
            {open.map(row)}
          </div>
        )}
      </section>

      {closed.length > 0 && (
        <section>
          <h2 className="font-bold text-lg mb-3">Closed ({closed.length})</h2>
          <div className="card divide-y" style={{ borderColor: 'var(--line)' }}>
            {closed.map(row)}
          </div>
        </section>
      )}
    </div>
  );
}
