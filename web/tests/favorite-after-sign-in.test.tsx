import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { StrictMode } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const push = vi.fn();
// Stable object: the load effects depend on [router].
const routerMock = { replace: vi.fn(), push, refresh: vi.fn(), back: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => '/beaute-divine',
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock('@sentry/nextjs', () => ({ captureMessage: vi.fn() }));
// The results map is Leaflet behind next/dynamic — out of this test's reach.
vi.mock('next/dynamic', () => ({ default: () => () => null }));
// The sign-in's own form is not what the reason line is about.
vi.mock('../components/auth/ConnexionClient', () => ({ ConnexionClient: () => null }));

import ConnexionPage from '../app/connexion/page';
import { RechercheClient } from '../components/discovery/RechercheClient';
import { FavoriteButton } from '../components/provider/FavoriteButton';
import {
  FAVORITE_AFTER_SIGN_IN_MAX_AGE_MS,
  signInForFavorite,
  takeFavoriteAfterSignIn,
} from '../lib/account/favorite-after-sign-in';
import type { Provider } from '../lib/api/providers';
import { signInReasonLine } from '../lib/auth/sign-in-reason';
import { emptyTree } from '../lib/localities';
import { providerFixture } from './fixtures';

/// docs/design/consumer-signin-push.md §14 (A3w, decision 205): a heart a
/// guest taps on the website is applied once they are back from the sign-in
/// it opened — the app's three outcomes — and `/connexion` says why it opened.

const STORAGE_KEY = 'myweli.favoriApresConnexion';
const REASON = 'Connectez-vous pour ajouter ce salon à vos favoris.';
const ADDED = 'Ajouté aux favoris';
const ALREADY = 'Déjà dans vos favoris';
const GENERIC = 'Une erreur est survenue. Réessayez.';
const NO_CONNECTION = 'Pas de connexion. Réessayez.';

const P1: Provider = providerFixture;
const P2: Provider = { ...providerFixture, id: 'p2', slug: 'salon-elegance', name: 'Salon Élégance' };

type Answer = 'throw' | { status: number; body?: unknown };

function mockFetch(answers: Record<string, Answer>) {
  const fn = vi.fn(async (url: string, init?: RequestInit) => {
    const path = String(url).split('?')[0];
    const a = answers[`${init?.method ?? 'GET'} ${path}`];
    if (a === 'throw') throw new TypeError('Failed to fetch');
    if (!a) return new Response('{}', { status: 404 });
    return new Response(a.status === 204 ? null : JSON.stringify(a.body ?? {}), {
      status: a.status,
    });
  });
  vi.stubGlobal('fetch', fn);
  const calls = (call: string) =>
    fn.mock.calls.filter(
      ([url, init]) => `${(init as RequestInit | undefined)?.method ?? 'GET'} ${String(url)}` === call,
    ).length;
  return { calls };
}

/// The page the person comes back to, with or without the marker.
function at(url: string) {
  window.history.replaceState(null, '', url);
}

function here() {
  return `${window.location.pathname}${window.location.search}`;
}

function stored(id: string, at: number = Date.now()) {
  window.sessionStorage.setItem(STORAGE_KEY, JSON.stringify({ id, at }));
}

function storedHeart(): { id: string; at: number } | null {
  const raw = window.sessionStorage.getItem(STORAGE_KEY);
  return raw ? JSON.parse(raw) : null;
}

/// The announcement: in the toast's polite live region.
async function expectSaid(sentence: string) {
  const said = await screen.findByText(sentence);
  expect(said.closest('[role="status"]')).toHaveAttribute('aria-live', 'polite');
}

/// Lets every pending answer and render land.
async function settle() {
  for (let i = 0; i < 5; i++) await act(async () => {});
}

beforeEach(() => {
  window.sessionStorage.clear();
  at('/');
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
  push.mockReset();
});

// --- the stored heart ---------------------------------------------------------

describe('the stored heart (lib/account/favorite-after-sign-in.ts)', () => {
  it('a guest’s heart is stored, and the sign-in carries the reason and the marker', () => {
    expect(signInForFavorite('p1', '/beaute-divine', 1000)).toBe(
      `/connexion?raison=favori&returnTo=${encodeURIComponent('/beaute-divine?suite=favori')}`,
    );
    expect(storedHeart()).toEqual({ id: 'p1', at: 1000 });
    // A page with its own query keeps it, the marker after it.
    expect(signInForFavorite('p2', '/recherche?q=tresses')).toBe(
      `/connexion?raison=favori&returnTo=${encodeURIComponent('/recherche?q=tresses&suite=favori')}`,
    );
    expect(storedHeart()?.id).toBe('p2');
  });

  it('back with the marker: the heart is taken once, the marker leaves the address, the rest stays', () => {
    stored('p1', 5000);
    at('/recherche?q=tresses&suite=favori&commune=cocody');
    expect(takeFavoriteAfterSignIn(6000)).toBe('p1');
    expect(here()).toBe('/recherche?q=tresses&commune=cocody');
    expect(storedHeart()).toBeNull();
    // Taken: a second answer finds nothing.
    at('/recherche?q=tresses&suite=favori');
    expect(takeFavoriteAfterSignIn(6000)).toBeNull();
  });

  it('a page whose only parameter was the marker has no « ? » left', () => {
    stored('p1');
    at('/beaute-divine?suite=favori');
    expect(takeFavoriteAfterSignIn()).toBe('p1');
    expect(here()).toBe('/beaute-divine');
  });

  it('without the marker nothing is taken: the heart waits for its own return', () => {
    stored('p1');
    at('/beaute-divine');
    expect(takeFavoriteAfterSignIn()).toBeNull();
    expect(storedHeart()?.id).toBe('p1');
    // Another value of the same parameter is not the marker either.
    at('/beaute-divine?suite=autre');
    expect(takeFavoriteAfterSignIn()).toBeNull();
    expect(storedHeart()?.id).toBe('p1');
    expect(here()).toBe('/beaute-divine?suite=autre');
  });

  it('the marker alone (a link) applies nothing, and is removed', () => {
    at('/beaute-divine?suite=favori');
    expect(takeFavoriteAfterSignIn()).toBeNull();
    expect(here()).toBe('/beaute-divine');
  });

  it('30 minutes old is still fresh; one millisecond more is not, and is forgotten', () => {
    stored('p1', 0);
    at('/beaute-divine?suite=favori');
    expect(takeFavoriteAfterSignIn(FAVORITE_AFTER_SIGN_IN_MAX_AGE_MS)).toBe('p1');

    stored('p1', 0);
    at('/beaute-divine?suite=favori');
    expect(takeFavoriteAfterSignIn(FAVORITE_AFTER_SIGN_IN_MAX_AGE_MS + 1)).toBeNull();
    expect(storedHeart()).toBeNull();
  });

  it('a heart from the future, or anything else stored, applies nothing', () => {
    for (const raw of [
      JSON.stringify({ id: 'p1', at: 10_000 }),
      'not json',
      'null',
      JSON.stringify({ id: '', at: 0 }),
      JSON.stringify({ id: 'p1' }),
      JSON.stringify({ id: 42, at: 0 }),
    ]) {
      window.sessionStorage.setItem(STORAGE_KEY, raw);
      at('/beaute-divine?suite=favori');
      expect(takeFavoriteAfterSignIn(5_000), raw).toBeNull();
    }
  });

  it('storage refused: the sign-in still opens; nothing is applied; the marker still leaves', () => {
    vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => {
      throw new DOMException('denied', 'SecurityError');
    });
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new DOMException('denied', 'SecurityError');
    });
    expect(signInForFavorite('p1', '/beaute-divine')).toContain('/connexion?raison=favori');
    at('/beaute-divine?suite=favori');
    expect(takeFavoriteAfterSignIn()).toBeNull();
    expect(here()).toBe('/beaute-divine');
  });
});

// --- the reason line ----------------------------------------------------------

describe('/connexion says why it opened', () => {
  it('maps the one known reason, and nothing else', () => {
    expect(signInReasonLine('favori')).toBe(REASON);
    for (const raw of [undefined, '', 'autre', 'toString', '__proto__', ['favori']]) {
      expect(signInReasonLine(raw as string | string[] | undefined)).toBeNull();
    }
  });

  it('the page shows it under its title — and only for that reason', () => {
    render(ConnexionPage({ searchParams: { raison: 'favori' } }));
    expect(screen.getByText(REASON)).toBeInTheDocument();
    cleanup();
    render(ConnexionPage({ searchParams: {} }));
    expect(screen.queryByText(REASON)).toBeNull();
    cleanup();
    render(ConnexionPage({ searchParams: { raison: '<b>autre</b>' } }));
    expect(screen.queryByText(REASON)).toBeNull();
    expect(screen.queryByText(/autre/)).toBeNull();
  });
});

// --- the salon page's heart ---------------------------------------------------

function renderSalon(strict = false) {
  const button = <FavoriteButton providerId="p1" slug="beaute-divine" />;
  return render(strict ? <StrictMode>{button}</StrictMode> : button);
}

describe('the salon page’s heart', () => {
  it('a guest’s tap opens the sign-in with the heart stored', async () => {
    mockFetch({
      'GET /api/me/favorites': { status: 401 },
      'POST /api/me/favorites/p1': { status: 401 },
    });
    renderSalon();
    await settle();
    fireEvent.click(screen.getByRole('button', { name: /Ajouter aux favoris/ }));
    await waitFor(() =>
      expect(push).toHaveBeenCalledWith(
        `/connexion?raison=favori&returnTo=${encodeURIComponent('/beaute-divine?suite=favori')}`,
      ),
    );
    expect(storedHeart()?.id).toBe('p1');
  });

  it('a removal that answers 401 opens the sign-in plainly, carrying nothing', async () => {
    mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [P1] } },
      'DELETE /api/me/favorites/p1': { status: 401 },
    });
    renderSalon();
    fireEvent.click(await screen.findByRole('button', { name: /Favori/, pressed: true }));
    await waitFor(() =>
      expect(push).toHaveBeenCalledWith('/connexion?returnTo=%2Fbeaute-divine'),
    );
    expect(storedHeart()).toBeNull();
  });

  it('back, signed in, not yet a favourite: added once, said with « Annuler », no focus moved', async () => {
    stored('p1');
    at('/beaute-divine?suite=favori');
    const { calls } = mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p1': { status: 204 },
    });
    renderSalon();
    await expectSaid(ADDED);
    expect(screen.getByRole('button', { name: 'Annuler' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Favori/ })).toHaveAttribute('aria-pressed', 'true');
    expect(calls('POST /api/me/favorites/p1')).toBe(1);
    expect(here()).toBe('/beaute-divine');
    expect(storedHeart()).toBeNull();
    await settle();
    expect(document.activeElement).toBe(document.body);
  });

  it('…and « Annuler » takes it back', async () => {
    stored('p1');
    at('/beaute-divine?suite=favori');
    const { calls } = mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p1': { status: 204 },
      'DELETE /api/me/favorites/p1': { status: 204 },
    });
    renderSalon();
    await expectSaid(ADDED);
    fireEvent.click(screen.getByRole('button', { name: 'Annuler' }));
    await waitFor(() =>
      expect(screen.getByRole('button', { name: /Ajouter aux favoris/ })).toHaveAttribute(
        'aria-pressed',
        'false',
      ),
    );
    expect(calls('DELETE /api/me/favorites/p1')).toBe(1);
  });

  it('back, already a favourite: nothing is sent, « Déjà dans vos favoris », the heart full', async () => {
    stored('p1');
    at('/beaute-divine?suite=favori');
    const { calls } = mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [P1] } },
      'POST /api/me/favorites/p1': { status: 204 },
      'DELETE /api/me/favorites/p1': { status: 204 },
    });
    renderSalon();
    await expectSaid(ALREADY);
    expect(screen.getByRole('button', { name: /Favori/ })).toHaveAttribute('aria-pressed', 'true');
    expect(calls('POST /api/me/favorites/p1')).toBe(0);
    expect(calls('DELETE /api/me/favorites/p1')).toBe(0);
    expect(screen.queryByRole('button', { name: 'Annuler' })).toBeNull();
  });

  for (const [label, read, sentence] of [
    ['the read answered 500', { status: 500 }, GENERIC],
    ['nothing answered the read', 'throw', NO_CONNECTION],
  ] as const) {
    it(`back, ${label}: its sentence under the button, nothing sent, the heart empty`, async () => {
      stored('p1');
      at('/beaute-divine?suite=favori');
      const { calls } = mockFetch({
        'GET /api/me/favorites': read,
        'POST /api/me/favorites/p1': { status: 204 },
      });
      renderSalon();
      expect(await screen.findByRole('alert')).toHaveTextContent(sentence);
      expect(calls('POST /api/me/favorites/p1')).toBe(0);
      expect(screen.getByRole('button', { name: /Ajouter aux favoris/ })).toHaveAttribute(
        'aria-pressed',
        'false',
      );
    });
  }

  it('back, the add refused: its sentence, the heart empty, nothing announced', async () => {
    stored('p1');
    at('/beaute-divine?suite=favori');
    mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p1': { status: 500 },
    });
    renderSalon();
    expect(await screen.findByRole('alert')).toHaveTextContent(GENERIC);
    expect(screen.queryByText(ADDED)).toBeNull();
    expect(screen.getByRole('button', { name: /Ajouter aux favoris/ })).toHaveAttribute(
      'aria-pressed',
      'false',
    );
  });

  it('back, the add answers 401 again: the sign-in opens again, the heart carried again', async () => {
    stored('p1');
    at('/beaute-divine?suite=favori');
    mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p1': { status: 401 },
    });
    renderSalon();
    await waitFor(() =>
      expect(push).toHaveBeenCalledWith(
        `/connexion?raison=favori&returnTo=${encodeURIComponent('/beaute-divine?suite=favori')}`,
      ),
    );
    expect(storedHeart()?.id).toBe('p1');
  });

  it('back, but no session after all (read 401): nothing sent, nothing said', async () => {
    stored('p1');
    at('/beaute-divine?suite=favori');
    const { calls } = mockFetch({ 'GET /api/me/favorites': { status: 401 } });
    renderSalon();
    await settle();
    expect(calls('POST /api/me/favorites/p1')).toBe(0);
    expect(screen.queryByRole('alert')).toBeNull();
    expect(screen.queryByText(ALREADY)).toBeNull();
    expect(here()).toBe('/beaute-divine');
  });

  for (const [label, setup] of [
    ['no marker (a later visit)', () => { stored('p1'); at('/beaute-divine'); }],
    ['another salon’s heart', () => { stored('p2'); at('/beaute-divine?suite=favori'); }],
    ['the marker alone (a link)', () => at('/beaute-divine?suite=favori')],
    ['a heart older than 30 minutes', () => {
      stored('p1', Date.now() - FAVORITE_AFTER_SIGN_IN_MAX_AGE_MS - 60_000);
      at('/beaute-divine?suite=favori');
    }],
  ] as const) {
    it(`CONTROL — ${label}: nothing is applied`, async () => {
      setup();
      const { calls } = mockFetch({
        'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
        'POST /api/me/favorites/p1': { status: 204 },
      });
      renderSalon();
      await settle();
      expect(calls('GET /api/me/favorites')).toBe(1);
      expect(calls('POST /api/me/favorites/p1')).toBe(0);
      expect(screen.queryByText(ADDED)).toBeNull();
    });
  }

  it('React’s development double-mount applies the heart once', async () => {
    stored('p1');
    at('/beaute-divine?suite=favori');
    const { calls } = mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p1': { status: 204 },
    });
    renderSalon(true);
    await expectSaid(ADDED);
    await settle();
    expect(calls('GET /api/me/favorites')).toBe(2);
    expect(calls('POST /api/me/favorites/p1')).toBe(1);
  });
});

// --- the search's hearts --------------------------------------------------------

function renderRecherche(results: Provider[] = [P1, P2], strict = false) {
  const page = (
    <RechercheClient
      title="Salons à Cocody"
      results={results}
      q="tresses"
      commune=""
      category=""
      sort="relevance"
      dispo={false}
      tree={emptyTree}
    />
  );
  return render(strict ? <StrictMode>{page}</StrictMode> : page);
}

async function heart(name: string) {
  const h = await screen.findByRole('button', { name });
  await waitFor(() => expect(h).toBeEnabled());
  return h;
}

describe('the search’s hearts', () => {
  it('a guest’s tap opens the sign-in with that card’s heart stored, back to this search', async () => {
    const assign = vi.fn();
    vi.stubGlobal('location', {
      ...window.location,
      assign,
      pathname: '/recherche',
      search: '?q=tresses',
    });
    const { calls } = mockFetch({ 'GET /api/me/favorites': { status: 401 } });
    renderRecherche();
    fireEvent.click(await heart('Ajouter Salon Élégance aux favoris'));
    await waitFor(() =>
      expect(assign).toHaveBeenCalledWith(
        `/connexion?raison=favori&returnTo=${encodeURIComponent('/recherche?q=tresses&suite=favori')}`,
      ),
    );
    expect(storedHeart()?.id).toBe('p2');
    expect(calls('POST /api/me/favorites/p2')).toBe(0);
  });

  it('a removal that answers 401 opens the sign-in plainly, carrying nothing', async () => {
    const assign = vi.fn();
    vi.stubGlobal('location', {
      ...window.location,
      assign,
      pathname: '/recherche',
      search: '?q=tresses',
    });
    mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [P1] } },
      'DELETE /api/me/favorites/p1': { status: 401 },
    });
    renderRecherche();
    fireEvent.click(await heart('Retirer Beauté Divine des favoris'));
    await waitFor(() =>
      expect(assign).toHaveBeenCalledWith(
        `/connexion?returnTo=${encodeURIComponent('/recherche?q=tresses')}`,
      ),
    );
    expect(storedHeart()).toBeNull();
  });

  it('back, signed in: that card’s salon is added once, said with « Annuler »; the search stays', async () => {
    stored('p2');
    at('/recherche?q=tresses&suite=favori');
    const { calls } = mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p2': { status: 204 },
    });
    renderRecherche();
    await expectSaid(ADDED);
    expect(screen.getByRole('button', { name: 'Annuler' })).toBeInTheDocument();
    expect(
      screen.getByRole('button', { name: 'Retirer Salon Élégance des favoris' }),
    ).toHaveAttribute('aria-pressed', 'true');
    expect(calls('POST /api/me/favorites/p2')).toBe(1);
    expect(calls('POST /api/me/favorites/p1')).toBe(0);
    expect(here()).toBe('/recherche?q=tresses');
  });

  it('back, already a favourite: nothing sent, « Déjà dans vos favoris »', async () => {
    stored('p1');
    at('/recherche?q=tresses&suite=favori');
    const { calls } = mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [P1] } },
      'POST /api/me/favorites/p1': { status: 204 },
      'DELETE /api/me/favorites/p1': { status: 204 },
    });
    renderRecherche();
    await expectSaid(ALREADY);
    expect(calls('POST /api/me/favorites/p1')).toBe(0);
    expect(calls('DELETE /api/me/favorites/p1')).toBe(0);
    expect(
      screen.getByRole('button', { name: 'Retirer Beauté Divine des favoris' }),
    ).toHaveAttribute('aria-pressed', 'true');
  });

  it('back, the read failed: the sentence under that card, nothing sent', async () => {
    stored('p2');
    at('/recherche?q=tresses&suite=favori');
    const { calls } = mockFetch({
      'GET /api/me/favorites': { status: 500 },
      'POST /api/me/favorites/p2': { status: 204 },
    });
    renderRecherche();
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent(GENERIC);
    // Under Salon Élégance's card — the heart's own card.
    expect(alert.parentElement).toHaveTextContent('Salon Élégance');
    expect(alert.parentElement).not.toHaveTextContent('Beauté Divine');
    expect(calls('POST /api/me/favorites/p2')).toBe(0);
  });

  it('back, the salon has left the results: still added; a refusal is said in the toast', async () => {
    stored('p9');
    at('/recherche?q=tresses&suite=favori');
    const { calls } = mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p9': { status: 500 },
    });
    renderRecherche();
    const said = await screen.findByText(GENERIC);
    expect(said.closest('[role="status"]')).not.toBeNull();
    expect(calls('POST /api/me/favorites/p9')).toBe(1);
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('back, but no session after all (read 401): nothing sent, nothing said', async () => {
    stored('p2');
    at('/recherche?q=tresses&suite=favori');
    const { calls } = mockFetch({ 'GET /api/me/favorites': { status: 401 } });
    renderRecherche();
    await heart('Ajouter Salon Élégance aux favoris');
    await settle();
    expect(calls('POST /api/me/favorites/p2')).toBe(0);
    expect(screen.queryByRole('alert')).toBeNull();
    expect(screen.queryByText(GENERIC)).toBeNull();
    expect(here()).toBe('/recherche?q=tresses');
  });

  it('CONTROL — no marker: nothing applied, the heart still stored', async () => {
    stored('p2');
    at('/recherche?q=tresses');
    const { calls } = mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p2': { status: 204 },
    });
    renderRecherche();
    await heart('Ajouter Salon Élégance aux favoris');
    await settle();
    expect(calls('POST /api/me/favorites/p2')).toBe(0);
    expect(storedHeart()?.id).toBe('p2');
  });

  it('React’s development double-mount applies the heart once', async () => {
    stored('p2');
    at('/recherche?q=tresses&suite=favori');
    const { calls } = mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p2': { status: 204 },
    });
    renderRecherche([P1, P2], true);
    await expectSaid(ADDED);
    await settle();
    expect(calls('POST /api/me/favorites/p2')).toBe(1);
  });
});
