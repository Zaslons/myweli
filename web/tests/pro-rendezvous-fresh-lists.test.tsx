import { act, cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn(), refresh: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  useSearchParams: () => new URLSearchParams(window.location.search),
}));

import { RendezVousClient } from '../components/pro/RendezVousClient';

/// docs/design/web-pro-truthful-failure.md §2.2 (B4.2) — « Calendrier » and
/// « Liste » follow what the Journée and the Semaine did. Before: a booking
/// accepted, finished or created there stayed in its OLD state in those two
/// views until a reload — they draw the appointments read once, at load. Now
/// every change re-reads the open view AND that list, and an older list
/// answer never lands over a newer one (the Journée's request-id model).

const SERVICE = {
  id: 's1',
  name: 'Tresses',
  description: '',
  price: 15000,
  durationMinutes: 60,
  providerId: 'p1',
  active: true,
};
const ME = {
  account: { id: 'acc1', businessName: 'Beauté Divine', phoneNumber: '+2250700000000' },
  provider: {
    id: 'p1',
    name: 'Beauté Divine',
    status: 'active',
    timezone: 'Africa/Abidjan',
    currency: 'XOF',
    services: [SERVICE],
    artists: [{ id: 'ar1', name: 'Awa' }],
  },
};

// A Wednesday; the salon is in Abidjan (UTC), so its day is the UTC day.
const TODAY = '2026-10-21';

/// The server: Koffi's booking today at 10:00, and what « Créer » added.
let koffi = 'pending';
let created: ReturnType<typeof booking>[] = [];
const booking = (id: string, date: string, time: string, client: string, status: string) => ({
  id,
  status,
  appointmentDate: `${date}T${time}:00.000Z`,
  clientDisplayName: client,
  serviceIds: ['s1'],
  totalPrice: 15000,
  artistId: 'ar1',
  durationMinutes: 60,
});
const everything = () => [booking('pj1', TODAY, '10:00', 'Koffi', koffi), ...created];

/// GET /api/pro/appointments: how many times it was asked, and the answers
/// held back (the next one asked, when `holdNext`) — each the server's state
/// WHEN it was asked.
let listAsked = 0;
let holdNext = false;
const held: (() => void)[] = [];
const journalAsked: string[] = [];

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date(`${TODAY}T12:00:00.000Z`));
  koffi = 'pending';
  created = [];
  listAsked = 0;
  holdNext = false;
  held.length = 0;
  journalAsked.length = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const u = String(url);
      const method = init?.method ?? 'GET';
      if (u === '/api/pro/me') return new Response(JSON.stringify(ME), { status: 200 });
      if (u === '/api/pro/appointments' && method === 'GET') {
        listAsked += 1;
        const body = JSON.stringify({ items: everything() });
        const answer = () => new Response(body, { status: 200 });
        if (holdNext) {
          holdNext = false;
          return new Promise<Response>((resolve) => held.push(() => resolve(answer())));
        }
        return answer();
      }
      if (u === '/api/pro/appointments' && method === 'POST') {
        const b = JSON.parse(String(init?.body));
        const at = String(b.appointmentDateTime);
        const made = booking(`new${created.length + 1}`, at.slice(0, 10), at.slice(11, 16), b.clientName, 'confirmed');
        created.push(made);
        return new Response(JSON.stringify(made), { status: 201 });
      }
      if (u === '/api/pro/appointments/pj1/accept') {
        koffi = 'confirmed';
        return new Response('{}', { status: 200 });
      }
      if (u === '/api/pro/appointments/pj1/complete') {
        koffi = 'completed';
        return new Response('{}', { status: 200 });
      }
      if (u.startsWith('/api/pro/journal?')) {
        const date = new URL(u, 'http://x').searchParams.get('date') ?? '';
        journalAsked.push(date);
        return new Response(
          JSON.stringify({
            date,
            hours: { open: '09:00', close: '18:00', breaks: [] },
            artists: [{ id: 'ar1', name: 'Awa', imageUrl: null }],
            appointments: everything().filter((a) => a.appointmentDate.startsWith(date)),
          }),
          { status: 200 },
        );
      }
      return new Response('{}', { status: 404 });
    }),
  );
});

afterEach(() => {
  vi.useRealTimers();
  cleanup();
  vi.unstubAllGlobals();
  routerMock.replace.mockReset();
  window.history.replaceState(null, '', '/');
});

/// The row « Liste » draws for a client (a link to the booking).
const listRow = (client: string) => screen.findByRole('link', { name: new RegExp(client) });

async function openJournee() {
  window.history.replaceState(null, '', '/pro/rendez-vous');
  render(<RendezVousClient />);
  return screen.findByRole('button', { name: /^Koffi, En attente/ });
}

async function act_(block: HTMLElement, action: string) {
  fireEvent.click(block);
  const panel = await screen.findByRole('dialog', { name: 'Détails du rendez-vous' });
  fireEvent.click(within(panel).getByRole('button', { name: action }));
}

describe('« Calendrier » and « Liste » follow the Journée and the Semaine (B4.2)', () => {
  it('« Accepter » in the Journée → the list is read again, and « Liste » says « Confirmé »', async () => {
    await act_(await openJournee(), 'Accepter');

    await waitFor(() => expect(listAsked).toBe(2));
    fireEvent.click(screen.getByRole('button', { name: 'Liste' }));
    expect((await listRow('Koffi')).textContent).toContain('Confirmé');

    fireEvent.click(screen.getByRole('button', { name: 'En attente' }));
    expect(await screen.findByText('Aucun rendez-vous')).toBeTruthy();
  });

  it('…and the « Calendrier »’s day list says it too', async () => {
    await act_(await openJournee(), 'Accepter');
    await waitFor(() => expect(listAsked).toBe(2));

    fireEvent.click(screen.getByRole('button', { name: 'Calendrier' }));
    expect((await listRow('Koffi')).textContent).toContain('Confirmé');
  });

  it('« Accepter » in the Semaine → the list is read again, and « Liste » says « Confirmé »', async () => {
    window.history.replaceState(null, '', '/pro/rendez-vous');
    render(<RendezVousClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Semaine' }));
    const grid = await screen.findByRole('table', { name: /^Semaine du / });

    await act_(await within(grid).findByRole('button', { name: /^Koffi, En attente/ }), 'Accepter');

    await waitFor(() => expect(listAsked).toBe(2));
    fireEvent.click(screen.getByRole('button', { name: 'Liste' }));
    expect((await listRow('Koffi')).textContent).toContain('Confirmé');
  });

  it('an OLDER list answer arriving last never lands over the newer one', async () => {
    // « Accepter » — its list answer is held — then « Terminé », whose answer
    // comes at once. The held one (« Confirmé ») then arrives: ignored.
    const block = await openJournee();
    holdNext = true;
    await act_(block, 'Accepter');
    await waitFor(() => expect(held).toHaveLength(1));

    await act_(await screen.findByRole('button', { name: /^Koffi, Confirmé/ }), 'Terminé');
    await waitFor(() => expect(listAsked).toBe(3));
    await act(async () => {
      held[0]();
    });

    fireEvent.click(screen.getByRole('button', { name: 'Liste' }));
    const row = await listRow('Koffi');
    await waitFor(() => expect(row.textContent).toContain('Terminé'));
    expect(row.textContent).not.toContain('Confirmé');
  });

  it('« + Nouveau rendez-vous » from the Semaine → the week is read again (the new booking in its grid) and the list too', async () => {
    window.history.replaceState(null, '', '/pro/rendez-vous');
    render(<RendezVousClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Semaine' }));
    await screen.findByRole('table', { name: /^Semaine du / });
    const weeksBefore = journalAsked.length;

    fireEvent.click(screen.getByRole('button', { name: '+ Nouveau rendez-vous' }));
    const dialog = within(screen.getByRole('dialog', { name: 'Nouveau rendez-vous' }));
    fireEvent.click(dialog.getByRole('checkbox', { name: /Tresses/ }));
    fireEvent.change(dialog.getByLabelText('Date du rendez-vous'), { target: { value: '2026-10-23' } });
    fireEvent.change(dialog.getByLabelText('Heure du rendez-vous'), { target: { value: '14:30' } });
    fireEvent.change(dialog.getByLabelText('Rechercher ou nommer le client'), { target: { value: 'Mariam' } });
    fireEvent.click(dialog.getByRole('checkbox', { name: 'Client sans numéro' }));
    fireEvent.click(dialog.getByRole('button', { name: 'Créer' }));

    await screen.findByText('Rendez-vous créé');
    await waitFor(() => expect(journalAsked.length).toBe(weeksBefore + 7));
    const grid = await screen.findByRole('table', { name: /^Semaine du / });
    expect(await within(grid).findByRole('button', { name: /^Mariam/ })).toBeTruthy();

    await waitFor(() => expect(listAsked).toBe(2));
    fireEvent.click(screen.getByRole('button', { name: 'Liste' }));
    fireEvent.click(screen.getByRole('button', { name: 'Tous' }));
    expect(await listRow('Mariam')).toBeTruthy();
  });
});
