import type { Service } from '../../lib/api/providers';
import { formatDuration, priceRange } from '../../lib/format';

export function ServiceList({
  services,
  currency,
}: {
  services: Service[];
  /// The salon's currency (multi-pays) — omitted → XOF.
  currency?: string | null;
}) {
  const active = services.filter((s) => s.active !== false);
  if (active.length === 0) return null;
  return (
    <section className="px-m py-l">
      <h2 className="text-titleLarge font-semibold text-textPrimary">Services & tarifs</h2>
      <ul className="mt-m divide-y divide-divider">
        {/* A price that cannot sit beside its service drops under it, on the
            right edge (web-salon-price-reflow.md). `flex-1` weighs only the
            name's longest word, so at normal text nothing moves. */}
        {active.map((s) => (
          <li
            key={s.id}
            className="flex flex-wrap items-baseline justify-between gap-x-m py-s"
          >
            <div className="flex-1">
              <p className="text-textPrimary">{s.name}</p>
              <p className="text-bodyMedium text-textTertiary">
                {formatDuration(s.durationMinutes)}
              </p>
            </div>
            <p className="ml-auto text-right text-textPrimary">
              {priceRange(s.price, s.priceMax, currency ?? undefined)}
            </p>
          </li>
        ))}
      </ul>
    </section>
  );
}
