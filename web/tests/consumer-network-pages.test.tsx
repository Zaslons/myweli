import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
const push = vi.fn();
// Stable object: the load effects depend on [router].
const routerMock = { replace, push, refresh: vi.fn(), back: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => '/mon-compte',
  useSearchParams: () => new URLSearchParams(),
}));

import { HeaderBell } from '../components/HeaderBell';
import { AccountClient } from '../components/account/AccountClient';
import { AppointmentDetailClient } from '../components/account/AppointmentDetailClient';
import { DataExportClient } from '../components/account/DataExportClient';
import { NotificationsClient } from '../components/account/NotificationsClient';
import { SalonVisitsCard } from '../components/account/SalonVisitsCard';
import { BookingFlow } from '../components/booking/BookingFlow';
import { FavoriteButton } from '../components/provider/FavoriteButton';
import { resetLocalitiesClientCache } from '../lib/use-localities';
import { providerFixture } from './fixtures';

/// docs/design/web-consumer-network-failure.md §1/§3/§10 — every consumer
/// page that loads on arrival, under a dropped connection. Before: the read
/// threw into a load that never caught it, `setLoading(false)` never ran, and
/// the page stayed on its skeleton (or « Chargement… ») for ever — no message,
/// no « Réessayer ». Now: the page's own error state. And the seven callers
/// whose « not 200 » branch said something false (§3.2) say the truth.

type Answer = 'throw' | { status: number; body?: unknown };

/// Answers by PATH (query stripped, exact match); anything unlisted is a 404.
function mockFetch(answers: Record<string, Answer>) {
  const fn = vi.fn(async (url: string) => {
    const path = String(url).split('?')[0];
    const a = answers[path] ?? answers['*'];
    if (a === 'throw') throw new TypeError('Failed to fetch');
    if (!a) return new Response('{}', { status: 404 });
    return new Response(JSON.stringify(a.body ?? {}), { status: a.status });
  });
  vi.stubGlobal('fetch', fn);
  return fn;
}

/// A rejection no one handled — what a load that throws leaves behind. Vitest
/// reports these for the whole run; collected here, the island that leaked
/// one is the test that goes red.
const unhandled: unknown[] = [];
const onUnhandled = (reason: unknown) => unhandled.push(reason);
beforeEach(() => {
  unhandled.length = 0;
  process.on('unhandledRejection', onUnhandled);
});

afterEach(() => {
  process.off('unhandledRejection', onUnhandled);
  cleanup();
  vi.unstubAllGlobals();
  resetLocalitiesClientCache();
  replace.mockReset();
  push.mockReset();
});

/// Neither loading state is left on screen.
function expectNotLoading(container: HTMLElement) {
  expect(container.querySelector('.animate-pulse')).toBeNull();
  expect(screen.queryByText('Chargement…')).toBeNull();
}

const GENERIC = 'Une erreur est survenue. Réessayez.';

const ME = { id: 'u1', name: 'Awa', email: 'awa@x.ci', phoneNumber: '+2250707123456' };
const APPT = {
  id: 'a1',
  status: 'confirmed',
  appointmentDate: '2099-01-15T09:00:00.000Z',
  providerId: 'p1',
  providerName: 'Beauté Divine',
  providerSlug: 'beaute-divine',
  providerStatus: 'active',
  serviceNames: ['Coupe'],
  totalPrice: 5000,
};
const FAV = { ...providerFixture, id: 'p1', name: 'Beauté Divine' };

describe('Mon compte (/mon-compte)', () => {
  it('no network: the error state and « Réessayer » — never the skeleton for ever', async () => {
    mockFetch({ '*': 'throw' });
    const { container } = render(<AccountClient />);

    expect(await screen.findByRole('alert')).toHaveTextContent(GENERIC);
    expect(screen.getByRole('button', { name: 'Réessayer' })).toBeInTheDocument();
    expectNotLoading(container);
    expect(replace).not.toHaveBeenCalled();
  });

  it('« Réessayer » with the network back: the account', async () => {
    mockFetch({ '*': 'throw' });
    render(<AccountClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Réessayer' }));
    mockFetch({
      '/api/me': { status: 200, body: ME },
      '/api/appointments': { status: 200, body: { items: [APPT] } },
      '/api/me/favorites': { status: 200, body: { favorites: [FAV] } },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(await screen.findByRole('button', { name: 'Se déconnecter' })).toBeInTheDocument();
    expect(screen.queryByRole('alert')).toBeNull();
  });

  for (const [label, answer] of [
    ['no network', 'throw'],
    ['a 500', { status: 500 }],
  ] as const) {
    it(`favorites fail (${label}): the section says so — never « Aucun favori »; the bookings stay`, async () => {
      mockFetch({
        '/api/me': { status: 200, body: ME },
        '/api/appointments': { status: 200, body: { items: [APPT] } },
        '/api/me/favorites': answer,
      });
      render(<AccountClient />);

      expect(await screen.findByText('Favoris indisponibles.')).toBeInTheDocument();
      expect(screen.getByRole('heading', { level: 2, name: 'Favoris' })).toBeInTheDocument();
      expect(screen.queryByText('Aucun favori')).toBeNull();
      // The rest of the page is there: the booking and the way out.
      expect(screen.getByText('Beauté Divine')).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Se déconnecter' })).toBeInTheDocument();

      // « Réessayer » brings the favorites back.
      mockFetch({
        '/api/me': { status: 200, body: ME },
        '/api/appointments': { status: 200, body: { items: [APPT] } },
        '/api/me/favorites': { status: 200, body: { favorites: [FAV] } },
      });
      fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
      expect(await screen.findByRole('button', { name: 'Retirer des favoris' })).toBeInTheDocument();
      expect(screen.queryByText('Favoris indisponibles.')).toBeNull();
    });
  }

  it('the server says no favorites: « Aucun favori » (unchanged)', async () => {
    mockFetch({
      '/api/me': { status: 200, body: ME },
      '/api/appointments': { status: 200, body: { items: [] } },
      '/api/me/favorites': { status: 200, body: { favorites: [] } },
    });
    render(<AccountClient />);
    expect(await screen.findByText('Aucun favori')).toBeInTheDocument();
    expect(screen.queryByText('Favoris indisponibles.')).toBeNull();
  });
});

describe('Le détail d’un rendez-vous (/mon-compte/[id])', () => {
  for (const [label, answer] of [
    ['no network', 'throw'],
    ['a 500', { status: 500 }],
  ] as const) {
    it(`${label}: the error under « Rendez-vous », « Réessayer » and the way back — never « introuvable »`, async () => {
      mockFetch({
        '/api/appointments/a1': answer,
        '/api/localities': { status: 200, body: { countries: [] } },
      });
      const { container } = render(<AppointmentDetailClient id="a1" />);

      expect(await screen.findByRole('heading', { level: 1, name: 'Rendez-vous' })).toBeInTheDocument();
      expect(screen.getByRole('alert')).toHaveTextContent(GENERIC);
      expect(screen.getByRole('button', { name: 'Réessayer' })).toBeInTheDocument();
      expect(screen.getByRole('link', { name: '← Mes rendez-vous' })).toHaveAttribute(
        'href',
        '/mon-compte',
      );
      expect(screen.queryByText('Rendez-vous introuvable')).toBeNull();
      expectNotLoading(container);
    });
  }

  for (const status of [404, 403]) {
    it(`a ${status} is still « Rendez-vous introuvable » (absent, or someone else's — BACKEND §3.3)`, async () => {
      mockFetch({
        '/api/appointments/a1': { status, body: { error: 'x' } },
        '/api/localities': { status: 200, body: { countries: [] } },
      });
      render(<AppointmentDetailClient id="a1" />);
      expect(await screen.findByRole('heading', { name: 'Rendez-vous introuvable' })).toBeInTheDocument();
      expect(screen.queryByRole('button', { name: 'Réessayer' })).toBeNull();
    });
  }

  it('« Réessayer » with the network back: the booking', async () => {
    mockFetch({ '*': 'throw' });
    render(<AppointmentDetailClient id="a1" />);
    await screen.findByRole('button', { name: 'Réessayer' });
    mockFetch({
      '/api/appointments/a1': { status: 200, body: APPT },
      '/api/localities': { status: 200, body: { countries: [] } },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(await screen.findByRole('heading', { level: 1, name: 'Beauté Divine' })).toBeInTheDocument();
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('a 401 still goes to the login', async () => {
    mockFetch({ '/api/appointments/a1': { status: 401 } });
    render(<AppointmentDetailClient id="a1" />);
    await waitFor(() => expect(replace).toHaveBeenCalledWith('/connexion?returnTo=/mon-compte/a1'));
  });
});

describe('Notifications (/mon-compte/notifications)', () => {
  it('no network: the error under « Notifications » and « Réessayer »', async () => {
    mockFetch({ '*': 'throw' });
    const { container } = render(<NotificationsClient />);

    expect(await screen.findByRole('heading', { level: 1, name: 'Notifications' })).toBeInTheDocument();
    expect(screen.getByRole('alert')).toHaveTextContent('Chargement impossible.');
    expect(screen.getByRole('button', { name: 'Réessayer' })).toBeInTheDocument();
    expectNotLoading(container);
  });

  it('the feed answers, the preferences do not: « Préférences indisponibles. »', async () => {
    mockFetch({
      '/api/me/notifications': { status: 200, body: { items: [] } },
      '/api/me/notification-preferences': 'throw',
    });
    render(<NotificationsClient />);
    expect(await screen.findByText('Préférences indisponibles.')).toBeInTheDocument();
    expect(screen.getByText('Aucune notification')).toBeInTheDocument();
  });
});

describe('Mes données (/mon-compte/donnees)', () => {
  it('no network: the error under « Mes données » and « Réessayer »', async () => {
    mockFetch({ '*': 'throw' });
    const { container } = render(<DataExportClient />);

    expect(await screen.findByRole('heading', { level: 1, name: 'Mes données' })).toBeInTheDocument();
    expect(screen.getByRole('alert')).toHaveTextContent('Chargement impossible.');
    expect(screen.getByRole('button', { name: 'Réessayer' })).toBeInTheDocument();
    expectNotLoading(container);
  });

  for (const [label, answers] of [
    ['the bookings fail (no network)', { '/api/appointments': 'throw', '/api/me/favorites': { status: 200, body: { favorites: [FAV] } } }],
    ['the bookings fail (500)', { '/api/appointments': { status: 500 }, '/api/me/favorites': { status: 200, body: { favorites: [FAV] } } }],
    ['the favorites fail (no network)', { '/api/appointments': { status: 200, body: { items: [APPT] } }, '/api/me/favorites': 'throw' }],
    ['the favorites fail (500)', { '/api/appointments': { status: 200, body: { items: [APPT] } }, '/api/me/favorites': { status: 500 } }],
  ] as const) {
    it(`${label}: the error — never an export that says 0`, async () => {
      mockFetch({ '/api/me': { status: 200, body: ME }, ...answers });
      render(<DataExportClient />);

      expect(await screen.findByRole('alert')).toHaveTextContent('Chargement impossible.');
      // The document a person downloads as « my data » must not be missing
      // half of it without a word.
      expect(screen.queryByRole('button', { name: 'Télécharger (JSON)' })).toBeNull();
    });
  }

  it('every read answers: the export, with its counts', async () => {
    mockFetch({
      '/api/me': { status: 200, body: ME },
      '/api/appointments': { status: 200, body: { items: [APPT] } },
      '/api/me/favorites': { status: 200, body: { favorites: [FAV] } },
    });
    render(<DataExportClient />);
    expect(await screen.findByRole('button', { name: 'Télécharger (JSON)' })).toBeInTheDocument();
  });
});

describe('Réserver — l’étape « Confirmation » (the session probe)', () => {
  const SLOT = '2099-01-15T14:30:00.000Z';

  async function openConfirm(me: Answer) {
    mockFetch({
      '/api/availability': { status: 200, body: { slots: [SLOT] } },
      '/api/me': me,
    });
    const view = render(<BookingFlow provider={providerFixture} prefillServiceIds={['s1']} />);
    fireEvent.click(await screen.findByRole('button', { name: /^\d{2}:\d{2}$/ }));
    // Two « Confirmer » render (the desktop aside and the mobile bar).
    fireEvent.click(screen.getAllByRole('button', { name: 'Confirmer' })[0]);
    return view;
  }

  for (const [label, answer] of [
    ['no network', 'throw'],
    ['a 500', { status: 500 }],
  ] as const) {
    it(`${label}: an error and « Réessayer » — never the login form to someone signed in, never « Chargement… » for ever`, async () => {
      const { container } = await openConfirm(answer);

      expect(await screen.findByRole('alert')).toHaveTextContent(GENERIC);
      expect(screen.getByRole('heading', { level: 2, name: 'Confirmation' })).toBeInTheDocument();
      expect(screen.queryByText('Connectez-vous pour confirmer votre réservation.')).toBeNull();
      expectNotLoading(container);

      // « Réessayer » asks again; the session answers this time.
      mockFetch({
        '/api/availability': { status: 200, body: { slots: [SLOT] } },
        '/api/me': { status: 200, body: ME },
      });
      fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
      expect(await screen.findByLabelText('Numéro de téléphone')).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Confirmer la réservation' })).toBeInTheDocument();
      expect(screen.queryByRole('alert')).toBeNull();
    });
  }

  it('a 401 is still « Connectez-vous » (not signed in)', async () => {
    await openConfirm({ status: 401 });
    expect(await screen.findByText('Connectez-vous pour confirmer votre réservation.')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Réessayer' })).toBeNull();
  });
});

describe('the islands that load on arrival — silent on a failure, and no rejection left behind', () => {
  /// Let the island's read settle, and any rejection surface.
  async function settle(fetchMock: ReturnType<typeof mockFetch>) {
    await waitFor(() => expect(fetchMock).toHaveBeenCalled());
    await new Promise((r) => setTimeout(r, 20));
  }

  it('the header bell renders nothing', async () => {
    const f = mockFetch({ '*': 'throw' });
    const { container } = render(<HeaderBell />);
    await settle(f);
    expect(container).toBeEmptyDOMElement();
    expect(unhandled).toEqual([]);
  });

  it('« Vos rendez-vous ici » renders nothing', async () => {
    const f = mockFetch({ '*': 'throw' });
    const { container } = render(<SalonVisitsCard providerId="p1" />);
    await settle(f);
    expect(container).toBeEmptyDOMElement();
    expect(unhandled).toEqual([]);
  });

  it('the salon page ♥ stays « Ajouter aux favoris », usable', async () => {
    const f = mockFetch({ '*': 'throw' });
    render(<FavoriteButton providerId="p1" slug="beaute-divine" />);
    await settle(f);
    expect(screen.getByRole('button', { name: /Ajouter aux favoris/ })).toBeEnabled();
    expect(unhandled).toEqual([]);
  });
});
