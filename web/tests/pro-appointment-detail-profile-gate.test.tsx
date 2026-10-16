import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
// Stable object: the page's load callback depends on [router].
const routerMock = { replace };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { ProAppointmentDetailClient } from '../components/pro/ProAppointmentDetailClient';
import { NO_CONNECTION_MESSAGE } from '../lib/api/network';
import type { ProAppointment } from '../lib/pro/today';

/// « Détails du rendez-vous » waits for its salon
/// (docs/design/pro-appointment-detail-profile-gate.md). A `/me` that answers
/// anything but 200 (or 401) used to fall through: the page rendered with NO
/// salon, so its clock was Abidjan's and its role shape an owner's — and
/// « Reprogrammer » sent the picked wall-clock as Abidjan time. For a salon at
/// UTC+1 that is a booking moved one hour off what the pro chose.
///
/// The fixture salon is in Libreville (UTC+1) — the one place an Abidjan
/// default is visibly wrong.

const APPT: ProAppointment = {
  id: 'a1',
  status: 'confirmed',
  appointmentDate: '2030-01-10T09:00:00.000Z', // 10:00 in Libreville
  clientDisplayName: 'Koffi',
  serviceIds: ['s1'],
  totalPrice: 15000,
};

const LIBREVILLE_ME = {
  account: { id: 'acc-1', businessName: 'Beauté Divine', phoneNumber: '+24106000000' },
  provider: {
    id: 'p1',
    name: 'Beauté Divine',
    status: 'active',
    countryCode: 'GA',
    timezone: 'Africa/Libreville',
    currency: 'XAF',
    services: [{ id: 's1', name: 'Tresses' }],
  },
};

type Answer = { status: number; body: unknown };

const meReads: string[] = [];
const listReads: string[] = [];
const rescheduled: Record<string, unknown>[] = [];

/// `me`: what each successive `GET /api/pro/me` answers (the last repeats).
function mockFetch(me: Answer[]) {
  meReads.length = 0;
  listReads.length = 0;
  rescheduled.length = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const u = String(url);
      if (u === '/api/pro/me') {
        const a = me[Math.min(meReads.length, me.length - 1)];
        meReads.push(u);
        return new Response(JSON.stringify(a.body), { status: a.status });
      }
      if (u === '/api/pro/appointments') {
        listReads.push(u);
        return new Response(JSON.stringify({ items: [APPT] }), { status: 200 });
      }
      if (u === `/api/pro/appointments/${APPT.id}/reschedule` && init?.method === 'POST') {
        rescheduled.push(JSON.parse(String(init.body ?? '{}')));
        return new Response('{}', { status: 200 });
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
});

/// The page settled into its error state — and nothing salon-shaped leaked.
/// No usable answer (status 0) names the network
/// (docs/design/web-pro-no-connection-copy.md §3); a server's failure keeps
/// the default.
async function expectErrorState(
  sentence: string = 'Une erreur est survenue. Réessayez.',
) {
  expect(
    await screen.findByRole('button', { name: 'Réessayer' }),
  ).toBeInTheDocument();
  expect(screen.getByRole('alert')).toHaveTextContent(sentence);
  // The page title survives the error (§4: one h1 per page, every state).
  expect(screen.getByRole('heading', { level: 1, name: 'Rendez-vous' })).toBeInTheDocument();
  // Nothing rendered from a salon the page does not have: no clock, no role
  // shape, no write.
  expect(screen.queryByText('Koffi')).toBeNull();
  expect(screen.queryByRole('button', { name: 'Reprogrammer' })).toBeNull();
  expect(screen.queryByRole('button', { name: 'Marquer comme terminé' })).toBeNull();
  expect(screen.queryByRole('button', { name: 'Marquer comme absent' })).toBeNull();
  expect(rescheduled).toHaveLength(0);
  expect(replace).not.toHaveBeenCalled();
  // The gate is in load(), not only in the render: a salon the page could
  // not load has no appointments fetched for it (the ClientCard order). The
  // render guard alone would hide the page too — this pins which line holds.
  expect(listReads).toHaveLength(0);
}

describe('ProAppointmentDetailClient — no salon, no page', () => {
  it('a /me 500 shows the error state with « Réessayer », never the detail', async () => {
    mockFetch([{ status: 500, body: { error: 'internal' } }]);
    render(<ProAppointmentDetailClient id={APPT.id} />);

    await expectErrorState();
  });

  it('a /me 403 does the same — the shell’s probe owns the sign-out, not this page', async () => {
    mockFetch([{ status: 403, body: { error: 'forbidden' } }]);
    render(<ProAppointmentDetailClient id={APPT.id} />);

    await expectErrorState();
  });

  it('a /me 200 without a profile body is no salon either', async () => {
    // getMyProvider casts the body: a 200 is only a salon if it holds one.
    // A `null` body is no usable answer — status 0 since #619 (readJson),
    // so the page says the network, as for a cut connection.
    mockFetch([{ status: 200, body: null }]);
    render(<ProAppointmentDetailClient id={APPT.id} />);

    await expectErrorState(NO_CONNECTION_MESSAGE);
  });

  it('« Réessayer » loads the detail once /me answers', async () => {
    mockFetch([
      { status: 503, body: {} },
      { status: 200, body: LIBREVILLE_ME },
    ]);
    render(<ProAppointmentDetailClient id={APPT.id} />);

    fireEvent.click(await screen.findByRole('button', { name: 'Réessayer' }));

    expect(
      await screen.findByRole('heading', { level: 1, name: 'Détails du rendez-vous' }),
    ).toBeInTheDocument();
    expect(screen.getByText('Koffi')).toBeInTheDocument();
    // The SALON's clock: 09:00Z is 10:00 in Libreville.
    expect(screen.getByText(/10:00/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Reprogrammer' })).toBeInTheDocument();
    expect(meReads).toHaveLength(2);
  });

  it('a 401 from /me still redirects to the pro login', async () => {
    mockFetch([{ status: 401, body: { error: 'unauthorized' } }]);
    render(<ProAppointmentDetailClient id={APPT.id} />);

    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro/connexion'));
  });
});

describe('ProAppointmentDetailClient — « Reprogrammer » is salon time', () => {
  // The control for the cases above: with the salon loaded, the timezone
  // reaches the write. Green before the fix and after — it is what makes the
  // red cases red for the right reason (the test can see an hour).
  it('a Libreville salon’s 10:00 crosses as 09:00Z', async () => {
    mockFetch([{ status: 200, body: LIBREVILLE_ME }]);
    render(<ProAppointmentDetailClient id={APPT.id} />);

    fireEvent.click(await screen.findByRole('button', { name: 'Reprogrammer' }));
    // Prefilled with the SALON wall-clock, not Abidjan's 09:00.
    expect(screen.getByLabelText('Nouvelle heure')).toHaveValue('10:00');
    fireEvent.change(screen.getByLabelText('Nouvelle date'), {
      target: { value: '2030-01-15' },
    });
    fireEvent.change(screen.getByLabelText('Nouvelle heure'), {
      target: { value: '10:00' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Confirmer' }));

    await waitFor(() => expect(rescheduled).toHaveLength(1));
    expect(rescheduled[0]).toEqual({ newDateTime: '2030-01-15T09:00:00.000Z' });
  });
});
