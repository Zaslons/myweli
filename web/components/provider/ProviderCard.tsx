import Image from 'next/image';
import type { Provider } from '../../lib/api/providers';
import { formatFcfa } from '../../lib/format';
import { salonInitial, salonNameOr, UNNAMED_SALON } from '../../lib/salon-name';
import { SalonRating } from '../Rating';

/// A real `sizes` per grid (docs/design/web-swiss-cards.md §2.2, the table in §2.3).
///
/// **A trap, in Next's code:** it keeps only the candidates at or above `640 × the
/// smallest vw` it finds here (`get-img-props.js:46-54`), so `92vw` alone drops every
/// file below 640w. `account` at `32vw` keeps 256w, which is what a 119-wide row picks
/// at DPR 2; held by tests/provider-card.test.tsx.
export const CARD_SIZES = {
  site: '(min-width: 1536px) 354px, (min-width: 1024px) 23vw, (min-width: 640px) 48vw, 92vw',
  row: '(min-width: 1024px) 18vw, 32vw',
  account: '(min-width: 1024px) 203px, (min-width: 640px) 312px, 32vw',
} as const;

/// `https://` is for dev seeds, not a security boundary: an `asset:` value makes
/// `next dev` throw, so it reads as no photo and the next form takes over. The server
/// is the authority on what a salon can store (spec §6).
const httpsOrNull = (url: string | null | undefined): string | null =>
  url && url.startsWith('https://') ? url : null;

/// A browser generates an `<img>`'s `::after` only when the image failed, so a loaded
/// photo is untouched. `alt` alone is not enough: Chromium still draws its broken-image
/// mark in the corner (measured, 548 colours there without this; spec §2.4).
const FAILED_COVER = 'after:absolute after:inset-0 after:bg-surfaceVariant';

/// The salon card, in two layouts: a salon's own photo, square and uncovered, with
/// flush-left text and one thin rule. **Design: docs/design/web-swiss-cards.md**, the
/// rule of the new look's cards and the reason for every class below (its §2.2).
///
/// Shared, with no `'use client'`, so `/` and the landings add no client code of their
/// own. Client lists may pass the favourite pair to render a heart (parity 2.15).
export function ProviderCard({
  provider,
  favorite,
  onToggleFavorite,
  favoriteBusy = false,
  favoritePending = false,
  layout = 'tile',
  imageSizes,
  imagePriority = false,
  linked = true,
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
  /// True while THIS heart's write is out (B5.2,
  /// docs/design/web-client-polish.md §2.2): a second click is not another
  /// write. `aria-disabled`, not `disabled` — the heart keeps the keyboard's
  /// focus, which a disabled button drops to <body>.
  favoritePending?: boolean;
  /// `tile`: the photo on top. `row`: the photo left, a third of the width.
  /// `rowOnPhone`: a row below `sm`, a tile from `sm` (the favourites, decision 3).
  layout?: 'tile' | 'row' | 'rowOnPhone';
  /// Defaults by layout. A grid of its own passes its own (`CARD_SIZES`).
  imageSizes?: string;
  /// One card per page at most, and only where it earns its place (spec §7).
  imagePriority?: boolean;
  /// False for a favourite whose salon stopped: that link ends on a 404. The root is a
  /// `<div>` then, with no hover (decision 3).
  linked?: boolean;
}) {
  const active = (provider.services ?? []).filter((s) => s.active !== false);
  const min = active.length ? Math.min(...active.map((s) => s.price)) : null;
  const name = salonNameOr(provider.name, UNNAMED_SALON);
  const row = layout === 'row';
  const phoneRow = layout === 'rowOnPhone';
  const sizes = imageSizes ?? (row ? CARD_SIZES.row : CARD_SIZES.site);

  // `?.`, not `.`: lib/api/account.ts validates only `id` and `name`.
  const photo = httpsOrNull(provider.imageUrls?.[0]);
  const logo = photo ? null : httpsOrNull(provider.logoUrl);
  const initial = salonInitial(name);
  const initialSize =
    row || phoneRow ? 'text-displaySmall sm:text-displayLarge' : 'text-displayLarge';
  const initialSizeOnFailure =
    row || phoneRow ? 'after:text-displaySmall sm:after:text-displayLarge' : 'after:text-displayLarge';
  const letter = (
    <span
      aria-hidden="true"
      className={`absolute bottom-0 left-0 font-semibold tracking-tight text-textSecondary ${initialSize}`}
    >
      {initial}
    </span>
  );

  // The one rule the card draws: it gives a no-photo tile an edge, where
  // `surfaceVariant` on `surface` is 1.045:1 and forced colours drop the fill. The list
  // draws the lines between rows, so a card never doubles one.
  const media = (
    <div
      className={`relative aspect-card border-b border-divider bg-surfaceVariant ${
        row ? 'w-1/3 shrink-0' : phoneRow ? 'w-1/3 shrink-0 sm:w-auto' : ''
      }`}
    >
      {photo ? (
        <>
          {/* Under the photo, so a slow one holds the salon's letter and paints over it
              with no shift. It has to come first: a loaded photo covers it whole. */}
          {letter}
          <Image
            fill
            src={photo}
            sizes={sizes}
            alt={name}
            data-initial={initial}
            // Next refuses `priority` and `loading` together.
            priority={imagePriority || undefined}
            loading={imagePriority ? undefined : 'lazy'}
            className={`object-cover ${FAILED_COVER} after:flex after:items-end after:font-semibold after:tracking-tight after:text-textSecondary after:content-initial ${initialSizeOnFailure}`}
          />
        </>
      ) : logo ? (
        // In the corner, on the name's x, with nothing under it: a letter would show
        // below a contained logo. Any aspect ratio can arrive (salon-logo.md §1).
        <div className="absolute bottom-0 left-0 h-2/3 w-2/3">
          <Image
            fill
            src={logo}
            sizes={sizes}
            alt={`Logo ${name}`}
            loading="lazy"
            className={`object-contain object-left-bottom ${FAILED_COVER}`}
          />
        </div>
      ) : (
        letter
      )}
    </div>
  );

  const body = (
    <div className={row ? 'min-w-0 flex-1' : phoneRow ? 'min-w-0 flex-1 sm:mt-sm' : 'mt-sm'}>
      {/* One inline run that wraps: the name has no other copy on the card, and the
          reader who enlarged the text is the one a clip would cost it (decision 2). A
          no-break space keeps the mark with the last word. */}
      <h3 className="break-words font-medium text-textPrimary">
        <span className={linked ? 'group-hover:underline group-focus-visible:underline' : undefined}>
          {name}
        </span>
        {provider.verified ? (
          <>
            {' '}
            <span title="Salon vérifié" aria-label="Salon vérifié" className="text-info">
              ✔︎
            </span>
          </>
        ) : null}
      </h3>
      {/* Its own line, the app's order. It wraps with the count at doubled text and
          stays inside the column, so no `whitespace-nowrap` here. */}
      <div className="mt-xs text-bodyMedium text-textTertiary">
        <SalonRating rating={provider.rating} reviewCount={provider.reviewCount} withCount />
      </div>
      <div className="flex">
        <div className="min-w-0 flex-1">
          {provider.commune ? (
            <p className="mt-xs text-bodyMedium text-textSecondary">{provider.commune}</p>
          ) : null}
          {min != null ? (
            <p className="mt-xs text-bodyMedium text-textTertiary">
              à partir de{' '}
              {/* `formatFcfa` puts a plain space before « FCFA »: without this, 320
                  reads « 15 000 / FCFA ». */}
              <span className="inline-block">
                {formatFcfa(min, provider.currency ?? undefined)}
              </span>
            </p>
          ) : null}
        </div>
        {/* As tall as the heart, in rem as the heart is: it fills the heart's band
            whatever the text, so the name and the rating above can never reach it. A
            px padding against a rem box is a named defect (WEB-SYSTEM §9). */}
        {onToggleFavorite ? <span aria-hidden="true" className="h-12 w-12 shrink-0" /> : null}
      </div>
    </div>
  );

  const rootClass = row
    ? 'group flex items-start gap-sm sm:gap-m'
    : phoneRow
      ? 'group flex items-start gap-sm sm:block'
      : 'group block';
  const card = linked ? (
    <a href={`/${provider.slug}`} className={rootClass}>
      {media}
      {body}
    </a>
  ) : (
    <div className={rootClass}>
      {media}
      {body}
    </div>
  );
  if (!onToggleFavorite) return card;
  return (
    <div className="relative">
      {card}
      <button
        type="button"
        aria-pressed={favorite}
        aria-label={favorite ? `Retirer ${name} des favoris` : `Ajouter ${name} aux favoris`}
        onClick={favoritePending ? undefined : onToggleFavorite}
        disabled={favoriteBusy}
        aria-disabled={favoritePending || undefined}
        aria-busy={favoriteBusy || favoritePending || undefined}
        className={`absolute bottom-0 right-0 flex h-12 w-12 items-center justify-center rounded-pill text-iconM leading-none disabled:opacity-50 aria-disabled:opacity-50 ${
          favorite ? 'text-error' : 'text-textTertiary'
        } hover:bg-surfaceVariant`}
      >
        {favorite ? '♥' : '♡'}
      </button>
    </div>
  );
}
