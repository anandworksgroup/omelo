'use client';

import { useId, useState } from 'react';
import { AskConsent, type AgencySummary, type OrderSummary } from '../../consent-ui';

export type PoolOrder = OrderSummary & { status: string };

/**
 * Ask a saved person for consent for one of the agency's open job orders.
 * Being in the pool grants nothing; this is the only way forward.
 */
export default function PoolConsent({
  candidate,
  orders,
  existing,
  agency,
  recruiterName,
  blockedReason,
}: {
  candidate: { identityId: string; name: string; label: string | null };
  orders: PoolOrder[];
  /** Latest consent per order id for this person. */
  existing: Record<string, { id: string; status: string }>;
  agency: AgencySummary;
  recruiterName: string | null;
  blockedReason: string | null;
}) {
  const uid = useId();
  const [orderId, setOrderId] = useState(orders[0]?.id ?? '');
  const order = orders.find((o) => o.id === orderId) ?? null;

  if (orders.length === 0)
    return <span className="text-xs muted">Open a job order to ask this person for consent.</span>;

  return (
    <div className="flex flex-wrap items-start gap-2 min-w-0">
      <label className="sr-only" htmlFor={`${uid}o`}>
        Job order
      </label>
      <select
        id={`${uid}o`}
        className="input !h-9 !py-0 text-sm !w-auto max-w-full"
        value={orderId}
        onChange={(e) => setOrderId(e.target.value)}
      >
        {orders.map((o) => (
          <option key={o.id} value={o.id}>
            {o.reference} · {o.title}
          </option>
        ))}
      </select>
      <AskConsent
        key={orderId}
        candidate={candidate}
        order={order}
        agency={agency}
        recruiterName={recruiterName}
        existing={existing[orderId] ?? null}
        acceptsRequests
        blockedReason={blockedReason}
      />
    </div>
  );
}
