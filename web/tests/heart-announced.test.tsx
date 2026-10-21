import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
const push = vi.fn();
// Stable object: the load effects depend on [router].
const routerMock = { replace, push, refresh: vi.fn(), back: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => '/mon-compte',
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock('@sentry/nextjs', () => ({ captureMessage: vi.fn() }));
// The results map is Leaflet behind next/dynamic — out of this test's reach.
vi.mock('next/dynamic', () => ({ default: () => () => null }));

import { AccountClient } from '../components/account/AccountClient';
import { RechercheClient } from '../components/discovery/RechercheClient';
import { FavoriteButton } from '../components/provider/FavoriteButton';
import type { Provider } from '../lib/api/providers';
import { emptyTree } from '../lib/localities';
import { providerFixture } from './fixtures';

/// docs/design/web-client-polish.md §2.2 and §2.4 (B5.2, B5.4; decision 16,
/// Q4). The search's ♥ when the favourites read FAILED sent a signed-in
/// visitor to the login page, and a double click wrote twice; and a ♥ that
/// worked said nothing — the app says « Ajouté aux favoris » / « Retiré des
/// favoris » with « Annuler ». Now the web does, on the search, the salon page
/// and « Mon compte ».

type Answer = 'throw' | { status: number; body?: unknown } | (() => Promise<Response>);

function mockFetch(answers: Record<string, Answer>) {
  const fn = vi.fn(async (url: string, init?: RequestInit) => {
    const path = String(url).split('?')[0];
    const method = init?.method ?? 'GET';
    const a = answers[`${method} ${path}`] ?? answers[path];
    if (a === 'throw') throw new TypeError('Failed to fetch');
    if (typeof a === 'function') return a();
    if (!a) return new Response('{}', { status: 404 });
    return reply(a.status, a.body);
  });
  vi.stubGlobal('fetch', fn);
  const writes = (call: string) =>
    fn.mock.calls.filter(
      ([url, init]) => `${(init as RequestInit | undefined)?.method ?? 'GET'} ${String(url)}` === call,
    ).length;
  return { fn, writes };
}

function reply(status: number, body: unknown = {}): Response {
  return new Response(status === 204 ? null : JSON.stringify(body), { status });
}

/// A write held in flight until the test lets it answer.
function deferred() {
  let answer!: (r: Response) => void;
  const promise = new Promise<Response>((r) => {
    answer = r;
  });
  return { call: () => promise, answer };
}

/// The page leaves through `window.location.assign` (the search) — caught.
function watchLeaving() {
  const assign = vi.fn();
  vi.stubGlobal('location', {
    ...window.location,
    assign,
    pathname: '/recherche',
    search: '?q=tresses',
  });
  return assign;
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
  push.mockReset();
});

const ADDED = 'Ajouté aux favoris';
const REMOVED = 'Retiré des favoris';

const P1: Provider = providerFixture;
const P2: Provider = { ...providerFixture, id: 'p2', slug: 'salon-elegance', name: 'Salon Élégance' };

/// The announcement: in a polite live region, with its « Annuler ».
async function expectAnnounced(sentence: string) {
  const said = await screen.findByText(sentence);
  const region = said.closest('[role="status"]');
  expect(region).not.toBeNull();
  expect(region).toHaveAttribute('aria-live', 'polite');
  return screen.getByRole('button', { name: 'Annuler' });
}

/// No announcement: a ♥ that did not change says so under its card, not here.
function expectNothingAnnounced() {
  expect(screen.queryByText(ADDED)).toBeNull();
  expect(screen.queryByText(REMOVED)).toBeNull();
  expect(screen.queryByRole('button', { name: 'Annuler' })).toBeNull();
}

/// The toast's region is on the page BEFORE anything is said (WEB-SYSTEM §7).
function expectRegionMounted() {
  expect(document.querySelector('[role="status"][aria-live="polite"]')).not.toBeNull();
}

// --- the search -------------------------------------------------------------

function renderRecherche() {
  return render(
    <RechercheClient
      title="Salons à Cocody"
      results={[P1, P2]}
      q=""
      commune=""
      category=""
      sort="relevance"
      dispo={false}
      tree={emptyTree}
    />,
  );
}

async function enabledHeart(name: string) {
  const heart = await screen.findByRole('button', { name });
  await waitFor(() => expect(heart).toBeEnabled());
  return heart;
}

describe('B5.2 — the search ♥ when the favourites read failed', () => {
  for (const [label, read] of [
    ['it answered 500', { status: 500 }],
    ['nothing answered', 'throw'],
    ['its list held something that is not a salon', { status: 200, body: { favorites: [null] } }],
  ] as const) {
    it(`${label}: a signed-in visitor’s ♥ writes — never the login page`, async () => {
      const assign = watchLeaving();
      const { writes } = mockFetch({
        'GET /api/me/favorites': read as Answer,
        'POST /api/me/favorites/p1': { status: 204 },
      });
      renderRecherche();
      fireEvent.click(await enabledHeart('Ajouter Beauté Divine aux favoris'));

      expect(
        await screen.findByRole('button', { name: 'Retirer Beauté Divine des favoris' }),
      ).toHaveAttribute('aria-pressed', 'true');
      expect(writes('POST /api/me/favorites/p1')).toBe(1);
      expect(assign).not.toHaveBeenCalled();
    });
  }

  it('…and when THAT write answers 401, the login page (the write decides)', async () => {
    const assign = watchLeaving();
    mockFetch({
      'GET /api/me/favorites': { status: 500 },
      'POST /api/me/favorites/p1': { status: 401 },
    });
    renderRecherche();
    fireEvent.click(await enabledHeart('Ajouter Beauté Divine aux favoris'));

    await waitFor(() =>
      expect(assign).toHaveBeenCalledWith(
        `/connexion?returnTo=${encodeURIComponent('/recherche?q=tresses')}`,
      ),
    );
    expectNothingAnnounced();
  });

  it('CONTROL — not signed in (401 on the read): the login page, nothing written', async () => {
    const assign = watchLeaving();
    const { writes } = mockFetch({ 'GET /api/me/favorites': { status: 401 } });
    renderRecherche();
    fireEvent.click(await enabledHeart('Ajouter Beauté Divine aux favoris'));

    await waitFor(() => expect(assign).toHaveBeenCalled());
    expect(writes('POST /api/me/favorites/p1')).toBe(0);
  });
});

describe('B5.2 — one ♥ write at a time, per card', () => {
  it('a double click writes once; that heart waits, the others do not', async () => {
    const held = deferred();
    const { writes } = mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p1': held.call,
    });
    renderRecherche();
    const heart = await enabledHeart('Ajouter Beauté Divine aux favoris');
    heart.focus();
    fireEvent.click(heart);
    fireEvent.click(heart);

    expect(writes('POST /api/me/favorites/p1')).toBe(1);
    // Busy, and still focused: `aria-disabled`, not `disabled`, which would
    // drop the keyboard's focus to <body> (spec §4).
    expect(heart).toHaveAttribute('aria-disabled', 'true');
    expect(heart).toHaveFocus();
    expect(screen.getByRole('button', { name: 'Ajouter Salon Élégance aux favoris' })).toBeEnabled();

    await act(async () => held.answer(reply(204)));
    expect(
      await screen.findByRole('button', { name: 'Retirer Beauté Divine des favoris' }),
    ).toBeEnabled();
    expect(screen.getAllByText(ADDED)).toHaveLength(1);
  });
});

describe('B5.4 — the search ♥ says what it did', () => {
  it('adding: « Ajouté aux favoris », in a region mounted before it, with « Annuler »', async () => {
    mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p1': { status: 204 },
    });
    renderRecherche();
    expectRegionMounted();
    fireEvent.click(await enabledHeart('Ajouter Beauté Divine aux favoris'));

    await expectAnnounced(ADDED);
  });

  it('removing: « Retiré des favoris »', async () => {
    mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [P1] } },
      'DELETE /api/me/favorites/p1': { status: 204 },
    });
    renderRecherche();
    fireEvent.click(await enabledHeart('Retirer Beauté Divine des favoris'));

    await expectAnnounced(REMOVED);
  });

  it('a ♥ that failed announces nothing — its sentence is under the card', async () => {
    mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p1': { status: 500 },
    });
    renderRecherche();
    fireEvent.click(await enabledHeart('Ajouter Beauté Divine aux favoris'));

    await screen.findByRole('alert');
    expectNothingAnnounced();
  });

  it('« Annuler » writes the opposite: the heart is empty again, the toast gone', async () => {
    const { writes } = mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p1': { status: 204 },
      'DELETE /api/me/favorites/p1': { status: 204 },
    });
    renderRecherche();
    fireEvent.click(await enabledHeart('Ajouter Beauté Divine aux favoris'));
    fireEvent.click(await expectAnnounced(ADDED));

    expect(
      await screen.findByRole('button', { name: 'Ajouter Beauté Divine aux favoris' }),
    ).toHaveAttribute('aria-pressed', 'false');
    expect(writes('DELETE /api/me/favorites/p1')).toBe(1);
    expectNothingAnnounced();
  });

  it('« Annuler » that fails: the heart stays full, the sentence under the card', async () => {
    mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p1': { status: 204 },
      'DELETE /api/me/favorites/p1': 'throw',
    });
    renderRecherche();
    fireEvent.click(await enabledHeart('Ajouter Beauté Divine aux favoris'));
    fireEvent.click(await expectAnnounced(ADDED));

    expect(await screen.findByRole('alert')).toHaveTextContent('Pas de connexion. Réessayez.');
    expect(
      screen.getByRole('button', { name: 'Retirer Beauté Divine des favoris' }),
    ).toHaveAttribute('aria-pressed', 'true');
  });
});

// --- the salon page -----------------------------------------------------------

describe('B5.4 — the salon page’s ♥ says what it did', () => {
  it('adding: « Ajouté aux favoris » with « Annuler », which takes it back', async () => {
    const { fn, writes } = mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p1': { status: 204 },
      'DELETE /api/me/favorites/p1': { status: 204 },
    });
    render(<FavoriteButton providerId="p1" slug="beaute-divine" />);
    expectRegionMounted();
    await waitFor(() => expect(fn).toHaveBeenCalledTimes(1));
    fireEvent.click(screen.getByRole('button', { name: /Ajouter aux favoris/ }));

    fireEvent.click(await expectAnnounced(ADDED));
    expect(
      await screen.findByRole('button', { name: /Ajouter aux favoris/ }),
    ).toHaveAttribute('aria-pressed', 'false');
    expect(writes('DELETE /api/me/favorites/p1')).toBe(1);
    expectNothingAnnounced();
  });

  it('removing: « Retiré des favoris »', async () => {
    mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [P1] } },
      'DELETE /api/me/favorites/p1': { status: 204 },
    });
    render(<FavoriteButton providerId="p1" slug="beaute-divine" />);
    fireEvent.click(await screen.findByRole('button', { name: /Favori/ }));

    await expectAnnounced(REMOVED);
  });

  it('a ♥ that failed announces nothing', async () => {
    const { fn } = mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p1': { status: 500 },
    });
    render(<FavoriteButton providerId="p1" slug="beaute-divine" />);
    await waitFor(() => expect(fn).toHaveBeenCalledTimes(1));
    fireEvent.click(screen.getByRole('button', { name: /Ajouter aux favoris/ }));

    await screen.findByRole('alert');
    expectNothingAnnounced();
  });
});

// --- « Mon compte » ------------------------------------------------------------

const ME = { id: 'u1', name: 'Awa', email: 'awa@x.ci', phoneNumber: '+2250707123456' };

function favoriteNames(): string[] {
  return screen
    .getAllByRole('heading', { level: 3 })
    .map((h) => h.textContent ?? '')
    .filter((t) => /Beauté Divine|Salon Élégance/.test(t))
    .map((t) => (t.includes('Beauté Divine') ? 'p1' : 'p2'));
}

describe('B5.4 — « Mon compte » says a favourite went (Q4)', () => {
  function accountReads(extra: Record<string, Answer>) {
    return mockFetch({
      'GET /api/me': { status: 200, body: ME },
      'GET /api/appointments': { status: 200, body: { items: [] } },
      'GET /api/me/favorites': { status: 200, body: { favorites: [P1, P2] } },
      ...extra,
    });
  }

  it('« Retirer des favoris »: « Retiré des favoris » with « Annuler », which puts the card back at its place', async () => {
    const { writes } = accountReads({
      'DELETE /api/me/favorites/p1': { status: 204 },
      'POST /api/me/favorites/p1': { status: 204 },
    });
    render(<AccountClient />);
    await waitFor(() => expect(favoriteNames()).toEqual(['p1', 'p2']));
    expectRegionMounted();
    fireEvent.click(screen.getAllByRole('button', { name: 'Retirer des favoris' })[0]);

    const undo = await expectAnnounced(REMOVED);
    await waitFor(() => expect(favoriteNames()).toEqual(['p2']));
    fireEvent.click(undo);

    await waitFor(() => expect(favoriteNames()).toEqual(['p1', 'p2']));
    expect(writes('POST /api/me/favorites/p1')).toBe(1);
    expectNothingAnnounced();
  });

  it('a removal that failed announces nothing (its sentence is under the card)', async () => {
    accountReads({ 'DELETE /api/me/favorites/p1': { status: 500 } });
    render(<AccountClient />);
    await waitFor(() => expect(favoriteNames()).toEqual(['p1', 'p2']));
    fireEvent.click(screen.getAllByRole('button', { name: 'Retirer des favoris' })[0]);

    await screen.findByRole('alert');
    expectNothingAnnounced();
  });

  it('« Annuler » that fails: said in the toast (no card to put it under), the card stays gone', async () => {
    accountReads({
      'DELETE /api/me/favorites/p1': { status: 204 },
      'POST /api/me/favorites/p1': 'throw',
    });
    render(<AccountClient />);
    await waitFor(() => expect(favoriteNames()).toEqual(['p1', 'p2']));
    fireEvent.click(screen.getAllByRole('button', { name: 'Retirer des favoris' })[0]);
    fireEvent.click(await expectAnnounced(REMOVED));

    const said = await screen.findByText('Pas de connexion. Réessayez.');
    expect(said.closest('[role="status"]')).not.toBeNull();
    expect(favoriteNames()).toEqual(['p2']);
  });
});
