import { describe, expect, it } from 'vitest';
import {
  buildServiceLandingSlug,
  matchesService,
  parseServiceLanding,
} from '../lib/service-landing';

describe('service landing', () => {
  it('parses service-commune combos (incl. hyphenated services)', () => {
    expect(parseServiceLanding('tresses-cocody')).toMatchObject({
      serviceSlug: 'tresses',
      commune: 'Cocody',
    });
    expect(parseServiceLanding('coupe-homme-plateau')).toMatchObject({
      serviceSlug: 'coupe-homme',
      commune: 'Plateau',
    });
    expect(parseServiceLanding('manucure-marcory')).toMatchObject({
      serviceSlug: 'manucure',
      commune: 'Marcory',
    });
  });

  it('returns null for a category slug, unknown service, or unknown commune', () => {
    expect(parseServiceLanding('coiffure-cocody')).toBeNull(); // category, not service
    expect(parseServiceLanding('tresses-nowhere')).toBeNull();
    expect(parseServiceLanding('random')).toBeNull();
  });

  it('matches free-text service names (deaccented)', () => {
    expect(matchesService('Tresses africaines', 'tresses')).toBe(true);
    expect(matchesService('Manucure', 'manucure')).toBe(true);
    expect(matchesService('Dégradé homme', 'coupe-homme')).toBe(true);
    expect(matchesService('Massage relaxant', 'massage')).toBe(true);
    expect(matchesService('Coupe femme', 'tresses')).toBe(false);
  });

  it('builds slugs', () => {
    expect(buildServiceLandingSlug('tresses', 'Cocody')).toBe('tresses-cocody');
  });
});
