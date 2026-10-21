import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
// Stable object: the load callbacks depend on [router].
const routerMock = { replace, push: vi.fn(), refresh: vi.fn(), back: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => '/pro',
  useSearchParams: () => new URLSearchParams(),
}));

import { AbonnementClient } from '../components/pro/AbonnementClient';
import { ClientCardClient } from '../components/pro/ClientCardClient';
import { EquipeClient } from '../components/pro/EquipeClient';
import { GoLiveCard } from '../components/pro/GoLiveCard';
import { JournalPanel } from '../components/pro/JournalPanel';
import { ManualBookingDialog } from '../components/pro/ManualBookingDialog';
import type { ProProfile } from '../lib/api/pro';
import type { ProAppointment } from '../lib/pro/today';

/// docs/design/web-pro-truthful-failure.md (backlog batch 4, PR A): a read that
/// failed says so — never a false « no offer », « no visit » or an empty list —
/// and a refusal names its reason. With no answer at all, every new sentence is
/// « Pas de connexion. Réessayez. » (SYSTEM.md §17).

const NO_CONNECTION = 'Pas de connexion. Réessayez.';

type Answer = 'throw' | { status: number; body?: unknown };

/// Answers by « METHOD path » (query stripped), each a list played in order —
/// the last one repeats. Records every call.
const calls: string[] = [];
function mockFetch(answers: Record<string, Answer | Answer[]>) {
  calls.length = 0;
  const queues = new Map(
    Object.entries(answers).map(([k, v]) => [k, Array.isArray(v) ? [...v] : [v]]),
  );
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const u = String(url);
      const method = init?.method ?? 'GET';
      const key = `${method} ${u.split('?')[0]}`;
      calls.push(`${method} ${u}`);
      const q = queues.get(key);
      if (!q) return new Response('{}', { status: 404 });
      const a = q.length > 1 ? q.shift()! : q[0];
      if (a === 'throw') throw new TypeError('Failed to fetch');
      return new Response(JSON.stringify(a.body ?? { error: 'internal' }), { status: a.status });
    }),
  );
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
});

const PROVIDER = {
  id: 'p1',
  name: 'Salon Awa',
  status: 'draft',
  timezone: 'Africa/Abidjan',
  currency: 'XOF',
  description: 'Un salon.',
  address: 'Rue des Jardins',
  commune: 'Cocody',
  latitude: 5.3,
  longitude: -3.9,
  services: [
    { id: 's1', name: 'Tresses', price: 5000, durationMinutes: 60, active: true },
    { id: 's2', name: 'B', price: 1, durationMinutes: 30, active: true },
    { id: 's3', name: 'C', price: 1, durationMinutes: 30, active: true },
  ],
  artists: [],
  imageUrls: ['a', 'b', 'c'],
  availability: {
    providerId: 'p1',
    weeklySchedule: { '0': [{ startTime: '09:00', endTime: '18:00' }] },
    blockedDates: [],
    bufferMinutes: 0,
  },
};
const ME = {
  account: { id: 'acc1', email: 'x@salon.test', businessType: 'salon', verificationStatus: 'pending' },
  provider: PROVIDER,
  membership: {
    role: 'owner',
    capabilities: ['members.manage', 'clients.view', 'journal.manage.all', 'journal.view.all'],
  },
};
const OFFER = {
  tier: 'pro',
  status: 'trial',
  trialEndsAt: '2099-10-12T00:00:00.000Z',
  graceEndsAt: '2099-10-19T00:00:00.000Z',
  seats: { cap: 5, used: 1 },
};

describe('Équipe — the offer that could not be read (Q1)', () => {
  const reads = (sub: Answer | Answer[]) => ({
    'GET /api/pro/me': { status: 200, body: ME },
    'GET /api/pro/members': { status: 200, body: { items: [] } },
    'GET /api/pro/salon-subscription': sub,
  });

  for (const [label, sub, said] of [
    ['a 500', { status: 500 }, 'Impossible de vérifier votre offre.'],
    ['no network', 'throw', NO_CONNECTION],
  ] as const) {
    it(`${label}: « ${said} » — never « Choisissez votre offre »; « Inviter » stays usable`, async () => {
      mockFetch(reads(sub));
      render(<EquipeClient />);
      expect(await screen.findByText(said)).toBeInTheDocument();
      expect(screen.queryByText(/Choisissez votre offre/)).toBeNull();
      expect(screen.getByRole('button', { name: /Inviter/ })).toBeEnabled();
    });
  }

  it('« Réessayer » reads the offer again: the seats come back', async () => {
    mockFetch(reads([{ status: 500 }, { status: 200, body: OFFER }]));
    render(<EquipeClient />);
    await screen.findByText('Impossible de vérifier votre offre.');
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(await screen.findByText(/1\s*\/\s*5|1 place|5 places/)).toBeInTheDocument();
    expect(screen.queryByText('Impossible de vérifier votre offre.')).toBeNull();
  });

  it('no offer at all (404) still says « Choisissez votre offre » (unchanged)', async () => {
    mockFetch(reads({ status: 404, body: { error: 'no_offer' } }));
    render(<EquipeClient />);
    expect(await screen.findByText(/Choisissez votre offre pour inviter/)).toBeInTheDocument();
  });
});

describe('La fiche client — the visit history (B4.1)', () => {
  const CARD = {
    id: 'sc1',
    displayName: 'Koffi',
    phone: '+2250700000101',
    tags: [],
    lastVisitAt: null,
    linked: false,
    createdAt: '2026-10-01T09:00:00.000Z',
    stats: { visits: 5, spentFcfa: 45000, noShows: 0, cancellations: 0 },
    notes: [],
  };
  const visit = (id: string): ProAppointment => ({
    id,
    status: 'completed',
    appointmentDate: '2026-09-01T10:00:00.000Z',
    clientDisplayName: 'Koffi',
    serviceIds: ['s1'],
    totalPrice: 5000,
  });
  const reads = (visits: Answer | Answer[]) => ({
    'GET /api/pro/me': { status: 200, body: ME },
    'GET /api/pro/clients/sc1': { status: 200, body: CARD },
    'GET /api/pro/clients/sc1/visits': visits,
  });

  for (const [label, answer, said] of [
    ['a 500', { status: 500 }, 'Historique indisponible.'],
    ['no network', 'throw', NO_CONNECTION],
  ] as const) {
    it(`${label}: « ${said} » — never « Aucune visite » beside « Visites 5 »`, async () => {
      mockFetch(reads(answer));
      render(<ClientCardClient clientId="sc1" />);
      expect(await screen.findByText(said)).toBeInTheDocument();
      expect(screen.queryByText('Aucune visite enregistrée.')).toBeNull();
    });
  }

  it('« Réessayer » reads the history again', async () => {
    mockFetch(reads([{ status: 500 }, { status: 200, body: { items: [visit('v1')], total: 1 } }]));
    render(<ClientCardClient clientId="sc1" />);
    await screen.findByText('Historique indisponible.');
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    await waitFor(() => expect(screen.queryByText('Historique indisponible.')).toBeNull());
    expect(calls.filter((c) => c.includes('/visits')).length).toBe(2);
  });

  it('« Charger plus » that fails says so and asks for the SAME page again — never skips one', async () => {
    mockFetch(
      reads([
        { status: 200, body: { items: [visit('v1')], total: 3 } }, // page 1
        { status: 500 }, // page 2, failed
        { status: 200, body: { items: [visit('v2')], total: 3 } }, // page 2, again
      ]),
    );
    render(<ClientCardClient clientId="sc1" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Charger plus' }));
    expect(await screen.findByText('Le chargement a échoué. Réessayez.')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Charger plus' }));
    await waitFor(() => expect(calls.filter((c) => c.includes('/visits')).length).toBe(3));
    const pages = calls.filter((c) => c.includes('/visits')).map((c) => new URL(c.slice(4), 'http://x').searchParams.get('page'));
    expect(pages).toEqual(['1', '2', '2']);
    await waitFor(() => expect(screen.queryByText('Le chargement a échoué. Réessayez.')).toBeNull());
  });

  it('« Charger plus » with no network: « Pas de connexion. Réessayez. »', async () => {
    mockFetch(reads([{ status: 200, body: { items: [visit('v1')], total: 3 } }, 'throw']));
    render(<ClientCardClient clientId="sc1" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Charger plus' }));
    expect(await screen.findByText(NO_CONNECTION)).toBeInTheDocument();
  });
});

describe('« Mettre en ligne » — a refusal names its reason (B4.3)', () => {
  const PROFILE = { ...ME, provider: { ...PROVIDER } } as unknown as ProProfile;
  const reads = (publish: Answer) => ({
    'GET /api/pro/acompte': {
      status: 200,
      body: { depositRequired: false, depositPercentage: 0, cancellationWindowHours: 24 },
    },
    'GET /api/pro/kyc': { status: 200, body: { status: 'pending', documents: [] } },
    'POST /api/pro/publish': publish,
  });

  for (const [label, answer, said] of [
    [
      'the demo account',
      { status: 403, body: { error: 'demo_account_locked' } },
      'Compte de démonstration — cette action est désactivée.',
    ],
    [
      'a suspended salon',
      { status: 403, body: { error: 'provider_suspended' } },
      'Votre salon est suspendu. Contactez MyWeli pour le réactiver — vos rendez-vous sont intacts.',
    ],
    ['no network', 'throw', NO_CONNECTION],
    ['a 500 (unchanged)', { status: 500 }, 'La mise en ligne a échoué. Réessayez.'],
  ] as const) {
    it(`${label}: « ${said} »`, async () => {
      mockFetch(reads(answer));
      render(<GoLiveCard profile={PROFILE} onPublished={vi.fn()} />);
      const go = await screen.findByRole('button', { name: 'Mettre en ligne' });
      await waitFor(() => expect(go).toBeEnabled());
      fireEvent.click(go);
      expect(await screen.findByText(said)).toBeInTheDocument();
    });
  }
});

describe('« Mon abonnement » — choosing an offer, refused (B4.3)', () => {
  for (const [label, answer, said] of [
    [
      'the demo account',
      { status: 403, body: { error: 'demo_account_locked' } },
      'Compte de démonstration — cette action est désactivée.',
    ],
    ['no network', 'throw', NO_CONNECTION],
    ['a 500 (unchanged)', { status: 500 }, 'Le changement d’offre a échoué. Réessayez.'],
  ] as const) {
    it(`${label}: « ${said} »`, async () => {
      mockFetch({
        'GET /api/pro/me': { status: 200, body: ME },
        'GET /api/pro/salon-subscription': { status: 404, body: { error: 'no_offer' } },
        'PUT /api/pro/salon-subscription': answer,
      });
      render(<AbonnementClient />);
      fireEvent.click((await screen.findAllByRole('button', { name: 'Choisir cette offre' }))[0]);
      expect(await screen.findByText(said)).toBeInTheDocument();
    });
  }
});

describe('Le panneau de la Journée — the client card (Q3)', () => {
  const APPT: ProAppointment = {
    id: 'a1',
    status: 'confirmed',
    appointmentDate: '2099-01-15T10:00:00.000Z',
    clientDisplayName: 'Koffi',
    serviceIds: ['s1'],
    totalPrice: 5000,
    salonClientId: 'sc1',
  };
  const OWNER = ME.membership as unknown as Parameters<typeof JournalPanel>[0]['membership'];
  const panel = () =>
    render(
      <JournalPanel
        providerId="p1"
        appt={APPT}
        membership={OWNER}
        serviceName={() => 'Tresses'}
        onClose={() => {}}
        onChanged={() => {}}
        onToast={() => {}}
        tz="Africa/Abidjan"
        currency="XOF"
      />,
    );

  for (const [label, answer, said] of [
    ['a 500', { status: 500 }, 'Fiche client indisponible.'],
    ['no network', 'throw', NO_CONNECTION],
  ] as const) {
    it(`${label}: « ${said} » with « Réessayer » — never nothing`, async () => {
      mockFetch({ 'GET /api/pro/clients/sc1': answer });
      panel();
      expect(await screen.findByText(said)).toBeInTheDocument();
      expect(screen.getByRole('button', { name: 'Réessayer' })).toBeInTheDocument();
    });
  }

  it('« Réessayer » reads the card again: « Voir la fiche »', async () => {
    mockFetch({
      'GET /api/pro/clients/sc1': [
        { status: 500 },
        {
          status: 200,
          body: {
            id: 'sc1',
            displayName: 'Koffi',
            tags: [],
            linked: false,
            createdAt: '2026-10-01T09:00:00.000Z',
            stats: { visits: 2, spentFcfa: 10000, noShows: 0, cancellations: 0 },
            notes: [],
          },
        },
      ],
    });
    panel();
    await screen.findByText('Fiche client indisponible.');
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(await screen.findByRole('link', { name: 'Voir la fiche' })).toBeInTheDocument();
  });
});

describe('« Nouveau rendez-vous » — the client suggestions (Q3)', () => {
  const dialog = () =>
    render(
      <ManualBookingDialog
        providerId="p1"
        profile={ME as unknown as ProProfile}
        dateTimeIso="2099-01-15T14:30:00.000Z"
        onClose={() => {}}
        onCreated={() => {}}
      />,
    );

  for (const [label, answer, said] of [
    ['a 500', { status: 500 }, 'Recherche indisponible.'],
    ['no network', 'throw', NO_CONNECTION],
  ] as const) {
    it(`${label}: « ${said} » — not the same thing as « no client »; the name can still be typed`, async () => {
      mockFetch({ 'GET /api/pro/clients': answer });
      dialog();
      const field = screen.getByLabelText('Rechercher ou nommer le client');
      fireEvent.change(field, { target: { value: 'Ko' } });
      expect(await screen.findByText(said)).toBeInTheDocument();
      expect(field).toBeEnabled();
    });
  }

  it('« Réessayer » searches again', async () => {
    mockFetch({
      'GET /api/pro/clients': [
        { status: 500 },
        { status: 200, body: { items: [{ id: 'sc1', displayName: 'Koffi', phone: null, tags: [], linked: false }], page: 1, pageSize: 20, total: 1 } },
      ],
    });
    dialog();
    fireEvent.change(screen.getByLabelText('Rechercher ou nommer le client'), {
      target: { value: 'Ko' },
    });
    await screen.findByText('Recherche indisponible.');
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(await screen.findByText('Koffi')).toBeInTheDocument();
  });
});
