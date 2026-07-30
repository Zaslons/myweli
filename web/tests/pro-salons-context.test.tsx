import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
let pathname = '/pro';
// Stable object: the probe callback depends on the router identity.
const routerMock = { replace };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => pathname,
}));

import {
  ProMembershipProvider,
  useProMembership,
} from '../components/pro/ProMembershipContext';

/// Team access R6c — the multi-salon context: « Mes salons » loads, a switch
/// posts the (server-validated) selection and bumps the remount epoch, and
/// a per-salon 403 `forbidden` on the probe clears the selection ONCE and
/// falls back — never a sign-out (`not_a_member` keeps the sign-out, pinned
/// in pro-membership-context.test.tsx).

const P1 = {
  account: { id: 'acc1', email: 'salon@example.com' },
  provider: { id: 'p1', name: 'Beauté Divine' },
  membership: { role: 'owner', capabilities: ['finances.view'] },
};
const P3 = {
  account: { id: 'acc1', email: 'salon@example.com' },
  provider: { id: 'p3', name: 'Institut Belle Vue' },
  membership: { role: 'owner', capabilities: ['finances.view'] },
};
const SALONS = {
  items: [
    { salonId: 'p1', salonName: 'Beauté Divine', role: 'owner', salonStatus: 'active', verified: true },
    { salonId: 'p3', salonName: 'Institut Belle Vue', role: 'owner', salonStatus: 'draft', verified: true },
  ],
  canAddSalon: true,
};

function Probe() {
  const { loading, salonName, salons, canAddSalon, switchSalon, switchEpoch } =
    useProMembership();
  if (loading) return <p>chargement</p>;
  return (
    <div>
      <p>salon:{salonName}</p>
      <p>count:{salons.length}</p>
      <p>add:{canAddSalon ? 'oui' : 'non'}</p>
      <p>epoch:{switchEpoch}</p>
      <button type="button" onClick={() => switchSalon('p3')}>
        basculer
      </button>
    </div>
  );
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
  pathname = '/pro';
});

describe('ProMembershipProvider — multi-salons', () => {
  it('loads « Mes salons »; a switch posts the selection and bumps the epoch', async () => {
    const calls: { url: string; body?: unknown }[] = [];
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string, init?: RequestInit) => {
        calls.push({
          url,
          body: init?.body ? JSON.parse(init.body as string) : undefined,
        });
        if (url === '/api/pro/me') {
          return new Response(JSON.stringify(P1), { status: 200 });
        }
        if (url === '/api/pro/salons') {
          return new Response(JSON.stringify(SALONS), { status: 200 });
        }
        if (url === '/api/pro/salons/select') {
          // The BFF validates then returns the SELECTED salon's payload.
          return new Response(JSON.stringify(P3), { status: 200 });
        }
        return new Response('{}', { status: 404 });
      }),
    );

    render(
      <ProMembershipProvider>
        <Probe />
      </ProMembershipProvider>,
    );

    expect(await screen.findByText('salon:Beauté Divine')).toBeTruthy();
    expect(screen.getByText('count:2')).toBeTruthy();
    expect(screen.getByText('add:oui')).toBeTruthy();
    expect(screen.getByText('epoch:0')).toBeTruthy();

    fireEvent.click(screen.getByText('basculer'));
    expect(await screen.findByText('salon:Institut Belle Vue')).toBeTruthy();
    expect(screen.getByText('epoch:1')).toBeTruthy();
    const select = calls.find((c) => c.url === '/api/pro/salons/select');
    expect(select?.body).toEqual({ salonId: 'p3' });
    expect(replace).not.toHaveBeenCalled();
  });

  it('a REFUSED switch keeps the current salon (no epoch bump)', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) => {
        if (url === '/api/pro/me') {
          return new Response(JSON.stringify(P1), { status: 200 });
        }
        if (url === '/api/pro/salons') {
          return new Response(JSON.stringify(SALONS), { status: 200 });
        }
        if (url === '/api/pro/salons/select') {
          return new Response(JSON.stringify({ error: 'forbidden' }), {
            status: 403,
          });
        }
        return new Response('{}', { status: 404 });
      }),
    );

    render(
      <ProMembershipProvider>
        <Probe />
      </ProMembershipProvider>,
    );
    await screen.findByText('salon:Beauté Divine');
    fireEvent.click(screen.getByText('basculer'));
    // Still the same salon, epoch untouched.
    await waitFor(() =>
      expect(screen.getByText('salon:Beauté Divine')).toBeTruthy(),
    );
    expect(screen.getByText('epoch:0')).toBeTruthy();
  });

  it('a per-salon 403 forbidden on the probe clears the selection once and '
    + 'falls back — NEVER a sign-out', async () => {
    const calls: { url: string; body?: unknown }[] = [];
    let probes = 0;
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string, init?: RequestInit) => {
        calls.push({
          url,
          body: init?.body ? JSON.parse(init.body as string) : undefined,
        });
        if (url === '/api/pro/me') {
          probes += 1;
          // The FIRST probe hits the revoked-selected salon; after the
          // clear, the default salon answers.
          return probes === 1
            ? new Response(JSON.stringify({ error: 'forbidden' }), {
                status: 403,
              })
            : new Response(JSON.stringify(P1), { status: 200 });
        }
        if (url === '/api/pro/salons') {
          return new Response(JSON.stringify(SALONS), { status: 200 });
        }
        if (url === '/api/pro/salons/select') {
          return new Response(JSON.stringify({ ok: true }), { status: 200 });
        }
        if (url === '/api/pro/auth/logout') {
          return new Response(JSON.stringify({ ok: true }), { status: 200 });
        }
        return new Response('{}', { status: 404 });
      }),
    );

    render(
      <ProMembershipProvider>
        <Probe />
      </ProMembershipProvider>,
    );

    expect(await screen.findByText('salon:Beauté Divine')).toBeTruthy();
    // The clear went through the select route with null…
    const clear = calls.find(
      (c) =>
        c.url === '/api/pro/salons/select' &&
        (c.body as { salonId?: string | null } | undefined)?.salonId === null,
    );
    expect(clear).toBeTruthy();
    // …and the session survived (no logout, no redirect).
    expect(calls.some((c) => c.url === '/api/pro/auth/logout')).toBe(false);
    expect(replace).not.toHaveBeenCalled();
  });
});
