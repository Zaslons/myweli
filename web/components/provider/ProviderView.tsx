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
import { BarClearance } from './BarClearance';
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
///
/// Below `lg`, a screen held sideways at 2.5 dppx and up names a smaller slot than the box, on
/// purpose (§1.9's one exception), so at the densities measured it asks for a 2× file and not
/// the 3840w one: ⅔ of the width from 2.5 dppx (844 wide at 3× asks 1920w), half of it from
/// 3.25 dppx (892 wide at 3.5× asks 1920w). Between them, above 3× and under 3.25× on a screen
/// about 950 wide and more, it still asks for 3840w, as before (§1.9 names the gaps). Neither `66.67vw` nor `calc(50vw)` is a bare `vw` (a bare `50vw` would add
/// 384w), so the candidates stay 640w and up. Upright screens and 2× screens keep the box.
export const COVER_SIZES =
  '(min-width: 1536px) 984px, (min-width: 1024px) calc(66.67vw - 40px), ' +
  '(orientation: landscape) and (min-resolution: 3.25dppx) calc(50vw), ' +
  '(orientation: landscape) and (min-resolution: 2.5dppx) 66.67vw, 100vw';

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

          Below `lg`, what the keyboard focuses here is kept clear of the booking bar by
          the page's scroll padding, which the bar carries (below). */}
      <div className="lg:col-span-4 lg:col-start-9 lg:row-span-2">
        <ProviderHero provider={p} slug={slug} preview={preview} className="lg:px-0 lg:pt-0" />
        <aside className="sticky top-l hidden lg:block">
          <BookingPanel provider={p} slug={slug} disabled={preview} />
        </aside>
      </div>

      {/* The sections. */}
      <div className="lg:col-span-8">
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

      {/* Mobile booking bar, fixed at the screen's foot below `lg`: « Réserver » never leaves
          the screen, at the page's very end included (BACKLOG 103). Fixed, it would stand on
          the footer's last link there, and a focused control could go under it, so
          `BarClearance` measures the bar and gives `<html>` a bottom padding as tall as the
          bar, so the page ends below the footer and the bar stops short of its last link, and
          a scroll padding of the bar plus `s`, so whatever the keyboard focuses, in the page or
          in the footer, stops 8px above it (WCAG 2.4.11), at every text size. Taken off from
          `lg` and when the page goes; the five store-linked pages never mount it. Not printed:
          fixed, it would stand at the foot of every printed page.
          As wide as the screen and never wider (`w-screen max-w-full`): a fixed box spans the
          layout viewport, and with doubled text on Android a row wider than the screen (the
          install banner's, 418px at 320) makes Chrome widen that viewport past the screen, so
          `inset-x-0` alone put « Réserver » off its right edge. `100vw` is the screen's width
          there; `max-w-full` keeps a window's classic scrollbar out of it.
          `data-floating-control` is how the favourite's toast finds it and moves clear of it
          (Toast.tsx, B11.5). */}
      <div
        data-floating-control=""
        className="fixed inset-x-0 bottom-0 z-sticky flex w-screen max-w-full items-center justify-between gap-m border-t border-divider bg-secondary px-m py-s print:hidden lg:hidden"
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
        <BarClearance />
      </div>
    </main>
  );
}
