'use client';

import type { ToastState } from '../lib/useToast';

/// The shared toast (§7, §10) — pairs with `useToast`.
///
/// The live region is ALWAYS rendered and the pill swaps INSIDE it: §7's own
/// rule is that the region must exist in the DOM **before** the text lands, or
/// nothing is read. Every pre-B5 toast mounted the region together with its
/// text ({toast ? <div role="status">…} — including the one that had
/// `role="status"`), which is exactly the unreliable shape. Keep this component
/// mounted unconditionally and let `toast` be null.
///
/// Kinds wear §15's colors: success/info = the brand pill (`bg-primary`),
/// error = `bg-error` (#8B0000 — ~10.6:1 under `secondary` white text).
/// Position: fixed bottom-center on `z-toast` — feedback is always on top (§9);
/// the pre-B5 EquipeClient toast had no z token and painted on DOM-order luck.
export function Toast({ toast }: { toast: ToastState }) {
  return (
    <div
      role="status"
      aria-live="polite"
      className="pointer-events-none fixed bottom-l left-1/2 z-toast -translate-x-1/2"
    >
      {toast ? (
        <div
          className={`rounded-lg px-l py-s text-bodyMedium text-secondary shadow-lg ${
            toast.kind === 'error' ? 'bg-error' : 'bg-primary'
          }`}
        >
          {toast.message}
        </div>
      ) : null}
    </div>
  );
}
