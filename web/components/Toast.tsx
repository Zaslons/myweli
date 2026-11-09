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
/// The region spans the screen with the page's side gutter and centres the
/// pill in it: centred by `left-1/2 -translate-x-1/2` instead, a long sentence
/// had half the screen to wrap in — 182 px wide and 456 px tall at 320 px with
/// doubled text (docs/design/web-pro-upload-resize.md, review 2026-11-09).
export function Toast({
  toast,
  aboveFloatingControl = false,
}: {
  toast: ToastState;
  /// The page has its own floating control at the bottom centre under `lg`
  /// (the search's « Carte » toggle: 24–72px): the toast sits above it there,
  /// at 80px (`bottom-xxxl` + `pb-m`), never over it.
  aboveFloatingControl?: boolean;
}) {
  return (
    <div
      role="status"
      aria-live="polite"
      className={`pointer-events-none fixed inset-x-0 z-toast flex justify-center px-m ${
        aboveFloatingControl ? 'bottom-xxxl pb-m lg:bottom-l lg:pb-0' : 'bottom-l'
      }`}
    >
      {toast ? (
        <div
          key={toast.id}
          className={`flex max-w-xl items-center gap-m rounded-lg px-l py-s text-bodyMedium text-secondary shadow-lg ${
            toast.kind === 'error' ? 'bg-error' : 'bg-primary'
          }`}
        >
          {toast.message}
          {toast.action ? (
            // The container lets clicks through; its one control takes them.
            <button
              type="button"
              onClick={toast.action.onAction}
              className="pointer-events-auto -my-s min-h-12 font-semibold text-secondary underline"
            >
              {toast.action.label}
            </button>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
