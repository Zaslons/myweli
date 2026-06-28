import type { Provider } from '../../lib/api/providers';

type Pair = NonNullable<Provider['beforeAfters']>[number];

/// Salon before/after pairs (FR-DISC-006). Side-by-side; drag-reveal slider
/// deferred. Hidden when there are none.
export function BeforeAfter({ pairs }: { pairs: Pair[] }) {
  if (!pairs || pairs.length === 0) return null;
  return (
    <section className="px-m py-l">
      <h2 className="text-xl font-semibold text-textPrimary">Avant / Après</h2>
      <div className="mt-m grid grid-cols-1 gap-m sm:grid-cols-2">
        {pairs.map((p, i) => (
          <figure
            key={`${p.before}-${i}`}
            className="rounded-lg border border-border bg-secondary p-s"
          >
            <div className="grid grid-cols-2 gap-xs">
              <div>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={p.before}
                  alt="Avant"
                  loading="lazy"
                  className="h-32 w-full rounded object-cover"
                />
                <figcaption className="mt-xs text-center text-xs text-textTertiary">
                  Avant
                </figcaption>
              </div>
              <div>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={p.after}
                  alt="Après"
                  loading="lazy"
                  className="h-32 w-full rounded object-cover"
                />
                <figcaption className="mt-xs text-center text-xs text-textTertiary">
                  Après
                </figcaption>
              </div>
            </div>
            {p.caption ? (
              <figcaption className="mt-s text-sm text-textSecondary">
                {p.caption}
              </figcaption>
            ) : null}
          </figure>
        ))}
      </div>
    </section>
  );
}
