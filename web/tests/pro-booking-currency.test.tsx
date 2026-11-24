import { cleanup, render, screen, within } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
// Stable object: the pages' load callbacks depend on [router].
const routerMock = { replace, push: vi.fn() };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { ClientCardClient } from '../components/pro/ClientCardClient';
import { JournalGrid } from '../components/pro/JournalGrid';
import { JournalPanel } from '../components/pro/JournalPanel';
import { ProAppointmentDetailClient } from '../components/pro/ProAppointmentDetailClient';
import { ProAppointmentRow } from '../components/pro/ProAppointmentRow';
import { buildUserDataExport } from '../lib/account/export';
import type { Appointment } from '../lib/account/appointments';
import type { ProProfile } from '../lib/api/pro';
import { formatFcfa } from '../lib/format';
import { buildProviderDataExport } from '../lib/pro/export';
import type { SalonClientCard } from '../lib/pro/clients';
import type { JournalDay } from '../lib/pro/journal';
import type { ProAppointment } from '../lib/pro/today';

/// Each booking's amount is in the currency the booking was made in, on every
/// espace-pro view that shows ONE booking, and in both data exports
/// (docs/design/appointment-currency-stamp.md §5.6–§5.7, decision 189, B14.4).
///
/// The server stores each booking's `currency` since migration 0047 (B14.1)
/// and refuses one without it since 0049 (B14.2). These views read the
/// salon's CURRENT currency instead, so the day a salon changes currency its
/// past bookings would be re-priced in the new one.
///
/// **`EUR`, never `XAF`.** The salon is XOF, and `formatFcfa` prints « FCFA »
/// for both XOF and XAF: an XAF stamp would render the same text either way.
///
/// **Every test checks a currency-blind control first** — the amount's digits
/// are on screen — so a missing « EUR » can only mean the wrong currency,
/// never a booking that was not rendered.

const eur = (n: number) => formatFcfa(n, 'EUR');
/// « 15 000 » alone (the thousands separator is Intl's narrow no-break space).
const digits = (n: number) => eur(n).split(' ')[0];
/// Testing Library collapses every whitespace — Intl's narrow no-break space
/// included — before a text matcher sees it; the expected side must be
/// collapsed the same way, or it never matches (raw `textContent` keeps it).
const norm = (s: string) => s.replace(/\s+/g, ' ').trim();
const has = (s: string) => (t: string) => t.includes(norm(s));

const STAMPED: ProAppointment = {
  id: 'a_eur',
  status: 'confirmed',
  appointmentDate: '2026-11-24T10:00:00.000Z',
  clientDisplayName: 'Aminata',
  serviceIds: ['s1'],
  totalPrice: 15000,
  depositAmount: 4500,
  durationMinutes: 60,
  artistId: 'artist-a',
  currency: 'EUR',
};

const PROVIDER = {
  id: 'p1',
  name: 'Beauté Divine',
  status: 'active',
  countryCode: 'CI',
  timezone: 'Africa/Abidjan',
  currency: 'XOF',
  services: [{ id: 's1', name: 'Tresses' }],
  artists: [{ id: 'artist-a', name: 'Awa' }],
};
const ME = {
  account: { id: 'acc-1', businessName: 'Beauté Divine', phoneNumber: '+2250700000000' },
  provider: PROVIDER,
};

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
});

describe('the espace pro: one booking, its own currency', () => {
  it('a booking row (Aujourd’hui, Rendez-vous)', () => {
    render(
      <ProAppointmentRow
        appt={STAMPED}
        serviceName={() => 'Tresses'}
        tz="Africa/Abidjan"
        currency="XOF"
      />,
    );
    expect(
      screen.getByText(has(digits(15000))),
      'the control: the booking’s amount is on screen',
    ).toBeInTheDocument();
    expect(
      screen.queryByText(has(eur(15000))),
      'the row prices the booking in EUR',
    ).not.toBeNull();
  });

  it('the « Journée » panel: total and announced deposit', () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response('{}', { status: 404 })));
    render(
      <JournalPanel
        providerId="p1"
        appt={STAMPED}
        membership={null}
        serviceName={() => 'Tresses'}
        onClose={() => {}}
        onChanged={() => {}}
        onToast={() => {}}
        tz="Africa/Abidjan"
        currency="XOF"
      />,
    );
    const panel = screen.getByRole('dialog', { name: 'Détails du rendez-vous' });
    const total = within(panel).getByText('Total');
    expect(
      total.nextElementSibling?.textContent,
      'the control: the total is on screen',
    ).toContain(digits(15000));
    expect(total.nextElementSibling?.textContent, 'the total').toBe(eur(15000));
    expect(
      within(panel).getByText('Acompte annoncé').nextElementSibling?.textContent,
      'the deposit',
    ).toBe(eur(4500));
  });

  it('the « Journée » grid: a block’s price', () => {
    const day: JournalDay = {
      date: '2026-11-24',
      hours: { open: '08:00', close: '20:00', breaks: [] },
      artists: [{ id: 'artist-a', name: 'Awa' }],
      appointments: [STAMPED],
    };
    render(
      <JournalGrid
        providerId="p1"
        day={day}
        profile={ME as unknown as ProProfile}
        onChanged={() => {}}
        onToast={() => {}}
      />,
    );
    expect(
      screen.getByText(has(digits(15000))),
      'the control: the block’s price is on screen',
    ).toBeInTheDocument();
    expect(
      screen.queryByText(has(eur(15000))),
      'the block prices the booking in EUR',
    ).not.toBeNull();
  });

  it('the booking’s page: total and announced deposit', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) => {
        const u = String(url);
        if (u === '/api/pro/me') return new Response(JSON.stringify(ME), { status: 200 });
        if (u === '/api/pro/appointments') {
          return new Response(JSON.stringify({ items: [STAMPED] }), { status: 200 });
        }
        return new Response('{}', { status: 404 });
      }),
    );
    render(<ProAppointmentDetailClient id="a_eur" />);
    const total = await screen.findByText('Total');
    expect(
      total.nextElementSibling?.textContent,
      'the control: the total is on screen',
    ).toContain(digits(15000));
    expect(total.nextElementSibling?.textContent, 'the total').toBe(eur(15000));
    expect(
      screen.getByText('Acompte annoncé').nextElementSibling?.textContent,
      'the deposit',
    ).toBe(eur(4500));
  });

  it('the client card: each visit in its own currency', async () => {
    const CARD: SalonClientCard = {
      id: 'sc1',
      displayName: 'Koffi',
      phone: '+2250700000101',
      tags: [],
      lastVisitAt: null,
      linked: false,
      createdAt: '2026-10-01T09:00:00.000Z',
      stats: { visits: 1, spentFcfa: 15000, noShows: 0, cancellations: 0 },
      notes: [],
    };
    // A price no other figure on the card holds, for the control.
    const visit = { ...STAMPED, status: 'completed', totalPrice: 123456 };
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) => {
        const u = String(url);
        if (u === '/api/pro/me') return new Response(JSON.stringify(ME), { status: 200 });
        if (u.startsWith('/api/pro/clients/sc1/visits')) {
          return new Response(JSON.stringify({ items: [visit], total: 1 }), { status: 200 });
        }
        if (u.startsWith('/api/pro/clients/sc1')) {
          return new Response(JSON.stringify(CARD), { status: 200 });
        }
        return new Response('{}', { status: 404 });
      }),
    );
    render(<ClientCardClient clientId="sc1" />);
    expect(
      await screen.findByText(has(digits(123456))),
      'the control: the visit row is on screen',
    ).toBeInTheDocument();
    expect(
      screen.queryByText(has(eur(123456))),
      'the visit is priced in the booking’s currency',
    ).not.toBeNull();
  });
});

describe('the data exports: each booking row carries its currency', () => {
  it('the client’s export (the stamp, else the salon’s) — as the app’s', () => {
    const doc = buildUserDataExport({
      me: { id: 'u1' },
      appointments: [
        {
          id: 'stamped',
          providerId: 'p1',
          appointmentDate: '2026-12-01T09:00:00.000Z',
          status: 'confirmed',
          totalPrice: 15000,
          currency: 'EUR',
          providerCurrency: 'XOF',
        },
        {
          id: 'older',
          providerId: 'p1',
          appointmentDate: '2026-12-02T09:00:00.000Z',
          status: 'confirmed',
          totalPrice: 15000,
          providerCurrency: 'XAF',
        },
      ] as Appointment[],
      favoriteProviderNames: [],
    });
    const rows = doc.appointments as Record<string, unknown>[];
    expect(rows[0].currency, 'the stamp wins').toBe('EUR');
    expect(rows[1].currency, 'no stamp: the salon’s').toBe('XAF');
  });

  it('the salon’s export (the stamp, else the salon’s) — as the app’s', () => {
    const doc = buildProviderDataExport({
      profile: ME as unknown as ProProfile,
      appointments: [
        { ...STAMPED, id: 'stamped' },
        { ...STAMPED, id: 'older', currency: undefined },
      ],
      clients: [],
      earnings: { totalEarnings: 0, transactions: [] as never[] },
    });
    const rows = doc.appointments as Record<string, unknown>[];
    expect(rows[0].currency, 'the stamp wins').toBe('EUR');
    expect(rows[1].currency, 'no stamp: the salon’s').toBe('XOF');
  });
});
