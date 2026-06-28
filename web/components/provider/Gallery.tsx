import Image from 'next/image';

/// Salon photo gallery (beyond the hero cover). Uses next/image (responsive +
/// lazy) against the R2 CDN allowlist in next.config.mjs.
export function Gallery({ images }: { images: string[] }) {
  if (images.length === 0) return null;
  return (
    <section className="px-m py-l">
      <h2 className="text-xl font-semibold text-textPrimary">Galerie</h2>
      <div className="mt-m grid grid-cols-2 gap-s sm:grid-cols-3">
        {images.map((src, i) => (
          <div
            key={`${src}-${i}`}
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
          </div>
        ))}
      </div>
    </section>
  );
}
