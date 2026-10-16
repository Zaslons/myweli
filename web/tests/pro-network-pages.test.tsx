import { cleanup, render, screen } from '@testing-library/react';
import type { ReactElement } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
// Stable object: the load effects depend on [router].
const routerMock = { replace, push: vi.fn(), refresh: vi.fn(), back: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => '/pro',
  useSearchParams: () => new URLSearchParams(),
  useParams: () => ({}),
}));

import { AbonnementClient } from '../components/pro/AbonnementClient';
import { AcompteClient } from '../components/pro/AcompteClient';
import { AujourdhuiClient } from '../components/pro/AujourdhuiClient';
import { AvisClient } from '../components/pro/AvisClient';
import { CatalogueClient } from '../components/pro/CatalogueClient';
import { ClientCardClient } from '../components/pro/ClientCardClient';
import { ClientsClient } from '../components/pro/ClientsClient';
import { DisponibilitesClient } from '../components/pro/DisponibilitesClient';
import { EquipeClient } from '../components/pro/EquipeClient';
import { MediasClient } from '../components/pro/MediasClient';
import { ProAppointmentDetailClient } from '../components/pro/ProAppointmentDetailClient';
import { ProfilClient } from '../components/pro/ProfilClient';
import { RendezVousClient } from '../components/pro/RendezVousClient';
import { RevenusClient } from '../components/pro/RevenusClient';
import { SalonPreviewClient } from '../components/pro/SalonPreviewClient';
import { VerificationClient } from '../components/pro/VerificationClient';
import { resetLocalitiesClientCache } from '../lib/use-localities';

/// docs/design/web-pro-network-failure.md §1/§10 — every Pro page that loads
/// on arrival, under a dropped connection. Before: the read threw into a load
/// that never caught it, `setLoading(false)` never ran, and the page stayed on
/// its skeleton for ever — no message, no « Réessayer ». Now: the page's own
/// error state, under its own h1.

type Answer = 'throw' | { status: number; body?: unknown };

/// The signed-in salon (no `membership` → the legacy owner: every
/// capability, so no page skips a read for want of one).
const PROFILE = {
  account: {
    id: 'acc1',
    businessName: 'Beauté Divine',
    businessType: 'salon',
    phoneNumber: '+2250700000000',
    email: 'owner@salon.test',
    verificationStatus: 'verified',
  },
  provider: {
    id: 'p1',
    name: 'Beauté Divine',
    status: 'active',
    countryCode: 'CI',
    timezone: 'Africa/Abidjan',
    currency: 'XOF',
    services: [],
    artists: [],
  },
};

/// Answers by PATH (query stripped, exact match); anything unlisted is a 404.
function mockFetch(answers: Record<string, Answer>) {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      const path = String(url).split('?')[0];
      const a = answers[path] ?? answers['*'];
      if (a === 'throw') throw new TypeError('Failed to fetch');
      if (!a) return new Response('{}', { status: 404 });
      return new Response(JSON.stringify(a.body ?? {}), { status: a.status });
    }),
  );
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  resetLocalitiesClientCache();
  replace.mockReset();
});

type Page = {
  /// The page's h1 — in every state (§4: one h1 per page).
  h1: string;
  el: () => ReactElement;
  /// The sentence of its error state.
  message?: string;
  /// The reads after `/me` whose failure is the page's error state.
  reads: string[];
};

const PAGES: Page[] = [
  { h1: 'Disponibilités', el: () => <DisponibilitesClient />, reads: [] },
  { h1: 'Profil', el: () => <ProfilClient />, reads: [] },
  { h1: 'Médias', el: () => <MediasClient />, reads: [] },
  // 404 is the setup state (« choisissez une offre ») — a dropped
  // connection must not read as one.
  { h1: 'Mon abonnement', el: () => <AbonnementClient />, reads: ['/api/pro/salon-subscription'] },
  { h1: 'Catalogue', el: () => <CatalogueClient />, reads: [] },
  // 404 is « Client introuvable. » — same.
  { h1: 'Fiche client', el: () => <ClientCardClient clientId="c1" />, reads: ['/api/pro/clients/c1'] },
  { h1: 'Clients', el: () => <ClientsClient />, reads: ['/api/pro/clients'] },
  { h1: 'Équipe', el: () => <EquipeClient />, reads: ['/api/pro/members'] },
  { h1: 'Rendez-vous', el: () => <RendezVousClient />, reads: ['/api/pro/appointments'] },
  { h1: 'Aujourd’hui', el: () => <AujourdhuiClient />, reads: ['/api/pro/appointments'] },
  {
    h1: 'Avis',
    el: () => <AvisClient />,
    message: 'Impossible de charger les avis.',
    reads: ['/api/pro/reviews'],
  },
  {
    h1: 'Revenus',
    el: () => <RevenusClient />,
    message: 'Chargement impossible.',
    reads: ['/api/pro/earnings'],
  },
  {
    h1: 'Vérification',
    el: () => <VerificationClient />,
    message: 'Chargement impossible.',
    reads: ['/api/pro/kyc'],
  },
  {
    h1: 'Aperçu du salon',
    el: () => <SalonPreviewClient />,
    message: 'Impossible de charger l’aperçu.',
    reads: [],
  },
  // 404 is « introuvable » (the appointment absent from the list).
  { h1: 'Rendez-vous', el: () => <ProAppointmentDetailClient id="a1" />, reads: ['/api/pro/appointments'] },
  // Needs #616 (acompte-off-parity D3): on the code before it, a failed
  // policy read is a BLANK FORM that a save writes over the real policy.
  { h1: 'Acompte', el: () => <AcompteClient />, reads: ['/api/pro/acompte'] },
];

/// The page's error state: its h1, the alert, « Réessayer » — and no
/// skeleton left spinning.
async function expectErrorState(page: Page) {
  expect(
    await screen.findByRole('button', { name: 'Réessayer' }),
  ).toBeInTheDocument();
  expect(
    screen.getByRole('heading', { level: 1, name: page.h1 }),
  ).toBeInTheDocument();
  expect(screen.getByRole('alert')).toHaveTextContent(
    page.message ?? 'Une erreur est survenue. Réessayez.',
  );
  expect(replace).not.toHaveBeenCalled();
}

describe('Pro pages — no network at all: the error state, never a skeleton for ever', () => {
  for (const page of PAGES) {
    it(`${page.h1} (${(page.el().type as { name: string }).name})`, async () => {
      mockFetch({ '*': 'throw' });
      render(page.el());
      await expectErrorState(page);
    });
  }
});

describe('Pro pages — the salon loads, then the page’s own read is cut', () => {
  for (const page of PAGES) {
    for (const read of page.reads) {
      it(`${page.h1} (${(page.el().type as { name: string }).name}) — ${read}`, async () => {
        mockFetch({
          '/api/pro/me': { status: 200, body: PROFILE },
          [read]: 'throw',
        });
        render(page.el());
        await expectErrorState(page);
      });
    }
  }
});
