import { addressWithCommune } from '../../lib/address';
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
import { SalonVisitsCard } from '../account/SalonVisitsCard';
import { JsonLd } from '../JsonLd';
import { BeforeAfter } from './BeforeAfter';
import { BookingPanel } from './BookingPanel';
import { Faq } from './Faq';
import { FavoriteButton } from './FavoriteButton';
import { Gallery } from './Gallery';
import { ProviderCover, ProviderHero } from './Hero';
import { Hours } from './Hours';
import { MapEmbed } from './MapEmbed';
import { ReviewList } from './ReviewList';
import { ServiceList } from './ServiceList';

/// The salon's place words come from ITS market fields (multi-pays MP3):
/// commune/city ride the provider payload; the country display name is the
/// tree lookup the caller passes (« Côte d'Ivoire » = degraded fallback).
export function providerMetadata(
  p: Provider,
  slug: string,
  countryName?: string | null,
): Metadata {
  const commune = p.commune ?? p.city ?? 'Abidjan';
  const country = countryName ?? 'Côte d’Ivoire';
  const cat = categoryLabelFr(p.category);
  const title = `${p.name} — ${cat} à ${commune}`;
  const description =
    `${p.name} : ${cat.toLowerCase()} à ${commune}, ${country}. ` +
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

function buildFaq(
  p: Provider,
  country: string,
): { question: string; answer: string }[] {
  const commune = p.commune ?? p.city ?? 'Abidjan';
  const items = [
    {
      question: `Comment réserver chez ${p.name} ?`,
      answer:
        `Réservez en ligne sur MyWeli en quelques secondes : choisissez un ` +
        `service, un créneau, puis confirmez. Disponible 24/7, sans appel.`,
    },
    {
      question: `Où se trouve ${p.name} ?`,
      // addressWithCommune — this sentence ships into FAQPage JSON-LD and is
      // quotable by AI overviews; before the dedupe it read « … situé à
      // Marcory, marcory, Rue des Nguéssous 93, … » on the owner's own page.
      answer: `${p.name} est situé à ${
        p.address ? addressWithCommune(p.address, commune) : commune
      }, ${country}.`,
    },
  ];
  const active = (p.services ?? []).filter((s) => s.active !== false);
  if (active.length > 0) {
    const min = Math.min(...active.map((s) => s.price));
    items.push({
      question: `Quels sont les tarifs de ${p.name} ?`,
      answer:
        `Les prestations démarrent à partir de ` +
        `${formatFcfa(min, p.currency ?? undefined)}. ` +
        'Voir la liste complète des services et tarifs sur la page.',
    });
  }
  items.push({
    question: 'Faut-il payer un acompte ?',
    answer: p.depositRequired
      ? `Oui, ce salon demande un acompte pour confirmer, payé directement au ` +
        `salon via Mobile Money — MyWeli ne prélève rien.`
      : `Non, aucun acompte n’est requis pour réserver chez ${p.name}.`,
  });
  return items;
}

/// How wide the cover is drawn: the full width below `lg`; from `lg`, columns 1–8 of the
/// site grid, ⅔ of the container less 40px; 984px once the container stops at 1536. Only
/// `100vw` is a bare `vw`, and Next 14 counts only those, so the srcset keeps today's 640w
/// and up: a `sizes` with no bare `vw` would list every width from 16w
/// (docs/design/web-swiss-salon.md §1.9).
export const COVER_SIZES =
  '(min-width: 1536px) 984px, (min-width: 1024px) calc(66.67vw - 40px), 100vw';

/// The public salon page.
/// Design: docs/design/web-swiss-salon.md §1 (the cover in 3:2 and, from `lg`, the name and
/// the booking panel beside it).
///
/// `preview` = the owner's own pre-publish render (docs/design/
/// pro-salon-lifecycle.md B4): no JSON-LD, no consumer favorite button,
/// booking CTAs disabled — everything else EXACTLY as a client will see it.
export function ProviderView({
  provider: p,
  slug,
  preview = false,
  countryName,
}: {
  provider: Provider;
  slug: string;
  preview?: boolean;
  /// The salon country's display name (tree lookup on p.countryCode);
  /// omitted → the Wave-0 fallback.
  countryName?: string | null;
}) {
  const url = `${siteUrl}/${slug}`;
  const commune = p.commune ?? p.city ?? 'Abidjan';
  const country = countryName ?? 'Côte d’Ivoire';
  const cat = categoryLabelFr(p.category).toLowerCase();
  const faq = buildFaq(p, country);
  const artists = p.artists ?? [];
  const min = minActivePrice(p.services);

  return (
    // The site's container and twelve columns from `lg` (web-swiss-direction.md §6.1, §7.6):
    // `SITE_CONTAINER` without its phone padding, since the cover runs edge to edge there and
    // each section brings its own. The cover's x is the header logo's (site-look.spec.ts).
    <main className="mx-auto max-w-screen-2xl lg:grid lg:grid-cols-12 lg:gap-x-l lg:px-l">
      {!preview ? (
        <>
          <JsonLd data={localBusinessJsonLd(p, url)} />
          <JsonLd data={faqJsonLd(faq)} />
          <JsonLd
            data={breadcrumbJsonLd([
              { name: 'Accueil', url: siteUrl },
              { name: p.name, url },
            ])}
          />
        </>
      ) : null}

      <ProviderCover provider={p} sizes={COVER_SIZES} className="lg:col-span-8" />

      {/* Columns 9–12 from `lg`: the name, then the booking panel, which sticks while the
          sections scroll. Before the sections in the DOM, so the panel is reached right
          after the name; below `lg` the panel is hidden and the order is the phone's.

          `max-lg:[&_*]:scroll-mb-fab`, on this column and the next: below `lg`, whatever the
          keyboard focuses in them stops 96px (`fab`) above the screen's foot, clear of the
          65px booking bar. The browser scrolls a focused control just into view at the
          bottom and took no account of the bar, so the FAQ's questions and a gallery photo
          were hidden under it (WCAG 2.4.11). On the columns and not on `main`, which holds
          the bar, whose own « Réserver » would chase its margin; `scroll-padding` on `<html>`
          would do it once, but that is CSS the five store-linked pages share
          (web-swiss-salon.md §1.4). Written here in the `className` and not in a constant,
          so ESLint reads it: `no-arbitrary-value` refuses a bracketed 96px there and
          `no-custom-classname` a misspelt token, neither of which it sees in a bare string.
          (Not spelt out in this comment: Tailwind reads comments too, and would emit the
          class.)
          With the browser's text at double size the bar is 113px and up to 19px of a focused
          control can still sit under it: a px margin against a rem bar (WEB-SYSTEM §9). */}
      <div className="lg:col-span-4 lg:col-start-9 lg:row-span-2 max-lg:[&_*]:scroll-mb-fab">
        <ProviderHero provider={p} slug={slug} preview={preview} className="lg:px-0 lg:pt-0" />
        <aside className="sticky top-l hidden lg:block">
          <BookingPanel provider={p} slug={slug} disabled={preview} />
        </aside>
      </div>

      {/* The sections, with the same clearance below `lg` as the column above. */}
      <div className="lg:col-span-8 max-lg:[&_*]:scroll-mb-fab">
        <p className="max-w-content px-m pt-m text-bodyLarge text-textSecondary">
          Réservez en ligne chez {p.name}, {cat} à {commune} ({country}).
          Services, tarifs, horaires et avis — réservation 24/7, sans appel.
        </p>

        {!preview ? (
          <div className="px-m pt-s">
            <FavoriteButton providerId={p.id} slug={slug} />
          </div>
        ) : null}

        <Gallery images={(p.imageUrls ?? []).slice(1)} />

        <ServiceList services={p.services ?? []} currency={p.currency} />

        <BeforeAfter pairs={p.beforeAfters ?? []} />

        {artists.length > 0 ? (
          <section className="px-m py-l">
            <h2 className="text-titleLarge font-semibold text-textPrimary">Équipe</h2>
            <ul className="mt-m flex flex-wrap gap-m text-bodyMedium">
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

        {/* Parity 2.7/2.8 — the signed-in client's bookings at this salon. */}
        <SalonVisitsCard providerId={p.id} />

        <ReviewList
          reviews={p.reviews ?? []}
          rating={p.rating}
          reviewCount={p.reviewCount}
          slug={p.slug ?? ''}
          tz={p.timezone}
        />

        <MapEmbed
          name={p.name}
          category={p.category}
          address={p.address}
          commune={p.commune}
          latitude={p.latitude}
          longitude={p.longitude}
        />

        {/* Contact — desktop uses the sticky panel; shown here on mobile. */}
        <section className="px-m py-l lg:hidden">
          <h2 className="text-titleLarge font-semibold text-textPrimary">Contact</h2>
          <div className="mt-m flex flex-wrap gap-s">
            <a
              href={`tel:${p.phoneNumber}`}
              className="inline-flex min-h-12 items-center rounded-control border border-primary bg-secondary px-l text-labelLarge font-medium text-textPrimary"
            >
              Appeler
            </a>
            {p.whatsapp ? (
              <a
                href={`https://wa.me/${p.whatsapp.replace(/[^0-9]/g, '')}`}
                target="_blank"
                rel="noopener noreferrer"
                className="inline-flex min-h-12 items-center rounded-control border border-primary bg-secondary px-l text-labelLarge font-medium text-textPrimary"
              >
                WhatsApp
              </a>
            ) : null}
          </div>
        </section>

        <Faq items={faq} />
      </div>

      {/* Mobile booking bar. Sticky, not fixed, and the last thing in `main`: it rides the
          screen's foot while the page scrolls and stops above the footer, as « Carte » does
          (web-swiss-cards.md §2.4, decision 5). Fixed, with the 48px « Réserver », it stood on
          the footer's last link at the page's end. In the flow, so `main` needs no bottom padding.
          `data-floating-control` is how the favourite's toast finds it and moves clear of it
          (Toast.tsx, B11.5). */}
      <div
        data-floating-control=""
        className="sticky bottom-0 z-sticky flex items-center justify-between gap-m border-t border-divider bg-secondary px-m py-s lg:hidden"
      >
        {min != null ? (
          <div className="text-bodyMedium">
            <span className="text-textTertiary">À partir de </span>
            <span className="font-semibold text-textPrimary">
              {formatFcfa(min, p.currency ?? undefined)}
            </span>
          </div>
        ) : (
          <span />
        )}
        <BookingCta slug={slug} disabled={preview} />
      </div>
    </main>
  );
}
