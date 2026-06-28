import type { Metadata } from 'next';
import type { Provider } from '../../lib/api/providers';
import { formatFcfa } from '../../lib/format';
import {
  breadcrumbJsonLd,
  categoryLabelFr,
  faqJsonLd,
  localBusinessJsonLd,
  siteUrl,
} from '../../lib/seo/jsonld';
import { minActivePrice } from '../../lib/provider-summary';
import { BookingCta } from '../BookingCta';
import { JsonLd } from '../JsonLd';
import { BeforeAfter } from './BeforeAfter';
import { BookingPanel } from './BookingPanel';
import { Faq } from './Faq';
import { Gallery } from './Gallery';
import { ProviderHero } from './Hero';
import { Hours } from './Hours';
import { MapEmbed } from './MapEmbed';
import { ReviewList } from './ReviewList';
import { ServiceList } from './ServiceList';

export function providerMetadata(p: Provider, slug: string): Metadata {
  const commune = p.commune ?? 'Abidjan';
  const cat = categoryLabelFr(p.category);
  const title = `${p.name} — ${cat} à ${commune}`;
  const description =
    `${p.name} : ${cat.toLowerCase()} à ${commune}, Côte d’Ivoire. ` +
    'Réservez en ligne — services, tarifs, horaires et avis.';
  const url = `${siteUrl}/${slug}`;
  return {
    title,
    description,
    alternates: { canonical: url },
    openGraph: {
      title,
      description,
      url,
      images: p.imageUrls?.length ? [p.imageUrls[0]] : undefined,
    },
  };
}

function buildFaq(p: Provider): { question: string; answer: string }[] {
  const commune = p.commune ?? 'Abidjan';
  const items = [
    {
      question: `Comment réserver chez ${p.name} ?`,
      answer:
        `Réservez en ligne sur Myweli en quelques secondes : choisissez un ` +
        `service, un créneau, puis confirmez. Disponible 24/7, sans appel.`,
    },
    {
      question: `Où se trouve ${p.name} ?`,
      answer:
        `${p.name} est situé à ${commune}` +
        `${p.address ? `, ${p.address}` : ''}, Côte d’Ivoire.`,
    },
  ];
  const active = (p.services ?? []).filter((s) => s.active !== false);
  if (active.length > 0) {
    const min = Math.min(...active.map((s) => s.price));
    items.push({
      question: `Quels sont les tarifs de ${p.name} ?`,
      answer:
        `Les prestations démarrent à partir de ${formatFcfa(min)}. ` +
        'Voir la liste complète des services et tarifs sur la page.',
    });
  }
  items.push({
    question: 'Faut-il payer un acompte ?',
    answer: p.depositRequired
      ? `Oui, ce salon demande un acompte pour confirmer, payé directement au ` +
        `salon via Mobile Money — Myweli ne prélève rien.`
      : `Non, aucun acompte n’est requis pour réserver chez ${p.name}.`,
  });
  return items;
}

export function ProviderView({ provider: p, slug }: { provider: Provider; slug: string }) {
  const url = `${siteUrl}/${slug}`;
  const commune = p.commune ?? 'Abidjan';
  const cat = categoryLabelFr(p.category).toLowerCase();
  const faq = buildFaq(p);
  const artists = p.artists ?? [];
  const min = minActivePrice(p.services);

  return (
    <main className="mx-auto max-w-5xl pb-xxl lg:pb-0">
      <JsonLd data={localBusinessJsonLd(p, url)} />
      <JsonLd data={faqJsonLd(faq)} />
      <JsonLd
        data={breadcrumbJsonLd([
          { name: 'Accueil', url: siteUrl },
          { name: p.name, url },
        ])}
      />

      <ProviderHero provider={p} />

      <div className="lg:grid lg:grid-cols-3 lg:gap-l">
        <div className="lg:col-span-2">
          <p className="px-m pt-m text-textSecondary">
            Réservez en ligne chez {p.name}, {cat} à {commune} (Côte d’Ivoire).
            Services, tarifs, horaires et avis — réservation 24/7, sans appel.
          </p>

          <Gallery images={(p.imageUrls ?? []).slice(1)} />

          <ServiceList services={p.services ?? []} />

          <BeforeAfter pairs={p.beforeAfters ?? []} />

          {artists.length > 0 ? (
            <section className="px-m py-l">
              <h2 className="text-xl font-semibold text-textPrimary">Équipe</h2>
              <ul className="mt-m flex flex-wrap gap-m text-sm">
                {artists.map((a) => (
                  <li key={a.id}>
                    <span className="text-textPrimary">{a.name}</span>
                    {a.specialization ? (
                      <span className="text-textTertiary">
                        {' '}
                        · {a.specialization}
                      </span>
                    ) : null}
                  </li>
                ))}
              </ul>
            </section>
          ) : null}

          <Hours availability={p.availability} />

          <ReviewList
            reviews={p.reviews ?? []}
            rating={p.rating}
            reviewCount={p.reviewCount}
          />

          <MapEmbed
            address={p.address}
            commune={p.commune}
            latitude={p.latitude}
            longitude={p.longitude}
          />

          {/* Contact — desktop uses the sticky panel; shown here on mobile. */}
          <section className="px-m py-l lg:hidden">
            <h2 className="text-xl font-semibold text-textPrimary">Contact</h2>
            <div className="mt-m flex flex-wrap gap-s">
              <a
                href={`tel:${p.phoneNumber}`}
                className="rounded-lg border border-border bg-secondary px-l py-s text-sm font-medium text-textPrimary"
              >
                Appeler
              </a>
              {p.whatsapp ? (
                <a
                  href={`https://wa.me/${p.whatsapp.replace(/[^0-9]/g, '')}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="rounded-lg border border-border bg-secondary px-l py-s text-sm font-medium text-textPrimary"
                >
                  WhatsApp
                </a>
              ) : null}
            </div>
          </section>

          <Faq items={faq} />
        </div>

        <aside className="hidden px-m pt-m lg:block">
          <div className="sticky top-l">
            <BookingPanel provider={p} slug={slug} />
          </div>
        </aside>
      </div>

      {/* Mobile sticky booking bar */}
      <div className="fixed inset-x-0 bottom-0 z-20 flex items-center justify-between gap-m border-t border-divider bg-secondary px-m py-s lg:hidden">
        {min != null ? (
          <div className="text-sm">
            <span className="text-textTertiary">À partir de </span>
            <span className="font-semibold text-textPrimary">
              {formatFcfa(min)}
            </span>
          </div>
        ) : (
          <span />
        )}
        <BookingCta slug={slug} />
      </div>
    </main>
  );
}
