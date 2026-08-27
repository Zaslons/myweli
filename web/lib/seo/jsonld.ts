import { timeOfDay } from '../time-of-day';
import type { Provider } from '../api/providers';
import { SOCIAL_PROFILES } from '../social';

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
    // Filled 2026-08-24, having been empty on purpose since 2026-08-20.
    //
    // `sameAs` is how a search engine learns that this site and a set of
    // social profiles are ONE entity — it is what makes "MyWeli" resolve to
    // us rather than to a similarly-named business, and most of how a
    // knowledge panel is earned. It is also the cheapest SEO there is.
    //
    // The bar the empty version set still stands: listing a URL that 404s, or
    // one we do not control, is worse than listing nothing, because it ties
    // the brand to something that is not us. `social.ts` records what was
    // checked and how. TikTok is not here because the account does not exist
    // yet — this list grows one verified profile at a time, never in advance.
    sameAs: SOCIAL_PROFILES.map((p) => p.url),
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

/// schema.org weekday names, indexed by the wire's `weeklySchedule` keys
/// ("0".."6" = Mon..Sun — the app/backend convention).
const SCHEMA_DAYS = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// `openingHoursSpecification` from the salon's availability — the spec's
/// long-missing half (web-m3-provider-page.md §"LocalBusiness"). One entry
/// per AVAILABLE range; `opens`/`closes` are bare `HH:mm` via [timeOfDay]
/// (the wire's date part is a carrier, and Google wants the time alone).
/// Empty when there is no availability — the caller omits the key then.
function openingHoursSpec(p: Provider) {
  const schedule = p.availability?.weeklySchedule;
  if (!schedule) return [];
  const spec = [];
  for (let day = 0; day < 7; day++) {
    for (const w of schedule[String(day)] ?? []) {
      if (w.isAvailable === false) continue;
      const opens = timeOfDay(w.startTime);
      const closes = timeOfDay(w.endTime);
      if (!opens || !closes) continue;
      spec.push({
        '@type': 'OpeningHoursSpecification',
        dayOfWeek: SCHEMA_DAYS[day],
        opens,
        closes,
      });
    }
  }
  return spec;
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
    ...(p.logoUrl ? { logo: p.logoUrl } : {}),
    telephone: p.phoneNumber,
    address: {
      '@type': 'PostalAddress',
      streetAddress: p.address,
      addressLocality: p.commune ?? p.city ?? undefined,
      // Multi-pays MP3: the salon's own market fields ('CI' = the
      // pre-backfill fallback only).
      addressCountry: p.countryCode ?? 'CI',
    },
    ...(openingHoursSpec(p).length
      ? { openingHoursSpecification: openingHoursSpec(p) }
      : {}),
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
