/// Salon photo gallery (beyond the hero cover). Plain <img> — the next/image
/// CDN allowlist is wired at the accounts phase (same as Hero).
export function Gallery({ images }: { images: string[] }) {
  if (images.length === 0) return null;
  return (
    <section className="px-m py-l">
      <h2 className="text-xl font-semibold text-textPrimary">Galerie</h2>
      <div className="mt-m grid grid-cols-2 gap-s sm:grid-cols-3">
        {images.map((src, i) => (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            key={`${src}-${i}`}
            src={src}
            alt=""
            loading="lazy"
            className="h-40 w-full rounded-lg object-cover"
          />
        ))}
      </div>
    </section>
  );
}
