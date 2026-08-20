import type { Provider } from '../api/providers';

/// JSON-LD builders (SEO/AEO/GEO). The Organization entity is the brand anchor
/// for generative engines (GEO); per-page entities (LocalBusiness, FAQPage…)
/// land with the provider/landing pages (M3+).

export const siteUrl =
  process.env.NEXT_PUBLIC_SITE_URL ?? 'http://localhost:3000';

/// Brand entity — emitted site-wide so search + AI consistently map
/// "réservation beauté en Côte d'Ivoire" → MyWeli.
export function organizationJsonLd() {
  return {
    '@context': 'https://schema.org',
    '@type': 'Organization',
    name: 'MyWeli',
    url: siteUrl,
    logo: `${siteUrl}/android-chrome-512.png`,
    description:
      'MyWeli — réservation beauté & bien-être en Côte d’Ivoire : ' +
      'coiffure, barbier, onglerie, spa. Réservez votre salon en ligne, 24/7.',
    areaServed: { '@type': 'Country', name: "Côte d'Ivoire" },
    // Empty ON PURPOSE, and pending rather than forgotten (2026-08-20).
    //
    // `sameAs` is how a search engine learns that this site and a set of
    // social profiles are ONE entity — it is what makes "MyWeli" resolve to
    // us rather than to a similarly-named business, and most of how a
    // knowledge panel is earned. It is also the cheapest SEO there is.
    //
    // MyWeli has no public profiles yet. Listing a URL that 404s, or one we
    // do not control, is worse than listing nothing: it ties the brand to
    // something that is not us. Fill this the day the accounts exist.
    sameAs: [] as string[],
  };
}

/// Serialize a JSON-LD object for a `<script type="application/ld+json">`.
export function jsonLdScript(data: unknown): string {
  return JSON.stringify(data);
}

/// WebSite entity + SearchAction (sitelinks search box) → /recherche. Emitted on
/// the home so engines can wire a MyWeli search box.
export function websiteJsonLd() {
  return {
    '@context': 'https://schema.org',
    '@type': 'WebSite',
    name: 'MyWeli',
    url: siteUrl,
    potentialAction: {
      '@type': 'SearchAction',
      target: {
        '@type': 'EntryPoint',
        urlTemplate: `${siteUrl}/recherche?q={search_term_string}`,
      },
      'query-input': 'required name=search_term_string',
    },
  };
}

/// CI service category → display label + schema.org LocalBusiness subtype.
const categoryMap: Record<string, { label: string; schemaType: string }> = {
  salon: { label: 'Salon de coiffure', schemaType: 'HairSalon' },
  barber: { label: 'Barbier', schemaType: 'HairSalon' },
  nail: { label: 'Onglerie', schemaType: 'NailSalon' },
  nails: { label: 'Onglerie', schemaType: 'NailSalon' },
  spa: { label: 'Spa', schemaType: 'DaySpa' },
  massage: { label: 'Massage & bien-être', schemaType: 'DaySpa' },
};

export function categoryLabelFr(category: string): string {
  return categoryMap[category]?.label ?? 'Beauté & bien-être';
}

function schemaTypeFor(category: string): string {
  return categoryMap[category]?.schemaType ?? 'HealthAndBeautyBusiness';
}

/// LocalBusiness (BeautySalon family) entity for a provider page (SEO).
export function localBusinessJsonLd(p: Provider, url: string) {
  const services = (p.services ?? []).filter((s) => s.active !== false);
  const reviews = (p.reviews ?? []).slice(0, 5).map((r) => ({
    '@type': 'Review',
    author: { '@type': 'Person', name: r.userName },
    reviewRating: { '@type': 'Rating', ratingValue: r.rating, bestRating: 5 },
    ...(r.text ? { reviewBody: r.text } : {}),
    datePublished: r.createdAt,
  }));
  return {
    '@context': 'https://schema.org',
    '@type': schemaTypeFor(p.category),
    name: p.name,
    url,
    description: p.description,
    image: p.imageUrls ?? [],
    telephone: p.phoneNumber,
    address: {
      '@type': 'PostalAddress',
      streetAddress: p.address,
      addressLocality: p.commune ?? p.city ?? undefined,
      // Multi-pays MP3: the salon's own market fields ('CI' = the
      // pre-backfill fallback only).
      addressCountry: p.countryCode ?? 'CI',
    },
    ...(p.latitude != null && p.longitude != null
      ? {
          geo: {
            '@type': 'GeoCoordinates',
            latitude: p.latitude,
            longitude: p.longitude,
          },
        }
      : {}),
    ...(p.reviewCount > 0
      ? {
          aggregateRating: {
            '@type': 'AggregateRating',
            ratingValue: p.rating,
            reviewCount: p.reviewCount,
          },
        }
      : {}),
    ...(reviews.length ? { review: reviews } : {}),
    makesOffer: services.map((s) => ({
      '@type': 'Offer',
      priceCurrency: p.currency ?? 'XOF',
      price: s.price,
      itemOffered: { '@type': 'Service', name: s.name },
    })),
    areaServed: p.commune ?? "Côte d'Ivoire",
  };
}

export function faqJsonLd(items: { question: string; answer: string }[]) {
  return {
    '@context': 'https://schema.org',
    '@type': 'FAQPage',
    mainEntity: items.map((i) => ({
      '@type': 'Question',
      name: i.question,
      acceptedAnswer: { '@type': 'Answer', text: i.answer },
    })),
  };
}

/// ItemList of providers on a landing page (SEO).
export function itemListJsonLd(items: { name: string; url: string }[]) {
  return {
    '@context': 'https://schema.org',
    '@type': 'ItemList',
    itemListElement: items.map((it, i) => ({
      '@type': 'ListItem',
      position: i + 1,
      name: it.name,
      url: it.url,
    })),
  };
}

export function breadcrumbJsonLd(crumbs: { name: string; url: string }[]) {
  return {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: crumbs.map((c, i) => ({
      '@type': 'ListItem',
      position: i + 1,
      name: c.name,
      item: c.url,
    })),
  };
}

/// A static content page (L1 — the four legal documents).
///
/// `WebPage` rather than `Article`: these are not editorial pieces, and
/// `dateModified` is the field that matters — a policy's date is a claim about
/// when the practice it describes last changed. It comes from the single
/// `LEGAL_UPDATED_AT`, so four pages cannot disagree.
export function webPageJsonLd({
  name,
  path,
  description,
  dateModified,
}: {
  name: string;
  path: string;
  description: string;
  dateModified: string;
}) {
  return {
    '@context': 'https://schema.org',
    '@type': 'WebPage',
    name,
    url: `${siteUrl}${path}`,
    description,
    inLanguage: 'fr-FR',
    dateModified,
    isPartOf: { '@type': 'WebSite', url: siteUrl },
    publisher: { '@type': 'Organization', name: 'MyWeli', url: siteUrl },
  };
}
