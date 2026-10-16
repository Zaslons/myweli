import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
let pathname = '/pro';
const routerMock = { replace };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => pathname,
}));

import { ProMembershipProvider } from '../components/pro/ProMembershipContext';
import { ProSidebar } from '../components/pro/ProSidebar';

/// Team access R6c — the sidebar « Mes salons » switcher: the block renders
/// for every role, the chevron/dropdown only when there is somewhere to go,
/// rows carry the role + « Brouillon » badge and the active check, and
/// « Ajouter un salon » follows the server-computed gate.

const OWNER_PROFILE = {
  account: { id: 'acc1', email: 'salon@example.com' },
  provider: { id: 'p1', name: 'Beauté Divine' },
  membership: {
    role: 'owner',
    capabilities: [
      'availability.manage',
      'catalogue.manage',
      'clients.view',
      'finances.view',
      'journal.manage.all',
      'journal.manage.own',
      'journal.view.all',
      'journal.view.own',
      'members.manage',
      'profile.manage',
      'salon.publish',
      'subscription.manage',
    ],
  },
};

function mockFetch(salons: unknown, canAddSalon: boolean, profile = OWNER_PROFILE) {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      if (url === '/api/pro/me') {
        return new Response(JSON.stringify(profile), { status: 200 });
      }
      if (url === '/api/pro/salons') {
        return new Response(JSON.stringify({ items: salons, canAddSalon }), {
          status: 200,
        });
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

const TWO_SALONS = [
  { salonId: 'p1', salonName: 'Beauté Divine', role: 'owner', salonStatus: 'active', verified: true },
  { salonId: 'p3', salonName: 'Institut Belle Vue', role: 'owner', salonStatus: 'draft', verified: true },
];

function host() {
  return render(
    <ProMembershipProvider>
      <ProSidebar />
    </ProMembershipProvider>,
  );
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
  pathname = '/pro';
});

describe('ProSidebar — the « Mes salons » switcher', () => {
  it('two salons → the switcher button opens the list with roles, the '
    + 'Brouillon badge and the active check', async () => {
    mockFetch(TWO_SALONS, false);
    host();

    const trigger = await screen.findByRole('button', {
      name: 'Changer de salon',
    });
    fireEvent.click(trigger);

    expect(screen.getByText('Institut Belle Vue')).toBeTruthy();
    expect(screen.getByText(/Propriétaire · Brouillon/)).toBeTruthy();
    // No add row without the gate.
    expect(screen.queryByText('Ajouter un salon')).toBeNull();
  });

  it('a single salon without the gate → plain text, no dead chevron', async () => {
    mockFetch([TWO_SALONS[0]], false);
    host();

    expect(await screen.findByText('Beauté Divine')).toBeTruthy();
    expect(
      screen.queryByRole('button', { name: 'Changer de salon' }),
    ).toBeNull();
  });

  it('the open gate adds « Ajouter un salon » (even with one salon)', async () => {
    mockFetch([TWO_SALONS[0]], true);
    host();

    const trigger = await screen.findByRole('button', {
      name: 'Changer de salon',
    });
    fireEvent.click(trigger);
    const add = screen.getByRole('link', { name: 'Ajouter un salon' });
    expect(add.getAttribute('href')).toBe('/pro/salons/nouveau');
  });
});

/// docs/design/web-pro-no-connection-copy.md §5 — a switch that did not
/// happen says why. Before: every failure, a dropped connection included,
/// read « Changement impossible — votre accès à ce salon a peut-être été
/// retiré. » — suspecting a revoked access that had nothing to do with it.
describe('ProSidebar — a failed switch says why', () => {
  const REVOKED =
    'Changement impossible — votre accès à ce salon a peut-être été retiré.';

  type Select = 'throw' | { status: number; raw?: string };

  function mockSwitch(select: Select) {
    vi.stubGlobal(
      'fetch',
      vi.fn(async (url: string) => {
        if (url === '/api/pro/me') {
          return new Response(JSON.stringify(OWNER_PROFILE), { status: 200 });
        }
        if (url === '/api/pro/salons') {
          return new Response(
            JSON.stringify({ items: TWO_SALONS, canAddSalon: false }),
            { status: 200 },
          );
        }
        if (url === '/api/pro/salons/select') {
          if (select === 'throw') throw new TypeError('Failed to fetch');
          return new Response(
            select.raw ?? JSON.stringify({ error: 'not_a_member' }),
            { status: select.status },
          );
        }
        return new Response('{}', { status: 404 });
      }),
    );
  }

  async function pickOther() {
    host();
    fireEvent.click(
      await screen.findByRole('button', { name: 'Changer de salon' }),
    );
    fireEvent.click(screen.getByRole('button', { name: /Institut Belle Vue/ }));
  }

  for (const [what, select, sentence] of [
    ['no network', 'throw', 'Pas de connexion. Réessayez.'],
    // The salon switched on the server, but its profile was lost on the way:
    // nothing usable came back, and picking again is safe.
    ['a 2xx whose body is lost', { status: 200, raw: '<html>' }, 'Pas de connexion. Réessayez.'],
    ['a 403 (revoked there since the list loaded)', { status: 403 }, REVOKED],
    ['a 500', { status: 500 }, REVOKED],
  ] as const) {
    it(`${what} → « ${sentence} »; the current salon stays`, async () => {
      mockSwitch(select);
      await pickOther();
      expect(await screen.findByRole('alert')).toHaveTextContent(sentence);
      expect(
        screen.getByRole('button', { name: 'Changer de salon' }),
      ).toHaveTextContent('Beauté Divine');
    });
  }
});
