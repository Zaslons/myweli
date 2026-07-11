import type { Provider } from '../../lib/api/providers';
import { formatFcfa } from '../../lib/format';

/// Compact provider card for lists (landing pages, related, etc.).
export function ProviderCard({ provider }: { provider: Provider }) {
  const active = (provider.services ?? []).filter((s) => s.active !== false);
  const min = active.length ? Math.min(...active.map((s) => s.price)) : null;
  return (
    <a
      href={`/${provider.slug}`}
      className="block rounded-xl border border-border bg-secondary p-m hover:bg-surfaceVariant"
    >
      <div className="flex items-baseline justify-between gap-m">
        <h3 className="flex items-center gap-xs font-medium text-textPrimary">
          <span className="truncate">{provider.name}</span>
          {provider.verified ? (
            <span
              title="Salon vérifié"
              aria-label="Salon vérifié"
              className="shrink-0 text-info"
            >
              ✔︎
            </span>
          ) : null}
        </h3>
        {provider.reviewCount > 0 ? (
          <span className="whitespace-nowrap text-sm text-textTertiary">
            ★ {provider.rating.toFixed(1)}
          </span>
        ) : null}
      </div>
      {provider.commune ? (
        <p className="mt-xs text-sm text-textSecondary">{provider.commune}</p>
      ) : null}
      {min != null ? (
        <p className="mt-xs text-sm text-textTertiary">
          à partir de {formatFcfa(min)}
        </p>
      ) : null}
    </a>
  );
}
