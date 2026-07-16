import Image from 'next/image';
import type { Provider } from '../../lib/api/providers';
import { categoryLabelFr } from '../../lib/seo/jsonld';
import { BookingCta } from '../BookingCta';

export function ProviderHero({ provider }: { provider: Provider }) {
  const hero = provider.imageUrls?.[0];
  const sub = [categoryLabelFr(provider.category), provider.commune]
    .filter(Boolean)
    .join(' · ');
  return (
    <header>
      {hero ? (
        <div className="relative h-56 w-full sm:h-80">
          <Image
            src={hero}
            alt={`Salon ${provider.name}`}
            fill
            priority
            sizes="100vw"
            className="object-cover"
          />
        </div>
      ) : null}
      <div className="px-m py-l">
        <p className="text-bodyMedium text-textTertiary">{sub}</p>
        <h1 className="mt-xs flex items-center gap-s text-headlineMedium font-semibold text-textPrimary">
          {provider.name}
          {provider.verified ? (
            <span className="rounded-pill bg-info/10 px-s py-xs text-labelMedium font-medium text-info">
              ✔ Vérifié
            </span>
          ) : null}
        </h1>
        {provider.reviewCount > 0 ? (
          <p className="mt-xs text-bodyMedium text-textSecondary">
            ★ {provider.rating.toFixed(1)} · {provider.reviewCount} avis
          </p>
        ) : null}
        <div className="mt-m">
          <BookingCta slug={provider.slug ?? ''} />
        </div>
      </div>
    </header>
  );
}
