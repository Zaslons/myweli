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
