import type { Provider } from '../../lib/api/providers';
import { formatFcfa } from '../../lib/format';
import { Rating } from '../Rating';

/// Compact provider card for lists (landing pages, related, etc.). Client
/// lists may pass the favorite pair to render a heart (parity 2.15).
export function ProviderCard({
  provider,
  favorite,
  onToggleFavorite,
  favoriteBusy = false,
}: {
  provider: Provider;
  favorite?: boolean;
  onToggleFavorite?: () => void;
  /// True while the favourite state is UNKNOWN — the list has not finished
  /// asking who you are. The heart is disabled then, because a control whose
  /// only honest answers are "not yet" and "I don't know" must not look ready:
  /// clicking during that window used to send a SIGNED-IN visitor to the login
  /// page, since `null` meant both "loading" and "anonymous".
  favoriteBusy?: boolean;
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
          {/* clip-ok: the whole card is an `<a>` to `/{slug}`, whose `<h1>` is
              this exact name in full. A search result is a pointer to a page,
              and the page is one tap away — this is the strongest recovery path
              of any truncation in the product. */}
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
            <Rating value={provider.rating} />
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
        disabled={favoriteBusy}
        aria-busy={favoriteBusy || undefined}
        className={`absolute bottom-0 right-0 flex h-12 w-12 items-center justify-center rounded-pill text-iconM leading-none disabled:opacity-50 ${
          favorite ? 'text-error' : 'text-textTertiary'
        } hover:bg-surfaceVariant`}
      >
        {favorite ? '♥' : '♡'}
      </button>
    </div>
  );
}
