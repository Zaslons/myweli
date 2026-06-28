import { describe, expect, it } from 'vitest';
import {
  resolveCategorySlug,
  resolveCommune,
  resolveSearchHref,
} from '../lib/discovery';
import { serviceSlugForQuery } from '../lib/service-landing';

describe('discovery resolution', () => {
  it('resolves communes (accent/case-insensitive)', () => {
    expect(resolveCommune('cocody')).toBe('Cocody');
    expect(resolveCommune('Adjame')).toBe('Adjamé');
    expect(resolveCommune('nowhere')).toBeNull();
  });

  it('resolves category labels/slugs', () => {
    expect(resolveCategorySlug('Coiffure')).toBe('coiffure');
    expect(resolveCategorySlug('barbier')).toBe('barbier');
    expect(resolveCategorySlug('xyz')).toBeNull();
  });

  it('resolves service queries via keywords', () => {
    expect(serviceSlugForQuery('tresses')).toBe('tresses');
    expect(serviceSlugForQuery('box braids')).toBe('tresses');
    expect(serviceSlugForQuery('dégradé')).toBe('coupe-homme');
  });
});

describe('resolveSearchHref', () => {
  it('category + commune → category landing', () => {
    expect(resolveSearchHref('Coiffure', 'Cocody')).toBe('/coiffure-cocody');
  });

  it('service + commune → service landing', () => {
    expect(resolveSearchHref('tresses', 'Cocody')).toBe('/tresses-cocody');
  });

  it('unknown commune → /recherche with query', () => {
    expect(resolveSearchHref('coiffure', 'Mars')).toBe(
      '/recherche?q=coiffure&commune=Mars',
    );
  });

  it('free text → /recherche', () => {
    expect(resolveSearchHref('coupe afro stylée', '')).toBe(
      '/recherche?q=coupe+afro+styl%C3%A9e',
    );
  });

  it('empty → /recherche', () => {
    expect(resolveSearchHref('', '')).toBe('/recherche');
  });
});
