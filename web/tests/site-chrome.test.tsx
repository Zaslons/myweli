import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const nav = vi.hoisted(() => ({ pathname: '/' }));
vi.mock('next/navigation', () => ({
  usePathname: () => nav.pathname,
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), refresh: vi.fn(), back: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
}));

import { Header } from '../components/Header';
import { SiteChrome } from '../components/SiteChrome';
import { SiteFooter } from '../components/SiteFooter';
import * as appStore from '../lib/appStore';
import { SITE_CONTAINER, SITE_EDGE } from '../lib/siteGrid';

/// docs/design/web-swiss-direction.md §3, §6.2, §7.8, §7.9.
const footerImage = (container: HTMLElement) => container.querySelector('footer img');
const wordmark = (container: HTMLElement) => container.querySelector('footer svg[data-wordmark]');

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  window.localStorage.clear();
  nav.pathname = '/';
});

describe('the footer keeps the large wordmark off the agenda', () => {
  it.each(['/', '/connexion', '/mon-compte', '/politique-confidentialite', '/support', '/coiffure/abidjan/cocody'])(
    '%s: the wordmark',
    (path) => {
      nav.pathname = path;
      const { container } = render(<SiteFooter />);
      expect(wordmark(container)).toBeInTheDocument();
      expect(footerImage(container)).toBeNull();
    },
  );

  // The prefix trap SiteChrome's comment records: `startsWith('/pro')` also
  // caught the public page for salons.
  it('/professionnels is public, whatever its first letters', () => {
    nav.pathname = '/professionnels';
    const { container } = render(<SiteFooter />);
    expect(wordmark(container)).toBeInTheDocument();
  });

  it.each(['/pro', '/pro/agenda', '/pro/connexion', '/pro/inscription'])('%s: the lockup, h-8', (path) => {
    nav.pathname = path;
    const { container } = render(<SiteFooter />);
    expect(footerImage(container)).toHaveAttribute('src', '/brand/myweli_lockup_horizontal_black.svg');
    expect(footerImage(container)).toHaveClass('h-8');
    expect(wordmark(container)).toBeNull();
  });

  it('is decorative in the footer: the header already names the page', () => {
    const { container, unmount } = render(<SiteFooter />);
    expect(wordmark(container)).toHaveAttribute('aria-hidden', 'true');
    unmount();
    nav.pathname = '/pro/agenda';
    const pro = render(<SiteFooter />);
    expect(footerImage(pro.container)).toHaveAttribute('alt', '');
  });
});

describe('the header', () => {
  it('is the real lockup at h-8, and it links home', () => {
    render(<Header />);
    const logo = screen.getByRole('img', { name: 'MyWeli' });
    expect(logo).toHaveAttribute('src', '/brand/myweli_lockup_horizontal_black.svg');
    expect(logo).toHaveClass('h-8');
    expect(screen.getByRole('link', { name: 'MyWeli — accueil' })).toHaveAttribute('href', '/');
  });

  it('sits on the shared container, and full width only when asked', () => {
    const { rerender, container } = render(<Header />);
    const nav_ = () => container.querySelector('nav') as HTMLElement;
    expect(nav_().className).toContain(SITE_CONTAINER);
    rerender(<Header fullWidth />);
    expect(nav_().className).toContain(SITE_EDGE);
    expect(nav_().className).not.toContain('max-w-screen-2xl');
  });
});

describe('SiteChrome gives /recherche a full-width header, and only it', () => {
  it.each([
    ['/recherche', false],
    ['/', true],
    ['/connexion', true],
  ])('%s', (path, bounded) => {
    nav.pathname = path;
    const { container } = render(<SiteChrome />);
    const hasBound = (container.querySelector('header nav') as HTMLElement).className.includes('max-w-screen-2xl');
    expect(hasBound).toBe(bounded);
  });
});

/// B0.19 (docs/design/web-pro-account-deletion.md §4.2, §7, §10 #12):
/// `/pro/suppression-compte` is a `/pro/…` path, so without its `PRO_AUTH`
/// entry `SiteChrome` renders NO header at all. It gets the Pro sign-in's: the
/// lockup home and « Espace pro », never the client's « Mon compte », and no
/// install banner (a person leaving is not pushed to install — WEB-SYSTEM §13).
describe('/pro/suppression-compte wears the Pro sign-in’s header', () => {
  beforeEach(() => {
    // A store link set, so a banner WOULD render on a consumer page.
    vi.spyOn(appStore, 'appStoreUrl').mockReturnValue('https://apps.apple.com/app/x');
  });

  it('the exact path: the banner landmark, the lockup home, « Espace pro », no « Mon compte », no install banner', () => {
    nav.pathname = '/pro/suppression-compte';
    const { container } = render(<SiteChrome />);
    const banner = screen.getByRole('banner');
    expect(banner.querySelector('a[aria-label="MyWeli — accueil"]')).toHaveAttribute('href', '/');
    expect(banner).toHaveTextContent('Espace pro');
    expect(screen.queryByRole('link', { name: 'Mon compte' })).toBeNull();
    expect(container.querySelector('aside')).toBeNull();
    expect(screen.queryByText(/téléchargez l’app MyWeli/)).toBeNull();
  });

  it.each(['/suppression-compte', '/', '/professionnels'])('%s keeps the consumer header', (path) => {
    nav.pathname = path;
    render(<SiteChrome />);
    expect(screen.getByRole('link', { name: 'Mon compte' })).toBeInTheDocument();
  });

  it.each(['/pro/suppression-compte/x', '/pro/suppression'])('%s is not the page: the dashboard rule (no header)', (path) => {
    nav.pathname = path;
    const { container } = render(<SiteChrome />);
    expect(container).toBeEmptyDOMElement();
  });
});

describe('the install banner starts on the same left edge as the logo', () => {
  beforeEach(() => {
    vi.spyOn(appStore, 'appStoreUrl').mockReturnValue('https://apps.apple.com/app/x');
  });

  it('bounded on a normal page, full width on /recherche', async () => {
    const { container, unmount } = render(<SiteChrome />);
    const inner = await screen.findByText(/téléchargez l’app MyWeli/);
    expect((inner.parentElement as HTMLElement).className).toContain(SITE_CONTAINER);
    expect(container.querySelector('aside')).toHaveClass('bg-primary');
    unmount();

    nav.pathname = '/recherche';
    render(<SiteChrome />);
    const wide = await screen.findByText(/téléchargez l’app MyWeli/);
    expect((wide.parentElement as HTMLElement).className).not.toContain('max-w-screen-2xl');
  });
});
