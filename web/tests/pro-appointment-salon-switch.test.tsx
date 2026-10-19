import { cleanup, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
const routerMock = { replace, push: vi.fn() };
vi.mock('next/navigation', () => ({
  useRouter: () => routerMock,
  usePathname: () => '/pro/rendez-vous/a2',
}));

import { ProAppointmentDetailClient } from '../components/pro/ProAppointmentDetailClient';
import { ProMembershipProvider } from '../components/pro/ProMembershipContext';
import { NO_CONNECTION_MESSAGE } from '../lib/api/network';

/// A notification about ANOTHER of the account's salons opens its booking
/// under that salon — the app's flow (`ProAppointmentDetailScreen(salonId:)`),
/// docs/design/web-pro-notifications.md §3.4. `?salon=` reaches the detail;
/// when it names a salon other than the active one, the page switches FIRST
/// (the same `switchSalon` as « Mes salons »), then loads.

const me = (id: string, name: string) => ({
  account: { id: 'acc1', businessName: name, phoneNumber: '+2250700000000', email: 'o@x.ci' },
  provider: { id, name, status: 'active', services: [{ id: 's1', name: 'Tresses' }] },
  membership: { role: 'owner', capabilities: ['journal.manage.all', 'journal.view.all'] },
});

const APPT_P2 = {
  id: 'a2',
  status: 'confirmed',
  appointmentDate: '2030-01-10T09:00:00.000Z',
  clientDisplayName: 'Aya',
  serviceIds: ['s1'],
  totalPrice: 15000,
};

let active = 'p1';
let select: number | 'throw' = 200;
const selects: unknown[] = [];

beforeEach(() => {
  active = 'p1';
  select = 200;
  selects.length = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const u = String(url);
      if (u === '/api/pro/me') {
        const body = active === 'p1' ? me('p1', 'Beauté Divine') : me('p2', 'Institut Libreville');
        return new Response(JSON.stringify(body), { status: 200 });
      }
      if (u === '/api/pro/salons') {
        return new Response(
          JSON.stringify({
            items: [
              { salonId: 'p1', salonName: 'Beauté Divine', role: 'owner', salonStatus: 'active' },
              { salonId: 'p2', salonName: 'Institut Libreville', role: 'owner', salonStatus: 'active' },
            ],
            canAddSalon: false,
          }),
          { status: 200 },
        );
      }
      if (u === '/api/pro/salons/select' && init?.method === 'POST') {
        selects.push(JSON.parse(String(init.body)));
        if (select === 'throw') throw new TypeError('Failed to fetch');
        if (select !== 200) {
          return new Response(JSON.stringify({ error: 'not_a_member' }), { status: select });
        }
        active = 'p2';
        return new Response(JSON.stringify(me('p2', 'Institut Libreville')), { status: 200 });
      }
      if (u === '/api/pro/appointments') {
        // The session's salon decides what the list holds.
        return new Response(JSON.stringify({ items: active === 'p2' ? [APPT_P2] : [] }), {
          status: 200,
        });
      }
      return new Response('{}', { status: 404 });
    }),
  );
});

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
});

function host(salon?: string) {
  return render(
    <ProMembershipProvider>
      <ProAppointmentDetailClient id="a2" salon={salon} />
    </ProMembershipProvider>,
  );
}

describe('the detail opens a notification under ITS salon', () => {
  it('another salon → switch first, then the booking loads', async () => {
    host('p2');
    expect(await screen.findByText('Aya')).toBeInTheDocument();
    expect(selects).toEqual([{ salonId: 'p2' }]);
  });

  it('the active salon → no switch', async () => {
    active = 'p2';
    host('p2');
    expect(await screen.findByText('Aya')).toBeInTheDocument();
    expect(selects).toEqual([]);
  });

  it('a refused switch → the switcher’s sentence, never another salon’s page', async () => {
    select = 403;
    host('p2');
    expect(
      await screen.findByText(
        'Changement impossible — votre accès à ce salon a peut-être été retiré.',
      ),
    ).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Réessayer' })).toBeInTheDocument();
    expect(screen.queryByText('Aya')).toBeNull();
  });

  it('no answer → « Pas de connexion »', async () => {
    select = 'throw';
    host('p2');
    expect(await screen.findByText(NO_CONNECTION_MESSAGE)).toBeInTheDocument();
  });
});
