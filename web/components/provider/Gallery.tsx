'use client';

import Image from 'next/image';
import { useState } from 'react';
import { Lightbox } from '../Lightbox';

/// Salon photo gallery (beyond the hero cover). next/image grid (responsive +
/// lazy, R2 CDN allowlist) — tap any photo for the fullscreen viewer
/// (parity 2.6, the app's swipe-to-view web idiom).
export function Gallery({ images }: { images: string[] }) {
  const [open, setOpen] = useState<string | null>(null);

  if (images.length === 0) return null;
  return (
    <section className="px-m py-l">
      <h2 className="text-xl font-semibold text-textPrimary">Galerie</h2>
      <div className="mt-m grid grid-cols-2 gap-s sm:grid-cols-3">
        {images.map((src, i) => (
          <button
            key={`${src}-${i}`}
            type="button"
            onClick={() => setOpen(src)}
            aria-label={`Agrandir la photo ${i + 1}`}
            className="relative h-40 w-full overflow-hidden rounded-lg"
          >
            <Image
              src={src}
              alt=""
              fill
              loading="lazy"
              sizes="(min-width: 640px) 33vw, 50vw"
              className="object-cover"
            />
          </button>
        ))}
      </div>
      {open ? (
        <Lightbox
          url={open}
          label="Photo du salon"
          onClose={() => setOpen(null)}
        />
      ) : null}
    </section>
  );
}
