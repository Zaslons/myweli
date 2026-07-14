import { describe, expect, it } from 'vitest';
import {
  buildLandingPath,
  categoryBySlug,
  categoryList,
  parseFlatLanding,
  siblingAreaLinks,
  siblingCategoryLinks,
} from '../lib/landing';
import { serviceList } from '../lib/service-landing';
import { fixtureTree } from './localities.test';

/// Multi-pays MP3 — the nested category taxonomy (/coiffure/abidjan/cocody)
/// + the legacy flat slugs as 308 redirect recognizers.
describe('nested landing paths', () => {
  it('builds the three levels', () => {
    expect(buildLandingPath('coiffure')).toBe('/coiffure');
    expect(buildLandingPath('coiffure', 'abidjan')).toBe('/coiffure/abidjan');
    expect(buildLandingPath('coiffure', 'abidjan', 'cocody')).toBe(
      '/coiffure/abidjan/cocody',
    );
  });

  it('categoryBySlug resolves roots; providers/services stay null', () => {
    expect(categoryBySlug('coiffure')?.apiKey).toBe('salon');
    expect(categoryBySlug('beaute-divine')).toBeNull();
    expect(categoryBySlug('tresses')).toBeNull();
  });
});

describe('parseFlatLanding (legacy redirect recognizer)', () => {
  it('maps known category-commune flat slugs to nested paths', () => {
    expect(parseFlatLanding('coiffure-cocody', fixtureTree)).toBe(
      '/coiffure/abidjan/cocody',
    );
    expect(parseFlatLanding('barbier-plateau', fixtureTree)).toBe(
      '/barbier/abidjan/plateau',
    );
    expect(parseFlatLanding('onglerie-adjame', fixtureTree)).toBe(
      '/onglerie/abidjan/adjame',
    );
    // A second-market area resolves to ITS city.
    expect(parseFlatLanding('coiffure-glass', fixtureTree)).toBe(
      '/coiffure/libreville/glass',
    );
  });

  it('returns null for unknown category or area', () => {
    expect(parseFlatLanding('beaute-divine', fixtureTree)).toBeNull();
    expect(parseFlatLanding('coiffure-nowhere', fixtureTree)).toBeNull();
    expect(parseFlatLanding('random', fixtureTree)).toBeNull();
  });
});

describe('sibling links', () => {
  const abidjan = fixtureTree.countries[0]!.cities[0]!;

  it('siblingAreaLinks: same root, the other areas of the city', () => {
    const links = siblingAreaLinks('coiffure', abidjan, 'cocody');
    expect(links).toHaveLength(10);
    expect(links[0]).toEqual({
      href: '/coiffure/abidjan/marcory',
      name: 'Marcory',
    });
    // No except → the city page's full area chip set.
    expect(siblingAreaLinks('coiffure', abidjan)).toHaveLength(11);
  });

  it('siblingCategoryLinks follow the page level', () => {
    expect(siblingCategoryLinks('coiffure')).toContainEqual({
      href: '/barbier',
      label: 'Barbier',
    });
    expect(
      siblingCategoryLinks('coiffure', 'abidjan', 'cocody'),
    ).toContainEqual({ href: '/spa/abidjan/cocody', label: 'Spa' });
    expect(siblingCategoryLinks('coiffure')).toHaveLength(4);
  });
});

describe('reserved slugs (the taxonomy roots stay routable)', () => {
  it('no root/city/area slug collides with an app route or `reserver`', () => {
    const appRoutes = [
      'reserver',
      'recherche',
      'connexion',
      'mon-compte',
      'pro',
      'api',
      'localities',
      'sitemap',
      'robots',
    ];
    const roots = [
      ...categoryList.map((c) => c.slug),
      ...serviceList.map((s) => s.slug),
    ];
    const geo = fixtureTree.countries.flatMap((country) =>
      country.cities.flatMap((city) => [
        city.slug,
        ...city.areas.map((a) => a.slug),
      ]),
    );
    for (const slug of [...roots, ...geo]) {
      expect(appRoutes).not.toContain(slug);
    }
    // And the backend reserves exactly these roots for provider slugs
    // (backend/lib/src/slug.dart reservedPublicSlugs) — pin the count so a
    // new taxonomy root is consciously added on both sides.
    expect(roots).toHaveLength(18);
  });
});
