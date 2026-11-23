import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn(), refresh: vi.fn(), back: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => '/mon-compte',
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock('@sentry/nextjs', () => ({ captureMessage: vi.fn() }));
vi.mock('next/dynamic', () => ({ default: () => () => null }));

import { AccountClient } from '../components/account/AccountClient';
import { ClientStatusChip } from '../components/account/ClientStatusChip';
import type { Appointment } from '../lib/account/appointments';

/// docs/design/web-account-bookings-truth.md §2.1–§2.6 and §8 (component):
/// « Mes rendez-vous » sorts, labels and sums up a client's bookings as the
/// app does, with a frozen clock and the BFF answered here.

const NOW = new Date('2026-11-23T12:00:00.000Z');
const DAY = 86_400_000;
const at = (ms: number) => new Date(NOW.getTime() + ms).toISOString();

const salon = {
  providerId: 'p1',
  providerName: 'Beauté Divine',
  providerSlug: 'beaute-divine',
  serviceIds: ['s1'],
  artistId: 'a1',
  totalPrice: 15_000,
  providerCurrency: 'XOF',
};
const appt = (id: string, status: string, ms: number, extra: Partial<Appointment> = {}): Appointment => ({
  id,
  status,
  appointmentDate: at(ms),
  ...salon,
  ...extra,
});

const FAR = appt('far', 'confirmed', 7 * DAY);
const SOON = appt('soon', 'pending', DAY);
const UNCONFIRMED = appt('unconfirmed', 'pending', -DAY);
const PAST_CONFIRMED = appt('past-confirmed', 'confirmed', -3 * DAY);
const ABSENT = appt('absent', 'noShow', -39 * DAY); // 15 October
const DONE = appt('done', 'completed', -44 * DAY, { totalPrice: 20_000 }); // 10 October
const DONE_STOPPED = appt('done-stopped', 'completed', -49 * DAY, {
  providerName: 'Salon Arrêté',
  providerSlug: 'salon-arrete',
  providerStatus: 'suspended',
}); // 5 October
const CANCELLED_OLD = appt('c-old', 'cancelled', -10 * DAY);
const CANCELLED_NEW = appt('c-new', 'cancelled', 2 * DAY);

// The server's order: newest first, in one list.
const ALL = [
  FAR,
  CANCELLED_NEW,
  SOON,
  UNCONFIRMED,
  PAST_CONFIRMED,
  CANCELLED_OLD,
  ABSENT,
  DONE,
  DONE_STOPPED,
];

function serve(items: Appointment[]) {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      const path = String(url).split('?')[0];
      if (path === '/api/me') {
        return new Response(JSON.stringify({ id: 'u1', name: 'Awa' }), { status: 200 });
      }
      if (path === '/api/appointments') {
        return new Response(JSON.stringify({ items }), { status: 200 });
      }
      if (path === '/api/me/favorites') {
        return new Response(JSON.stringify({ favorites: [] }), { status: 200 });
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

async function open(items: Appointment[]) {
  serve(items);
  render(<AccountClient />);
  await screen.findByRole('heading', { level: 2, name: 'Mes rendez-vous' });
}

const tab = (name: string) =>
  fireEvent.click(
    within(screen.getByRole('group', { name: 'Filtrer mes rendez-vous' })).getByRole('button', {
      name,
    }),
  );

/// The bookings block: the section the « Mes rendez-vous » heading opens.
const bookings = () =>
  screen.getByRole('heading', { level: 2, name: 'Mes rendez-vous' }).closest('section')!;

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(NOW);
});

afterEach(() => {
  cleanup();
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe('« À venir »', () => {
  it('lists future pending and confirmed bookings only, soonest first, as a list', async () => {
    await open(ALL);
    const list = within(bookings()).getByRole('list');
    const items = within(list).getAllByRole('listitem');
    expect(items).toHaveLength(2);
    expect(items[0].querySelector('a')).toHaveAttribute('href', '/mon-compte/soon');
    expect(items[1].querySelector('a')).toHaveAttribute('href', '/mon-compte/far');
    expect(within(items[0]).getByText('En attente')).toBeInTheDocument();
    expect(within(items[1]).getByText('Confirmé')).toBeInTheDocument();
    // The past pending booking left: it no longer waits here as « En attente ».
    expect(within(bookings()).queryByText('Non confirmé')).toBeNull();
  });
});

describe('« Passés »', () => {
  it('shows the summary of « Terminé » visits only', async () => {
    await open(ALL);
    tab('Passés');
    const terms = within(bookings()).getAllByRole('term').map((t) => t.textContent);
    const values = within(bookings()).getAllByRole('definition').map((d) => d.textContent);
    expect(terms).toEqual(['visites', 'dépensés']);
    // Two completed (35 000), not the five past bookings.
    expect(values[0]).toBe('2');
    expect(values[1]).toBe('35 000 FCFA');
  });

  it('hides the summary when nothing is « Terminé »', async () => {
    await open([UNCONFIRMED, ABSENT]);
    tab('Passés');
    expect(within(bookings()).queryAllByRole('term')).toHaveLength(0);
    expect(within(bookings()).getAllByRole('listitem')).toHaveLength(2);
  });

  it('groups by month, newest first, each an h3 under the h2', async () => {
    await open(ALL);
    tab('Passés');
    const months = within(bookings()).getAllByRole('heading', { level: 3 });
    expect(months.map((h) => h.textContent)).toEqual(['novembre 2026', 'octobre 2026']);
    // Newest first inside: yesterday, then three days ago; then October's.
    expect(
      within(bookings())
        .getAllByRole('listitem')
        .map((li) => li.querySelector('a')?.getAttribute('href')),
    ).toEqual([
      '/mon-compte/unconfirmed',
      '/mon-compte/past-confirmed',
      '/mon-compte/absent',
      '/mon-compte/done',
      '/mon-compte/done-stopped',
    ]);
  });

  it('labels each booking by the client rule', async () => {
    await open(ALL);
    tab('Passés');
    const [unconfirmed, pastConfirmed, absent, done, doneStopped] =
      within(bookings()).getAllByRole('listitem');
    expect(within(unconfirmed).getByText('Non confirmé')).toBeInTheDocument();
    expect(within(pastConfirmed).getByText('Confirmé')).toBeInTheDocument();
    expect(within(absent).getByText('Absent')).toBeInTheDocument();
    expect(within(done).getByText('Terminé')).toBeInTheDocument();
    expect(within(doneStopped).getByText('Terminé')).toBeInTheDocument();
  });

  it('offers « Réserver à nouveau » under each booking at a live salon, naming it', async () => {
    await open(ALL);
    tab('Passés');
    const items = within(bookings()).getAllByRole('listitem');
    const rebook = within(bookings()).getAllByRole('link', { name: /^Réserver à nouveau/ });
    expect(rebook).toHaveLength(4);
    for (const link of rebook) {
      expect(link).toHaveAccessibleName('Réserver à nouveau chez Beauté Divine');
      expect(link).toHaveAttribute('href', '/beaute-divine/reserver?services=s1&artist=a1');
      expect(link.className).toContain('min-h-12');
    }
    // The stopped salon: no button; its card says why, once.
    const stopped = items[4];
    expect(within(stopped).queryByRole('link', { name: /Réserver à nouveau/ })).toBeNull();
    expect(
      within(stopped).getAllByText('Ce salon ne prend plus de rendez-vous sur MyWeli.'),
    ).toHaveLength(1);
  });
});

describe('« Annulés »', () => {
  it('lists cancelled bookings only, newest first — no absence', async () => {
    await open(ALL);
    tab('Annulés');
    const items = within(bookings()).getAllByRole('listitem');
    expect(items.map((li) => li.querySelector('a')?.getAttribute('href'))).toEqual([
      '/mon-compte/c-new',
      '/mon-compte/c-old',
    ]);
    expect(within(bookings()).queryByText('Absent')).toBeNull();
    expect(within(bookings()).getByRole('list')).toBeInTheDocument();
  });
});

describe('an empty state for each tab (§2.5, decision 184)', () => {
  it('says what each tab would hold, with a link only where it helps', async () => {
    await open([]);
    const expected: [string, string, string, boolean][] = [
      ['À venir', 'Aucun rendez-vous', 'Vos réservations apparaîtront ici.', true],
      ['Passés', 'Aucun rendez-vous passé', 'Vos rendez-vous passés apparaîtront ici.', true],
      ['Annulés', 'Aucun rendez-vous annulé', 'Vos rendez-vous annulés apparaîtront ici.', false],
    ];
    for (const [name, title, description, discover] of expected) {
      tab(name);
      await waitFor(() => expect(within(bookings()).getByText(title)).toBeInTheDocument());
      expect(within(bookings()).getByText(description)).toBeInTheDocument();
      expect(
        within(bookings()).queryAllByRole('link', { name: 'Découvrir des salons' }),
        name,
      ).toHaveLength(discover ? 1 : 0);
      expect(within(bookings()).queryAllByRole('list'), name).toHaveLength(0);
    }
  });
});

describe('the headings (§2.6)', () => {
  it('opens the bookings with an h2 that comes before the months and « Favoris »', async () => {
    await open(ALL);
    tab('Passés');
    const order = screen
      .getAllByRole('heading')
      .map((h) => `${h.tagName}:${h.textContent}`);
    expect(order.slice(0, 3)).toEqual([
      'H2:Mes rendez-vous',
      'H3:novembre 2026',
      'H3:octobre 2026',
    ]);
    expect(order).toContain('H2:Favoris');
    expect(order.indexOf('H2:Favoris')).toBeGreaterThan(order.indexOf('H3:octobre 2026'));
  });
});

describe('ClientStatusChip (§2.3)', () => {
  const chip = (a: Appointment) => {
    const { container } = render(<ClientStatusChip appt={a} now={NOW} />);
    return container.firstElementChild as HTMLElement;
  };

  it('draws neutral as `ink` — a visible pill on the card’s white', () => {
    for (const a of [UNCONFIRMED, DONE]) {
      const el = chip(a);
      expect(el.className).toContain('bg-textSecondary/10');
      expect(el.className).not.toContain('bg-surface');
      cleanup();
    }
  });

  it('draws the other tones `tinted`', () => {
    expect(chip(SOON).className).toContain('bg-warningLight/20');
    cleanup();
    expect(chip(PAST_CONFIRMED).className).toContain('bg-success/10');
    cleanup();
    expect(chip(ABSENT).className).toContain('bg-error/10');
    cleanup();
    expect(chip(CANCELLED_OLD).className).toContain('bg-error/10');
  });
});
