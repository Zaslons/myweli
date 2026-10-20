import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
// Stable object: the load effects depend on [router].
const routerMock = { replace, push: vi.fn(), refresh: vi.fn() };
/// What the router reports. `null`: the live address, as Next's does once it
/// has followed a `history.replaceState` (14.1+). A string: a router that has
/// not caught up yet — Next's sync is a transition, so it can lag the page.
const routerState = { query: null as string | null };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  useSearchParams: () =>
    new URLSearchParams(routerState.query ?? window.location.search),
}));

import { ProAppointmentDetailClient } from '../components/pro/ProAppointmentDetailClient';
import { RendezVousClient } from '../components/pro/RendezVousClient';
import type { ProAppointment } from '../lib/pro/today';

/// docs/design/web-pro-agenda-url.md — the agenda keeps its view and day in
/// the address. Before: every way to a booking left the page, and every way
/// back (« ← Rendez-vous », the browser's Back, a reload) remounted it on
/// today's Journée — the salon looking at next Tuesday, or at its « En
/// attente », started over. The app keeps the day for the session
/// (`ProJournalProvider._selectedDate`) and pops back onto it.

// The fixture salon is in Abidjan (UTC), so its day is the UTC day.
const TODAY = new Date().toISOString().slice(0, 10);
const plusDays = (key: string, n: number) => {
  const d = new Date(`${key}T12:00:00.000Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
};
const TOMORROW = plusDays(TODAY, 1);
const DAY = '2026-10-25';

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

const PENDING: ProAppointment = {
  id: 'a1',
  status: 'pending',
  appointmentDate: `${TOMORROW}T10:00:00.000Z`,
  clientDisplayName: 'Aminata',
  serviceIds: ['s1'],
  totalPrice: 15000,
};

/// Every Journée date asked for, in order.
const asked: string[] = [];

function mockFetch(list: ProAppointment[] = [PENDING]) {
  asked.length = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      const u = String(url);
      if (u === '/api/pro/me') {
        return new Response(JSON.stringify(ME), { status: 200 });
      }
      if (u === '/api/pro/appointments') {
        return new Response(JSON.stringify({ items: list }), { status: 200 });
      }
      if (u.startsWith('/api/pro/journal?')) {
        const date = new URL(u, 'http://x').searchParams.get('date') ?? '';
        asked.push(date);
        return new Response(
          JSON.stringify({
            date,
            hours: { open: '09:00', close: '18:00', breaks: [] },
            artists: [{ id: 'ar1', name: 'Awa', imageUrl: null }],
            appointments: [
              {
                id: 'pj1',
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

/// The address the page was opened at.
function openAt(path: string) {
  window.history.replaceState(null, '', path);
}

const search = () => window.location.search;

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
  routerState.query = null;
  window.history.replaceState(null, '', '/');
});

describe('the agenda reads its address', () => {
  it('a bare address is today’s Journée, and stays bare', async () => {
    mockFetch();
    openAt('/pro/rendez-vous');
    render(<RendezVousClient />);
    await screen.findByRole('button', { name: /Koffi/ });
    expect(asked).toEqual([TODAY]);
    expect(screen.getByLabelText('Date')).toHaveValue(TODAY);
    expect(search()).toBe('');
  });

  it('?jour= opens the Journée on that day — the first request is for it, not for today', async () => {
    mockFetch();
    openAt(`/pro/rendez-vous?jour=${DAY}`);
    render(<RendezVousClient />);
    await screen.findByRole('button', { name: /Koffi/ });
    expect(asked).toEqual([DAY]);
    expect(screen.getByLabelText('Date')).toHaveValue(DAY);
    expect(search()).toBe(`?jour=${DAY}`);
  });

  it('?vue=liste&filtre=en-attente opens the Liste on « En attente »', async () => {
    mockFetch();
    openAt('/pro/rendez-vous?vue=liste&filtre=en-attente');
    render(<RendezVousClient />);
    expect(await screen.findByRole('button', { name: 'Liste' })).toHaveAttribute(
      'aria-pressed',
      'true',
    );
    expect(screen.getByRole('button', { name: 'En attente' })).toHaveAttribute(
      'aria-pressed',
      'true',
    );
    expect(screen.getByText(/Aminata/)).toBeInTheDocument();
  });

  it('?vue=calendrier&jour= opens the Calendrier on that day', async () => {
    mockFetch();
    openAt(`/pro/rendez-vous?vue=calendrier&jour=${DAY}`);
    render(<RendezVousClient />);
    expect(await screen.findByRole('button', { name: 'Calendrier' })).toHaveAttribute(
      'aria-pressed',
      'true',
    );
    expect(screen.getByText('pour 25 octobre 2026')).toBeInTheDocument();
    // The Journée was never asked for: it is not the view on screen.
    expect(asked).toEqual([]);
  });

  it('a wrong address opens today’s Journée and is written back clean', async () => {
    mockFetch();
    openAt('/pro/rendez-vous?jour=2026-02-30&vue=annee&filtre=x'); // « semaine » is a view now
    render(<RendezVousClient />);
    await screen.findByRole('button', { name: /Koffi/ });
    expect(asked).toEqual([TODAY]);
    await waitFor(() => expect(search()).toBe(''));
  });
});

describe('the agenda writes its address — replaced, never stacked', () => {
  it('› writes ?jour=, without a history entry (Back must leave the page, not walk the days)', async () => {
    mockFetch();
    openAt('/pro/rendez-vous');
    render(<RendezVousClient />);
    await screen.findByRole('button', { name: /Koffi/ });
    const entries = window.history.length;

    fireEvent.click(screen.getByRole('button', { name: 'Jour suivant' }));
    await waitFor(() => expect(search()).toBe(`?jour=${TOMORROW}`));
    fireEvent.click(screen.getByRole('button', { name: 'Jour suivant' }));
    await waitFor(() => expect(search()).toBe(`?jour=${plusDays(TODAY, 2)}`));
    expect(window.history.length).toBe(entries);
  });

  it('back to today is the bare address again (« aujourd’hui » stays relative)', async () => {
    mockFetch();
    openAt(`/pro/rendez-vous?jour=${DAY}`);
    render(<RendezVousClient />);
    await screen.findByRole('button', { name: /Koffi/ });
    fireEvent.click(screen.getByRole('button', { name: 'Aujourd’hui' }));
    await waitFor(() => expect(search()).toBe(''));
  });

  it('the date field and the view tabs write it too', async () => {
    mockFetch();
    openAt('/pro/rendez-vous');
    render(<RendezVousClient />);
    await screen.findByRole('button', { name: /Koffi/ });

    fireEvent.change(screen.getByLabelText('Date'), { target: { value: DAY } });
    await waitFor(() => expect(search()).toBe(`?jour=${DAY}`));

    fireEvent.click(screen.getByRole('button', { name: 'Liste' }));
    await waitFor(() => expect(search()).toBe('?vue=liste'));
    fireEvent.click(screen.getByRole('button', { name: 'Tous' }));
    await waitFor(() => expect(search()).toBe('?vue=liste&filtre=tous'));

    fireEvent.click(screen.getByRole('button', { name: 'Calendrier' }));
    await waitFor(() => expect(search()).toBe('?vue=calendrier'));
  });
});

describe('a navigation to this same page from elsewhere', () => {
  /// Found by the e2e, not by this suite: Next's <Link> to the SAME route —
  /// the menu's « Rendez-vous » from `?jour=…` — changes the address and does
  /// NOT remount the page. The address went bare while the screen kept the
  /// dated day: the two disagreed. (jsdom has no router, so the model here is
  /// the address changing under a page that re-renders without remounting.)
  it('the menu’s « Rendez-vous » (the bare address) shows today’s Journée', async () => {
    mockFetch();
    openAt(`/pro/rendez-vous?jour=${DAY}`);
    const { rerender } = render(<RendezVousClient />);
    await screen.findByRole('button', { name: /Koffi/ });
    expect(screen.getByLabelText('Date')).toHaveValue(DAY);

    openAt('/pro/rendez-vous');
    rerender(<RendezVousClient />);
    await waitFor(() => expect(screen.getByLabelText('Date')).toHaveValue(TODAY));
    expect(search()).toBe('');
    await waitFor(() => expect(asked.at(-1)).toBe(TODAY));
  });

  it('a link to another view of this page opens it', async () => {
    mockFetch();
    openAt('/pro/rendez-vous');
    const { rerender } = render(<RendezVousClient />);
    await screen.findByRole('button', { name: /Koffi/ });

    openAt('/pro/rendez-vous?vue=liste&filtre=en-attente');
    rerender(<RendezVousClient />);
    await waitFor(() =>
      expect(screen.getByRole('button', { name: 'En attente' })).toHaveAttribute(
        'aria-pressed',
        'true',
      ),
    );
    expect(search()).toBe('?vue=liste&filtre=en-attente');
  });

  it('the page’s OWN writes are not mistaken for one (no loop, no revert)', async () => {
    mockFetch();
    openAt('/pro/rendez-vous');
    const { rerender } = render(<RendezVousClient />);
    await screen.findByRole('button', { name: /Koffi/ });
    fireEvent.click(screen.getByRole('button', { name: 'Jour suivant' }));
    await waitFor(() => expect(search()).toBe(`?jour=${TOMORROW}`));
    rerender(<RendezVousClient />);
    rerender(<RendezVousClient />);
    expect(screen.getByLabelText('Date')).toHaveValue(TOMORROW);
    expect(search()).toBe(`?jour=${TOMORROW}`);
  });

  it('two quick › — the router reports the first write AFTER the second: still not a navigation', async () => {
    // Next's sync is a transition: the router can still say the FIRST day
    // when the page is already on the second. Taken for a navigation, that
    // late echo would put the grid back one day under the salon's finger.
    mockFetch();
    openAt('/pro/rendez-vous');
    const { rerender } = render(<RendezVousClient />);
    await screen.findByRole('button', { name: /Koffi/ });
    const twoDays = plusDays(TODAY, 2);

    routerState.query = ''; // the router has not caught up with anything yet
    fireEvent.click(screen.getByRole('button', { name: 'Jour suivant' }));
    fireEvent.click(screen.getByRole('button', { name: 'Jour suivant' }));
    await waitFor(() => expect(search()).toBe(`?jour=${twoDays}`));

    // After EACH step, not only at the end: a revert put right by the next
    // echo is still a day the salon saw jump back.
    for (const late of [`?jour=${TOMORROW}`, `?jour=${twoDays}`, null]) {
      routerState.query = late;
      rerender(<RendezVousClient />);
      expect(screen.getByLabelText('Date'), `router at ${late}`).toHaveValue(twoDays);
      expect(search(), `router at ${late}`).toBe(`?jour=${twoDays}`);
    }
  });
});

describe('the way to a booking carries the agenda, so the way back can return to it', () => {
  it('the Liste’s rows', async () => {
    mockFetch();
    openAt('/pro/rendez-vous?vue=liste&filtre=tous');
    render(<RendezVousClient />);
    await screen.findByText(/Aminata/);
    expect(document.querySelector('a[href^="/pro/rendez-vous/a1"]')).toHaveAttribute(
      'href',
      '/pro/rendez-vous/a1?vue=liste&filtre=tous',
    );
  });

  it('the Journée panel’s « Voir le rendez-vous »', async () => {
    mockFetch();
    openAt(`/pro/rendez-vous?jour=${DAY}`);
    render(<RendezVousClient />);
    fireEvent.click(await screen.findByRole('button', { name: /Koffi/ }));
    expect(screen.getByRole('link', { name: 'Voir le rendez-vous' })).toHaveAttribute(
      'href',
      `/pro/rendez-vous/pj1?jour=${DAY}`,
    );
  });

  it('today’s Journée carries nothing — the booking’s address stays plain', async () => {
    mockFetch();
    openAt('/pro/rendez-vous');
    render(<RendezVousClient />);
    fireEvent.click(await screen.findByRole('button', { name: /Koffi/ }));
    expect(screen.getByRole('link', { name: 'Voir le rendez-vous' })).toHaveAttribute(
      'href',
      '/pro/rendez-vous/pj1',
    );
  });
});

describe('« ← Rendez-vous » on the booking page goes back to the same agenda', () => {
  it('hands back the agenda’s own parameters — and nothing else', async () => {
    mockFetch([PENDING]);
    openAt(`/pro/rendez-vous/a1?jour=${DAY}&salon=p9`);
    render(<ProAppointmentDetailClient id="a1" />);
    expect(await screen.findByRole('link', { name: '← Rendez-vous' })).toHaveAttribute(
      'href',
      `/pro/rendez-vous?jour=${DAY}`,
    );
  });

  it('drops a bad value, keeps the good ones', async () => {
    mockFetch([PENDING]);
    openAt('/pro/rendez-vous/a1?jour=nope&vue=liste&filtre=tous');
    render(<ProAppointmentDetailClient id="a1" />);
    expect(await screen.findByRole('link', { name: '← Rendez-vous' })).toHaveAttribute(
      'href',
      '/pro/rendez-vous?vue=liste&filtre=tous',
    );
  });

  it('opened from elsewhere (no parameters): today’s Journée, as before', async () => {
    mockFetch([PENDING]);
    openAt('/pro/rendez-vous/a1');
    render(<ProAppointmentDetailClient id="a1" />);
    expect(await screen.findByRole('link', { name: '← Rendez-vous' })).toHaveAttribute(
      'href',
      '/pro/rendez-vous',
    );
  });

  it('« Rendez-vous introuvable. » too', async () => {
    mockFetch([]);
    openAt(`/pro/rendez-vous/zz?vue=calendrier&jour=${DAY}`);
    render(<ProAppointmentDetailClient id="zz" />);
    await screen.findByText('Rendez-vous introuvable.');
    expect(screen.getByRole('link', { name: '← Rendez-vous' })).toHaveAttribute(
      'href',
      `/pro/rendez-vous?vue=calendrier&jour=${DAY}`,
    );
  });
});
