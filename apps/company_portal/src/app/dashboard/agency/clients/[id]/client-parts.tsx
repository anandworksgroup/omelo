'use client';

import { useRouter } from 'next/navigation';
import { useId, useState, useTransition } from 'react';
import {
  deleteClientContact,
  endClientLink,
  findEmployerCompanies,
  requestClientLink,
  saveClientContact,
  type ContactInput,
} from '../../actions';

function ErrorLine({ text }: { text: string | null }) {
  if (!text) return null;
  return (
    <p className="text-sm basis-full break-words" role="alert" style={{ color: 'var(--color-danger)' }}>
      {text}
    </p>
  );
}

/* ------------------------------------------------------------------ */
/* Contacts                                                            */
/* ------------------------------------------------------------------ */

export type Contact = {
  id: string;
  name: string;
  title: string | null;
  email: string | null;
  phone: string | null;
  isPrimary: boolean;
  notes: string | null;
};

function ContactForm({
  clientId,
  contact,
  onDone,
}: {
  clientId: string;
  contact: Contact | null;
  onDone: () => void;
}) {
  const uid = useId();
  const router = useRouter();
  const [v, setV] = useState<ContactInput>({
    name: contact?.name ?? '',
    title: contact?.title ?? '',
    email: contact?.email ?? '',
    phone: contact?.phone ?? '',
    isPrimary: contact?.isPrimary ?? false,
    notes: contact?.notes ?? '',
  });
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();
  const set = (k: keyof ContactInput) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
    setV((s) => ({ ...s, [k]: e.target.value }));

  return (
    <form
      className="surface rounded-lg p-3 grid gap-3 sm:grid-cols-2"
      onSubmit={(e) => {
        e.preventDefault();
        setError(null);
        start(async () => {
          const res = await saveClientContact(clientId, contact?.id ?? null, v);
          if (!res.ok) return setError(res.error);
          router.refresh();
          onDone();
        });
      }}
    >
      <div>
        <label className="label" htmlFor={`${uid}n`}>
          Name *
        </label>
        <input id={`${uid}n`} className="input" required maxLength={120} value={v.name} onChange={set('name')} />
      </div>
      <div>
        <label className="label" htmlFor={`${uid}t`}>
          Title
        </label>
        <input id={`${uid}t`} className="input" maxLength={120} value={v.title} onChange={set('title')} placeholder="HR manager" />
      </div>
      <div>
        <label className="label" htmlFor={`${uid}e`}>
          Email
        </label>
        <input id={`${uid}e`} className="input" type="email" maxLength={254} value={v.email} onChange={set('email')} />
      </div>
      <div>
        <label className="label" htmlFor={`${uid}p`}>
          Phone
        </label>
        <input id={`${uid}p`} className="input" type="tel" maxLength={40} value={v.phone} onChange={set('phone')} />
      </div>
      <div className="sm:col-span-2">
        <label className="label" htmlFor={`${uid}no`}>
          Notes
        </label>
        <textarea id={`${uid}no`} className="input" rows={2} maxLength={1000} value={v.notes} onChange={set('notes')} />
      </div>
      <label className="flex items-center gap-2 text-sm sm:col-span-2">
        <input type="checkbox" checked={v.isPrimary} onChange={(e) => setV((s) => ({ ...s, isPrimary: e.target.checked }))} />
        Primary contact
      </label>
      <ErrorLine text={error} />
      <div className="flex flex-wrap gap-2 sm:col-span-2">
        <button className="btn btn-primary w-full sm:w-auto" disabled={pending || !v.name.trim()}>
          {pending ? 'Saving…' : 'Save contact'}
        </button>
        <button type="button" className="btn btn-ghost w-full sm:w-auto" onClick={onDone}>
          Cancel
        </button>
      </div>
    </form>
  );
}

export function Contacts({ clientId, contacts, canEdit }: { clientId: string; contacts: Contact[]; canEdit: boolean }) {
  const router = useRouter();
  const [editing, setEditing] = useState<string | 'new' | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  return (
    <div className="space-y-3">
      {contacts.length === 0 && editing !== 'new' && <p className="text-sm muted">No contacts yet.</p>}
      <ul className="space-y-2">
        {contacts.map((c) =>
          editing === c.id ? (
            <li key={c.id}>
              <ContactForm clientId={clientId} contact={c} onDone={() => setEditing(null)} />
            </li>
          ) : (
            <li key={c.id} className="flex items-start gap-3 flex-wrap border-t hairline pt-2 first:border-t-0 first:pt-0">
              <div className="flex-1 min-w-[12rem]">
                <p className="font-semibold text-sm break-words">
                  {c.name}
                  {c.isPrimary && <span className="pill ml-2 text-[0.7rem]">Primary</span>}
                </p>
                <p className="text-xs muted break-words">
                  {[c.title, c.email, c.phone].filter(Boolean).join(' · ') || 'No details'}
                </p>
                {c.notes && <p className="text-xs mt-1 break-words whitespace-pre-line">{c.notes}</p>}
              </div>
              {canEdit && (
                <div className="flex gap-2">
                  <button type="button" className="btn btn-ghost !h-8 !px-2.5 text-sm" onClick={() => setEditing(c.id)}>
                    Edit
                  </button>
                  <button
                    type="button"
                    className="btn btn-ghost !h-8 !px-2.5 text-sm"
                    disabled={pending}
                    onClick={() => {
                      setError(null);
                      start(async () => {
                        const res = await deleteClientContact(clientId, c.id);
                        if (!res.ok) setError(res.error);
                        else router.refresh();
                      });
                    }}
                  >
                    Remove
                  </button>
                </div>
              )}
            </li>
          )
        )}
      </ul>
      {editing === 'new' ? (
        <ContactForm clientId={clientId} contact={null} onDone={() => setEditing(null)} />
      ) : (
        canEdit && (
          <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setEditing('new')}>
            + Add contact
          </button>
        )
      )}
      <ErrorLine text={error} />
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Link to an employer company on Omelo                                */
/* ------------------------------------------------------------------ */

export function LinkCompany({
  clientId,
  linkStatus,
  companyName,
  canRequest,
  canEnd,
}: {
  clientId: string;
  linkStatus: string;
  companyName: string | null;
  canRequest: boolean;
  canEnd: boolean;
}) {
  const uid = useId();
  const router = useRouter();
  const [term, setTerm] = useState('');
  const [found, setFound] = useState<{ id: string; name: string; verified: boolean; slug: string }[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState<string | null>(null);
  const [confirmEnd, setConfirmEnd] = useState(false);
  const [pending, start] = useTransition();
  const [open, setOpen] = useState(linkStatus === 'unlinked' || linkStatus === 'declined');

  const search = () => {
    setError(null);
    start(async () => {
      const res = await findEmployerCompanies(term);
      if (!res.ok) {
        setFound(null);
        return setError(res.error);
      }
      setFound(res.companies);
    });
  };

  return (
    <div className="space-y-3">
      {linkStatus === 'confirmed' && (
        <p className="text-sm">
          Linked to <strong>{companyName ?? 'their company'}</strong> on Omelo. When they connect one of their jobs to a
          job order, your submissions go straight into that job&apos;s pipeline.
        </p>
      )}
      {linkStatus === 'pending' && (
        <p className="text-sm">
          Waiting for <strong>{companyName ?? 'the company'}</strong> to confirm. Their owners and admins were notified.
        </p>
      )}
      {linkStatus === 'declined' && (
        <p className="text-sm" style={{ color: 'var(--color-danger)' }}>
          {companyName ?? 'The company'} declined the link. You can still recruit for them off-platform and record
          outcomes yourself.
        </p>
      )}
      {linkStatus === 'unlinked' && (
        <p className="text-sm muted">
          Not linked. If this client uses Omelo, ask them to confirm a link. You cannot link a company yourself — the
          company has to agree.
        </p>
      )}

      {linkStatus === 'confirmed' &&
        canEnd &&
        (confirmEnd ? (
          <div className="flex flex-wrap gap-2 items-center">
            <span className="text-sm">End the link? Connected jobs are disconnected; past submissions stay.</span>
            <button
              type="button"
              className="btn btn-primary !h-9 !px-3 text-sm"
              style={{ background: 'var(--color-danger)' }}
              disabled={pending}
              onClick={() =>
                start(async () => {
                  setError(null);
                  const res = await endClientLink(clientId);
                  if (!res.ok) return setError(res.error);
                  setConfirmEnd(false);
                  router.refresh();
                })
              }
            >
              End link
            </button>
            <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setConfirmEnd(false)}>
              Keep
            </button>
          </div>
        ) : (
          <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setConfirmEnd(true)}>
            End link
          </button>
        ))}

      {canRequest && linkStatus !== 'confirmed' && (
        <>
          {!open ? (
            <button type="button" className="btn btn-ghost !h-9 !px-3 text-sm" onClick={() => setOpen(true)}>
              Ask a different company
            </button>
          ) : (
            <div className="space-y-2">
              <form
                className="flex flex-wrap gap-2 items-end"
                onSubmit={(e) => {
                  e.preventDefault();
                  search();
                }}
              >
                <div className="flex-1 min-w-[12rem]">
                  <label className="label" htmlFor={`${uid}q`}>
                    Find the company on Omelo
                  </label>
                  <input
                    id={`${uid}q`}
                    className="input"
                    type="search"
                    maxLength={80}
                    value={term}
                    onChange={(e) => setTerm(e.target.value)}
                    placeholder="Company name"
                  />
                </div>
                <button className="btn btn-ghost w-full sm:w-auto" disabled={pending || term.trim().length < 2}>
                  {pending ? 'Searching…' : 'Search'}
                </button>
              </form>
              {found && found.length === 0 && <p className="text-sm muted">No employer on Omelo matches that name.</p>}
              {found && found.length > 0 && (
                <ul className="space-y-1.5">
                  {found.map((c) => (
                    <li key={c.id} className="flex items-center gap-2 flex-wrap surface rounded-lg p-2.5">
                      <span className="flex-1 min-w-0 text-sm break-words">
                        <strong>{c.name}</strong>{' '}
                        {c.verified ? (
                          <span style={{ color: 'var(--color-verified)' }}>✓ verified</span>
                        ) : (
                          <span className="muted">unverified</span>
                        )}
                      </span>
                      <button
                        type="button"
                        className="btn btn-primary !h-8 !px-3 text-sm"
                        disabled={pending}
                        onClick={() =>
                          start(async () => {
                            setError(null);
                            const res = await requestClientLink(clientId, c.id);
                            if (!res.ok) return setError(res.error);
                            setDone(`Request sent to ${c.name}. Their owners and admins decide.`);
                            setFound(null);
                            setOpen(false);
                            router.refresh();
                          })
                        }
                      >
                        Ask to link
                      </button>
                    </li>
                  ))}
                </ul>
              )}
            </div>
          )}
        </>
      )}
      {done && (
        <p className="text-sm" role="status" style={{ color: 'var(--color-verified)' }}>
          {done}
        </p>
      )}
      <ErrorLine text={error} />
    </div>
  );
}
