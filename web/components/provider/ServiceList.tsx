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
      <h2 className="text-xl font-semibold text-textPrimary">Services & tarifs</h2>
      <ul className="mt-m divide-y divide-divider">
        {active.map((s) => (
          <li
            key={s.id}
            className="flex items-baseline justify-between gap-m py-s"
          >
            <div>
              <p className="text-textPrimary">{s.name}</p>
              <p className="text-sm text-textTertiary">
                {formatDuration(s.durationMinutes)}
              </p>
            </div>
            <p className="whitespace-nowrap text-textPrimary">
              {priceRange(s.price, s.priceMax, currency ?? undefined)}
            </p>
          </li>
        ))}
      </ul>
    </section>
  );
}
