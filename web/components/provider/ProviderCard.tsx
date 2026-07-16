import type { Provider } from '../../lib/api/providers';
import { formatFcfa } from '../../lib/format';

/// Compact provider card for lists (landing pages, related, etc.). Client
/// lists may pass the favorite pair to render a heart (parity 2.15).
export function ProviderCard({
  provider,
  favorite,
  onToggleFavorite,
}: {
  provider: Provider;
  favorite?: boolean;
  onToggleFavorite?: () => void;
}) {
  const active = (provider.services ?? []).filter((s) => s.active !== false);
  const min = active.length ? Math.min(...active.map((s) => s.price)) : null;
  const card = (
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
          <span className="whitespace-nowrap text-bodyMedium text-textTertiary">
            ★ {provider.rating.toFixed(1)}
          </span>
        ) : null}
      </div>
      {provider.commune ? (
        <p className="mt-xs text-bodyMedium text-textSecondary">{provider.commune}</p>
      ) : null}
      {min != null ? (
        <p className="mt-xs text-bodyMedium text-textTertiary">
          à partir de {formatFcfa(min, provider.currency ?? undefined)}
        </p>
      ) : null}
    </a>
  );
  if (!onToggleFavorite) return card;
  return (
    <div className="relative">
      {card}
      <button
        type="button"
        aria-pressed={favorite}
        aria-label={
          favorite
            ? `Retirer ${provider.name} des favoris`
            : `Ajouter ${provider.name} aux favoris`
        }
        onClick={onToggleFavorite}
        className={`absolute bottom-0 right-0 flex h-12 w-12 items-center justify-center rounded-pill text-iconM leading-none ${
          favorite ? 'text-error' : 'text-textTertiary'
        } hover:bg-surfaceVariant`}
      >
        {favorite ? '♥' : '♡'}
      </button>
    </div>
  );
}
