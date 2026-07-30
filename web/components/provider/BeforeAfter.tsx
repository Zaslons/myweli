import Image from 'next/image';
import type { Provider } from '../../lib/api/providers';

type Pair = NonNullable<Provider['beforeAfters']>[number];

/// Salon before/after pairs (FR-DISC-006). Side-by-side; drag-reveal slider
/// deferred. Hidden when there are none.
export function BeforeAfter({ pairs }: { pairs: Pair[] }) {
  if (!pairs || pairs.length === 0) return null;
  return (
    <section className="px-m py-l">
      <h2 className="text-titleLarge font-semibold text-textPrimary">Avant / Après</h2>
      <div className="mt-m grid grid-cols-1 gap-m sm:grid-cols-2">
        {pairs.map((p, i) => (
          <figure
            key={`${p.before}-${i}`}
            className="rounded-lg border border-border bg-secondary p-s"
          >
            <div className="grid grid-cols-2 gap-xs">
              <div>
                <div className="relative h-32 w-full overflow-hidden rounded-sm">
                  <Image
                    src={p.before}
                    alt="Avant"
                    fill
                    loading="lazy"
                    sizes="(min-width: 640px) 25vw, 50vw"
                    className="object-cover"
                  />
                </div>
                <figcaption className="mt-xs text-center text-bodySmall text-textTertiary">
                  Avant
                </figcaption>
              </div>
              <div>
                <div className="relative h-32 w-full overflow-hidden rounded-sm">
                  <Image
                    src={p.after}
                    alt="Après"
                    fill
                    loading="lazy"
                    sizes="(min-width: 640px) 25vw, 50vw"
                    className="object-cover"
                  />
                </div>
                <figcaption className="mt-xs text-center text-bodySmall text-textTertiary">
                  Après
                </figcaption>
              </div>
            </div>
            {p.caption ? (
              <figcaption className="mt-s text-bodyMedium text-textSecondary">
                {p.caption}
              </figcaption>
            ) : null}
          </figure>
        ))}
      </div>
    </section>
  );
}
