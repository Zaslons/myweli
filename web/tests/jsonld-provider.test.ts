import { describe, expect, it } from 'vitest';
import {
  breadcrumbJsonLd,
  faqJsonLd,
  itemListJsonLd,
  localBusinessJsonLd,
} from '../lib/seo/jsonld';
import { providerFixture } from './fixtures';

describe('provider JSON-LD', () => {
  const ld = localBusinessJsonLd(providerFixture, 'https://myweli.ci/beaute-divine');

  it('streetAddress carries the STREET — the commune lives in addressLocality only', () => {
    // The owner's stored address began with the commune; repeating it inside
    // streetAddress is a structured-data error (fix/address-commune-dedupe).
    const dup = localBusinessJsonLd(
      { ...providerFixture, address: 'marcory, Rue des Nguéssous 93', commune: 'Marcory' },
      'https://myweli.ci/beaute-divine',
    );
    expect(dup.address.streetAddress).toBe('Rue des Nguéssous 93');
    expect(dup.address.addressLocality).toBe('Marcory');
    // The base fixture's address ends with its commune too — stripped.
    expect(ld.address.streetAddress).toBe('Rue des Jardins');
  });

  it('maps a salon to a LocalBusiness with address + geo', () => {
    expect(ld['@type']).toBe('HairSalon');
    expect(ld.name).toBe('Beauté Divine');
    expect(ld.address['@type']).toBe('PostalAddress');
    expect(ld.address.addressCountry).toBe('CI');
    expect(ld.address.addressLocality).toBe('Cocody');
    expect(ld.geo).toMatchObject({ latitude: 5.35, longitude: -3.99 });
  });

  it('LocalBusiness.logo appears only when the salon has one', () => {
    // salon-logo.md §5 — the SEO half of the logo render set.
    const branded = localBusinessJsonLd(
      { ...providerFixture, logoUrl: 'https://cdn.example/logo.jpg' },
      'https://myweli.ci/beaute-divine',
    );
    expect(branded.logo).toBe('https://cdn.example/logo.jpg');
    expect('logo' in ld).toBe(false);
  });

  it('openingHoursSpecification: available ranges only, bare HH:mm, real day names', () => {
    // The spec's long-missing half (web-m3-provider-page.md). The fixture:
    // Monday split (two ranges), Tuesday one UNAVAILABLE slot, rest closed.
    const spec = ld.openingHoursSpecification as {
      dayOfWeek: string;
      opens: string;
      closes: string;
    }[];
    expect(spec).toHaveLength(2);
    expect(spec[0]).toMatchObject({
      '@type': 'OpeningHoursSpecification',
      dayOfWeek: 'Monday',
      opens: '09:00',
      closes: '12:00',
    });
    expect(spec[1]).toMatchObject({ dayOfWeek: 'Monday', opens: '14:00' });
    // The unavailable Tuesday slot must NOT advertise the salon as open.
    expect(spec.some((s) => s.dayOfWeek === 'Tuesday')).toBe(false);
    // Bare times — the wire's carrier date must not leak into search.
    for (const s of spec) {
      expect(s.opens).toMatch(/^\d{2}:\d{2}$/);
      expect(s.closes).toMatch(/^\d{2}:\d{2}$/);
    }
  });

  it('no availability → the key is omitted entirely', () => {
    const bare = localBusinessJsonLd(
      { ...providerFixture, availability: undefined },
      'https://myweli.ci/beaute-divine',
    );
    expect('openingHoursSpecification' in bare).toBe(false);
  });

  it('includes aggregateRating, reviews and offers', () => {
    expect(ld.aggregateRating).toMatchObject({ ratingValue: 4.8, reviewCount: 12 });
    expect(ld.review).toHaveLength(1);
    expect(ld.makesOffer).toHaveLength(1);
    expect(ld.makesOffer[0].priceCurrency).toBe('XOF');
  });

  it("a foreign-market salon carries ITS currency + country (multi-pays MP3)", () => {
    const gabon = localBusinessJsonLd(
      { ...providerFixture, currency: 'XAF', countryCode: 'GA' },
      'https://myweli.ci/institut-belle-vue',
    );
    expect(gabon.makesOffer[0].priceCurrency).toBe('XAF');
    expect(gabon.address.addressCountry).toBe('GA');
    // Missing market fields (pre-backfill rows) keep the Wave-0 fallbacks.
    expect(ld.makesOffer[0].priceCurrency).toBe('XOF');
  });

  it('builds a FAQPage and a BreadcrumbList', () => {
    const faq = faqJsonLd([{ question: 'Q ?', answer: 'A.' }]);
    expect(faq['@type']).toBe('FAQPage');
    expect(faq.mainEntity[0]['@type']).toBe('Question');

    const crumbs = breadcrumbJsonLd([
      { name: 'Accueil', url: 'https://myweli.ci' },
      { name: 'Beauté Divine', url: 'https://myweli.ci/beaute-divine' },
    ]);
    expect(crumbs['@type']).toBe('BreadcrumbList');
    expect(crumbs.itemListElement[1].position).toBe(2);

    const list = itemListJsonLd([
      { name: 'A', url: 'https://x/a' },
      { name: 'B', url: 'https://x/b' },
    ]);
    expect(list['@type']).toBe('ItemList');
    expect(list.itemListElement[1]).toMatchObject({ position: 2, name: 'B' });
  });
});
