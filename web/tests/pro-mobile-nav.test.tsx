import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
const routerMock = { replace }; // STABLE — a fresh object each call churns the
// context's `probe` callback, which re-fetches on every render (an async loop
// that findBy/waitFor pumps to OOM). Mirrors pro-sidebar-switcher.test.tsx.
let pathname = '/pro';
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => pathname,
}));

import { ProMembershipProvider } from '../components/pro/ProMembershipContext';
import { ProShell } from '../components/pro/ProShell';

/// B0 — the pro dashboard's mobile nav (WEB-SYSTEM §9). The persistent sidebar
/// becomes an off-canvas drawer below `lg`; this covers the drawer's a11y
/// contract — the hamburger is a disclosure, and Escape / the ✕ close it,
/// locking body scroll while open.
///
/// `useIsDesktop` reads `matchMedia`, which jsdom doesn't implement, so we mock
/// it to report a PHONE. (Without the mock the hook stays on its desktop
/// default — which is exactly why the existing sidebar RTL test is untouched by
/// any of this.) All assertions are synchronous: `fireEvent` flushes React's
/// `act()`, so the state settles before the next line.

const OWNER = {
  account: { id: 'acc1', email: 'salon@example.com' },
  provider: { id: 'p1', name: 'Beauté Divine' },
  membership: { role: 'owner', capabilities: ['clients.view', 'profile.manage'] },
};

beforeEach(() => {
  vi.stubGlobal(
    'matchMedia',
    vi.fn((query: string) => ({
      matches: false, // a phone: below the lg breakpoint
      media: query,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
    })),
  );
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      if (url === '/api/pro/me') {
        return new Response(JSON.stringify(OWNER), { status: 200 });
      }
      if (url === '/api/pro/salons') {
        return new Response(
          JSON.stringify({
            items: [
              { salonId: 'p1', salonName: 'Beauté Divine', role: 'owner', salonStatus: 'active', verified: true },
            ],
            canAddSalon: false,
          }),
          { status: 200 },
        );
      }
      return new Response('{}', { status: 404 });
    }),
  );
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
  pathname = '/pro';
  document.body.style.overflow = '';
});

function host() {
  return render(
    <ProMembershipProvider>
      <ProShell>
        <p>Le contenu</p>
      </ProShell>
    </ProMembershipProvider>,
  );
}

describe('ProShell — the mobile nav drawer', () => {
  it('the hamburger is a disclosure: closed by default, opens the drawer', () => {
    host();
    const hamburger = screen.getByRole('button', { name: 'Ouvrir le menu' });
    expect(hamburger.getAttribute('aria-expanded')).toBe('false');
    expect(hamburger.getAttribute('aria-controls')).toBe('pro-sidebar-nav');

    fireEvent.click(hamburger);
    expect(hamburger.getAttribute('aria-expanded')).toBe('true');
  });

  it('Escape closes the drawer', () => {
    host();
    const hamburger = screen.getByRole('button', { name: 'Ouvrir le menu' });
    fireEvent.click(hamburger);
    expect(hamburger.getAttribute('aria-expanded')).toBe('true');

    fireEvent.keyDown(window, { key: 'Escape' });
    expect(hamburger.getAttribute('aria-expanded')).toBe('false');
  });

  it('the drawer ✕ closes it', () => {
    host();
    const hamburger = screen.getByRole('button', { name: 'Ouvrir le menu' });
    fireEvent.click(hamburger);

    fireEvent.click(screen.getByRole('button', { name: 'Fermer le menu' }));
    expect(hamburger.getAttribute('aria-expanded')).toBe('false');
  });

  it('opening locks body scroll; closing restores it', () => {
    host();
    const hamburger = screen.getByRole('button', { name: 'Ouvrir le menu' });

    fireEvent.click(hamburger);
    expect(document.body.style.overflow).toBe('hidden');

    fireEvent.keyDown(window, { key: 'Escape' });
    expect(document.body.style.overflow).toBe('');
  });

  it('the nav renders exactly ONCE — no duplicate links to trip the e2e', async () => {
    host();
    // « Profil » is visible to every role; there must be a single one — the whole
    // reason B0 repositions ONE DOM tree with CSS instead of rendering a mobile +
    // a desktop copy (which would break the strict e2e/RTL selectors). `findAll`
    // waits out the async membership load that swaps the skeleton for the nav.
    const profil = await screen.findAllByRole('link', { name: 'Profil' });
    expect(profil).toHaveLength(1);
  });
});
