import { cleanup, render } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';
import type { Provider } from '../lib/api/providers';
import type { LocalityTree } from '../lib/localities';
import { resolveTaxonomyRoot } from '../lib/taxonomy';
import { TaxonomyLandingView } from '../components/landing/TaxonomyLandingView';
import { providerFixture } from './fixtures';

/// **The first card's photo is fetched first, on each landing level, and only that one**
/// (docs/design/web-swiss-cards.md §7, decision 6).
///
/// The e2e reads the real pages, but the stub shows one salon on `/coiffure` and on
/// `/coiffure/abidjan`, so « exactly one » cannot see a second there: with the prop on
/// every card of those two levels alone, it stayed green. Here each level has three.
const salons: Provider[] = ['a', 'b', 'c'].map((id) => ({
  ...providerFixture,
  id,
  slug: `salon-${id}`,
  name: `Salon ${id}`,
  imageUrls: [`https://cdn.example/${id}.jpg`],
  citySlug: 'abidjan',
  countryCode: 'CI',
  // A service `/tresses` matches, so the service root lists them as well.
  services: providerFixture.services?.map((service) => ({ ...service, name: 'Tresses africaines' })),
}));

vi.mock('../lib/api/providers', () => ({
  listProviders: async () => salons,
  listProvidersByCommune: async () => salons,
  searchProviders: async () => salons,
}));

const area = { id: 'marcory', slug: 'marcory', name: 'Marcory', labelKind: 'commune', lat: 5.28, lng: -4.05 };
const city = { id: 'abidjan', slug: 'abidjan', name: 'Abidjan', timezone: 'Africa/Abidjan', lat: 5.336, lng: -4.026, areas: [area] };
const tree = {
  countries: [{ code: 'CI', name: "Côte d'Ivoire", currency: 'XOF', phonePrefix: '+225', operators: [], cities: [city] }],
} as unknown as LocalityTree;

afterEach(cleanup);

describe.each([
  ['root', { level: 'root' as const }],
  ['city', { level: 'city' as const, city }],
  ['area', { level: 'area' as const, city, area }],
])('a landing at the %s level, with three salons', (_name, level) => {
  it.each(['coiffure', 'tresses'])('/%s: only the first photo is fetched first, the others stay lazy', async (slug) => {
    const root = resolveTaxonomyRoot(slug);
    if (!root) throw new Error(`no taxonomy root ${slug}`);
    const { container } = render(await TaxonomyLandingView({ ...level, root, tree } as Parameters<typeof TaxonomyLandingView>[0]));
    const photos = [...container.querySelectorAll<HTMLImageElement>('main img[data-initial]')];
    expect(photos.length, 'each salon’s photo, or this proves nothing').toBe(3);
    expect(photos.map((img) => img.getAttribute('fetchpriority'))).toEqual(['high', null, null]);
    expect(photos.map((img) => img.getAttribute('loading'))).toEqual([null, 'lazy', 'lazy']);
  });
});
