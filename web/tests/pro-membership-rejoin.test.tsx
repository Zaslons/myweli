import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
let pathname = '/pro';
// Stable object: the probe callback depends on the router identity.
const routerMock = { replace };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => pathname,
}));

import { AujourdhuiClient } from '../components/pro/AujourdhuiClient';
import {
  ProMembershipProvider,
  useProMembership,
} from '../components/pro/ProMembershipContext';
import { ProSidebar } from '../components/pro/ProSidebar';

/// The rejoin gate on the web (docs/design/pro-rejoin-gate.md §2–§4): a
/// `403 not_a_member` from a still-live session asks for the account's own
/// invitations first. One or more → the « Invitations » page replaces the
/// dashboard and the session is kept; none, or any failure → today's sign-out
/// with the banner (fail closed), after ONE re-check of /me when the list was
/// empty. The not_a_member sign-out itself stays pinned in
/// pro-membership-context.test.tsx.

const MOTIF = '/pro/connexion?motif=acces-retire';

const INV = {
  id: 'inv-1',
  providerId: 'p1',
  salonName: 'Beauté Divine',
  role: 'staff',
  roleLabel: 'Collaborateur',
  expiresAt: '2099-01-01T00:00:00.000Z',
};
const INV_OTHER = {
  id: 'inv-2',
  providerId: 'p2',
  salonName: 'Institut Belle Vue',
  role: 'reception',
  roleLabel: 'Réception',
  expiresAt: '2099-01-01T00:00:00.000Z',
};
const STAFF_P1 = {
  account: { id: 'acc-x', email: 'ancien@equipe.test' },
  provider: { id: 'p1', name: 'Beauté Divine', status: 'active' },
  membership: {
    role: 'staff',
    capabilities: ['journal.manage.own', 'journal.view.own'],
    artistId: 'a1',
    artistName: 'Awa',
  },
};
const OWNER_P1 = {
  account: { id: 'acc1', email: 'salon@example.com' },
  provider: { id: 'p1', name: 'Beauté Divine' },
  membership: { role: 'owner', capabilities: ['finances.view'] },
};

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status });
const notAMember = () => json(403, { error: 'not_a_member' });

/// `n` is the 1-based call count of THAT url, so a route can answer a
/// sequence (the revoked probe, then the re-check after an accept).
type Handler = (n: number, init?: RequestInit) => Promise<Response> | Response;

function mockFetch(routes: Record<string, Handler>) {
  const calls: string[] = [];
  const counts = new Map<string, number>();
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      calls.push(`${init?.method ?? 'GET'} ${url}`);
      const n = (counts.get(url) ?? 0) + 1;
      counts.set(url, n);
      const handler = routes[url];
      if (handler) return handler(n, init);
      if (url === '/api/pro/auth/logout') return json(200, { ok: true });
      if (url === '/api/pro/salons/select') return json(200, { ok: true });
      return new Response('{}', { status: 404 });
    }),
  );
  return {
    calls,
    count: (call: string) => calls.filter((c) => c === call).length,
  };
}

function Dashboard() {
  const { loading, membership } = useProMembership();
  if (loading) return <p>chargement</p>;
  return <p>tableau de bord · role:{membership?.role ?? 'legacy'}</p>;
}

function renderProvider() {
  return render(
    <ProMembershipProvider>
      <Dashboard />
    </ProMembershipProvider>,
  );
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
  pathname = '/pro';
});

describe('ProMembershipProvider — the rejoin gate', () => {
  it('not_a_member + an invitation → the « Invitations » page instead of the '
    + 'dashboard; the session is kept', async () => {
    const { calls } = mockFetch({
      '/api/pro/me': notAMember,
      '/api/pro/invitations': () => json(200, { invitations: [INV] }),
    });

    renderProvider();

    expect(
      await screen.findByRole('heading', { level: 1, name: 'Invitations' }),
    ).toBeTruthy();
    expect(screen.getByText(/vous\s+invite comme Collaborateur/)).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Rejoindre' })).toBeTruthy();
    // Nothing of the dashboard (ProShell lives in the children).
    expect(screen.queryByText(/tableau de bord/)).toBeNull();
    // The session survives; the lost salon's selection does not.
    expect(calls).not.toContain('POST /api/pro/auth/logout');
    expect(replace).not.toHaveBeenCalled();
    expect(calls).toContain('POST /api/pro/salons/select');
  });

  it('not_a_member + NO invitation → re-checks /me once, then logout + motif', async () => {
    const { calls, count } = mockFetch({
      '/api/pro/me': notAMember,
      '/api/pro/invitations': () => json(200, { invitations: [] }),
    });

    renderProvider();

    await waitFor(() => expect(replace).toHaveBeenCalledWith(MOTIF));
    expect(calls).toContain('POST /api/pro/auth/logout');
    expect(count('GET /api/pro/me')).toBe(2);
  });

  it('an EMPTY list whose re-check answers 200 (an accept just landed) '
    + 'enters the app instead of signing out', async () => {
    const { calls } = mockFetch({
      '/api/pro/me': (n) => (n === 1 ? notAMember() : json(200, STAFF_P1)),
      '/api/pro/invitations': () => json(200, { invitations: [] }),
    });

    renderProvider();

    expect(await screen.findByText(/role:staff/)).toBeTruthy();
    expect(calls).not.toContain('POST /api/pro/auth/logout');
    expect(replace).not.toHaveBeenCalledWith(MOTIF);
  });

  it('the invitations check FAILS (500) → re-checks /me once, then logout + '
    + 'motif: fail closed', async () => {
    const { calls, count } = mockFetch({
      '/api/pro/me': notAMember,
      '/api/pro/invitations': () => json(500, { error: 'internal' }),
    });

    renderProvider();

    await waitFor(() => expect(replace).toHaveBeenCalledWith(MOTIF));
    expect(calls).toContain('POST /api/pro/auth/logout');
    // Spec §10: the re-check precedes a sign-out decided on a FAILED list
    // too (the app's _decideOnRevoked) — it can only keep a session the
    // server ties to a salon.
    expect(count('GET /api/pro/me')).toBe(2);
    expect(screen.queryByRole('heading', { name: 'Invitations' })).toBeNull();
  });

  it('a FAILED list whose re-check answers 200 (an accept elsewhere just '
    + 'landed) enters the app instead of signing out', async () => {
    const { calls } = mockFetch({
      '/api/pro/me': (n) => (n === 1 ? notAMember() : json(200, STAFF_P1)),
      '/api/pro/invitations': () => json(502, { error: 'bad_gateway' }),
    });

    renderProvider();

    expect(await screen.findByText(/role:staff/)).toBeTruthy();
    expect(calls).not.toContain('POST /api/pro/auth/logout');
    expect(replace).not.toHaveBeenCalledWith(MOTIF);
  });

  it('the invitations check answers 401 (the session is gone) → logout + '
    + 'motif', async () => {
    const { calls } = mockFetch({
      '/api/pro/me': notAMember,
      '/api/pro/invitations': () => json(401, { error: 'not_authenticated' }),
    });

    renderProvider();

    await waitFor(() => expect(replace).toHaveBeenCalledWith(MOTIF));
    expect(calls).toContain('POST /api/pro/auth/logout');
  });

  it('the invitations fetch REJECTS (no network) → logout + motif', async () => {
    const { calls } = mockFetch({
      '/api/pro/me': notAMember,
      '/api/pro/invitations': () => {
        throw new TypeError('Failed to fetch');
      },
    });

    renderProvider();

    await waitFor(() => expect(replace).toHaveBeenCalledWith(MOTIF));
    expect(calls).toContain('POST /api/pro/auth/logout');
  });

  it('Rejoindre → loading, then the joined salon’s dashboard at /pro and '
    + '« Vous avez rejoint {salon} »', async () => {
    let releaseAccept: () => void = () => {};
    const { calls, count } = mockFetch({
      '/api/pro/me': (n) => (n === 1 ? notAMember() : json(200, STAFF_P1)),
      '/api/pro/invitations': () => json(200, { invitations: [INV] }),
      '/api/pro/invitations/inv-1/accept': () =>
        new Promise((resolve) => {
          releaseAccept = () =>
            resolve(json(200, { id: 'inv-1', status: 'active' }));
        }),
      '/api/pro/salons': () =>
        json(200, { items: [], canAddSalon: false }),
    });

    renderProvider();
    fireEvent.click(await screen.findByRole('button', { name: 'Rejoindre' }));
    // While the accept is out, the button wears its busy state.
    await waitFor(() =>
      expect(
        screen
          .getByRole('button', { name: 'Rejoindre' })
          .getAttribute('aria-busy'),
      ).toBe('true'),
    );
    releaseAccept();

    expect(await screen.findByText(/role:staff/)).toBeTruthy();
    expect(replace).toHaveBeenCalledWith('/pro');
    expect(
      await screen.findByText('Vous avez rejoint Beauté Divine'),
    ).toBeTruthy();
    expect(screen.queryByRole('heading', { name: 'Invitations' })).toBeNull();
    expect(calls).not.toContain('POST /api/pro/auth/logout');
    // « Mes salons » reloads for the new membership (mount + after the join).
    await waitFor(() => expect(count('GET /api/pro/salons')).toBe(2));
  });

  it('joining from a deeper page waits for /pro: no page of the old path '
    + 'mounts under the new role', async () => {
    pathname = '/pro/clients';
    mockFetch({
      '/api/pro/me': (n) => (n === 1 ? notAMember() : json(200, STAFF_P1)),
      '/api/pro/invitations': () => json(200, { invitations: [INV] }),
      '/api/pro/invitations/inv-1/accept': () =>
        json(200, { id: 'inv-1', status: 'active' }),
    });

    const { rerender } = renderProvider();
    fireEvent.click(await screen.findByRole('button', { name: 'Rejoindre' }));

    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro'));
    // Still on /pro/clients: the gate holds its loading state — the clients
    // page (a Collaborateur cannot use it) is never mounted.
    expect(screen.getByText('Chargement…')).toBeTruthy();
    expect(screen.queryByText(/tableau de bord/)).toBeNull();

    // The navigation lands.
    pathname = '/pro';
    rerender(
      <ProMembershipProvider>
        <Dashboard />
      </ProMembershipProvider>,
    );
    expect(await screen.findByText(/role:staff/)).toBeTruthy();
    expect(screen.queryByRole('heading', { name: 'Invitations' })).toBeNull();
  });

  it('Refuser on the LAST card → logout + motif', async () => {
    const { calls } = mockFetch({
      '/api/pro/me': notAMember,
      '/api/pro/invitations': () => json(200, { invitations: [INV] }),
      '/api/pro/invitations/inv-1/decline': () =>
        json(200, { declined: true }),
    });

    renderProvider();
    fireEvent.click(await screen.findByRole('button', { name: 'Refuser' }));

    await waitFor(() => expect(replace).toHaveBeenCalledWith(MOTIF));
    expect(calls).toContain('POST /api/pro/auth/logout');
  });

  it('Refuser one card of two → that card goes, the page stays', async () => {
    const { calls } = mockFetch({
      '/api/pro/me': notAMember,
      '/api/pro/invitations': () =>
        json(200, { invitations: [INV, INV_OTHER] }),
      '/api/pro/invitations/inv-1/decline': () =>
        json(200, { declined: true }),
    });

    renderProvider();
    await screen.findByText(/invite comme Collaborateur/);
    fireEvent.click(screen.getAllByRole('button', { name: 'Refuser' })[0]);

    await waitFor(() =>
      expect(screen.queryByText(/invite comme Collaborateur/)).toBeNull(),
    );
    expect(screen.getByText(/invite comme Réception/)).toBeTruthy();
    expect(screen.getByRole('heading', { name: 'Invitations' })).toBeTruthy();
    expect(calls).not.toContain('POST /api/pro/auth/logout');
  });

  it('accept 409 invitation_expired on the LAST card → logout + motif, and '
    + 'the expiry travels to the login (S3 → S6, as the app)', async () => {
    const { calls } = mockFetch({
      '/api/pro/me': notAMember,
      '/api/pro/invitations': () => json(200, { invitations: [INV] }),
      '/api/pro/invitations/inv-1/accept': () =>
        json(409, { error: 'invitation_expired' }),
    });

    renderProvider();
    fireEvent.click(await screen.findByRole('button', { name: 'Rejoindre' }));

    await waitFor(() =>
      expect(replace).toHaveBeenCalledWith(`${MOTIF}&raison=invitation-expiree`),
    );
    expect(calls).toContain('POST /api/pro/auth/logout');
  });

  it('accept 404 not_found on the LAST card → the « introuvable » reason '
    + 'travels too', async () => {
    mockFetch({
      '/api/pro/me': notAMember,
      '/api/pro/invitations': () => json(200, { invitations: [INV] }),
      '/api/pro/invitations/inv-1/accept': () =>
        json(404, { error: 'not_found' }),
    });

    renderProvider();
    fireEvent.click(await screen.findByRole('button', { name: 'Rejoindre' }));

    await waitFor(() =>
      expect(replace).toHaveBeenCalledWith(
        `${MOTIF}&raison=invitation-introuvable`,
      ),
    );
  });

  it('« Se déconnecter » on the gate → logout + motif', async () => {
    const { calls } = mockFetch({
      '/api/pro/me': notAMember,
      '/api/pro/invitations': () => json(200, { invitations: [INV] }),
    });

    renderProvider();
    fireEvent.click(
      await screen.findByRole('button', { name: 'Se déconnecter' }),
    );

    await waitFor(() => expect(replace).toHaveBeenCalledWith(MOTIF));
    expect(calls).toContain('POST /api/pro/auth/logout');
  });

  it('two not_a_member answers in flight share ONE invitations check', async () => {
    let releaseList: () => void = () => {};
    const { count } = mockFetch({
      '/api/pro/me': notAMember,
      '/api/pro/invitations': () =>
        new Promise((resolve) => {
          releaseList = () => resolve(json(200, { invitations: [INV] }));
        }),
    });

    const { rerender } = renderProvider();
    await waitFor(() => expect(count('GET /api/pro/invitations')).toBe(1));
    // A navigation while the first check is still out: a second probe, a
    // second not_a_member…
    pathname = '/pro/clients';
    rerender(
      <ProMembershipProvider>
        <Dashboard />
      </ProMembershipProvider>,
    );
    await waitFor(() => expect(count('GET /api/pro/me')).toBe(2));
    releaseList();

    expect(
      await screen.findByRole('heading', { name: 'Invitations' }),
    ).toBeTruthy();
    // …and still one check.
    expect(count('GET /api/pro/invitations')).toBe(1);
  });

  it('while the gate is up, a navigation does not probe again', async () => {
    const { count } = mockFetch({
      '/api/pro/me': notAMember,
      '/api/pro/invitations': () => json(200, { invitations: [INV] }),
    });

    const { rerender } = renderProvider();
    await screen.findByRole('heading', { name: 'Invitations' });
    expect(count('GET /api/pro/me')).toBe(1);

    pathname = '/pro/profil';
    rerender(
      <ProMembershipProvider>
        <Dashboard />
      </ProMembershipProvider>,
    );
    await new Promise((r) => setTimeout(r, 0));
    expect(count('GET /api/pro/me')).toBe(1);
    expect(replace).not.toHaveBeenCalled();
  });

  it('revoked MID-SESSION: the page names the salon that was lost', async () => {
    mockFetch({
      '/api/pro/me': (n) => (n === 1 ? json(200, OWNER_P1) : notAMember()),
      '/api/pro/invitations': () =>
        json(200, { invitations: [INV_OTHER] }),
    });

    const { rerender } = renderProvider();
    expect(await screen.findByText(/role:owner/)).toBeTruthy();

    pathname = '/pro/clients';
    rerender(
      <ProMembershipProvider>
        <Dashboard />
      </ProMembershipProvider>,
    );

    expect(
      await screen.findByText('Votre accès à Beauté Divine a été retiré.'),
    ).toBeTruthy();
    expect(screen.queryByText(/tableau de bord/)).toBeNull();
    expect(replace).not.toHaveBeenCalled();
  });

  it('a fresh login OR a page load (no salon known: the web keeps no '
    + 'membership cache) shows no « accès retiré » line above another '
    + 'salon’s card', async () => {
    mockFetch({
      '/api/pro/me': notAMember,
      '/api/pro/invitations': () =>
        json(200, { invitations: [INV_OTHER] }),
    });

    renderProvider();
    await screen.findByRole('heading', { name: 'Invitations' });

    expect(screen.queryByText(/a été retiré/)).toBeNull();
  });
});

describe('ProMembershipProvider — the rejoin gate, review fixes', () => {
  // [3]/[16] A sign-out is real or it is not shown.
  it('the sign-out’s logout call FAILS (no network) → never the signed-out '
    + 'login over a live session: a locked page that says so, and a retry '
    + 'that lands', async () => {
    let logoutDown = true;
    mockFetch({
      '/api/pro/me': notAMember,
      '/api/pro/invitations': () => json(200, { invitations: [] }),
      '/api/pro/auth/logout': () => {
        if (logoutDown) throw new TypeError('Failed to fetch');
        return json(200, { ok: true });
      },
    });

    renderProvider();

    expect(await screen.findByText('Pas de connexion. Réessayez.')).toBeTruthy();
    expect(replace).not.toHaveBeenCalled();
    // Locked: nothing of the dashboard, the revoked banner, the way out.
    expect(screen.queryByText(/tableau de bord/)).toBeNull();
    expect(
      screen.getByText('Votre accès à ce salon a été retiré.'),
    ).toBeTruthy();

    logoutDown = false;
    fireEvent.click(screen.getByRole('button', { name: 'Se déconnecter' }));
    await waitFor(() => expect(replace).toHaveBeenCalledWith(MOTIF));
  });

  it('« Se déconnecter » on the gate with NO network → stays on the gate, '
    + 'says so, the button comes back', async () => {
    mockFetch({
      '/api/pro/me': notAMember,
      '/api/pro/invitations': () => json(200, { invitations: [INV] }),
      '/api/pro/auth/logout': () => {
        throw new TypeError('Failed to fetch');
      },
    });

    renderProvider();
    fireEvent.click(
      await screen.findByRole('button', { name: 'Se déconnecter' }),
    );

    expect(await screen.findByText('Pas de connexion. Réessayez.')).toBeTruthy();
    expect(replace).not.toHaveBeenCalled();
    expect(screen.getByRole('heading', { name: 'Invitations' })).toBeTruthy();
    await waitFor(() =>
      expect(
        (screen.getByRole('button', { name: 'Se déconnecter' }) as HTMLButtonElement)
          .disabled,
      ).toBe(false),
    );
  });

  // [4] Never a nav drawn from an absent membership after a join.
  it('joining from /pro when the post-accept /me FAILS once: no owner nav for '
    + 'the new member — the sidebar waits, and the next probe brings the '
    + 'member’s own', async () => {
    mockFetch({
      '/api/pro/me': (n) =>
        n === 1
          ? notAMember()
          : n === 2
            ? json(503, { error: 'unavailable' })
            : json(200, STAFF_P1),
      '/api/pro/invitations': () => json(200, { invitations: [INV] }),
      '/api/pro/invitations/inv-1/accept': () =>
        json(200, { id: 'inv-1', status: 'active' }),
      '/api/pro/salons': () => json(200, { items: [], canAddSalon: false }),
    });

    render(
      <ProMembershipProvider>
        <ProSidebar />
      </ProMembershipProvider>,
    );
    fireEvent.click(await screen.findByRole('button', { name: 'Rejoindre' }));

    // The member's identity block: the profile committed.
    expect(await screen.findByText('ancien@equipe.test')).toBeTruthy();
    expect(screen.queryByRole('link', { name: 'Équipe' })).toBeNull();
    expect(screen.queryByRole('link', { name: 'Revenus' })).toBeNull();
    expect(screen.getByRole('link', { name: 'Rendez-vous' })).toBeTruthy();
  });

  it('…and while /me stays down, the sidebar keeps its skeleton — never the '
    + 'owner-shaped fallback', async () => {
    const { count } = mockFetch({
      '/api/pro/me': (n) =>
        n === 1 ? notAMember() : json(503, { error: 'unavailable' }),
      '/api/pro/invitations': () => json(200, { invitations: [INV] }),
      '/api/pro/invitations/inv-1/accept': () =>
        json(200, { id: 'inv-1', status: 'active' }),
      '/api/pro/salons': () => json(200, { items: [], canAddSalon: false }),
    });

    render(
      <ProMembershipProvider>
        <ProSidebar />
      </ProMembershipProvider>,
    );
    fireEvent.click(await screen.findByRole('button', { name: 'Rejoindre' }));

    await waitFor(() =>
      expect(screen.queryByRole('heading', { name: 'Invitations' })).toBeNull(),
    );
    await waitFor(() => expect(count('GET /api/pro/me')).toBeGreaterThanOrEqual(2));
    // Let every probe the join starts settle before looking.
    for (let i = 0; i < 5; i += 1) await new Promise((r) => setTimeout(r, 0));
    expect(screen.queryByRole('link', { name: 'Équipe' })).toBeNull();
    expect(screen.queryByRole('link', { name: 'Revenus' })).toBeNull();
    expect(screen.queryByRole('link', { name: 'Aujourd’hui' })).toBeNull();
  });

  it('…and « Réessayer » on « Aujourd’hui » re-probes the membership too, so '
    + 'the sidebar heals with the page', async () => {
    // The page fetches /me too, so the answers follow the story, not a count.
    let accepted = false;
    let meDown = true;
    mockFetch({
      '/api/pro/me': () =>
        !accepted
          ? notAMember()
          : meDown
            ? json(503, { error: 'unavailable' })
            : json(200, STAFF_P1),
      '/api/pro/invitations': () =>
        json(200, { invitations: accepted ? [] : [INV] }),
      '/api/pro/invitations/inv-1/accept': () => {
        accepted = true;
        return json(200, { id: 'inv-1', status: 'active' });
      },
      '/api/pro/appointments': () => json(200, { items: [] }),
      '/api/pro/salons': () => json(200, { items: [], canAddSalon: false }),
    });

    render(
      <ProMembershipProvider>
        <ProSidebar />
        <AujourdhuiClient />
      </ProMembershipProvider>,
    );
    fireEvent.click(await screen.findByRole('button', { name: 'Rejoindre' }));
    const retry = await screen.findByRole('button', { name: 'Réessayer' });

    meDown = false;
    fireEvent.click(retry);

    expect(await screen.findByText('ancien@equipe.test')).toBeTruthy();
    expect(screen.queryByRole('link', { name: 'Équipe' })).toBeNull();
  });

  // [5] A dead session on the gate goes to the login.
  it('« Rejoindre » answers 401 (the session is gone) → logout + motif, never '
    + '« Invitation impossible à accepter. »', async () => {
    const { calls } = mockFetch({
      '/api/pro/me': notAMember,
      '/api/pro/invitations': () => json(200, { invitations: [INV] }),
      '/api/pro/invitations/inv-1/accept': () =>
        json(401, { error: 'not_authenticated' }),
    });

    renderProvider();
    fireEvent.click(await screen.findByRole('button', { name: 'Rejoindre' }));

    await waitFor(() => expect(replace).toHaveBeenCalledWith(MOTIF));
    expect(calls).toContain('POST /api/pro/auth/logout');
    expect(screen.queryByText('Invitation impossible à accepter.')).toBeNull();
  });

  it('« Refuser » answers 401 → logout + motif, never « Refus impossible. »',
    async () => {
      const { calls } = mockFetch({
        '/api/pro/me': notAMember,
        '/api/pro/invitations': () =>
          json(200, { invitations: [INV, INV_OTHER] }),
        '/api/pro/invitations/inv-1/decline': () =>
          json(401, { error: 'session_expired' }),
      });

      renderProvider();
      await screen.findByText(/invite comme Collaborateur/);
      fireEvent.click(screen.getAllByRole('button', { name: 'Refuser' })[0]);

      await waitFor(() => expect(replace).toHaveBeenCalledWith(MOTIF));
      expect(calls).toContain('POST /api/pro/auth/logout');
      expect(screen.queryByText('Refus impossible.')).toBeNull();
    });

  // [9]/[14] One answer at a time — the way out included.
  it('while « Rejoindre » is out, « Se déconnecter » waits too', async () => {
    let releaseAccept: () => void = () => {};
    mockFetch({
      '/api/pro/me': (n) => (n === 1 ? notAMember() : json(200, STAFF_P1)),
      '/api/pro/invitations': () => json(200, { invitations: [INV] }),
      '/api/pro/invitations/inv-1/accept': () =>
        new Promise((resolve) => {
          releaseAccept = () =>
            resolve(json(200, { id: 'inv-1', status: 'active' }));
        }),
    });

    renderProvider();
    fireEvent.click(await screen.findByRole('button', { name: 'Rejoindre' }));

    await waitFor(() =>
      expect(
        (screen.getByRole('button', { name: 'Se déconnecter' }) as HTMLButtonElement)
          .disabled,
      ).toBe(true),
    );
    releaseAccept();
    expect(await screen.findByText(/role:staff/)).toBeTruthy();
  });

  it('while « Se déconnecter » is out, the cards wait', async () => {
    let releaseLogout: () => void = () => {};
    mockFetch({
      '/api/pro/me': notAMember,
      '/api/pro/invitations': () => json(200, { invitations: [INV] }),
      '/api/pro/auth/logout': () =>
        new Promise((resolve) => {
          releaseLogout = () => resolve(json(200, { ok: true }));
        }),
    });

    renderProvider();
    fireEvent.click(
      await screen.findByRole('button', { name: 'Se déconnecter' }),
    );

    await waitFor(() =>
      expect(
        (screen.getByRole('button', { name: 'Rejoindre' }) as HTMLButtonElement)
          .disabled,
      ).toBe(true),
    );
    expect(
      (screen.getByRole('button', { name: 'Refuser' }) as HTMLButtonElement)
        .disabled,
    ).toBe(true);
    releaseLogout();
    await waitFor(() => expect(replace).toHaveBeenCalledWith(MOTIF));
  });

  // [11] The sign-out after the last « Refuser » is a wait, not an empty page.
  it('« Refuser » on the LAST card: the loading state while the sign-out runs '
    + '— no empty invitations page, no live « Se déconnecter »', async () => {
    let releaseLogout: () => void = () => {};
    mockFetch({
      '/api/pro/me': notAMember,
      '/api/pro/invitations': () => json(200, { invitations: [INV] }),
      '/api/pro/invitations/inv-1/decline': () =>
        json(200, { declined: true }),
      '/api/pro/auth/logout': () =>
        new Promise((resolve) => {
          releaseLogout = () => resolve(json(200, { ok: true }));
        }),
    });

    renderProvider();
    fireEvent.click(await screen.findByRole('button', { name: 'Refuser' }));

    expect(await screen.findByText('Chargement…')).toBeTruthy();
    expect(
      screen.queryByText('Un salon vous a invité à rejoindre son équipe.'),
    ).toBeNull();
    expect(screen.queryByRole('button', { name: 'Se déconnecter' })).toBeNull();
    releaseLogout();
    await waitFor(() => expect(replace).toHaveBeenCalledWith(MOTIF));
  });

  // [7] Focus never falls to <body> when the gate's content is swapped.
  it('the gate’s wait (S2: joining from a deeper page) puts focus on the page '
    + 'heading, not on <body>', async () => {
    pathname = '/pro/clients';
    mockFetch({
      '/api/pro/me': (n) => (n === 1 ? notAMember() : json(200, STAFF_P1)),
      '/api/pro/invitations': () => json(200, { invitations: [INV] }),
      '/api/pro/invitations/inv-1/accept': () =>
        json(200, { id: 'inv-1', status: 'active' }),
    });

    renderProvider();
    const join = await screen.findByRole('button', { name: 'Rejoindre' });
    join.focus();
    fireEvent.click(join);

    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro'));
    expect(screen.getByText('Chargement…')).toBeTruthy();
    expect(document.activeElement).toBe(
      screen.getByRole('heading', { level: 1, name: 'Invitations' }),
    );
  });
});

describe('« Aujourd’hui » — accepting while already a member', () => {
  it('Rejoindre → « Vous avez rejoint {salon} » and « Mes salons » reloads', async () => {
    const { count } = mockFetch({
      '/api/pro/me': () => json(200, STAFF_P1),
      '/api/pro/appointments': () => json(200, { items: [] }),
      '/api/pro/invitations': () =>
        json(200, { invitations: [INV_OTHER] }),
      '/api/pro/invitations/inv-2/accept': () =>
        json(200, { id: 'inv-2', status: 'active' }),
      '/api/pro/salons': () =>
        json(200, { items: [], canAddSalon: false }),
    });

    render(
      <ProMembershipProvider>
        <AujourdhuiClient />
      </ProMembershipProvider>,
    );
    await screen.findByText(/invite comme Réception/);
    fireEvent.click(screen.getByRole('button', { name: 'Rejoindre' }));

    expect(
      await screen.findByText('Vous avez rejoint Institut Belle Vue'),
    ).toBeTruthy();
    await waitFor(() => expect(count('GET /api/pro/salons')).toBe(2));
    expect(replace).not.toHaveBeenCalled();
  });
});
