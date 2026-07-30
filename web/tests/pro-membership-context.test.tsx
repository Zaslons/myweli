import { cleanup, render, screen, waitFor } from '@testing-library/react';
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

/// Team access R5b — the membership probe. The critical paths: a 403
/// not_a_member signs the member out onto the banner URL; a 200 exposes the
/// capabilities to the sidebar.

function Probe() {
  const { loading, membership, can, salonName } = useProMembership();
  if (loading) return <p>chargement</p>;
  return (
    <div>
      <p>role:{membership?.role ?? 'legacy'}</p>
      <p>finances:{can('finances.view') ? 'oui' : 'non'}</p>
      <p>salon:{salonName}</p>
    </div>
  );
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
  pathname = '/pro';
});

describe('ProMembershipProvider', () => {
  it('REVOKED (403 not_a_member) → logout + the motif redirect, once', async () => {
    const calls: string[] = [];
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string, init?: RequestInit) => {
        calls.push(`${init?.method ?? 'GET'} ${url}`);
        if (url === '/api/pro/me') {
          return new Response(JSON.stringify({ error: 'not_a_member' }), {
            status: 403,
          });
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

    await waitFor(() =>
      expect(replace).toHaveBeenCalledWith(
        '/pro/connexion?motif=acces-retire',
      ),
    );
    expect(calls).toContain('POST /api/pro/auth/logout');
  });

  it('200 with a manager membership → can() reflects the capabilities', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) =>
        url === '/api/pro/me'
          ? new Response(
              JSON.stringify({
                account: { id: 'acc2', email: 'awa.manager@equipe.test' },
                provider: { id: 'p1', name: 'Beauté Divine' },
                membership: {
                  role: 'manager',
                  capabilities: ['journal.manage.all', 'clients.view'],
                },
              }),
              { status: 200 },
            )
          : new Response('{}', { status: 404 }),
      ),
    );

    render(
      <ProMembershipProvider>
        <Probe />
      </ProMembershipProvider>,
    );

    expect(await screen.findByText('role:manager')).toBeTruthy();
    expect(screen.getByText('finances:non')).toBeTruthy();
    expect(screen.getByText('salon:Beauté Divine')).toBeTruthy();
    expect(replace).not.toHaveBeenCalled();
  });

  it('LEGACY 200 without a membership block → owner-shaped can()', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) =>
        url === '/api/pro/me'
          ? new Response(
              JSON.stringify({
                account: { id: 'acc1' },
                provider: { id: 'p1', name: 'Beauté Divine' },
              }),
              { status: 200 },
            )
          : new Response('{}', { status: 404 }),
      ),
    );

    render(
      <ProMembershipProvider>
        <Probe />
      </ProMembershipProvider>,
    );

    expect(await screen.findByText('role:legacy')).toBeTruthy();
    expect(screen.getByText('finances:oui')).toBeTruthy();
  });

  it('401 → no redirect from the context (page guards own it)', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => new Response(null, { status: 401 })),
    );

    render(
      <ProMembershipProvider>
        <Probe />
      </ProMembershipProvider>,
    );

    await screen.findByText('role:legacy');
    expect(replace).not.toHaveBeenCalled();
  });
});
