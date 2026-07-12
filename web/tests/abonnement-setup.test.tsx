import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
vi.mock('next/navigation', () => ({ useRouter: () => ({ replace }) }));

import { AbonnementClient } from '../components/pro/AbonnementClient';

/// Team access R5a — the offer picker's SETUP state. A 404 on
/// GET /providers/{id}/subscription is the free no-offer state (not an error):
/// the « 3 mois offerts » headline + the three cards, and choosing one starts
/// the trial.

function mockOffer(opts: { getStatus: number; getBody?: unknown }) {
  const calls: { url: string; method: string; body: Record<string, unknown> }[] =
    [];
  const fn = vi.fn(async (url: string, init?: RequestInit) => {
    const method = init?.method ?? 'GET';
    const body = init?.body ? JSON.parse(init.body as string) : {};
    calls.push({ url, method, body });
    if (url === '/api/pro/me' || url === '/api/pro/provider') {
      return new Response(
        JSON.stringify({ provider: { id: 'p1', name: 'Beauté Divine' } }),
        { status: 200 },
      );
    }
    if (url.startsWith('/api/pro/salon-subscription')) {
      return new Response(JSON.stringify(opts.getBody ?? { error: 'no_offer' }), {
        status: opts.getStatus,
      });
    }
    return new Response('{}', { status: 404 });
  });
  vi.stubGlobal('fetch', fn);
  return { fn, calls };
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
});

describe('AbonnementClient — setup (no offer)', () => {
  it('404 → the 3-months-free headline + the three cards', async () => {
    mockOffer({ getStatus: 404 });
    render(<AbonnementClient />);
    expect(await screen.findByText(/3 mois offerts/)).toBeTruthy();
    expect(screen.getByRole('heading', { name: 'Pro' })).toBeTruthy();
    expect(screen.getByRole('heading', { name: 'Business' })).toBeTruthy();
    expect(screen.getByRole('heading', { name: 'Réseau' })).toBeTruthy();
    // Every card offers the choice in setup.
    expect(
      screen.getAllByRole('button', { name: 'Choisir cette offre' }),
    ).toHaveLength(3);
  });

  it('choosing a tier PUTs the offer and shows the trial banner', async () => {
    const { calls } = mockOffer({ getStatus: 404 });
    // After the PUT the component holds the returned live-trial offer.
    const fn = vi.fn(async (url: string, init?: RequestInit) => {
      const method = init?.method ?? 'GET';
      calls.push({ url, method, body: init?.body ? JSON.parse(init.body as string) : {} });
      if (url === '/api/pro/me' || url === '/api/pro/provider') {
        return new Response(
          JSON.stringify({ provider: { id: 'p1', name: 'Beauté Divine' } }),
          { status: 200 },
        );
      }
      if (url.startsWith('/api/pro/salon-subscription')) {
        if (method === 'PUT') {
          return new Response(
            JSON.stringify({
              tier: 'pro',
              status: 'trial',
              trialEndsAt: '2026-10-12T00:00:00.000Z',
              graceEndsAt: '2026-10-19T00:00:00.000Z',
              seats: { cap: 5, used: 1 },
            }),
            { status: 200 },
          );
        }
        return new Response(JSON.stringify({ error: 'no_offer' }), {
          status: 404,
        });
      }
      return new Response('{}', { status: 404 });
    });
    vi.stubGlobal('fetch', fn);

    render(<AbonnementClient />);
    const choose = await screen.findAllByRole('button', {
      name: 'Choisir cette offre',
    });
    fireEvent.click(choose[0]);

    await waitFor(() =>
      expect(screen.getByText(/Essai gratuit/)).toBeTruthy(),
    );
    const put = calls.find((c) => c.method === 'PUT');
    expect(put?.body).toMatchObject({ providerId: 'p1', tier: 'pro' });
  });

  it('trial_used (409) → the contact notice', async () => {
    const fn = vi.fn(async (url: string, init?: RequestInit) => {
      const method = init?.method ?? 'GET';
      if (url === '/api/pro/me' || url === '/api/pro/provider') {
        return new Response(
          JSON.stringify({ provider: { id: 'p1', name: 'Beauté Divine' } }),
          { status: 200 },
        );
      }
      if (url.startsWith('/api/pro/salon-subscription')) {
        if (method === 'PUT') {
          return new Response(JSON.stringify({ error: 'trial_used' }), {
            status: 409,
          });
        }
        return new Response(JSON.stringify({ error: 'no_offer' }), {
          status: 404,
        });
      }
      return new Response('{}', { status: 404 });
    });
    vi.stubGlobal('fetch', fn);

    render(<AbonnementClient />);
    const choose = await screen.findAllByRole('button', {
      name: 'Choisir cette offre',
    });
    fireEvent.click(choose[0]);
    expect(await screen.findByText(/essai gratuit a déjà été utilisé/i)).toBeTruthy();
  });
});
