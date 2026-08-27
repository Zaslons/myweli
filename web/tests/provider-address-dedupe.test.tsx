import { cleanup, render, screen, within } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn(), refresh: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => '/beaute-divine',
}));

import { MapEmbed } from '../components/provider/MapEmbed';
import { ProviderView } from '../components/provider/ProviderView';
import { providerFixture } from './fixtures';

/// The address ↔ commune dedupe at its RENDER sites
/// (fix/address-commune-dedupe). The helpers are unit-tested in
/// address.test.ts; these pin the WIRING — an append restored at either site
/// re-prints « marcory, …, Marcory » while every helper test stays green.
const DUP = {
  ...providerFixture,
  address: 'marcory, Rue des Nguéssous 93',
  commune: 'Marcory',
  // No coords: MapEmbed renders its address-only branch (no
  // IntersectionObserver, no MapLibre) and ProviderView stays jsdom-safe.
  latitude: null,
  longitude: null,
};

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('the commune paints ONCE', () => {
  it('MapEmbed does not re-append a commune the address already says', () => {
    const { container } = render(
      <MapEmbed
        name={DUP.name}
        address={DUP.address}
        commune={DUP.commune}
        latitude={null}
        longitude={null}
      />,
    );
    const text = container.textContent ?? '';
    expect(text).toContain('marcory, Rue des Nguéssous 93');
    expect(text).not.toMatch(/Nguéssous 93, Marcory/i);
    // Control: a clean address still gets its commune appended.
    const clean = render(
      <MapEmbed
        name={DUP.name}
        address="Rue des Jardins"
        commune="Cocody"
        latitude={null}
        longitude={null}
      />,
    );
    expect(clean.container.textContent).toContain('Rue des Jardins, Cocody');
  });

  it('the FAQ answer — which ships into FAQPage JSON-LD — says it once', () => {
    // Before the dedupe this sentence duplicated TWICE: « … situé à Marcory,
    // marcory, Rue des Nguéssous 93, … ».
    vi.stubGlobal('fetch', vi.fn(async () => new Response('{}', { status: 404 })));
    const { container } = render(
      <ProviderView provider={DUP} slug="beaute-divine" />,
    );
    const faq = within(container).getByText(/est situé à/);
    const mentions = (faq.textContent ?? '').match(/marcory/gi) ?? [];
    expect(mentions).toHaveLength(1);
    expect(faq.textContent).toContain('marcory, Rue des Nguéssous 93');
  });
});
