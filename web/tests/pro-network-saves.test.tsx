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
// Stable object: the load callbacks depend on [router].
const routerMock = { replace, push: vi.fn(), refresh: vi.fn() };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { CatalogueClient } from '../components/pro/CatalogueClient';
import { ClientCardClient } from '../components/pro/ClientCardClient';
import { DisponibilitesClient } from '../components/pro/DisponibilitesClient';
import { ProLoginOptions } from '../components/pro/ProLoginOptions';

/// docs/design/web-pro-network-failure.md §1/§3 — a save with no network. Since
/// docs/design/app-failure-messages.md §2.2 it SAYS so: « Pas de connexion.
/// Réessayez. », the sentence the app says (« L’enregistrement a échoué » is
/// for a server that refused).
/// Before: the write threw, `setBusy(false)` never ran, and the button stayed
/// disabled for ever — inside « Modifier le numéro », a dialog that cannot be
/// closed while it saves, the salon was shut in until a reload. Now: the
/// save's own failure sentence, and the control back.

const PROVIDER = {
  id: 'p1',
  name: 'Beauté Divine',
  status: 'active',
  timezone: 'Africa/Abidjan',
  currency: 'XOF',
  services: [{ id: 's1', name: 'Tresses', durationMinutes: 60, price: 5000, active: true }],
  artists: [],
  availability: {
    providerId: 'p1',
    weeklySchedule: {
      '0': [{ startTime: '09:00', endTime: '17:00', isAvailable: true }],
    },
    blockedDates: [],
    bufferMinutes: 0,
  },
};

const CARD = {
  id: 'sc1',
  displayName: 'Koffi',
  phone: '+2250700000101',
  tags: [],
  lastVisitAt: null,
  linked: false,
  phoneEditable: true,
  createdAt: '2026-10-01T09:00:00.000Z',
  stats: { visits: 0, spentFcfa: 0, noShows: 0, cancellations: 0 },
  notes: [],
};

/// Reads answer; every write (any method but GET) has no network — until
/// `online()` is called.
let writesDown = true;
const writes: string[] = [];

function mockFetch() {
  writesDown = true;
  writes.length = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const u = String(url);
      const method = init?.method ?? 'GET';
      if (method !== 'GET') {
        writes.push(`${method} ${u.split('?')[0]}`);
        if (writesDown) throw new TypeError('Failed to fetch');
        return new Response('{}', { status: 200 });
      }
      if (u === '/api/pro/me') {
        return new Response(
          JSON.stringify({ account: { id: 'acc1', email: 'x@salon.test' }, provider: PROVIDER }),
          { status: 200 },
        );
      }
      if (u.startsWith('/api/pro/clients/sc1/visits')) {
        return new Response(JSON.stringify({ items: [], total: 0 }), { status: 200 });
      }
      if (u.startsWith('/api/pro/clients/sc1?')) {
        return new Response(JSON.stringify(CARD), { status: 200 });
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

describe('a save with no network says so and gives the control back', () => {
  it('« Modifier le numéro »: the sentence, « Enregistrer » back, and the dialog closes again', async () => {
    mockFetch();
    render(<ClientCardClient clientId="sc1" />);
    await screen.findByRole('heading', { level: 1, name: /^Koffi/ });

    fireEvent.click(screen.getByRole('button', { name: 'Modifier le numéro' }));
    const dialog = screen.getByRole('dialog', { name: 'Modifier le numéro' });
    fireEvent.change(within(dialog).getByLabelText('Numéro de téléphone'), {
      target: { value: '+225 05 05 12 34 56' },
    });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Enregistrer' }));

    expect(
      await within(dialog).findByText('Pas de connexion. Réessayez.'),
    ).toBeInTheDocument();
    expect(writes).toEqual(['PATCH /api/pro/clients/sc1']);
    expect(within(dialog).getByRole('button', { name: 'Enregistrer' })).toBeEnabled();

    // Not shut in: « Annuler » closes it.
    fireEvent.click(within(dialog).getByRole('button', { name: 'Annuler' }));
    await waitFor(() =>
      expect(screen.queryByRole('dialog', { name: 'Modifier le numéro' })).toBeNull(),
    );
  });

  it('Disponibilités « Enregistrer »: the sentence, the button back — and the retry goes through', async () => {
    mockFetch();
    render(<DisponibilitesClient />);
    const save = await screen.findByRole('button', { name: 'Enregistrer' });

    fireEvent.click(save);
    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Pas de connexion. Réessayez.',
    );
    expect(screen.getByRole('button', { name: 'Enregistrer' })).toBeEnabled();

    writesDown = false; // the network is back
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));
    await waitFor(() => expect(writes).toHaveLength(2));
    await waitFor(() => expect(screen.queryByRole('alert')).toBeNull());
  });

  it('Catalogue — a service saved with no network: the sentence, the form usable', async () => {
    mockFetch();
    render(<CatalogueClient />);
    fireEvent.click((await screen.findAllByRole('button', { name: 'Modifier' }))[0]);
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Pas de connexion. Réessayez.',
    );
    expect(writes).toEqual(['PATCH /api/pro/catalogue/services/s1']);
    expect(screen.getByRole('button', { name: 'Enregistrer' })).toBeEnabled();
    expect(screen.getByLabelText('Nom du service')).toHaveValue('Tresses');
  });

  it('Catalogue — an employee saved with no network: « Pas de connexion. Réessayez. »', async () => {
    mockFetch();
    render(<CatalogueClient />);
    // `Tabs` are plain buttons in a group (components/Tabs.tsx).
    fireEvent.click(await screen.findByRole('button', { name: 'Employés' }));
    fireEvent.click(screen.getByRole('button', { name: 'Ajouter un employé' }));
    fireEvent.change(screen.getByLabelText('Nom'), { target: { value: 'Awa' } });
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('Pas de connexion. Réessayez.');
    expect(screen.getByRole('button', { name: 'Enregistrer' })).toBeEnabled();
  });
});

describe('Pro login with no network — « Pas de connexion », never a wrong cause', () => {
  function mockAuth(down: { request: boolean; verify: boolean }) {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) => {
        if (url === '/api/pro/auth/email/request') {
          if (down.request) throw new TypeError('Failed to fetch');
          return new Response(JSON.stringify({ devCode: '123456' }), { status: 202 });
        }
        if (url === '/api/pro/auth/email/verify') {
          if (down.verify) throw new TypeError('Failed to fetch');
          return new Response('{}', { status: 200 });
        }
        return new Response('{}', { status: 404 });
      }),
    );
  }

  function askForCode() {
    fireEvent.change(screen.getByLabelText('Votre e-mail'), {
      target: { value: 'owner@salon.test' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Continuer avec e-mail' }));
  }

  it('« Continuer avec e-mail »: not « E-mail invalide » — the e-mail is fine', async () => {
    mockAuth({ request: true, verify: false });
    render(<ProLoginOptions onSuccess={vi.fn()} />);
    askForCode();

    expect(await screen.findByText('Pas de connexion. Réessayez.')).toBeInTheDocument();
    expect(screen.queryByText('E-mail invalide ou envoi impossible.')).toBeNull();
    expect(screen.getByLabelText('Votre e-mail')).not.toHaveAttribute('aria-invalid', 'true');
    expect(screen.getByRole('button', { name: 'Continuer avec e-mail' })).toBeEnabled();
  });

  it('« Se connecter »: not « Code incorrect » under the field — the code was never judged', async () => {
    mockAuth({ request: false, verify: true });
    const onSuccess = vi.fn();
    render(<ProLoginOptions onSuccess={onSuccess} />);
    askForCode();
    const code = await screen.findByLabelText('Code à 6 chiffres');
    fireEvent.change(code, { target: { value: '123456' } });
    fireEvent.click(screen.getByRole('button', { name: 'Se connecter' }));

    expect(await screen.findByText('Pas de connexion. Réessayez.')).toBeInTheDocument();
    expect(screen.queryByText('Code incorrect ou expiré.')).toBeNull();
    expect(screen.getByLabelText('Code à 6 chiffres')).not.toHaveAttribute('aria-invalid', 'true');
    expect(screen.getByRole('button', { name: 'Se connecter' })).toBeEnabled();
    expect(onSuccess).not.toHaveBeenCalled();
  });
});
