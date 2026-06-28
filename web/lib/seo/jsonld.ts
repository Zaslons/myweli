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
    logo: `${siteUrl}/logo.png`,
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
