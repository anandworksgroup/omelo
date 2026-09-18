'use client';

import { useEffect, useId, useRef } from 'react';

/**
 * Modal built on the native <dialog>: focus trapping, Escape and the
 * backdrop come from the browser. Full-width sheet on phones, centred card
 * from `sm` up.
 */
export default function Dialog({
  open,
  onClose,
  title,
  description,
  children,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  description?: React.ReactNode;
  children: React.ReactNode;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  const titleId = useId();

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) d.showModal();
    if (!open && d.open) d.close();
  }, [open]);

  return (
    <dialog
      ref={ref}
      aria-labelledby={titleId}
      onClose={onClose}
      onClick={(e) => {
        // A click on the backdrop lands on the <dialog> element itself.
        if (e.target === e.currentTarget) onClose();
      }}
      className="card p-0 w-[calc(100vw-1.5rem)] max-w-lg max-h-[calc(100dvh-1.5rem)] m-auto backdrop:bg-black/50"
      style={{ color: 'var(--fg)' }}
    >
      {open && (
        <div className="p-4 sm:p-5 space-y-4">
          <div className="flex items-start gap-3">
            <div className="flex-1 min-w-0">
              <h2 id={titleId} className="font-bold text-lg break-words">
                {title}
              </h2>
              {description && <div className="text-sm muted mt-0.5 break-words">{description}</div>}
            </div>
            <button
              type="button"
              onClick={onClose}
              className="btn btn-ghost !h-9 !w-9 !p-0 shrink-0"
              aria-label="Close"
            >
              ✕
            </button>
          </div>
          {children}
        </div>
      )}
    </dialog>
  );
}
