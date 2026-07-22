import { cleanup, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
// Stable object: the client's load effect depends on [router].
const routerMock = { replace };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { AujourdhuiClient } from '../components/pro/AujourdhuiClient';
import type { Membership } from '../lib/pro/team';

/// Team access R5b — the role-shaped dashboard. Manager: counts without the
/// money row (the server field-gates revenue — rendering it would lie 0 F).
/// Staff: « {salon} — votre planning », no stats, no dashboard call.

const MANAGER: Membership = {
  role: 'manager',
  capabilities: [
    'availability.manage',
    'catalogue.manage',
    'clients.view',
    'journal.manage.all',
    'journal.manage.own',
    'journal.view.all',
    'journal.view.own',
    'profile.manage',
  ],
};
const STAFF: Membership = {
  role: 'staff',
  capabilities: ['journal.manage.own', 'journal.view.own'],
  artistId: 'a1',
  artistName: 'Awa',
};

function mockFetch(membership: Membership) {
  const calls: string[] = [];
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      calls.push(url);
      if (url === '/api/pro/me') {
        return new Response(
          JSON.stringify({
            account: { id: 'acc-m', email: 'x@equipe.test' },
            provider: { id: 'p1', name: 'Beauté Divine', status: 'active' },
            membership,
          }),
          { status: 200 },
        );
      }
      if (url === '/api/pro/appointments') {
        return new Response(JSON.stringify({ items: [] }), { status: 200 });
      }
      if (url.startsWith('/api/pro/dashboard')) {
        // Field-gated: counts only (no revenue keys) for a manager.
        return new Response(
          JSON.stringify({ todayAppointments: 1, pendingRequests: 1 }),
          { status: 200 },
        );
      }
      if (url === '/api/pro/invitations') {
        return new Response(JSON.stringify({ invitations: [] }), {
          status: 200,
        });
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

describe('AujourdhuiClient — role shapes', () => {
  it('manager: counts row yes, money row NO, no offer fetch', async () => {
    const calls = mockFetch(MANAGER);
    render(<AujourdhuiClient />);

    const pending = await screen.findByText('Demandes en attente');
    // Parity with the app (B7): the value is DashboardStats.pendingRequests —
    // pending across ALL dates (1 in the mock), not the today-only count (0:
    // the appointments list is empty). The today-only fallback showing here
    // would read 0.
    await waitFor(() =>
      expect(pending.previousElementSibling?.textContent).toBe('1'),
    );
    expect(screen.queryByText('Revenus ce mois')).toBeNull();
    expect(screen.queryByText('Revenus aujourd’hui')).toBeNull();
    // The dashboard call still runs (journal.view.all) …
    await waitFor(() =>
      expect(calls.some((u) => u.startsWith('/api/pro/dashboard'))).toBe(true),
    );
    // … but never the owner-only offer read.
    expect(calls.some((u) => u.startsWith('/api/pro/salon-subscription'))).toBe(
      false,
    );
  });

  it('staff: « {salon} — votre planning », no stats, no dashboard call', async () => {
    const calls = mockFetch(STAFF);
    render(<AujourdhuiClient />);

    expect(
      await screen.findByRole('heading', {
        name: 'Beauté Divine — votre planning',
      }),
    ).toBeTruthy();
    expect(screen.queryByText('Demandes en attente')).toBeNull();
    expect(screen.queryByText('Revenus ce mois')).toBeNull();
    expect(screen.queryByText('Configurer mon profil')).toBeNull();
    expect(screen.getByText('Rendez-vous du jour')).toBeTruthy();
    expect(calls.some((u) => u.startsWith('/api/pro/dashboard'))).toBe(false);
  });
});
