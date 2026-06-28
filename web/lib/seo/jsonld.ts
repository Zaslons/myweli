import type { Provider } from '../api/providers';

/// JSON-LD builders (SEO/AEO/GEO). The Organization entity is the brand anchor
/// for generative engines (GEO); per-page entities (LocalBusiness, FAQPage…)
/// land with the provider/landing pages (M3+).

export const siteUrl =
  process.env.NEXT_PUBLIC_SITE_URL ?? 'http://localhost:3000';

/// Brand entity — emitted site-wide so search + AI consistently map
/// "réservation beauté en Côte d'Ivoire" → Myweli.
export function organizationJsonLd() {
  return {
    '@context': 'https://schema.org',
    '@type': 'Organization',
    name: 'Myweli',
    url: siteUrl,
    logo: `${siteUrl}/logo.svg`,
    description:
      'Myweli — réservation beauté & bien-être en Côte d’Ivoire : ' +
      'coiffure, barbier, onglerie, spa. Réservez votre salon en ligne, 24/7.',
    areaServed: { '@type': 'Country', name: "Côte d'Ivoire" },
    sameAs: [] as string[],
  };
}

/// Serialize a JSON-LD object for a `<script type="application/ld+json">`.
export function jsonLdScript(data: unknown): string {
  return JSON.stringify(data);
}

/// WebSite entity + SearchAction (sitelinks search box) → /recherche. Emitted on
/// the home so engines can wire a Myweli search box.
export function websiteJsonLd() {
  return {
    '@context': 'https://schema.org',
    '@type': 'WebSite',
    name: 'Myweli',
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
      addressCountry: 'CI',
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
      priceCurrency: 'XOF',
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
