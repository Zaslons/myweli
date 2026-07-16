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
      className="fixed inset-0 z-modal flex items-center justify-center bg-primary/80 p-m"
      role="dialog"
      aria-label={label}
      onClick={onClose}
    >
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={url}
        alt={label}
        className="max-h-full max-w-full rounded-lg object-contain"
      />
      <button
        type="button"
        aria-label="Fermer"
        onClick={onClose}
        className="absolute right-4 top-4 rounded-pill bg-primary/60 px-sm py-xs text-lg text-secondary"
      >
        ✕
      </button>
    </div>
  );
}
