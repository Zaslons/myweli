import { cleanup, render } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

// The search's map is Leaflet behind next/dynamic, out of this test's reach, and its search
// bar asks for a router.
vi.mock('next/dynamic', () => ({ default: () => () => null }));
vi.mock('next/navigation', () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), refresh: vi.fn(), back: vi.fn() }),
  usePathname: () => '/recherche',
  useSearchParams: () => new URLSearchParams(),
}));

import type { Provider } from '../lib/api/providers';
import { emptyTree, type LocalityTree } from '../lib/localities';
import { resolveTaxonomyRoot } from '../lib/taxonomy';
import { RechercheClient } from '../components/discovery/RechercheClient';
import { TaxonomyLandingView } from '../components/landing/TaxonomyLandingView';
import { firstPhotoIndex, ProviderCard } from '../components/provider/ProviderCard';
import { providerFixture } from './fixtures';

/// **The first photo is fetched first, on each landing level and on `/recherche`, and only
/// that one** (docs/design/web-swiss-cards.md §7, decision 6). The first photo, not the first
/// card: a logo or a letter before it does not take it, and a list with no photo has none.
///
/// The e2e reads the real pages, but the stub shows one salon on `/coiffure` and on
/// `/coiffure/abidjan`, so « exactly one » cannot see a second there: with the prop on
/// every card of those two levels alone, it stayed green. Here each level has several.
const salon = (id: string, media: Partial<Provider>): Provider => ({
  ...providerFixture,
  id,
  slug: `salon-${id}`,
  name: `Salon ${id}`,
  imageUrls: [],
  logoUrl: null,
  citySlug: 'abidjan',
  countryCode: 'CI',
  // A service `/tresses` matches, so the service root lists them as well.
  services: providerFixture.services?.map((service) => ({ ...service, name: 'Tresses africaines' })),
  ...media,
});
const photo = (id: string) => salon(id, { imageUrls: [`https://cdn.example/${id}.jpg`] });
const logo = (id: string) => salon(id, { logoUrl: `https://cdn.example/${id}-logo.png` });
const letter = (id: string) => salon(id, {});

/// `want` is the salon holding the prop, or null when none should.
const LISTS: { title: string; list: Provider[]; want: string | null; index: number }[] = [
  { title: 'a photo first', list: [photo('a'), photo('b'), photo('c')], want: 'a', index: 0 },
  { title: 'a logo first, then a photo', list: [logo('a'), photo('b'), photo('c')], want: 'b', index: 1 },
  { title: 'a letter first, then a photo', list: [letter('a'), photo('b'), photo('c')], want: 'b', index: 1 },
  { title: 'a logo and a letter, then a photo', list: [logo('a'), letter('b'), photo('c')], want: 'c', index: 2 },
  { title: 'no photo at all', list: [logo('a'), letter('b'), logo('c')], want: null, index: -1 },
  {
    title: 'a first image that is not https',
    list: [salon('a', { imageUrls: ['asset:assets/a.png'] }), photo('b')],
    want: 'b',
    index: 1,
  },
  { title: 'an empty first image', list: [salon('a', { imageUrls: [''] }), photo('b')], want: 'b', index: 1 },
  {
    title: 'a favourite’s gallery that never came',
    list: [salon('a', { imageUrls: undefined }), photo('b')],
    want: 'b',
    index: 1,
  },
];

let salons: Provider[] = [];
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

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

/// Who holds the prop: the card's own photo with a high fetch priority, and nothing lazy there.
const holders = (container: HTMLElement) => [...container.querySelectorAll<HTMLImageElement>('img[fetchpriority="high"]')];

const expectHolder = (container: HTMLElement, want: string | null) => {
  const held = holders(container);
  expect(held.map((img) => img.getAttribute('alt'))).toEqual(want ? [`Salon ${want}`] : []);
  // Every other picture stays lazy, the logos included.
  const others = [...container.querySelectorAll('img')].filter((img) => !held.includes(img));
  expect(others.every((img) => img.getAttribute('loading') === 'lazy')).toBe(true);
  expect(held.every((img) => !img.hasAttribute('loading'))).toBe(true);
};

describe.each([
  ['root', { level: 'root' as const }],
  ['city', { level: 'city' as const, city }],
  ['area', { level: 'area' as const, city, area }],
])('a landing at the %s level', (_name, level) => {
  it.each(['coiffure', 'tresses'])('/%s, with three photos: only the first is fetched first, the others stay lazy', async (slug) => {
    salons = [photo('a'), photo('b'), photo('c')];
    const root = resolveTaxonomyRoot(slug);
    if (!root) throw new Error(`no taxonomy root ${slug}`);
    const { container } = render(await TaxonomyLandingView({ ...level, root, tree } as Parameters<typeof TaxonomyLandingView>[0]));
    const photos = [...container.querySelectorAll<HTMLImageElement>('main img[data-initial]')];
    expect(photos.length, 'each salon’s photo, or this proves nothing').toBe(3);
    expect(photos.map((img) => img.getAttribute('fetchpriority'))).toEqual(['high', null, null]);
    expect(photos.map((img) => img.getAttribute('loading'))).toEqual([null, 'lazy', 'lazy']);
  });

  it.each(LISTS)('$title', async ({ list, want }) => {
    salons = list;
    const root = resolveTaxonomyRoot('coiffure');
    if (!root) throw new Error('no taxonomy root coiffure');
    const { container } = render(await TaxonomyLandingView({ ...level, root, tree } as Parameters<typeof TaxonomyLandingView>[0]));
    expect(container.querySelectorAll('main li h3').length, 'the list, or this proves nothing').toBe(list.length);
    expectHolder(container, want);
  });
});

describe('/recherche', () => {
  it.each(LISTS)('$title', ({ list, want }) => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response(null, { status: 401 })));
    const { container } = render(
      <RechercheClient
        title="Salons"
        results={list}
        q=""
        commune=""
        category=""
        sort="relevance"
        dispo={false}
        tree={emptyTree}
      />,
    );
    expect(container.querySelectorAll('h3').length, 'the list, or this proves nothing').toBe(list.length);
    expectHolder(container, want);
  });
});

describe('firstPhotoIndex', () => {
  it.each(LISTS)('$title', ({ list, index }) => {
    expect(firstPhotoIndex(list)).toBe(index);
  });

  it('an empty list has none', () => {
    expect(firstPhotoIndex([])).toBe(-1);
  });

  // The rule is the card's own: what the helper calls a photo is what the card draws as one.
  it('it agrees with the card on every salon above', () => {
    for (const provider of LISTS.flatMap(({ list }) => list)) {
      const { container, unmount } = render(<ProviderCard provider={provider} />);
      expect(container.querySelector('img[data-initial]') !== null, provider.id).toBe(firstPhotoIndex([provider]) === 0);
      unmount();
    }
  });
});
