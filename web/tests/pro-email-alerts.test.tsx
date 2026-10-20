import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
const push = vi.fn();
// STABLE — a fresh object each call churns the membership probe's callback
// (pro-mobile-nav.test.tsx).
const routerMock = { replace, push };
let pathname = '/pro/notifications';
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => pathname,
}));
// A next/link outside an app router throws on click (no router to push to);
// a plain anchor keeps the href under test and swallows jsdom's
// « navigation not implemented ».
vi.mock('next/link', async () => {
  const React = await import('react');
  return {
    default: ({
      href,
      children,
      onClick,
      prefetch: _prefetch,
      ...rest
    }: {
      href: string;
      children: React.ReactNode;
      onClick?: (e: React.MouseEvent<HTMLAnchorElement>) => void;
      prefetch?: boolean;
    } & React.AnchorHTMLAttributes<HTMLAnchorElement>) =>
      React.createElement(
        'a',
        {
          ...rest,
          href,
          onClick: (e: React.MouseEvent<HTMLAnchorElement>) => {
            onClick?.(e);
            e.preventDefault();
          },
        },
        children,
      ),
  };
});

import { ProMembershipProvider } from '../components/pro/ProMembershipContext';
import { ProNotificationsClient } from '../components/pro/ProNotificationsClient';
import { ProShell } from '../components/pro/ProShell';

/// docs/design/salon-email-alerts.md §4 — « Alertes par e-mail » on the
/// salon's Notifications page: when no notification of the MyWeli Pro app can
/// reach a member, the server writes to them instead. Each member sets their
/// own; on by default (owner Q2).

const OWNER = {
  account: { id: 'acc1', email: 'salon@example.com' },
  provider: { id: 'p1', name: 'Beauté Divine' },
  membership: { role: 'owner', capabilities: ['clients.view', 'profile.manage'] },
};

const NOTE = {
  id: 'n1',
  type: 'general',
  title: 'Nouvelle réservation',
  body: 'Nouvelle demande de réservation le 28/06/2026 à 14:30.',
  createdAt: '2026-06-28T10:00:00.000Z',
  read: false,
  route: '/pro/appointment/a1?salon=p1',
};

let feed: unknown[] = [NOTE];
let prefsRead: number | 'offline' = 200;
let prefsWrite: number | 'offline' = 200;
let stored = { reminders: true, marketing: true, push: true, emailAlerts: true };
const puts: unknown[] = [];

beforeEach(() => {
  feed = [NOTE];
  prefsRead = 200;
  prefsWrite = 200;
  stored = { reminders: true, marketing: true, push: true, emailAlerts: true };
  puts.length = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const u = String(url);
      if (u === '/api/pro/me') return new Response(JSON.stringify(OWNER), { status: 200 });
      if (u === '/api/pro/salons') {
        return new Response(
          JSON.stringify({
            items: [{ salonId: 'p1', salonName: 'Beauté Divine', role: 'owner', salonStatus: 'active' }],
            canAddSalon: false,
          }),
          { status: 200 },
        );
      }
      if (u === '/api/pro/notifications') {
        return new Response(JSON.stringify({ items: feed }), { status: 200 });
      }
      if (u === '/api/pro/notification-preferences') {
        if (init?.method === 'PUT') {
          const body = JSON.parse(String(init.body));
          puts.push(body);
          if (prefsWrite === 'offline') throw new TypeError('Failed to fetch');
          if (prefsWrite !== 200) return new Response('{}', { status: prefsWrite });
          stored = { ...stored, ...body };
          return new Response(JSON.stringify(stored), { status: 200 });
        }
        if (prefsRead === 'offline') throw new TypeError('Failed to fetch');
        if (prefsRead !== 200) return new Response('{}', { status: prefsRead });
        return new Response(JSON.stringify(stored), { status: 200 });
      }
      return new Response('{}', { status: 404 });
    }),
  );
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
  push.mockReset();
});

function host() {
  return render(
    <ProMembershipProvider>
      <ProShell>
        <ProNotificationsClient />
      </ProShell>
    </ProMembershipProvider>,
  );
}

const sw = () => screen.findByRole('switch', { name: 'Alertes par e-mail' });

describe('« Alertes par e-mail » (owner Q2: the words as written, on by default)', () => {
  it('under « Préférences », on, and it says where it writes', async () => {
    host();
    expect(await sw()).toHaveAttribute('aria-checked', 'true');
    expect(screen.getByRole('heading', { name: 'Préférences' })).toBeInTheDocument();
    expect(
      screen.getByText(
        'Si une notification de l’app MyWeli Pro ne peut pas vous parvenir, nous vous écrivons à salon@example.com : nouvelle demande, report, annulation, justificatif d’acompte.',
      ),
    ).toBeInTheDocument();
  });

  it('a click turns it off — the write carries that one field', async () => {
    host();
    fireEvent.click(await sw());
    await waitFor(() => expect(puts).toEqual([{ emailAlerts: false }]));
    expect(await sw()).toHaveAttribute('aria-checked', 'false');
  });

  it('a refused write puts it back and says so', async () => {
    prefsWrite = 500;
    host();
    fireEvent.click(await sw());
    expect(await screen.findByText('L’enregistrement a échoué. Réessayez.')).toBeInTheDocument();
    expect(await sw()).toHaveAttribute('aria-checked', 'true');
  });

  it('no network → it goes back, and the sentence says why', async () => {
    prefsWrite = 'offline';
    host();
    fireEvent.click(await sw());
    expect(await screen.findByText('Pas de connexion. Réessayez.')).toBeInTheDocument();
    expect(await sw()).toHaveAttribute('aria-checked', 'true');
  });

  it('the preferences cannot be read: the list stays, the section can retry', async () => {
    prefsRead = 500;
    host();
    expect(await screen.findByText(NOTE.body)).toBeInTheDocument();
    const retry = await screen.findByRole('button', { name: 'Réessayer' });
    expect(screen.queryByRole('switch')).toBeNull();
    prefsRead = 200;
    fireEvent.click(retry);
    expect(await sw()).toHaveAttribute('aria-checked', 'true');
  });

  it('an empty feed still has the switch', async () => {
    feed = [];
    host();
    expect(await sw()).toBeInTheDocument();
  });

  it('an API older than the switch (no emailAlerts) shows none — not one that saves nothing', async () => {
    const { emailAlerts: _gone, ...older } = stored;
    stored = older as typeof stored;
    host();
    expect(await screen.findByText(NOTE.body)).toBeInTheDocument();
    await waitFor(() => expect(vi.mocked(fetch).mock.calls.some(([u]) => String(u) === '/api/pro/notification-preferences')).toBe(true));
    // Settled: no switch, no heading, no error.
    await new Promise((r) => setTimeout(r, 50));
    expect(screen.queryByRole('switch')).toBeNull();
    expect(screen.queryByRole('heading', { name: 'Préférences' })).toBeNull();
    expect(screen.queryByRole('button', { name: 'Réessayer' })).toBeNull();
  });

  it('a member who turned it off finds it off', async () => {
    stored = { ...stored, emailAlerts: false };
    host();
    expect(await sw()).toHaveAttribute('aria-checked', 'false');
  });
});
