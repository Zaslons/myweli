import { describe, expect, it } from 'vitest';
import { buildLandingSlug, parseLandingSlug } from '../lib/landing';

describe('landing slugs', () => {
  it('parses known category-commune combos', () => {
    expect(parseLandingSlug('coiffure-cocody')).toMatchObject({
      apiKey: 'salon',
      label: 'Coiffure',
      commune: 'Cocody',
    });
    expect(parseLandingSlug('barbier-plateau')).toMatchObject({
      apiKey: 'barber',
      commune: 'Plateau',
    });
    expect(parseLandingSlug('onglerie-adjame')).toMatchObject({
      apiKey: 'nail',
      commune: 'Adjamé',
    });
  });

  it('returns null for unknown category or commune', () => {
    expect(parseLandingSlug('beaute-divine')).toBeNull(); // a provider slug
    expect(parseLandingSlug('coiffure-nowhere')).toBeNull();
    expect(parseLandingSlug('random')).toBeNull();
  });

  it('builds slugs (deaccented commune)', () => {
    expect(buildLandingSlug('coiffure', 'Cocody')).toBe('coiffure-cocody');
    expect(buildLandingSlug('barbier', 'Adjamé')).toBe('barbier-adjame');
  });
});
