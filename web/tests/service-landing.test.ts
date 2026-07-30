import { describe, expect, it } from 'vitest';
import {
  buildServicePath,
  matchesService,
  parseFlatServiceLanding,
  serviceBySlug,
  siblingServiceLinks,
} from '../lib/service-landing';
import { fixtureTree } from './localities.test';

/// Multi-pays MP3 — the nested service taxonomy (/tresses/abidjan/cocody).
describe('service landing', () => {
  it('serviceBySlug resolves roots (incl. hyphenated); categories stay null', () => {
    expect(serviceBySlug('tresses')?.label).toBe('Tresses & nattes');
    expect(serviceBySlug('coupe-homme')?.label).toBe('Coupe homme & dégradé');
    expect(serviceBySlug('coiffure')).toBeNull();
  });

  it('builds the three levels', () => {
    expect(buildServicePath('tresses')).toBe('/tresses');
    expect(buildServicePath('tresses', 'abidjan')).toBe('/tresses/abidjan');
    expect(buildServicePath('coupe-homme', 'abidjan', 'plateau')).toBe(
      '/coupe-homme/abidjan/plateau',
    );
  });

  it('parseFlatServiceLanding maps legacy combos (incl. hyphenated services)', () => {
    expect(parseFlatServiceLanding('tresses-cocody', fixtureTree)).toBe(
      '/tresses/abidjan/cocody',
    );
    expect(parseFlatServiceLanding('coupe-homme-plateau', fixtureTree)).toBe(
      '/coupe-homme/abidjan/plateau',
    );
    expect(parseFlatServiceLanding('manucure-marcory', fixtureTree)).toBe(
      '/manucure/abidjan/marcory',
    );
  });

  it('returns null for a category slug, unknown service, or unknown area', () => {
    expect(parseFlatServiceLanding('coiffure-cocody', fixtureTree)).toBeNull();
    expect(parseFlatServiceLanding('tresses-nowhere', fixtureTree)).toBeNull();
    expect(parseFlatServiceLanding('random', fixtureTree)).toBeNull();
  });

  it('matches free-text service names (deaccented)', () => {
    expect(matchesService('Tresses africaines', 'tresses')).toBe(true);
    expect(matchesService('Manucure', 'manucure')).toBe(true);
    expect(matchesService('Dégradé homme', 'coupe-homme')).toBe(true);
    expect(matchesService('Massage relaxant', 'massage')).toBe(true);
    expect(matchesService('Coupe femme', 'tresses')).toBe(false);
  });

  it('sibling service links follow the page level', () => {
    expect(siblingServiceLinks('tresses')).toHaveLength(12);
    expect(
      siblingServiceLinks('tresses', 'abidjan', 'cocody'),
    ).toContainEqual({ href: '/tissage/abidjan/cocody', label: 'Tissage' });
  });
});
