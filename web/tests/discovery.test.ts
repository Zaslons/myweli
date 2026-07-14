import { describe, expect, it } from 'vitest';
import { emptyTree } from '../lib/api/localities';
import {
  resolveArea,
  resolveCategorySlug,
  resolveSearchHref,
} from '../lib/discovery';
import { serviceSlugForQuery } from '../lib/service-landing';
import { fixtureTree } from './localities.test';

describe('discovery resolution', () => {
  it('resolves areas against the tree (accent/case-insensitive)', () => {
    expect(resolveArea('cocody', fixtureTree)).toEqual({
      citySlug: 'abidjan',
      areaSlug: 'cocody',
      name: 'Cocody',
    });
    expect(resolveArea('Adjame', fixtureTree)?.areaSlug).toBe('adjame');
    expect(resolveArea('Port-Bouët', fixtureTree)?.areaSlug).toBe(
      'port-bouet',
    );
    // A second-market area carries ITS city.
    expect(resolveArea('Glass', fixtureTree)?.citySlug).toBe('libreville');
    expect(resolveArea('nowhere', fixtureTree)).toBeNull();
    expect(resolveArea('cocody', emptyTree)).toBeNull();
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

describe('resolveSearchHref (nested destinations)', () => {
  it('category + area → the nested category landing', () => {
    expect(resolveSearchHref('Coiffure', 'Cocody', fixtureTree)).toBe(
      '/coiffure/abidjan/cocody',
    );
  });

  it('service + area → the nested service landing', () => {
    expect(resolveSearchHref('tresses', 'Cocody', fixtureTree)).toBe(
      '/tresses/abidjan/cocody',
    );
  });

  it('unknown commune → /recherche with query', () => {
    expect(resolveSearchHref('coiffure', 'Mars', fixtureTree)).toBe(
      '/recherche?q=coiffure&commune=Mars',
    );
  });

  it('free text → /recherche', () => {
    expect(resolveSearchHref('coupe afro stylée', '', fixtureTree)).toBe(
      '/recherche?q=coupe+afro+styl%C3%A9e',
    );
  });

  it('empty → /recherche; an empty tree degrades to /recherche', () => {
    expect(resolveSearchHref('', '', fixtureTree)).toBe('/recherche');
    expect(resolveSearchHref('Coiffure', 'Cocody', emptyTree)).toBe(
      '/recherche?q=Coiffure&commune=Cocody',
    );
  });
});
