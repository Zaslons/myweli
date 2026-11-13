import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

// Stable object: the preview's load depends on [router] — a new router per
// render would reload it for ever.
const routerMock = { replace: vi.fn(), push: vi.fn(), back: vi.fn(), prefetch: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => '/pro/apercu',
  useSearchParams: () => new URLSearchParams(),
}));

import { SalonPreviewClient } from '../components/pro/SalonPreviewClient';
import { providerFixture } from './fixtures';

/// « Aperçu de ma page »'s banner (owner, 2026-11-13 —
/// docs/design/web-salon-validation.md §4.4): the preview reads /me itself
/// (outside the dashboard shell) and names the validation's state; a server
/// before B0.18 keeps today's sentence. The sentences are pinned in
/// salon-validation.test.ts; here, that the page reads `validation` from /me.

function me(status: string, validation?: unknown) {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) =>
      String(url) === '/api/pro/me'
        ? new Response(
            JSON.stringify({
              account: { id: 'a', businessName: 'Salon Awa', phoneNumber: '+225' },
              // No coords: the map's address-only branch (jsdom has no
              // IntersectionObserver), as provider-address-dedupe does.
              provider: { ...providerFixture, latitude: null, longitude: null, status },
              membership: { role: 'owner', capabilities: ['salon.publish'] },
              ...(validation === undefined ? {} : { validation }),
            }),
            { status: 200 },
          )
        : new Response('{}', { status: 404 }),
    ),
  );
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

const banner = async () =>
  (await screen.findByRole('complementary', { name: 'Aperçu du salon' })).textContent;

describe('SalonPreviewClient — the banner follows the validation', () => {
  it('pending (new server)', async () => {
    me('draft', { state: 'pending', wentLive: false });
    render(<SalonPreviewClient />);
    expect(await banner()).toContain(
      'Aperçu — votre salon est en cours de validation. Voici ce que verront vos clients.',
    );
  });

  it('refused for good (new server): no promise of clients', async () => {
    me('draft', { state: 'refused', wentLive: false, refusal: { code: 'test_salon', final: true } });
    render(<SalonPreviewClient />);
    const text = await banner();
    expect(text).toContain('Aperçu — la mise en ligne de votre salon a été refusée.');
    expect(text).not.toContain('Voici ce que verront vos clients');
  });

  it('suspended (new server): §6.1’s sentence', async () => {
    me('suspended', null);
    render(<SalonPreviewClient />);
    expect(await banner()).toContain('Votre salon est suspendu. Contactez MyWeli pour en savoir plus.');
  });

  it('a server before B0.18, draft: today’s sentence', async () => {
    me('draft');
    render(<SalonPreviewClient />);
    expect(await banner()).toContain(
      'Aperçu — votre salon n’est pas encore en ligne. Voici ce que verront vos clients.',
    );
  });

  it('a server before B0.18, suspended: today’s sentence', async () => {
    me('suspended');
    render(<SalonPreviewClient />);
    expect(await banner()).toContain(
      'Votre salon est suspendu. Contactez MyWeli pour le réactiver — vos rendez-vous sont intacts.',
    );
  });
});
