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
const OWNER: Membership = {
  role: 'owner',
  capabilities: [...MANAGER.capabilities, 'finances.view', 'salon.publish'],
};

/// Any money label on the home. Rename-proof on purpose: the negative checks
/// below were keyed on « Revenus ce mois », and the day the label became
/// « Revenus prévus ce mois » they would have gone on passing with the money
/// row on screen. The owner test proves this matches what the row renders.
const MONEY_LABEL = /^Revenus/;

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
        // Field-gated server-side: the revenue keys only with finances.view.
        const money = membership.capabilities.includes('finances.view');
        return new Response(
          JSON.stringify({
            todayAppointments: 1,
            pendingRequests: 1,
            ...(money
              ? { todayRevenue: 62000, weekRevenue: 98000, monthRevenue: 410000 }
              : {}),
          }),
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
    expect(screen.queryAllByText(MONEY_LABEL)).toHaveLength(0);
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
    expect(screen.queryAllByText(MONEY_LABEL)).toHaveLength(0);
    expect(screen.queryByText('Configurer mon profil')).toBeNull();
    expect(screen.getByText('Rendez-vous du jour')).toBeTruthy();
    expect(calls.some((u) => u.startsWith('/api/pro/dashboard'))).toBe(false);
  });

  /// provider-dashboard-stats.md §12: the home's money figures count
  /// confirmed + completed bookings, while « Revenus » (/pro/revenus) counts
  /// completed only — so the home says « prévus ». Same words as the app.
  it('owner: the money row is « Revenus prévus … », each over its figure', async () => {
    mockFetch(OWNER);
    render(<AujourdhuiClient />);

    const labels = [
      ['Revenus prévus aujourd’hui', /62\s000/],
      ['Revenus prévus cette semaine', /98\s000/],
      ['Revenus prévus ce mois', /410\s000/],
    ] as const;
    for (const [label, figure] of labels) {
      const el = await screen.findByText(label);
      // The figure renders once the best-effort stats call lands ('—' before).
      await waitFor(() =>
        expect(el.previousElementSibling?.textContent).toMatch(figure),
      );
    }
    // Exactly those three — no bare « Revenus … » left beside them.
    expect(
      screen.queryAllByText(MONEY_LABEL).map((e) => e.textContent),
    ).toEqual(labels.map(([l]) => l));
  });
});
