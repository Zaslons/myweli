import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
// Stable object: the page's load callback depends on [router].
const routerMock = { replace };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { ProAppointmentDetailClient } from '../components/pro/ProAppointmentDetailClient';
import { NO_CONNECTION_MESSAGE } from '../lib/api/network';
import type { Membership } from '../lib/pro/team';
import type { ProAppointment } from '../lib/pro/today';

/// docs/design/web-pro-journal-panel-deposit.md §2.3 — the booking's own page,
/// aligned with the panel. The audit's P2: the screenshot sat behind
/// « Voir le justificatif », with no guidance, and a failed load did nothing at
/// all (`proDepositScreenshotUrl` turned every failure into `null`, and
/// `setProofUrl(null)` changed nothing on screen). « Marquer comme absent » was
/// offered on a booking that had not started.

const PROOF_URL = 'https://acct.r2.cloudflarestorage.com/deposit/u2/proof.jpg?X-Amz-Signature=s';
const HOUR = 3_600_000;
const inHours = (h: number) => new Date(Date.now() + h * HOUR).toISOString();
const GUIDANCE =
  'Confirmez le rendez-vous une fois l’acompte reçu sur votre compte Mobile Money.';
const ENLARGE = 'Agrandir le justificatif d’acompte';

const PENDING: ProAppointment = {
  id: 'a1',
  status: 'pending',
  appointmentDate: inHours(30),
  clientDisplayName: 'Aminata',
  serviceIds: ['s1'],
  totalPrice: 15000,
  depositAmount: 5000,
  depositScreenshotUrl: 'deposit/u2/proof.jpg',
};

const ME = {
  account: { id: 'acc-1', businessName: 'Beauté Divine', phoneNumber: '+2250700000000' },
  provider: {
    id: 'p1',
    name: 'Beauté Divine',
    status: 'active',
    countryCode: 'CI',
    timezone: 'Africa/Abidjan',
    currency: 'XOF',
    services: [{ id: 's1', name: 'Tresses' }],
  },
};

const STAFF: Membership = {
  role: 'staff',
  capabilities: ['journal.manage.own', 'journal.view.own'],
  artistId: 'artist-a',
  artistName: 'Awa',
};

type Answer = 'throw' | { status: number; body?: unknown };

const proofReads: string[] = [];
const posts: string[] = [];

function mockFetch(
  appt: ProAppointment,
  opts: { proof?: Answer; membership?: Membership } = {},
) {
  proofReads.length = 0;
  posts.length = 0;
  const proof = opts.proof ?? { status: 200, body: { url: PROOF_URL } };
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const u = String(url);
      if (u === '/api/pro/me') {
        const body = opts.membership ? { ...ME, membership: opts.membership } : ME;
        return new Response(JSON.stringify(body), { status: 200 });
      }
      if (u === '/api/pro/appointments') {
        return new Response(JSON.stringify({ items: [appt] }), { status: 200 });
      }
      if (u.endsWith('/deposit-screenshot')) {
        proofReads.push(u);
        if (proof === 'throw') throw new TypeError('Failed to fetch');
        return new Response(JSON.stringify(proof.body ?? {}), { status: proof.status });
      }
      if (init?.method === 'POST') {
        posts.push(u);
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

describe('the booking page — the deposit screenshot', () => {
  it('loads by itself (no « Voir le justificatif » to click), after the app’s guidance', async () => {
    mockFetch(PENDING);
    render(<ProAppointmentDetailClient id="a1" />);
    const thumb = await screen.findByRole('button', { name: ENLARGE });
    expect(within(thumb).getByAltText('Justificatif d’acompte')).toHaveAttribute(
      'src',
      PROOF_URL,
    );
    expect(screen.getByText(GUIDANCE)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Voir le justificatif' })).toBeNull();
    expect(proofReads).toEqual(['/api/pro/appointments/a1/deposit-screenshot']);
  });

  it('a failed load says so — it used to do nothing', async () => {
    mockFetch(PENDING, { proof: 'throw' });
    render(<ProAppointmentDetailClient id="a1" />);
    expect(await screen.findByText(NO_CONNECTION_MESSAGE)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Réessayer' })).toBeInTheDocument();
  });

  it('a refused load says « Capture indisponible. Réessayez. »', async () => {
    mockFetch(PENDING, { proof: { status: 500, body: { error: 'internal' } } });
    render(<ProAppointmentDetailClient id="a1" />);
    expect(await screen.findByText('Capture indisponible. Réessayez.')).toBeInTheDocument();
  });

  it('no screenshot: the app’s words, not « Justificatif d’acompte non reçu. »', async () => {
    mockFetch({ ...PENDING, depositScreenshotUrl: null });
    render(<ProAppointmentDetailClient id="a1" />);
    expect(
      await screen.findByText('Aucune capture jointe pour le moment.'),
    ).toBeInTheDocument();
    expect(screen.queryByText('Justificatif d’acompte non reçu.')).toBeNull();
    expect(proofReads).toEqual([]);
  });

  it('confirmed: no guidance (Q1), the screenshot stays', async () => {
    mockFetch({ ...PENDING, status: 'confirmed' });
    render(<ProAppointmentDetailClient id="a1" />);
    await screen.findByRole('button', { name: ENLARGE });
    expect(screen.queryByText(GUIDANCE)).toBeNull();
  });

  it('a Collaborateur: the amount, no screenshot request (the server would refuse it)', async () => {
    mockFetch({ ...PENDING, status: 'confirmed' }, { membership: STAFF });
    render(<ProAppointmentDetailClient id="a1" />);
    expect(await screen.findByText('Acompte annoncé')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: ENLARGE })).toBeNull();
    expect(screen.queryByText('Aucune capture jointe pour le moment.')).toBeNull();
    await new Promise((r) => setTimeout(r, 0));
    expect(proofReads).toEqual([]);
  });
});

describe('the booking page — « Marquer comme absent »', () => {
  const CONFIRMED: ProAppointment = {
    ...PENDING,
    status: 'confirmed',
    depositAmount: 0,
    depositScreenshotUrl: null,
  };

  it('is not offered before the start', async () => {
    mockFetch({ ...CONFIRMED, appointmentDate: inHours(2) });
    render(<ProAppointmentDetailClient id="a1" />);
    expect(
      await screen.findByRole('button', { name: 'Marquer comme terminé' }),
    ).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Marquer comme absent' })).toBeNull();
  });

  it('once started, it asks in the app’s words, and sends only on « Marquer absent »', async () => {
    mockFetch({ ...CONFIRMED, appointmentDate: inHours(-1) });
    render(<ProAppointmentDetailClient id="a1" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Marquer comme absent' }));
    expect(screen.getByText('Client absent ?')).toBeInTheDocument();
    expect(screen.getByText('Le client ne s’est pas présenté.')).toBeInTheDocument();
    expect(screen.queryByText(/L’acompte est conservé/)).toBeNull();
    expect(posts).toEqual([]);
    fireEvent.click(screen.getByRole('button', { name: 'Marquer absent' }));
    await waitFor(() => expect(posts).toEqual(['/api/pro/appointments/a1/no-show']));
  });

  it('with a deposit, the confirmation says the salon keeps it', async () => {
    mockFetch({ ...PENDING, status: 'confirmed', appointmentDate: inHours(-1) });
    render(<ProAppointmentDetailClient id="a1" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Marquer comme absent' }));
    expect(
      screen.getByText('L’acompte est conservé selon votre politique d’annulation.'),
    ).toBeInTheDocument();
  });
});
