import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
// Stable object: the client's init callback depends on [router].
const routerMock = { replace };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { RevenusClient } from '../components/pro/RevenusClient';

/// « Revenus » says what its total counts (provider-earnings.md §12): the
/// total is completed bookings only, while the home's « Revenus prévus … »
/// cards also count confirmed ones. So the card reads « Total réalisé », the
/// figure, then « Rendez-vous terminés » — the app's words — and nothing on
/// the page says « encaissé »: MyWeli never sees a payment.

function mockFetch(transactions: unknown[], total: number) {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      if (url === '/api/pro/me') {
        return new Response(
          JSON.stringify({
            account: { id: 'acc-o', email: 'o@salon.test' },
            provider: { id: 'p1', name: 'Beauté Divine', status: 'active' },
          }),
          { status: 200 },
        );
      }
      if (url.startsWith('/api/pro/earnings')) {
        return new Response(
          JSON.stringify({ totalEarnings: total, transactions }),
          { status: 200 },
        );
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

/// The total card's lines, top to bottom.
async function totalCard(): Promise<string[]> {
  const label = await screen.findByText('Total réalisé');
  return Array.from(label.parentElement?.children ?? []).map(
    (e) => e.textContent ?? '',
  );
}

describe('RevenusClient — the words', () => {
  it('with takings: « Total réalisé », the figure, « Rendez-vous terminés »', async () => {
    mockFetch(
      [
        {
          id: 'transaction_a1',
          appointmentId: 'a1',
          amount: 15000,
          date: '2026-10-14T10:00:00Z',
          status: 'completed',
        },
      ],
      15000,
    );
    render(<RevenusClient />);

    const lines = await totalCard();
    expect(lines).toHaveLength(3);
    expect(lines[0]).toBe('Total réalisé');
    expect(lines[1]).toMatch(/15\s000/);
    expect(lines[2]).toBe('Rendez-vous terminés');
    expect(screen.queryByText('Total')).toBeNull();
    expect(document.body.textContent).not.toMatch(/encaiss/i);
  });

  it('empty period: the empty state promises completed bookings, not payments', async () => {
    mockFetch([], 0);
    render(<RevenusClient />);

    expect(await totalCard()).toEqual([
      'Total réalisé',
      expect.stringMatching(/^0\s/),
      'Rendez-vous terminés',
    ]);
    expect(await screen.findByText('Aucune transaction')).toBeTruthy();
    // Before the exact string, so the old « Les encaissements … » fails on
    // the word that is wrong rather than on a near-miss.
    expect(document.body.textContent).not.toMatch(/encaiss/i);
    expect(
      screen.getByText(
        'Les rendez-vous terminés de la période choisie apparaîtront ici.',
      ),
    ).toBeTruthy();
  });
});
