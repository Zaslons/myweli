'use client';

import { Modal } from './Modal';

/// Fullscreen photo viewer (parity 2.6 — the app's tap-to-view). Backdrop, ✕
/// or Escape closes. Shared by the salon gallery and the review photos.
/// B5: `<Modal>` supplies the dialog contract (§8 — trap, Escape, restore,
/// scroll lock); the darker `bg-primary/80` scrim and the borderless panel are
/// this viewer's own look.
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
    <Modal
      label={label}
      onClose={onClose}
      scrimClassName="bg-primary/80"
      // `contents`: the panel box vanishes and the img/✕ become the fixed
      // wrapper's own flex items — the pre-B5 geometry, where `max-h-full`
      // resolves against the VIEWPORT-sized wrapper. A regular panel broke
      // portrait photos: its height is content-driven, so the img's
      // percentage cap resolved against nothing and tall shots clipped
      // (the review measured it). The trap still walks the DOM subtree.
      panelClassName="contents"
    >
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
        className="fixed right-m top-m flex min-h-12 min-w-12 items-center justify-center rounded-pill bg-primary/60 text-iconM text-secondary"
      >
        ✕
      </button>
    </Modal>
  );
}
