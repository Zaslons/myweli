import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const routerMock = { replace: vi.fn(), push: vi.fn() };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { AvisClient } from '../components/pro/AvisClient';

/// docs/design/salon-reviews-summary.md — the « Avis » card shows the whole
/// salon: the web averaged the 50 reviews it had loaded beside the server's
/// total (60 here), so a salon whose 10 oldest were 1★ read « 5,0 ».

const FIFTY_FIVES = Array.from({ length: 50 }, (_, i) => ({
  id: `r${i}`,
  rating: 5,
  comment: '',
  userName: 'Awa',
  createdAt: '2026-10-01T10:00:00.000Z',
}));

function stub(body: Record<string, unknown>) {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      const u = String(url);
      if (u === '/api/pro/me') {
        return new Response(
          JSON.stringify({ account: { id: 'acc' }, provider: { id: 'p1', name: 'Beauté Divine' } }),
          { status: 200 },
        );
      }
      if (u.startsWith('/api/pro/reviews')) {
        return new Response(JSON.stringify(body), { status: 200 });
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('AvisClient — the card is the whole salon’s', () => {
  it('the server’s average, count and bars — not the page’s', async () => {
    stub({
      items: FIFTY_FIVES,
      page: 1,
      pageSize: 50,
      total: 60,
      summary: {
        average: 4.2,
        count: 60,
        distribution: { '5': 50, '4': 0, '3': 0, '2': 0, '1': 10 },
      },
    });
    render(<AvisClient />);
    expect(await screen.findByText('60 avis')).toBeInTheDocument();
    expect(screen.getByText(/4,2/)).toBeInTheDocument();
    expect(screen.queryByText(/5,0/)).toBeNull();
    const one = screen.getByRole('progressbar', { name: '1 étoiles' });
    expect(one).toHaveAttribute('aria-valuenow', '10');
    expect(one).toHaveAttribute('aria-valuemax', '60');
  });

  it('a server without the summary: the page’s own numbers, as before', async () => {
    stub({ items: FIFTY_FIVES.slice(0, 2), page: 1, pageSize: 50, total: 2 });
    render(<AvisClient />);
    expect(await screen.findByText('2 avis')).toBeInTheDocument();
    expect(screen.getByText(/5,0/)).toBeInTheDocument();
  });
});
