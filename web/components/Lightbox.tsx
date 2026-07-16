'use client';

/// Fullscreen photo viewer (parity 2.6 — the app's tap-to-view). Backdrop or
/// ✕ closes. Shared by the salon gallery and the review photos.
export function Lightbox({
  url,
  label,
  onClose,
}: {
  url: string;
  label: string;
  onClose: () => void;
}) {
  return (
    <div
      className="fixed inset-0 z-modal flex items-center justify-center p-m"
      role="dialog"
      aria-label={label}
    >
      {/* The scrim carries the dismiss click and is decoration to AT —
          ProShell's own drawer-scrim precedent (jsx-a11y strict would rightly
          flag a click handler on the dialog wrapper itself). */}
      <div
        aria-hidden="true"
        className="absolute inset-0 bg-primary/80"
        onClick={onClose}
      />
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={url}
        alt={label}
        className="relative max-h-full max-w-full rounded-lg object-contain"
      />
      <button
        type="button"
        aria-label="Fermer"
        onClick={onClose}
        className="absolute right-m top-m flex min-h-12 min-w-12 items-center justify-center rounded-pill bg-primary/60 text-iconM text-secondary"
      >
        ✕
      </button>
    </div>
  );
}
