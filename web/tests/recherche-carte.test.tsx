import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// The search's map is behind next/dynamic, out of this test's reach, and its search bar asks
// for a router.
vi.mock('next/dynamic', () => ({ default: () => () => null }));
vi.mock('next/navigation', () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), refresh: vi.fn(), back: vi.fn() }),
  usePathname: () => '/recherche',
  useSearchParams: () => new URLSearchParams(),
}));

import { RechercheClient } from '../components/discovery/RechercheClient';
import { CARD_SIZES } from '../components/provider/ProviderCard';
import { ProviderView } from '../components/provider/ProviderView';
import type { Provider } from '../lib/api/providers';
import { emptyTree } from '../lib/localities';
import { providerFixture } from './fixtures';

/// B11.5: where « Carte » stands decides what it can ride over, and the toast finds it by its
/// marker. jsdom has no layout, so these hold the wiring: the e2e holds the geometry.
const salon = (id: string): Provider => ({ ...providerFixture, id, slug: `salon-${id}`, name: `Salon ${id}` });
const page = (results: Provider[]) =>
  render(
    <RechercheClient
      title="Salons"
      results={results}
      q=""
      commune=""
      category=""
      sort="relevance"
      dispo={false}
      tree={emptyTree}
    />,
  );

beforeEach(() => {
  vi.stubGlobal('fetch', vi.fn(async () => new Response(null, { status: 401 })));
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe('« Carte » on /recherche', () => {
  it('with results it is the last child of the box that holds the rows, so it rides over the rows only', () => {
    const { container } = page([salon('a'), salon('b'), salon('c')]);
    const carte = screen.getByRole('button', { name: 'Carte' });
    expect(carte).toHaveAttribute('data-floating-control');
    const box = carte.parentElement!;
    expect(box.lastElementChild).toBe(carte);
    expect(box.querySelectorAll('h3'), 'the rows, or this proves nothing').toHaveLength(3);
    // Nothing above the list shares its box: the heading, the search, the filters, « N salons ».
    expect(box.contains(container.querySelector('h1'))).toBe(false);
    expect(box.contains(container.querySelector('form'))).toBe(false);
    expect(box.contains(screen.getByText(/Disponible aujourd/))).toBe(false);
  });

  it('with no result it stands after the empty state, outside its box', () => {
    page([]);
    const carte = screen.getByRole('button', { name: 'Carte' });
    const title = screen.getByText('Aucun salon trouvé');
    expect(title.compareDocumentPosition(carte) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
    expect(carte.parentElement!.contains(title)).toBe(false);
  });

  it('the press hands the focus to « Liste », which is marked too, and back to « Carte »', () => {
    page([salon('a')]);
    const carte = screen.getByRole('button', { name: 'Carte' });
    carte.focus();
    act(() => {
      fireEvent.click(carte);
    });
    const liste = screen.getByRole('button', { name: 'Liste' });
    expect(liste).toHaveFocus();
    expect(liste).toHaveAttribute('data-floating-control');
    act(() => {
      fireEvent.click(liste);
    });
    expect(screen.getByRole('button', { name: 'Carte' })).toHaveFocus();
  });

  it('a press from elsewhere (a click that does not focus, as in Safari) takes no focus', () => {
    page([salon('a')]);
    act(() => {
      fireEvent.click(screen.getByRole('button', { name: 'Carte' }));
    });
    expect(screen.getByRole('button', { name: 'Liste' })).not.toHaveFocus();
  });

  it('from md in a landscape window the map stands beside the list, so « Carte » is not shown', () => {
    page([salon('a')]);
    const carte = screen.getByRole('button', { name: 'Carte' });
    expect(carte.className.split(' ')).toEqual(expect.arrayContaining(['md:landscape:hidden', 'lg:hidden']));
    // The rows' photos are fetched at the split view's width there too.
    expect(CARD_SIZES.row).toContain('(min-width: 768px) and (orientation: landscape) 18vw');
  });

  it('from md in a landscape window both columns show: the grid, the map, its hidden title and the list', () => {
    const { container } = page([salon('a')]);
    const classes = (el: Element | null | undefined) => (el?.className ?? '').split(' ');
    // The map column holds the second h1, the screen-reader one for the « Carte » view.
    const h1s = container.querySelectorAll('h1');
    expect(h1s, 'the list heading and the map view heading').toHaveLength(2);
    const mapTitle = h1s[1];
    const mapColumn = mapTitle.parentElement;
    const grid = mapColumn?.parentElement;
    expect(classes(grid)).toEqual(expect.arrayContaining(['md:landscape:grid', 'lg:grid']));
    // Shown beside the list in a landscape window from md, as from lg; hidden on a phone held upright.
    expect(classes(mapColumn)).toEqual(expect.arrayContaining(['hidden', 'md:landscape:block', 'lg:block']));
    // There the list's h1 shows too, so the map's own stays out of the page: one h1.
    expect(classes(mapTitle)).toEqual(expect.arrayContaining(['sr-only', 'md:landscape:hidden', 'lg:hidden']));
    // The « Carte » view hides the list on a phone only: in a landscape window from md it stays.
    act(() => {
      fireEvent.click(screen.getByRole('button', { name: 'Carte' }));
    });
    const listColumn = container.querySelector('h1')?.parentElement;
    expect(classes(listColumn)).toEqual(expect.arrayContaining(['hidden', 'md:landscape:block', 'lg:block']));
  });
});

describe('the salon page', () => {
  it('its booking bar is the one floating control the toast clears', () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response('{}', { status: 404 })));
    // No coords: the map's address-only branch, so no IntersectionObserver (jsdom has none).
    const { container } = render(
      <ProviderView provider={{ ...providerFixture, latitude: null, longitude: null }} slug="beaute-divine" />,
    );
    const marked = container.querySelectorAll('[data-floating-control]');
    expect(marked).toHaveLength(1);
    expect(marked[0].textContent).toMatch(/Réserver/);
  });
});
