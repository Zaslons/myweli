import { describe, expect, it } from 'vitest';
import {
  breadcrumbJsonLd,
  faqJsonLd,
  localBusinessJsonLd,
} from '../lib/seo/jsonld';
import { providerFixture } from './fixtures';

describe('provider JSON-LD', () => {
  const ld = localBusinessJsonLd(providerFixture, 'https://myweli.ci/beaute-divine');

  it('maps a salon to a LocalBusiness with address + geo', () => {
    expect(ld['@type']).toBe('HairSalon');
    expect(ld.name).toBe('Beauté Divine');
    expect(ld.address['@type']).toBe('PostalAddress');
    expect(ld.address.addressCountry).toBe('CI');
    expect(ld.address.addressLocality).toBe('Cocody');
    expect(ld.geo).toMatchObject({ latitude: 5.35, longitude: -3.99 });
  });

  it('includes aggregateRating, reviews and offers', () => {
    expect(ld.aggregateRating).toMatchObject({ ratingValue: 4.8, reviewCount: 12 });
    expect(ld.review).toHaveLength(1);
    expect(ld.makesOffer).toHaveLength(1);
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
  });
});
