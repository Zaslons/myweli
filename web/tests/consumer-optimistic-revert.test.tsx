import {
  act,
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
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
import { NotificationsClient } from '../components/account/NotificationsClient';
import { RechercheClient } from '../components/discovery/RechercheClient';
import { FavoriteButton } from '../components/provider/FavoriteButton';
import type { Provider } from '../lib/api/providers';
import { emptyTree } from '../lib/localities';
import { providerFixture } from './fixtures';

/// docs/design/web-consumer-optimistic-revert.md — a write that failed puts
/// the screen back and says why, under the gesture: « Pas de connexion.
/// Réessayez. » when nothing answered (status 0), the screen's own sentence
/// otherwise. Before: « Retirer des favoris » and « marquer comme lu » / « Tout
/// lire » kept the change the server refused; the ♥ and the name's « OK » came
/// back without a word.

type Answer = 'throw' | { status: number; body?: unknown } | (() => Promise<Response>);

/// Answers by « METHOD path » first, then by path (query stripped); anything
/// unlisted is a 404.
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
  return fn;
}

/// A BFF answer. A 204 has no body — `new Response('{}', { status: 204 })`
/// throws, and `send()` would read that as no network.
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

/// What a browser does to a focused button that becomes `disabled` (focus
/// fixup), which jsdom does not: focus falls to <body>. Not `.blur()` — jsdom
/// ignores it on a disabled button (no longer a focusable area), which left
/// the focus tests passing with the restore deleted. Focus moves to a
/// throwaway button that is then removed: jsdom does send THAT to <body>.
function dropFocus() {
  const away = document.createElement('button');
  document.body.appendChild(away);
  away.focus();
  away.remove();
  expect(document.activeElement).toBe(document.body);
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
  push.mockReset();
});

const NO_CONNECTION = 'Pas de connexion. Réessayez.';
const GENERIC = 'Une erreur est survenue. Réessayez.';
const SAVE_FAILED = 'L’enregistrement a échoué. Réessayez.';

/// Each failure, both ways: nothing answered (status 0), and the BFF refused.
const FAILURES: { label: string; answer: Answer; sentence: string }[] = [
  { label: 'without network', answer: 'throw', sentence: NO_CONNECTION },
  { label: 'the BFF refused (500)', answer: { status: 500 }, sentence: GENERIC },
];

const P1: Provider = providerFixture;
const P2: Provider = { ...providerFixture, id: 'p2', slug: 'salon-elegance', name: 'Salon Élégance' };

// --- 1. Mon compte — « Retirer des favoris » -------------------------------

const ME = { id: 'u1', name: 'Awa', email: 'awa@x.ci', phoneNumber: '+2250707123456' };
const ACCOUNT_READS: Record<string, Answer> = {
  'GET /api/me': { status: 200, body: ME },
  'GET /api/appointments': { status: 200, body: { items: [] } },
  'GET /api/me/favorites': { status: 200, body: { favorites: [P1, P2] } },
};

/// The card's wrapper: the ProviderCard link, its « Retirer » button, its line.
function favoriteCard(name: RegExp): HTMLElement {
  return screen.getByRole('heading', { name }).closest('a')!.parentElement!;
}

function favoriteNames(): string[] {
  return screen
    .getAllByRole('heading', { level: 3 })
    .map((h) => h.textContent ?? '')
    .filter((t) => /Beauté Divine|Salon Élégance/.test(t))
    .map((t) => (t.includes('Beauté Divine') ? 'p1' : 'p2'));
}

describe('Mon compte — « Retirer des favoris » (docs/design/web-consumer-optimistic-revert.md §3.2 ①)', () => {
  for (const f of FAILURES) {
    it(`${f.label}: the card comes back at its place, the sentence under it`, async () => {
      mockFetch({ ...ACCOUNT_READS, 'DELETE /api/me/favorites/p1': f.answer });
      render(<AccountClient />);
      await screen.findByRole('heading', { name: /Beauté Divine/ });
      fireEvent.click(
        within(favoriteCard(/Beauté Divine/)).getByRole('button', { name: 'Retirer des favoris' }),
      );

      const alert = await screen.findByRole('alert');
      expect(alert).toHaveTextContent(f.sentence);
      // Back, in its own place — before the other one.
      expect(favoriteNames()).toEqual(['p1', 'p2']);
      expect(within(favoriteCard(/Beauté Divine/)).getByRole('alert')).toBe(alert);
      expect(within(favoriteCard(/Salon Élégance/)).queryByRole('alert')).toBeNull();
    });
  }

  it('in flight the card is gone (still optimistic); the answer decides', async () => {
    const d = deferred();
    mockFetch({ ...ACCOUNT_READS, 'DELETE /api/me/favorites/p1': d.call });
    render(<AccountClient />);
    await screen.findByRole('heading', { name: /Beauté Divine/ });
    fireEvent.click(
      within(favoriteCard(/Beauté Divine/)).getByRole('button', { name: 'Retirer des favoris' }),
    );

    expect(screen.queryByRole('heading', { name: /Beauté Divine/ })).toBeNull();
    await act(async () => d.answer(reply(500)));
    expect(await screen.findByRole('heading', { name: /Beauté Divine/ })).toBeInTheDocument();
  });

  it('focus fell with the card: it comes back on that card’s « Retirer des favoris »', async () => {
    const d = deferred();
    mockFetch({ ...ACCOUNT_READS, 'DELETE /api/me/favorites/p1': d.call });
    render(<AccountClient />);
    await screen.findByRole('heading', { name: /Beauté Divine/ });
    const button = within(favoriteCard(/Beauté Divine/)).getByRole('button', {
      name: 'Retirer des favoris',
    });
    button.focus();
    fireEvent.click(button);
    expect(document.activeElement).toBe(document.body);

    await act(async () => d.answer(Response.error()));
    await screen.findByRole('alert');
    expect(
      within(favoriteCard(/Beauté Divine/)).getByRole('button', { name: 'Retirer des favoris' }),
    ).toHaveFocus();
  });

  it('undo is this one card, never a snapshot: a removal that worked meanwhile stays done (SYSTEM §15)', async () => {
    const p1 = deferred();
    const p2 = deferred();
    mockFetch({
      ...ACCOUNT_READS,
      'DELETE /api/me/favorites/p1': p1.call,
      'DELETE /api/me/favorites/p2': p2.call,
    });
    render(<AccountClient />);
    await screen.findByRole('heading', { name: /Beauté Divine/ });
    fireEvent.click(
      within(favoriteCard(/Beauté Divine/)).getByRole('button', { name: 'Retirer des favoris' }),
    );
    fireEvent.click(
      within(favoriteCard(/Salon Élégance/)).getByRole('button', { name: 'Retirer des favoris' }),
    );
    // The second removal lands while the first is still out; then the first fails.
    await act(async () => p2.answer(reply(204)));
    await act(async () => p1.answer(reply(500)));

    expect(await screen.findByRole('alert')).toHaveTextContent(GENERIC);
    expect(favoriteNames()).toEqual(['p1']);
  });

  it('a removal that worked: the card goes, no sentence (unchanged)', async () => {
    mockFetch({ ...ACCOUNT_READS, 'DELETE /api/me/favorites/p1': { status: 204 } });
    render(<AccountClient />);
    await screen.findByRole('heading', { name: /Beauté Divine/ });
    fireEvent.click(
      within(favoriteCard(/Beauté Divine/)).getByRole('button', { name: 'Retirer des favoris' }),
    );

    await waitFor(() => expect(favoriteNames()).toEqual(['p2']));
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('a retry that works clears the sentence and removes the card', async () => {
    let calls = 0;
    mockFetch({
      ...ACCOUNT_READS,
      'DELETE /api/me/favorites/p1': async () =>
        reply(++calls === 1 ? 500 : 204),
    });
    render(<AccountClient />);
    await screen.findByRole('heading', { name: /Beauté Divine/ });
    fireEvent.click(
      within(favoriteCard(/Beauté Divine/)).getByRole('button', { name: 'Retirer des favoris' }),
    );
    await screen.findByRole('alert');
    fireEvent.click(
      within(favoriteCard(/Beauté Divine/)).getByRole('button', { name: 'Retirer des favoris' }),
    );

    await waitFor(() => expect(favoriteNames()).toEqual(['p2']));
    expect(screen.queryByRole('alert')).toBeNull();
  });
});

// --- 2. Notifications — open one, « Tout lire » ------------------------------

const N1 = {
  id: 'n1',
  type: 'reminder',
  title: 'Rappel : demain 10 h',
  body: 'Beauté Divine',
  createdAt: '2026-10-15T09:00:00.000Z',
  read: false,
  route: null,
};
const N2 = { ...N1, id: 'n2', title: 'Nouvelle offre', read: false };
const N3 = { ...N1, id: 'n3', title: 'Bienvenue', read: true };
const NOTIF_READS: Record<string, Answer> = {
  'GET /api/me/notifications': { status: 200, body: { items: [N1, N2, N3] } },
  'GET /api/me/notification-preferences': {
    status: 200,
    body: { reminders: true, marketing: true, push: true },
  },
};

function notification(title: string): HTMLElement {
  return screen.getByRole('button', { name: new RegExp(title) });
}
function isUnread(title: string): boolean {
  return within(notification(title)).queryByLabelText('Non lu') !== null;
}

describe('Notifications — open one (§3.2 ②)', () => {
  for (const f of FAILURES) {
    it(`${f.label}: it is unread again, the sentence under it`, async () => {
      mockFetch({ ...NOTIF_READS, 'POST /api/me/notifications/n1/read': f.answer });
      render(<NotificationsClient />);
      fireEvent.click(await screen.findByRole('button', { name: /Rappel : demain/ }));

      const alert = await screen.findByRole('alert');
      expect(alert).toHaveTextContent(f.sentence);
      expect(isUnread('Rappel : demain')).toBe(true);
      expect(notification('Rappel : demain').closest('li')).toContainElement(alert);
    });
  }

  it('a retry that works clears the sentence', async () => {
    let calls = 0;
    mockFetch({
      ...NOTIF_READS,
      'POST /api/me/notifications/n1/read': async () => reply(++calls === 1 ? 500 : 204),
    });
    render(<NotificationsClient />);
    fireEvent.click(await screen.findByRole('button', { name: /Rappel : demain/ }));
    await screen.findByRole('alert');
    fireEvent.click(screen.getByRole('button', { name: /Rappel : demain/ }));

    await act(async () => {});
    expect(isUnread('Rappel : demain')).toBe(false);
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('read on the server: it stays read, no sentence (unchanged)', async () => {
    const fn = mockFetch({ ...NOTIF_READS, 'POST /api/me/notifications/n1/read': { status: 204 } });
    render(<NotificationsClient />);
    fireEvent.click(await screen.findByRole('button', { name: /Rappel : demain/ }));

    await waitFor(() =>
      expect(fn.mock.calls.some(([u]) => String(u).endsWith('/n1/read'))).toBe(true),
    );
    await act(async () => {});
    expect(isUnread('Rappel : demain')).toBe(false);
    expect(screen.queryByRole('alert')).toBeNull();
  });
});

describe('Notifications — « Tout lire » (§3.2 ③)', () => {
  for (const f of FAILURES) {
    it(`${f.label}: the ones it marked are unread again, « Tout lire » comes back, the sentence`, async () => {
      mockFetch({ ...NOTIF_READS, 'POST /api/me/notifications/read-all': f.answer });
      render(<NotificationsClient />);
      fireEvent.click(await screen.findByRole('button', { name: 'Tout lire' }));

      expect(await screen.findByRole('alert')).toHaveTextContent(f.sentence);
      expect(screen.getByRole('button', { name: 'Tout lire' })).toBeInTheDocument();
      expect(isUnread('Rappel : demain')).toBe(true);
      expect(isUnread('Nouvelle offre')).toBe(true);
      // Undo undoes THIS gesture, never a snapshot (SYSTEM §15): read before, read after.
      expect(isUnread('Bienvenue')).toBe(false);
      expect(screen.getByRole('alert').closest('li')).toBeNull();
    });
  }

  it('a notification read on its own while « Tout lire » was out stays read', async () => {
    const d = deferred();
    mockFetch({
      ...NOTIF_READS,
      'POST /api/me/notifications/read-all': d.call,
      'POST /api/me/notifications/n1/read': { status: 204 },
    });
    render(<NotificationsClient />);
    // n1 read on its own first; then « Tout lire » marks the rest (n2) and fails.
    fireEvent.click(await screen.findByRole('button', { name: /Rappel : demain/ }));
    await waitFor(() => expect(isUnread('Rappel : demain')).toBe(false));
    fireEvent.click(screen.getByRole('button', { name: 'Tout lire' }));
    await act(async () => d.answer(reply(500)));

    await screen.findByRole('alert');
    expect(isUnread('Nouvelle offre')).toBe(true);
    expect(isUnread('Rappel : demain')).toBe(false);
  });

  it('focus fell with the button: it comes back on « Tout lire »', async () => {
    const d = deferred();
    mockFetch({ ...NOTIF_READS, 'POST /api/me/notifications/read-all': d.call });
    render(<NotificationsClient />);
    const button = await screen.findByRole('button', { name: 'Tout lire' });
    button.focus();
    fireEvent.click(button);
    expect(screen.queryByRole('button', { name: 'Tout lire' })).toBeNull();

    await act(async () => d.answer(Response.error()));
    await screen.findByRole('alert');
    expect(screen.getByRole('button', { name: 'Tout lire' })).toHaveFocus();
  });

  it('a retry that works clears the sentence', async () => {
    let calls = 0;
    mockFetch({
      ...NOTIF_READS,
      'POST /api/me/notifications/read-all': async () => reply(++calls === 1 ? 500 : 204),
    });
    render(<NotificationsClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Tout lire' }));
    await screen.findByRole('alert');
    fireEvent.click(screen.getByRole('button', { name: 'Tout lire' }));

    await act(async () => {});
    expect(screen.queryByLabelText('Non lu')).toBeNull();
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('read on the server: all read, the button gone, no sentence (unchanged)', async () => {
    mockFetch({ ...NOTIF_READS, 'POST /api/me/notifications/read-all': { status: 204 } });
    render(<NotificationsClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Tout lire' }));

    await act(async () => {});
    expect(screen.queryByRole('button', { name: 'Tout lire' })).toBeNull();
    expect(screen.queryByLabelText('Non lu')).toBeNull();
    expect(screen.queryByRole('alert')).toBeNull();
  });
});

// --- 3a. Le ♥ du salon --------------------------------------------------------

describe('Le ♥ du salon (§3.2 ④)', () => {
  for (const f of FAILURES) {
    it(`${f.label}, adding: still « Ajouter aux favoris », the sentence`, async () => {
      const fn = mockFetch({
        'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
        'POST /api/me/favorites/p1': f.answer,
      });
      render(<FavoriteButton providerId="p1" slug="beaute-divine" />);
      await waitFor(() => expect(fn).toHaveBeenCalledTimes(1));
      fireEvent.click(screen.getByRole('button', { name: /Ajouter aux favoris/ }));

      expect(await screen.findByRole('alert')).toHaveTextContent(f.sentence);
      const button = screen.getByRole('button', { name: /Ajouter aux favoris/ });
      expect(button).toHaveAttribute('aria-pressed', 'false');
      expect(button).toBeEnabled();
      expect(push).not.toHaveBeenCalled();
    });

    it(`${f.label}, removing: still « Favori », the sentence`, async () => {
      mockFetch({
        'GET /api/me/favorites': { status: 200, body: { favorites: [P1] } },
        'DELETE /api/me/favorites/p1': f.answer,
      });
      render(<FavoriteButton providerId="p1" slug="beaute-divine" />);
      fireEvent.click(await screen.findByRole('button', { name: /Favori/ }));

      expect(await screen.findByRole('alert')).toHaveTextContent(f.sentence);
      expect(screen.getByRole('button', { name: /Favori/ })).toHaveAttribute('aria-pressed', 'true');
    });
  }

  it('focus fell while the button was disabled: it comes back', async () => {
    const d = deferred();
    const fn = mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p1': d.call,
    });
    render(<FavoriteButton providerId="p1" slug="beaute-divine" />);
    await waitFor(() => expect(fn).toHaveBeenCalledTimes(1));
    const button = screen.getByRole('button', { name: /Ajouter aux favoris/ });
    button.focus();
    fireEvent.click(button);
    dropFocus();

    await act(async () => d.answer(reply(500)));
    await screen.findByRole('alert');
    expect(screen.getByRole('button', { name: /Ajouter aux favoris/ })).toHaveFocus();
  });

  it('a retry that works clears the sentence', async () => {
    let calls = 0;
    const fn = mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p1': async () =>
        reply(++calls === 1 ? 500 : 204),
    });
    render(<FavoriteButton providerId="p1" slug="beaute-divine" />);
    await waitFor(() => expect(fn).toHaveBeenCalledTimes(1));
    fireEvent.click(screen.getByRole('button', { name: /Ajouter aux favoris/ }));
    await screen.findByRole('alert');
    fireEvent.click(screen.getByRole('button', { name: /Ajouter aux favoris/ }));

    await screen.findByRole('button', { name: /Favori/ });
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('a 401 still leads to the login page, without a sentence (unchanged)', async () => {
    mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p1': { status: 401 },
    });
    render(<FavoriteButton providerId="p1" slug="beaute-divine" />);
    await act(async () => {});
    fireEvent.click(screen.getByRole('button', { name: /Ajouter aux favoris/ }));

    await waitFor(() =>
      expect(push).toHaveBeenCalledWith('/connexion?returnTo=%2Fbeaute-divine'),
    );
    expect(screen.queryByRole('alert')).toBeNull();
  });
});

// --- 3b. Le ♥ de la recherche -------------------------------------------------

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

/// The result card's wrapper (the heart lives inside it, the line under it).
function resultCard(heart: HTMLElement): HTMLElement {
  return heart.closest('[role="presentation"]') as HTMLElement;
}

describe('Le ♥ de la recherche (§3.2 ⑤)', () => {
  for (const f of FAILURES) {
    it(`${f.label}: the heart does not move, the sentence under that card only`, async () => {
      mockFetch({
        'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
        'POST /api/me/favorites/p1': f.answer,
      });
      renderRecherche();
      const heart = await screen.findByRole('button', { name: 'Ajouter Beauté Divine aux favoris' });
      await waitFor(() => expect(heart).toBeEnabled());
      fireEvent.click(heart);

      const alert = await screen.findByRole('alert');
      expect(alert).toHaveTextContent(f.sentence);
      expect(resultCard(heart)).toContainElement(alert);
      expect(
        screen.getByRole('button', { name: 'Ajouter Beauté Divine aux favoris' }),
      ).toHaveAttribute('aria-pressed', 'false');
      const other = screen.getByRole('button', { name: 'Ajouter Salon Élégance aux favoris' });
      expect(within(resultCard(other)).queryByRole('alert')).toBeNull();
    });
  }

  it('removing fails: the heart stays full', async () => {
    mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [P1] } },
      'DELETE /api/me/favorites/p1': 'throw',
    });
    renderRecherche();
    const heart = await screen.findByRole('button', { name: 'Retirer Beauté Divine des favoris' });
    fireEvent.click(heart);

    expect(await screen.findByRole('alert')).toHaveTextContent(NO_CONNECTION);
    expect(
      screen.getByRole('button', { name: 'Retirer Beauté Divine des favoris' }),
    ).toHaveAttribute('aria-pressed', 'true');
  });

  it('a retry that works clears that card’s sentence', async () => {
    let calls = 0;
    mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p1': async () =>
        reply(++calls === 1 ? 500 : 204),
    });
    renderRecherche();
    const heart = await screen.findByRole('button', { name: 'Ajouter Beauté Divine aux favoris' });
    await waitFor(() => expect(heart).toBeEnabled());
    fireEvent.click(heart);
    await screen.findByRole('alert');
    fireEvent.click(heart);

    await screen.findByRole('button', { name: 'Retirer Beauté Divine des favoris' });
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('a 401 (the session ended after the probe): the login page, like the anonymous heart', async () => {
    const assign = vi.fn();
    mockFetch({
      'GET /api/me/favorites': { status: 200, body: { favorites: [] } },
      'POST /api/me/favorites/p1': { status: 401 },
    });
    vi.stubGlobal('location', { ...window.location, assign, pathname: '/recherche', search: '?q=tresses' });
    renderRecherche();
    const heart = await screen.findByRole('button', { name: 'Ajouter Beauté Divine aux favoris' });
    await waitFor(() => expect(heart).toBeEnabled());
    fireEvent.click(heart);

    await waitFor(() =>
      expect(assign).toHaveBeenCalledWith(
        `/connexion?returnTo=${encodeURIComponent('/recherche?q=tresses')}`,
      ),
    );
    expect(screen.queryByRole('alert')).toBeNull();
  });
});

// --- 4. Mon compte — le nom ---------------------------------------------------

async function editName(to: string) {
  fireEvent.click(await screen.findByRole('button', { name: 'Modifier le nom' }));
  fireEvent.change(screen.getByRole('textbox', { name: 'Nom' }), { target: { value: to } });
}

describe('Mon compte — le nom, « OK » (§3.2 ⑥)', () => {
  const NAME_FAILURES = [
    { label: 'without network', answer: 'throw' as Answer, sentence: NO_CONNECTION },
    { label: 'the BFF refused (500)', answer: { status: 500 } as Answer, sentence: SAVE_FAILED },
  ];
  for (const f of NAME_FAILURES) {
    it(`${f.label}: the editor stays with the draft, the sentence`, async () => {
      mockFetch({ ...ACCOUNT_READS, 'PATCH /api/me': f.answer });
      render(<AccountClient />);
      await editName('Awa K.');
      fireEvent.click(screen.getByRole('button', { name: 'OK' }));

      expect(await screen.findByRole('alert')).toHaveTextContent(f.sentence);
      expect(screen.getByRole('textbox', { name: 'Nom' })).toHaveValue('Awa K.');
      expect(screen.getByRole('button', { name: 'OK' })).toBeEnabled();
      // The draft is not the name: « Annuler » shows the one the server has.
      fireEvent.click(screen.getByRole('button', { name: 'Annuler' }));
      expect(screen.getByText('Awa')).toBeInTheDocument();
      expect(screen.queryByText('Awa K.')).toBeNull();
    });
  }

  it('« Annuler » closes it with the editor, and « Modifier le nom » opens a clean one', async () => {
    mockFetch({ ...ACCOUNT_READS, 'PATCH /api/me': { status: 500 } });
    render(<AccountClient />);
    await editName('Awa K.');
    fireEvent.click(screen.getByRole('button', { name: 'OK' }));
    await screen.findByRole('alert');

    fireEvent.click(screen.getByRole('button', { name: 'Annuler' }));
    expect(screen.queryByRole('alert')).toBeNull();
    fireEvent.click(screen.getByRole('button', { name: 'Modifier le nom' }));
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('a new « OK » takes the last sentence away while it is out; a success closes the editor (unchanged)', async () => {
    const second = deferred();
    let calls = 0;
    mockFetch({
      ...ACCOUNT_READS,
      'PATCH /api/me': () => (++calls === 1 ? Promise.resolve(reply(500)) : second.call()),
    });
    render(<AccountClient />);
    await editName('Awa K.');
    fireEvent.click(screen.getByRole('button', { name: 'OK' }));
    await screen.findByRole('alert');
    fireEvent.click(screen.getByRole('button', { name: 'OK' }));
    expect(screen.queryByRole('alert')).toBeNull();

    await act(async () => second.answer(reply(200)));
    expect(await screen.findByText('Awa K.')).toBeInTheDocument();
    expect(screen.queryByRole('textbox', { name: 'Nom' })).toBeNull();
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('focus fell while « OK » was disabled: it comes back', async () => {
    const d = deferred();
    mockFetch({ ...ACCOUNT_READS, 'PATCH /api/me': d.call });
    render(<AccountClient />);
    await editName('Awa K.');
    const ok = screen.getByRole('button', { name: 'OK' });
    ok.focus();
    fireEvent.click(ok);
    dropFocus();

    await act(async () => d.answer(Response.error()));
    await screen.findByRole('alert');
    expect(screen.getByRole('button', { name: 'OK' })).toHaveFocus();
  });
});
