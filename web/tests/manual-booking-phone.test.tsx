import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { ManualBookingDialog } from '../components/pro/ManualBookingDialog';
import type { ProProfile } from '../lib/api/pro';

/// The manual-booking PHONE boundary (plan « fix/manual-booking-phone »).
///
/// Every earlier test fed a pre-formed E.164 string to a helper or the API
/// client, so the actual defect — the dialog sending raw field text that the
/// backend refuses as `invalid_phone`, surfaced as « Création impossible.
/// Réessayez. » — was invisible to 700+ green tests. These cross the REAL
/// form boundary: what a receptionist types is what must become E.164.
const PROFILE = {
  account: { id: 'acc-1', email: 'x@salon.test' },
  provider: {
    id: 'p1',
    name: 'Beauté Divine',
    status: 'active',
    timezone: 'Africa/Abidjan',
    currency: 'XOF',
    services: [
      {
        id: 's1',
        name: 'Tresses',
        description: '',
        price: 15000,
        durationMinutes: 120,
        providerId: 'p1',
        active: true,
      },
    ],
  },
} as unknown as ProProfile;

/// Every POST /api/pro/appointments body, in order.
const posted: Record<string, unknown>[] = [];

function mockFetch({ createStatus = 200, createBody = '{}' } = {}) {
  posted.length = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      if (String(url).startsWith('/api/pro/clients')) {
        return new Response(JSON.stringify({ items: [] }), { status: 200 });
      }
      if (url === '/api/pro/appointments') {
        posted.push(JSON.parse(String(init?.body ?? '{}')));
        return new Response(createBody, { status: createStatus });
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

function renderDialog() {
  const onCreated = vi.fn();
  render(
    <ManualBookingDialog
      providerId="p1"
      profile={PROFILE}
      dateTimeIso="2027-01-15T14:30:00.000Z"
      onClose={() => {}}
      onCreated={onCreated}
    />,
  );
  return onCreated;
}

/// Name the client (reveals the new-client phone field), pick the service.
function fillBasics() {
  fireEvent.change(
    screen.getByLabelText('Rechercher ou nommer le client'),
    { target: { value: 'Awa' } },
  );
  fireEvent.click(screen.getByRole('checkbox', { name: /Tresses/ }));
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

describe('ManualBookingDialog — the phone crosses as E.164', () => {
  it('the field\'s E.164 output IS the payload — raw text never crosses', async () => {
    // The login-options idiom: in international mode jsdom fires the full
    // value (live, the field shows +225 and the user types the national
    // digits after it — libphonenumber keeps CI's trunk 0 either way).
    mockFetch();
    const onCreated = renderDialog();
    fillBasics();

    fireEvent.change(
      screen.getByLabelText('Téléphone (pour retrouver ce client)'),
      { target: { value: '+2250708091011' } },
    );
    fireEvent.click(screen.getByRole('button', { name: 'Créer' }));

    await waitFor(() => expect(posted).toHaveLength(1));
    expect(posted[0].clientPhone).toBe('+2250708091011');
    await waitFor(() => expect(onCreated).toHaveBeenCalled());
  });

  it('an impossible number is refused AT THE FIELD — nothing is sent', async () => {
    mockFetch();
    renderDialog();
    fillBasics();

    fireEvent.change(
      screen.getByLabelText('Téléphone (pour retrouver ce client)'),
      { target: { value: '12' } },
    );
    fireEvent.click(screen.getByRole('button', { name: 'Créer' }));

    await screen.findByText('Saisissez un numéro de téléphone valide.');
    expect(posted).toHaveLength(0);
  });

  it("a server invalid_phone names the fault — never « Création impossible »", async () => {
    // Defence in depth: if a bypass ever reaches the server, the 400 must
    // name the field, not invite a retry that cannot succeed.
    mockFetch({
      createStatus: 400,
      createBody: JSON.stringify({ error: 'invalid_phone' }),
    });
    renderDialog();
    fillBasics();
    fireEvent.change(
      screen.getByLabelText('Téléphone (pour retrouver ce client)'),
      { target: { value: '+2250708091011' } },
    );
    fireEvent.click(screen.getByRole('button', { name: 'Créer' }));

    await screen.findByText(
      'Numéro invalide (format international, ex. +2250700000000).',
    );
    expect(screen.queryByText(/Création impossible/)).toBeNull();
  });
});
