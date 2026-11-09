import { act, cleanup, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn(), refresh: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => '/beaute-divine',
}));

import { ProviderHero } from '../components/provider/Hero';
import { FavoriteButton } from '../components/provider/FavoriteButton';
import { COVER_SIZES, ProviderView } from '../components/provider/ProviderView';
import type { Provider } from '../lib/api/providers';
import { providerFixture } from './fixtures';

/// The salon page's cover and its layout (docs/design/web-swiss-salon.md §1). What these
/// can hold without a browser: the attributes the cover is fetched with, the DOM order the
/// grid and the Tab key follow, the preview's disabled « Réserver », and the heart's focus
/// and toast. Every box and every scroll is tests/e2e/salon-page.spec.ts's.

/// No coordinates: MapEmbed renders its address-only branch, with no MapLibre, so the page
/// stays jsdom-safe (as provider-address-dedupe.test.tsx does).
const SALON: Provider = { ...providerFixture, latitude: null, longitude: null };

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

/// Signed out: the favourites read and the visits card are refused, as on a first visit.
function signedOut() {
  const fn = vi.fn(async () => new Response('{}', { status: 401 }));
  vi.stubGlobal('fetch', fn);
  return fn;
}

const page = (provider: Provider = SALON, preview = false) =>
  render(<ProviderView provider={provider} slug="beaute-divine" preview={preview} />);

const follows = (a: Node, b: Node) =>
  (a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0;

describe('the cover is fetched at its exact width, first (§1.9)', () => {
  it('its `sizes` is the page’s, its srcset is today’s eight widths from 640w, and it is a priority', () => {
    signedOut();
    page();
    const cover = screen.getByAltText(`Salon ${SALON.name}`);
    expect(cover.getAttribute('sizes')).toBe(COVER_SIZES);
    // Next 14 counts only a bare `vw` in `sizes`: with none, every width from 16w comes
    // back, and with a smallest of 60vw, 384w does. Both would be a page that asks a
    // phone for a smaller file than its screen.
    const widths = (cover.getAttribute('srcset') ?? '')
      .split(',')
      .map((candidate) => Number(candidate.trim().split(/\s+/)[1]?.replace(/w$/, '')));
    expect(widths).toEqual([640, 750, 828, 1080, 1200, 1920, 2048, 3840]);
    expect(cover).toHaveAttribute('fetchpriority', 'high');
    expect(cover).not.toHaveAttribute('loading', 'lazy');
  });

  it('held sideways at 2.5 dppx and up, below lg, it names a 2× slot: the denser clause first, and no bare `vw` (decision 106)', () => {
    // §1.9's one exception. The browser reads `sizes` part by part, at its top-level commas,
    // and the first match wins: swapped, 892×412 at 3.5× would match the 2.5 dppx clause and
    // ask for 3840w again. `calc(50vw)`, because a bare `50vw` would be Next's smallest counted
    // `vw` and add 384w. Without either clause a sideways 3× or 3.5× phone asks for 3840w.
    expect(COVER_SIZES.split(/,(?![^(]*\))/).map((part) => part.trim())).toEqual([
      '(min-width: 1536px) 984px',
      '(min-width: 1024px) calc(66.67vw - 40px)',
      '(orientation: landscape) and (min-resolution: 3.25dppx) calc(50vw)',
      '(orientation: landscape) and (min-resolution: 2.5dppx) 66.67vw',
      '100vw',
    ]);
  });
});

describe('the order the grid and the Tab key follow (§1.4)', () => {
  it('the <h1> comes before every <h2>, the panel’s « Réserver » before the heart, and the bar is `main`’s last child', () => {
    signedOut();
    const { container } = page();
    const h1 = screen.getByRole('heading', { level: 1 });
    const h2s = screen.getAllByRole('heading', { level: 2 });
    expect(h2s.length, 'the sections, or this proves nothing').toBeGreaterThan(3);
    for (const h2 of h2s) expect(follows(h1, h2), `« ${h2.textContent} » before the <h1>`).toBe(true);

    const panel = container.querySelector('aside');
    expect(panel, 'the booking panel').not.toBeNull();
    const panelCta = within(panel as HTMLElement).getByRole('link', { name: 'Réserver' });
    const heart = screen.getByRole('button', { name: /Ajouter aux favoris/ });
    expect(follows(panelCta, heart)).toBe(true);

    const main = container.querySelector('main')!;
    const bar = main.lastElementChild as HTMLElement;
    expect(within(bar).getByRole('link', { name: 'Réserver' })).toHaveAttribute(
      'href',
      '/beaute-divine/reserver',
    );
    expect(bar.textContent).toContain('À partir de');
  });

  it('with no photo there is no cover, the name stays in columns 9–12, and it still comes first', () => {
    signedOut();
    const { container } = page({ ...SALON, imageUrls: [] });
    expect(screen.queryByAltText(`Salon ${SALON.name}`)).toBeNull();
    expect(container.querySelector('.aspect-cover')).toBeNull();
    const h1 = screen.getByRole('heading', { level: 1 });
    // The rail: the name block's parent, which also holds the panel.
    const rail = h1.closest('header')!.parentElement!;
    expect(rail.querySelector('aside'), 'the rail holds the panel').not.toBeNull();
    expect(rail.className.split(' ')).toContain('lg:col-start-9');
    for (const h2 of screen.getAllByRole('heading', { level: 2 })) expect(follows(h1, h2)).toBe(true);
  });
});

describe('the owner’s preview books nothing (§1.4)', () => {
  it('the hero’s « Réserver » is a disabled button, not a link', () => {
    const { container } = render(<ProviderHero provider={SALON} preview />);
    const cta = screen.getByRole('button', { name: 'Réserver' });
    expect(cta).toBeDisabled();
    expect(cta).toHaveAttribute('title', 'Disponible après la mise en ligne');
    expect(container.querySelector('a[href$="/reserver"]')).toBeNull();
  });

  it('nowhere on the page is there a link to the booking: the hero, the panel and the bar', () => {
    signedOut();
    const { container } = page(SALON, true);
    expect(container.querySelector('a[href$="/reserver"]')).toBeNull();
    const ctas = screen.getAllByRole('button', { name: 'Réserver' });
    expect(ctas).toHaveLength(3);
    for (const cta of ctas) expect(cta).toBeDisabled();
  });
});

describe('the heart (§1.4)', () => {
  it('on load it leaves the focus where it is, so the page does not scroll to it', async () => {
    const fn = vi.fn(async () =>
      new Response(JSON.stringify({ favorites: [] }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      }),
    );
    vi.stubGlobal('fetch', fn);
    expect(document.activeElement).toBe(document.body);
    render(<FavoriteButton providerId={SALON.id} slug="beaute-divine" />);
    await waitFor(() => expect(fn).toHaveBeenCalledTimes(1));
    await act(async () => {});
    expect(screen.getByRole('button', { name: /Ajouter aux favoris/ })).not.toHaveFocus();
    expect(document.activeElement).toBe(document.body);
  });

  // In rem, as the bar's height is: the px lift (`bottom-xxxl pb-m`, « Carte »'s) left the pill
  // over the bar with the browser's text at double size (§1.4).
  it('its toast is lifted above the booking bar under `lg` in rem, and back at 24px from `lg`', () => {
    signedOut();
    render(<FavoriteButton providerId={SALON.id} slug="beaute-divine" />);
    const region = screen.getByRole('status').className.split(' ');
    expect(region).toContain('bottom-20');
    expect(region).toContain('lg:bottom-l');
    expect(region).not.toContain('bottom-xxxl');
  });
});
