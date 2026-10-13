import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
// Stable object: the card's load callback depends on [router].
const routerMock = { replace };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { ClientCardClient } from '../components/pro/ClientCardClient';
import type { SalonClientCard } from '../lib/pro/clients';

/// The phone line of the Pro client card, `/pro/clients/[id]`
/// (docs/design/clients-c1.md §6; docs/design/amounts-that-fit.md §2 « Web »).
///
/// The card printed the stored E.164 number as it is kept — « +2250700000101 » —
/// where the app's card reads « +225 07 00 00 01 01 ». This is the first test
/// that renders `ClientCardClient` at all: `pro-clients.test.ts` covers the
/// link helpers and could not see what the card shows a person.
///
/// Two values travel side by side and must not be confused:
/// - what is **read** — grouped, by `formatPhoneNumber` (the app's twin);
/// - what is **used** — the stored number, untouched, in the three places that
///   act on it: `tel:`, `wa.me`, and the client handed to the manual-booking
///   dialog, where it becomes `clientPhone` in the POST. The third is the one
///   the server refuses when it is wrong (`invalid_phone`, a 400), and it was
///   the one with no guard: the review mutated it and every test stayed green.
///
/// **What this file cannot show:** jsdom has no layout, so « the number stays
/// on one line and the actions drop below it » is pinned here by its classes
/// only. The measurements — one rendered line, the dropped actions clear of
/// the number above and of the button below — are the reflow gate's
/// (`tests/e2e/type-overflow.spec.ts`, the client-card row's `setup`).

const CARD: SalonClientCard = {
  id: 'sc1',
  displayName: 'Koffi',
  phone: '+2250700000101',
  tags: ['VIP'],
  lastVisitAt: null,
  linked: false,
  createdAt: '2026-10-01T09:00:00.000Z',
  stats: { visits: 3, spentFcfa: 45000, noShows: 0, cancellations: 0 },
  notes: [],
};

/// One bookable service — only the dialog case needs it (« Créer » stays
/// disabled until a service is ticked). The shape is
/// `manual-booking-phone.test.tsx`'s.
const SERVICE = {
  id: 's1',
  name: 'Tresses',
  description: '',
  price: 15000,
  durationMinutes: 120,
  providerId: 'p1',
  active: true,
};

/// Every POST /api/pro/appointments body, in order.
const posted: Record<string, unknown>[] = [];

function mockFetch(card: SalonClientCard, services: unknown[] = []) {
  posted.length = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const u = String(url);
      if (u === '/api/pro/appointments') {
        posted.push(JSON.parse(String(init?.body ?? '{}')));
        return new Response('{}', { status: 200 });
      }
      if (u === '/api/pro/me') {
        return new Response(
          JSON.stringify({
            account: { id: 'acc-1', email: 'x@salon.test' },
            provider: {
              id: 'p1',
              name: 'Beauté Divine',
              status: 'active',
              timezone: 'Africa/Abidjan',
              currency: 'XOF',
              services,
            },
          }),
          { status: 200 },
        );
      }
      if (u.startsWith(`/api/pro/clients/${card.id}/visits`)) {
        return new Response(JSON.stringify({ items: [], total: 0 }), {
          status: 200,
        });
      }
      if (u.startsWith(`/api/pro/clients/${card.id}?`)) {
        return new Response(JSON.stringify(card), { status: 200 });
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

/// Renders the card and waits for the loaded state — the `<h1>` exists in no
/// other state (loading is a skeleton, the error state titles itself « Fiche
/// client »), so every assertion below is about the real card.
async function renderCard(card: SalonClientCard, services: unknown[] = []) {
  mockFetch(card, services);
  render(<ClientCardClient clientId={card.id} />);
  await screen.findByRole('heading', { level: 1, name: card.displayName });
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
});

describe('ClientCardClient — the phone line', () => {
  it('shows the Ivorian number grouped in pairs, not as stored', async () => {
    await renderCard(CARD);

    const number = screen.getByText('+225 07 00 00 01 01');
    // Exactly: RTL's matcher collapses whitespace, `textContent` does not.
    expect(number.textContent).toBe('+225 07 00 00 01 01');
    expect(screen.queryByText('+2250700000101')).toBeNull();
  });

  it('the links dial the STORED number — the grouping never reaches an href', async () => {
    await renderCard(CARD);

    expect(
      screen.getByRole('link', { name: 'Appeler' }).getAttribute('href'),
    ).toBe('tel:+2250700000101');
    expect(
      screen.getByRole('link', { name: 'WhatsApp' }).getAttribute('href'),
    ).toBe('https://wa.me/2250700000101');
  });

  it('« Nouveau rendez-vous » books with the STORED number — the grouping never reaches the POST', async () => {
    // The third consumer of the stored number, and the only one a server
    // refuses: the dialog sends its pre-picked client's phone as `clientPhone`,
    // and the backend answers 400 `invalid_phone` to anything that is not
    // E.164 (`^\+[1-9]\d{7,14}$` — « +225 07 00 00 01 01 » is not). Handing the
    // dialog the text the card SHOWS would fail every booking opened from an
    // Ivorian client's card, and no test said so: the e2e stub accepts any
    // phone, and `manual-booking-phone.test.tsx` renders the dialog on its
    // own, with a number it is given. This crosses the real seam — the card
    // opens the dialog, and the body that leaves is read.
    await renderCard(CARD, [SERVICE]);

    fireEvent.click(screen.getByRole('button', { name: 'Nouveau rendez-vous' }));
    const dialog = within(
      screen.getByRole('dialog', { name: 'Nouveau rendez-vous' }),
    );
    fireEvent.click(dialog.getByRole('checkbox', { name: /Tresses/ }));
    // A date no clock will reach while this test exists (the dialog refuses a
    // past one). The salon is in Abidjan, UTC+0: the wall clock IS the instant.
    fireEvent.change(dialog.getByLabelText('Date du rendez-vous'), {
      target: { value: '2099-01-15' },
    });
    fireEvent.change(dialog.getByLabelText('Heure du rendez-vous'), {
      target: { value: '14:30' },
    });
    fireEvent.click(dialog.getByRole('button', { name: 'Créer' }));

    await waitFor(() => expect(posted).toHaveLength(1));
    expect(posted[0].clientName).toBe('Koffi');
    expect(posted[0].appointmentDateTime).toBe('2099-01-15T14:30:00.000Z');
    expect(posted[0].clientPhone).toBe('+2250700000101');
    // The card answers a created booking by closing the dialog and saying so.
    await screen.findByText('Rendez-vous créé');
    expect(screen.queryByRole('dialog')).toBeNull();
  });

  it('the number may not wrap, and the row may — the actions drop below it', async () => {
    await renderCard(CARD);

    // Once grouped the number has five places a line could break. It is on the
    // may-not-break list (SYSTEM.md §13.3), and it is kept whole by CSS rather
    // than by no-break spaces so that a copied number pastes with plain ones.
    const number = screen.getByText('+225 07 00 00 01 01');
    expect(number.tagName).toBe('SPAN');
    expect(number.className.split(/\s+/)).toContain('whitespace-nowrap');
    // WEB-SYSTEM §9 rule 1: a row that cannot fit must wrap, not spill.
    const row = number.parentElement!;
    expect(row.className.split(/\s+/)).toContain('flex-wrap');
    expect(row.contains(screen.getByRole('link', { name: 'Appeler' }))).toBe(
      true,
    );
    expect(row.contains(screen.getByRole('link', { name: 'WhatsApp' }))).toBe(
      true,
    );
  });

  it('the two actions wrap as ONE unit, and the avatar keeps its width', async () => {
    await renderCard(CARD);

    // Both of these were measured once in a real browser while this was built
    // (headless Chromium over this component's markup and the compiled CSS),
    // and jsdom cannot repeat the measurement — so each is pinned by its class.
    //
    // 1. As three loose items the row broke between the two actions at 375px:
    //    « Appeler » stayed beside the number and « WhatsApp » dropped alone.
    //    They share a wrapper so they drop together.
    const call = screen.getByRole('link', { name: 'Appeler' });
    const whatsapp = screen.getByRole('link', { name: 'WhatsApp' });
    expect(call.parentElement).toBe(whatsapp.parentElement);
    expect(call.parentElement!.tagName).toBe('SPAN');
    expect(call.parentElement!.parentElement).toBe(
      screen.getByText('+225 07 00 00 01 01').parentElement,
    );
    // 2. A row that may wrap makes its column shrinkable, and the avatar
    //    beside it then gave up width too: 32.7 × 48 at 320px, an oval.
    const avatar = screen.getByText('K');
    expect(avatar.className.split(/\s+/)).toContain('shrink-0');
  });

  it('a non-Ivorian number is shown exactly as stored', async () => {
    // Gabon is a live market (+241). The app leaves every non-+225 number
    // alone, and so does the twin — a library that « formats every country »
    // would be a different rule from the app's.
    await renderCard({ ...CARD, phone: '+24177000000' });

    expect(screen.getByText('+24177000000').textContent).toBe('+24177000000');
    expect(
      screen.getByRole('link', { name: 'Appeler' }).getAttribute('href'),
    ).toBe('tel:+24177000000');
    expect(
      screen.getByRole('link', { name: 'WhatsApp' }).getAttribute('href'),
    ).toBe('https://wa.me/24177000000');
  });

  it('a client with no phone has no phone row at all', async () => {
    await renderCard({ ...CARD, phone: null });

    expect(screen.queryByRole('link', { name: 'Appeler' })).toBeNull();
    expect(screen.queryByRole('link', { name: 'WhatsApp' })).toBeNull();
    expect(screen.queryByText(/\+225/)).toBeNull();
    // The rest of the card is there — this is the loaded card, not a blank.
    expect(
      screen.getByRole('button', { name: 'Nouveau rendez-vous' }),
    ).toBeTruthy();
  });
});
