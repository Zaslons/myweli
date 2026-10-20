import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn(), refresh: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  useSearchParams: () => new URLSearchParams(window.location.search),
}));

import { RendezVousClient } from '../components/pro/RendezVousClient';
import type { ProAppointment } from '../lib/pro/today';

/// docs/design/web-pro-week-strip.md — the app's « Ma journée » has the week
/// above the day (`_WeekStrip`: seven days, a dot that grows with the load, a
/// tap shows that day). The web Journée had ‹ date › and nothing else.

const ME = {
  account: { id: 'acc1', businessName: 'Beauté Divine', phoneNumber: '+2250700000000' },
  provider: {
    id: 'p1',
    name: 'Beauté Divine',
    status: 'active',
    timezone: 'Africa/Abidjan',
    currency: 'XOF',
    services: [{ id: 's1', name: 'Tresses' }],
    artists: [{ id: 'ar1', name: 'Awa' }],
  },
};

const appt = (id: string, iso: string, status = 'confirmed'): ProAppointment => ({
  id,
  status,
  appointmentDate: iso,
  clientDisplayName: 'Aminata',
  serviceIds: ['s1'],
  totalPrice: 15000,
});

/// The salon's list: three on Monday the 19th, one cancelled on Thursday.
const LIST = [
  appt('m1', '2026-10-19T09:00:00.000Z'),
  appt('m2', '2026-10-19T10:00:00.000Z', 'pending'),
  appt('m3', '2026-10-19T11:00:00.000Z'),
  appt('t1', '2026-10-22T09:00:00.000Z', 'cancelled'),
];

const asked: string[] = [];
let journalStatus = 200;

function mockFetch() {
  asked.length = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      const u = String(url);
      if (u === '/api/pro/me') return new Response(JSON.stringify(ME), { status: 200 });
      if (u === '/api/pro/appointments') {
        return new Response(JSON.stringify({ items: LIST }), { status: 200 });
      }
      if (u.startsWith('/api/pro/journal?')) {
        const date = new URL(u, 'http://x').searchParams.get('date') ?? '';
        asked.push(date);
        if (journalStatus !== 200) return new Response('{}', { status: journalStatus });
        return new Response(
          JSON.stringify({
            date,
            hours: { open: '09:00', close: '18:00', breaks: [] },
            artists: [{ id: 'ar1', name: 'Awa', imageUrl: null }],
            appointments: [
              {
                id: `pj-${date}`,
                status: 'confirmed',
                appointmentDate: `${date}T09:00:00.000Z`,
                clientDisplayName: 'Koffi',
                serviceIds: ['s1'],
                totalPrice: 15000,
                artistId: 'ar1',
                durationMinutes: 60,
              },
            ],
          }),
          { status: 200 },
        );
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

const strip = () => screen.findByRole('group', { name: /^Semaine du / });

// « Today » is pinned outside the fixture week (only Date is faked — the
// timers stay real, so waitFor still polls).
beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date('2026-11-10T12:00:00.000Z'));
});

afterEach(() => {
  vi.useRealTimers();
  cleanup();
  vi.unstubAllGlobals();
  journalStatus = 200;
  window.history.replaceState(null, '', '/');
});

describe('the Journée shows its week', () => {
  it('seven days, Monday first, the shown day pressed', async () => {
    window.history.replaceState(null, '', '/pro/rendez-vous?jour=2026-10-21');
    mockFetch();
    render(<RendezVousClient />);
    const group = await strip();
    expect(group).toHaveAccessibleName('Semaine du 19 octobre');
    const days = within(group).getAllByRole('button');
    expect(days).toHaveLength(7);
    expect(days[0]).toHaveTextContent(/^Lun\s*19/);
    expect(days[6]).toHaveTextContent(/^Dim\s*25/);
    await waitFor(() =>
      expect(within(group).getByRole('button', { pressed: true })).toHaveAccessibleName(
        /^Mer 21 octobre/,
      ),
    );
  });

  it('each day says how many — cancelled ones do not count', async () => {
    window.history.replaceState(null, '', '/pro/rendez-vous?jour=2026-10-21');
    mockFetch();
    render(<RendezVousClient />);
    const group = await strip();
    expect(
      within(group).getByRole('button', { name: 'Lun 19 octobre, 3\u00a0rendez-vous' }),
    ).toBeInTheDocument();
    // Thursday's only booking was cancelled: no dot, « aucun ».
    expect(
      within(group).getByRole('button', { name: 'Jeu 22 octobre, aucun rendez-vous' }),
    ).toBeInTheDocument();
    // The shown day counts its loaded day (pj-2026-10-21), not the list.
    await waitFor(() =>
      expect(
        within(group).getByRole('button', { name: 'Mer 21 octobre, 1\u00a0rendez-vous' }),
      ).toBeInTheDocument(),
    );
  });

  it('a click shows that day — the grid is read for it and the address follows', async () => {
    window.history.replaceState(null, '', '/pro/rendez-vous?jour=2026-10-21');
    mockFetch();
    render(<RendezVousClient />);
    const group = await strip();
    fireEvent.click(within(group).getByRole('button', { name: /^Ven 23 octobre/ }));
    await waitFor(() => expect(asked.at(-1)).toBe('2026-10-23'));
    expect(screen.getByLabelText('Date')).toHaveValue('2026-10-23');
    expect(window.location.search).toBe('?jour=2026-10-23');
    expect(within(group).getByRole('button', { pressed: true })).toHaveAccessibleName(
      /^Ven 23 octobre/,
    );
  });

  it('‹ on a Monday shows the week before', async () => {
    window.history.replaceState(null, '', '/pro/rendez-vous?jour=2026-10-19');
    mockFetch();
    render(<RendezVousClient />);
    expect(await strip()).toHaveAccessibleName('Semaine du 19 octobre');
    fireEvent.click(screen.getByRole('button', { name: 'Jour précédent' }));
    await waitFor(async () =>
      expect(await strip()).toHaveAccessibleName('Semaine du 12 octobre'),
    );
    expect(
      within(await strip()).getByRole('button', { pressed: true }),
    ).toHaveAccessibleName(/^Dim 18 octobre/);
  });

  it('the strip stays when the day cannot be read — another day is one click away', async () => {
    window.history.replaceState(null, '', '/pro/rendez-vous?jour=2026-10-21');
    journalStatus = 503;
    mockFetch();
    render(<RendezVousClient />);
    expect(await screen.findByRole('button', { name: 'Réessayer' })).toBeInTheDocument();
    const group = await strip();
    journalStatus = 200;
    fireEvent.click(within(group).getByRole('button', { name: /^Mar 20 octobre/ }));
    await waitFor(() => expect(asked.at(-1)).toBe('2026-10-20'));
  });

  it('today is named', async () => {
    window.history.replaceState(null, '', '/pro/rendez-vous');
    mockFetch();
    render(<RendezVousClient />);
    const group = await strip();
    expect(
      within(group).getByRole('button', { name: /, aujourd’hui$/ }),
    ).toHaveAttribute('aria-pressed', 'true');
  });

  it('only on the Journée', async () => {
    window.history.replaceState(null, '', '/pro/rendez-vous?vue=calendrier');
    mockFetch();
    render(<RendezVousClient />);
    await screen.findByTestId('month-grid');
    expect(screen.queryByRole('group', { name: /^Semaine du / })).toBeNull();
  });
});
