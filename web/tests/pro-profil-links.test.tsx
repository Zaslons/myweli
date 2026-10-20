import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
// Stable object: ProfilClient's load effect depends on [router] — a fresh
// object per render would loop the effect forever.
const routerMock = { replace };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
}));
// MapLibre (LocationPicker) is browser-only — the slim view never mounts it,
// but next/dynamic still resolves the import; stub it out.
vi.mock('next/dynamic', () => ({
  default: () => () => null,
}));

import { ProfilClient } from '../components/pro/ProfilClient';

/// docs/design/web-pro-profil-support.md — the Profil links the app shows,
/// gated by the same capabilities (`pro_profile_screen.dart`): a Manager no
/// longer sees Vérification, Acompte or Abonnement, pages it cannot use; and
/// the app's « Aide & Support » — « Nous écrire », for every role, to the
/// page the app opens (`AppConfig.supportUrl` = myweli.com/support).

/// A full-view member: the owner, or a Manager (`profile.manage` without the
/// owner-only `salon.publish`).
const MANAGER_CAPS = [
  'journal.view.all',
  'journal.manage.all',
  'journal.view.own',
  'journal.manage.own',
  'clients.view',
  'catalogue.manage',
  'availability.manage',
  'profile.manage',
];
const OWNER_CAPS = [
  ...MANAGER_CAPS,
  'finances.view',
  'deposit.manage',
  'members.manage',
  'subscription.manage',
  'salon.publish',
];

function mockFullView(role: 'owner' | 'manager') {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      if (url === '/api/pro/me') {
        return new Response(
          JSON.stringify({
            account: { id: 'acc-m', email: `${role}@equipe.test` },
            provider: { id: 'p1', name: 'Beauté Divine', status: 'active' },
            membership: {
              role,
              capabilities: role === 'owner' ? OWNER_CAPS : MANAGER_CAPS,
            },
          }),
          { status: 200 },
        );
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

function mockFetch(opts: { deleteStatus?: number } = {}) {
  const calls: { url: string; method: string }[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const method = init?.method ?? 'GET';
      calls.push({ url, method });
      if (url === '/api/pro/me') {
        return new Response(
          JSON.stringify({
            account: { id: 'acc-s', email: 'sonia.staff@equipe.test' },
            provider: { id: 'p1', name: 'Beauté Divine', status: 'active' },
            membership: {
              role: 'staff',
              capabilities: ['journal.manage.own', 'journal.view.own'],
              artistId: 'a1',
              artistName: 'Awa',
            },
          }),
          { status: 200 },
        );
      }
      if (url === '/api/pro/account' && method === 'DELETE') {
        return new Response(null, { status: opts.deleteStatus ?? 204 });
      }
      return new Response('{}', { status: 404 });
    }),
  );
  return calls;
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
});

const link = (name: string | RegExp) => screen.queryByRole('link', { name });

describe('ProfilClient — the links follow the role, as in the app', () => {
  it('owner: Vérification, Acompte, Abonnement, Photos — and Aide & Support', async () => {
    mockFullView('owner');
    render(<ProfilClient />);
    await screen.findByLabelText('Nom du salon');
    expect(link(/^Vérification/)).toHaveAttribute('href', '/pro/verification');
    expect(link(/^Acompte/)).toHaveAttribute('href', '/pro/acompte');
    expect(link(/^Abonnement/)).toHaveAttribute('href', '/pro/abonnement');
    expect(link(/^Photos & Avant\/Après/)).toHaveAttribute('href', '/pro/medias');
    expect(link(/^Aide & Support/)).toHaveAttribute('href', '/support');
  });

  it('manager: only what a Manager can open — Photos — and Aide & Support', async () => {
    mockFullView('manager');
    render(<ProfilClient />);
    await screen.findByLabelText('Nom du salon');
    expect(link(/^Vérification/)).toBeNull();
    expect(link(/^Acompte/)).toBeNull();
    expect(link(/^Abonnement/)).toBeNull();
    expect(link(/^Photos & Avant\/Après/)).toHaveAttribute('href', '/pro/medias');
    expect(link(/^Aide & Support/)).toHaveAttribute('href', '/support');
  });

  it('« Aide & Support » says « Nous écrire », the app’s words', async () => {
    mockFullView('owner');
    render(<ProfilClient />);
    await screen.findByLabelText('Nom du salon');
    expect(link(/^Aide & Support/)).toHaveTextContent('Nous écrire');
  });

  it('the slim view (Collaborateur, Réception) has it too', async () => {
    mockFetch();
    render(<ProfilClient />);
    await screen.findByText('sonia.staff@equipe.test');
    expect(link(/^Aide & Support/)).toHaveAttribute('href', '/support');
  });
});
