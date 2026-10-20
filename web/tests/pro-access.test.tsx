import { cleanup, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

let pathname = '/';
const replace = vi.fn();
const routerMock = { replace, push: vi.fn() };
vi.mock('next/navigation', () => ({
  usePathname: () => pathname,
  useRouter: () => routerMock,
  useSearchParams: () => ({ get: () => null }),
}));

import { LegalConsentText } from '../components/LegalConsentText';
import { Header } from '../components/Header';
import { ProBand } from '../components/home/ProBand';
import { SiteChrome } from '../components/SiteChrome';
import { SiteFooter } from '../components/SiteFooter';
import { LoginOptions } from '../components/auth/LoginOptions';
import { ProConnexionClient } from '../components/pro/ProConnexionClient';
import { ProLoginOptions } from '../components/pro/ProLoginOptions';
import { ProRegisterClient } from '../components/pro/ProRegisterClient';

/// A salon finds and opens its Espace Pro (docs/design/web-pro-access.md):
/// the four doors (§3), the Pro sign-in pages that lead back to the site
/// (P4), and the consent the law asks for before an account exists (§5).

let meStatus = 401;

beforeEach(() => {
  pathname = '/';
  meStatus = 401;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      const u = String(url);
      if (u === '/api/pro/me') {
        return new Response(
          JSON.stringify(
            meStatus === 200
              ? { account: { id: 'a' }, provider: { id: 'p1', name: 'Beauté Divine' } }
              : { error: 'unauthorized' },
          ),
          { status: meStatus },
        );
      }
      if (u.startsWith('/api/localities')) {
        return new Response(JSON.stringify({ countries: [] }), { status: 200 });
      }
      return new Response('{}', { status: 401 });
    }),
  );
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
});

const consentText = (lead: string) =>
  `${lead}, vous acceptez nos Conditions d’utilisation et notre Politique de confidentialité.`;

describe('P1 — the header door', () => {
  it('« Espace pro » leads to the salons page', () => {
    render(<Header />);
    expect(screen.getByRole('link', { name: 'Espace pro' })).toHaveAttribute(
      'href',
      '/professionnels',
    );
  });
});

describe('the chrome, by route', () => {
  it('the public header shows on /professionnels (a /pro prefix test used to hide it)', () => {
    pathname = '/professionnels';
    render(<SiteChrome />);
    expect(screen.getByRole('link', { name: 'Mon compte' })).toBeInTheDocument();
  });

  it('the dashboard keeps its own shell — no public header on /pro or /pro/…', () => {
    for (const p of ['/pro', '/pro/clients', '/pro/notifications']) {
      pathname = p;
      const { container } = render(<SiteChrome />);
      expect(container).toBeEmptyDOMElement();
      cleanup();
    }
  });

  it('P4 — the Pro sign-in pages lead back to the site, without the client’s account', () => {
    for (const p of ['/pro/connexion', '/pro/inscription']) {
      pathname = p;
      render(<SiteChrome />);
      const banner = screen.getByRole('banner');
      expect(within(banner).getByRole('link', { name: 'MyWeli — accueil' })).toHaveAttribute(
        'href',
        '/',
      );
      expect(within(banner).getByText('Espace pro')).toBeInTheDocument();
      expect(within(banner).queryByRole('link', { name: 'Mon compte' })).toBeNull();
      cleanup();
    }
  });
});

describe('P2 — the footer group', () => {
  it('« Professionnels »: the salons page, sign-up, sign-in', () => {
    render(<SiteFooter />);
    const nav = screen.getByRole('navigation', { name: 'Professionnels' });
    const links = within(nav).getAllByRole('link');
    expect(links.map((l) => [l.textContent, l.getAttribute('href')])).toEqual([
      ['MyWeli Pro pour les salons', '/professionnels'],
      ['Inscrire mon salon', '/pro/inscription'],
      ['Connexion Espace pro', '/pro/connexion'],
    ]);
  });
});

describe('P3 — the home band', () => {
  it('asks the salon, says what it gets, and leads to the salons page', () => {
    render(<ProBand />);
    expect(screen.getByRole('heading', { level: 2, name: 'Vous êtes un salon ?' })).toBeInTheDocument();
    expect(
      screen.getByText(
        'Recevez vos réservations en ligne, 24 h/24, et gérez agenda, équipe et clientèle au même endroit.',
      ),
    ).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Découvrir MyWeli Pro' })).toHaveAttribute(
      'href',
      '/professionnels',
    );
  });
});

describe('§5 — consent before an account exists', () => {
  it('the component links both documents', () => {
    render(<LegalConsentText lead="En continuant" />);
    expect(screen.getByText((_, el) => el?.tagName === 'P' && el.textContent === consentText('En continuant'))).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Conditions d’utilisation' })).toHaveAttribute('href', '/cgu');
    expect(screen.getByRole('link', { name: 'Politique de confidentialité' })).toHaveAttribute(
      'href',
      '/politique-confidentialite',
    );
  });

  it('Pro sign-up: « En créant votre compte professionnel, … »', () => {
    render(<ProRegisterClient />);
    expect(
      screen.getByText((_, el) => el?.tagName === 'P' && el.textContent === consentText('En créant votre compte professionnel')),
    ).toBeInTheDocument();
  });

  it('Pro sign-in: « En continuant, … »', () => {
    render(<ProLoginOptions onSuccess={() => {}} />);
    expect(
      screen.getByText((_, el) => el?.tagName === 'P' && el.textContent === consentText('En continuant')),
    ).toBeInTheDocument();
  });

  it('client sign-in: the same sentence, now with its links', () => {
    render(<LoginOptions onSuccess={() => {}} />);
    expect(
      screen.getByText((_, el) => el?.tagName === 'P' && el.textContent === consentText('En continuant')),
    ).toBeInTheDocument();
    expect(screen.queryByText('En continuant, vous acceptez nos conditions d’utilisation.')).toBeNull();
  });
});

describe('§7 — a signed-in salon is not asked to sign in again', () => {
  it('a live Pro session on /pro/connexion goes straight to the dashboard', async () => {
    meStatus = 200;
    render(<ProConnexionClient />);
    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro'));
  });

  it('no session → the login stays', async () => {
    render(<ProConnexionClient />);
    expect(await screen.findByLabelText('Votre e-mail')).toBeInTheDocument();
    await new Promise((r) => setTimeout(r, 20));
    expect(replace).not.toHaveBeenCalled();
  });
});
