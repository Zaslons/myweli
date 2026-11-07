import Image from 'next/image';
import { Chip } from '../Chip';
import { SalonRating } from '../Rating';
import type { Provider } from '../../lib/api/providers';
import { categoryLabelFr } from '../../lib/seo/jsonld';
import { BookingCta } from '../BookingCta';

// Design: docs/design/web-swiss-salon.md §1.

/// The salon's cover: its first photo, 3:2 at every width (web-swiss-direction.md §6.4, §7.6;
/// BACKLOG decisions 95 and 97), cut at `object-subject` as the card is (decision 96;
/// web-swiss-cards.md §11). The logo sits on it, bottom-left, ringed so it reads on any photo
/// (salon-cover-photo.md §2.1, item 4). Until the photo arrives, or if it fails, the box keeps
/// its shape in `surfaceVariant`. No photo, no cover. Where it goes and how wide it is drawn
/// are the page's: `ProviderView` passes the grid classes and `sizes`.
export function ProviderCover({
  provider,
  sizes,
  className = '',
}: {
  provider: Provider;
  sizes: string;
  className?: string;
}) {
  const hero = provider.imageUrls?.[0];
  const logo = provider.logoUrl;
  if (!hero) return null;
  return (
    <div className={`relative aspect-cover w-full bg-surfaceVariant ${className}`}>
      <Image
        src={hero}
        alt={`Salon ${provider.name}`}
        fill
        priority
        sizes={sizes}
        className="object-cover object-subject"
      />
      {logo ? (
        <div className="absolute bottom-m left-m h-16 w-16 overflow-hidden rounded-pill border-2 border-secondary bg-secondary shadow-lg">
          <Image
            src={logo}
            alt={`Logo ${provider.name}`}
            fill
            sizes="64px"
            className="object-cover"
          />
        </div>
      ) : null}
    </div>
  );
}

/// The salon's name block: category and place, the `<h1>`, the rating, and « Réserver ».
/// From `lg` the booking panel sits right under it and carries « Réserver », so this one goes.
/// In the owner's preview it is disabled, as every booking control there is
/// (pro-salon-lifecycle.md B4). The `<h1>` wraps, so « ✔ Vérifié » takes a line of its own
/// beside a long name in the narrow column rather than breaking in two.
export function ProviderHero({
  provider,
  slug = provider.slug ?? '',
  preview = false,
  className = '',
}: {
  provider: Provider;
  slug?: string;
  preview?: boolean;
  className?: string;
}) {
  const sub = [categoryLabelFr(provider.category), provider.commune]
    .filter(Boolean)
    .join(' · ');
  return (
    <header className={`px-m py-l ${className}`}>
      <p className="text-bodyMedium text-textTertiary">{sub}</p>
      <h1 className="mt-xs flex flex-wrap items-center gap-s text-headlineMedium font-semibold text-textPrimary">
        {provider.name}
        {provider.verified ? (
          <Chip variant="tinted" tint="info">
            ✔ Vérifié
          </Chip>
        ) : null}
      </h1>
      <p className="mt-xs text-bodyMedium text-textSecondary">
        <SalonRating
          rating={provider.rating}
          reviewCount={provider.reviewCount}
          withCount
          dense={false}
        />
      </p>
      <div className="mt-m lg:hidden">
        <BookingCta slug={slug} disabled={preview} />
      </div>
    </header>
  );
}
