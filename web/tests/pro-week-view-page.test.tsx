import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn(), refresh: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  useSearchParams: () => new URLSearchParams(window.location.search),
}));

import { RendezVousClient } from '../components/pro/RendezVousClient';

/// docs/design/web-pro-week-view.md (owner decisions 2026-10-20) — the
/// « Semaine » tab: one column per day, the artists side by side and an
/// « Artiste » filter, the Journée's panel, click-to-create, drag to another
/// day; desktop only.

const OWNER_ME = {
  account: { id: 'acc1', businessName: 'Beauté Divine', phoneNumber: '+2250700000000' },
  provider: {
    id: 'p1',
    name: 'Beauté Divine',
    status: 'active',
    timezone: 'Africa/Abidjan',
    currency: 'XOF',
    services: [{ id: 's1', name: 'Tresses' }],
    artists: [{ id: 'ar1', name: 'Awa' }, { id: 'ar2', name: 'Mia' }],
  },
};
let me: Record<string, unknown> = OWNER_ME;

const block = (id: string, date: string, time: string, artistId: string, client: string) => ({
  id,
  status: 'confirmed',
  appointmentDate: `${date}T${time}:00.000Z`,
  clientDisplayName: client,
  serviceIds: ['s1'],
  totalPrice: 15000,
  artistId,
  durationMinutes: 60,
});

let empty = false;
const asked: string[] = [];
const reschedules: { url: string; body: Record<string, unknown> }[] = [];

function journal(date: string) {
  const wednesdayClosed = date === '2026-10-21';
  const appointments = empty
    ? []
    : date === '2026-10-19'
      ? [block('pj-mon', date, '09:00', 'ar1', 'Koffi'), block('pj-mon2', date, '09:30', 'ar2', 'Aminata')]
      : date === '2026-10-20'
        ? [block('pj-tue', date, '10:00', 'ar1', 'Fatou')]
        : [];
  return {
    date,
    hours: wednesdayClosed ? null : { open: '08:00', close: '19:00', breaks: [] },
    artists: [{ id: 'ar1', name: 'Awa', imageUrl: null }, { id: 'ar2', name: 'Mia', imageUrl: null }],
    appointments,
  };
}

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date('2026-10-21T12:00:00.000Z'));
  me = OWNER_ME;
  empty = false;
  asked.length = 0;
  reschedules.length = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const u = String(url);
      if (u === '/api/pro/me') return new Response(JSON.stringify(me), { status: 200 });
      if (u === '/api/pro/appointments') return new Response(JSON.stringify({ items: [] }), { status: 200 });
      if (u.startsWith('/api/pro/journal?')) {
        const date = new URL(u, 'http://x').searchParams.get('date') ?? '';
        asked.push(date);
        return new Response(JSON.stringify(journal(date)), { status: 200 });
      }
      if (u.endsWith('/reschedule')) {
        reschedules.push({ url: u, body: JSON.parse(String(init?.body)) });
        return new Response('{}', { status: 200 });
      }
      return new Response('{}', { status: 404 });
    }),
  );
});

afterEach(() => {
  vi.useRealTimers();
  cleanup();
  vi.unstubAllGlobals();
  window.history.replaceState(null, '', '/');
  // @ts-expect-error — restore jsdom's absent matchMedia
  delete window.matchMedia;
});

async function openWeek(path = '/pro/rendez-vous') {
  window.history.replaceState(null, '', path);
  render(<RendezVousClient />);
  fireEvent.click(await screen.findByRole('button', { name: 'Semaine' }));
  return screen.findByRole('table', { name: /^Semaine du / });
}

const WEEK = ['2026-10-19', '2026-10-20', '2026-10-21', '2026-10-22', '2026-10-23', '2026-10-24', '2026-10-25'];

describe('the « Semaine » tab', () => {
  it('seven days, Monday first, read in one go — and the week named', async () => {
    const grid = await openWeek();
    expect(grid).toHaveAccessibleName('Semaine du 19 octobre');
    const headers = within(grid).getAllByRole('columnheader');
    expect(headers.map((h) => h.textContent)).toEqual([
      'Lun 19', 'Mar 20', 'Mer 21', 'Jeu 22', 'Ven 23', 'Sam 24', 'Dim 25',
    ]);
    await waitFor(() => expect(WEEK.every((d) => asked.includes(d))).toBe(true));
  });

  it('a closed day says « Fermé »', async () => {
    const grid = await openWeek();
    expect(await within(grid).findByText('Fermé')).toBeInTheDocument();
  });

  it('simultaneous bookings side by side, each naming its artist, its day and its time', async () => {
    const grid = await openWeek();
    expect(
      await within(grid).findByRole('button', { name: 'Koffi, Confirmé — Awa, Lun 19 à 09:00' }),
    ).toBeInTheDocument();
    expect(
      within(grid).getByRole('button', { name: 'Aminata, Confirmé — Mia, Lun 19 à 09:30' }),
    ).toBeInTheDocument();
  });

  it('‹ › change the week, « Cette semaine » comes back — the address follows', async () => {
    await openWeek();
    fireEvent.click(screen.getByRole('button', { name: 'Semaine suivante' }));
    expect(await screen.findByRole('table', { name: 'Semaine du 26 octobre' })).toBeInTheDocument();
    await waitFor(() => expect(asked).toContain('2026-11-01'));
    expect(window.location.search).toBe('?vue=semaine&jour=2026-10-28');
    fireEvent.click(screen.getByRole('button', { name: 'Cette semaine' }));
    expect(await screen.findByRole('table', { name: 'Semaine du 19 octobre' })).toBeInTheDocument();
    expect(window.location.search).toBe('?vue=semaine');
  });

  it('← / → move by a week', async () => {
    await openWeek();
    fireEvent.keyDown(window, { key: 'ArrowLeft' });
    expect(await screen.findByRole('table', { name: 'Semaine du 12 octobre' })).toBeInTheDocument();
  });

  it('the « Artiste » filter keeps one artist', async () => {
    const grid = await openWeek();
    await within(grid).findByRole('button', { name: /^Koffi/ });
    fireEvent.change(screen.getByLabelText('Artiste'), { target: { value: 'ar2' } });
    expect(within(grid).queryByRole('button', { name: /^Koffi/ })).toBeNull();
    expect(within(grid).getByRole('button', { name: /^Aminata/ })).toBeInTheDocument();
  });

  it('a booking opens the Journée’s panel', async () => {
    const grid = await openWeek();
    fireEvent.click(await within(grid).findByRole('button', { name: /^Koffi/ }));
    expect(await screen.findByRole('dialog', { name: 'Détails du rendez-vous' })).toBeInTheDocument();
  });

  it('a click in a day’s empty space opens « Nouveau rendez-vous »', async () => {
    const grid = await openWeek();
    fireEvent.click(await within(grid).findByRole('button', { name: 'Créer un rendez-vous — Mar 20' }));
    expect(await screen.findByRole('dialog', { name: 'Nouveau rendez-vous' })).toBeInTheDocument();
  });

  it('a booking dropped on another day is moved there — the artist kept', async () => {
    const grid = await openWeek();
    const koffi = await within(grid).findByRole('button', { name: /^Koffi/ });
    fireEvent.dragStart(koffi, { dataTransfer: { setData: () => {}, getData: () => 'pj-mon' } });
    fireEvent.drop(within(grid).getByRole('button', { name: 'Créer un rendez-vous — Jeu 22' }), {
      dataTransfer: { getData: () => 'pj-mon' },
    });
    await waitFor(() => expect(reschedules).toHaveLength(1));
    expect(reschedules[0].url).toBe('/api/pro/appointments/pj-mon/reschedule');
    expect(String(reschedules[0].body.newDateTime)).toMatch(/^2026-10-22T/);
    expect(reschedules[0].body.artistId).toBeUndefined();
  });

  it('nothing this week: it says so, and the grid stays to create', async () => {
    empty = true;
    const grid = await openWeek();
    expect(await screen.findByText('Aucun rendez-vous cette semaine.')).toBeInTheDocument();
    expect(within(grid).getByRole('button', { name: 'Créer un rendez-vous — Lun 19' })).toBeInTheDocument();
  });

  it('a Collaborateur reads their week: nothing to create, nothing to drag', async () => {
    me = { ...OWNER_ME, membership: { role: 'staff', capabilities: ['journal.view.own', 'journal.manage.own'] } };
    const grid = await openWeek();
    const koffi = await within(grid).findByRole('button', { name: /^Koffi/ });
    expect(koffi).not.toHaveAttribute('draggable', 'true');
    expect(within(grid).queryByRole('button', { name: /^Créer un rendez-vous/ })).toBeNull();
  });

  it('on a phone there is no « Semaine »; its address opens the Journée', async () => {
    window.matchMedia = ((q: string) => ({
      matches: false,
      media: q,
      addEventListener: () => {},
      removeEventListener: () => {},
    })) as unknown as typeof window.matchMedia;
    window.history.replaceState(null, '', '/pro/rendez-vous?vue=semaine&jour=2026-10-20');
    render(<RendezVousClient />);
    expect(await screen.findByRole('button', { name: 'Journée' })).toBeInTheDocument();
    await waitFor(() => expect(screen.queryByRole('button', { name: 'Semaine' })).toBeNull());
    await waitFor(() => expect(asked).toContain('2026-10-20'));
    expect(screen.queryByRole('table', { name: /^Semaine du / })).toBeNull();
  });
});
