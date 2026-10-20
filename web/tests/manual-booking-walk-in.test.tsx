import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { ManualBookingDialog } from '../components/pro/ManualBookingDialog';
import type { ProProfile } from '../lib/api/pro';

/// docs/design/web-manual-booking-walk-in.md (owner Q1: like the app) — a
/// walk-in nobody knows is « Client sans numéro » and no name; a new client
/// otherwise needs a number (« Saisissez un numéro de téléphone. », under the
/// field); the name is optional. The web used to demand a name and let the
/// number go.
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

function mockFetch({
  createStatus = 200,
  createBody = '{}',
  clients = [] as Record<string, unknown>[],
} = {}) {
  posted.length = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      if (String(url).startsWith('/api/pro/clients')) {
        return new Response(JSON.stringify({ items: clients }), { status: 200 });
      }
      if (url === '/api/pro/appointments') {
        posted.push(JSON.parse(String(init?.body ?? '{}')));
        return new Response(createBody, { status: createStatus });
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

function renderDialog(initialClient?: {
  id: string;
  name: string;
  phone?: string;
  linked?: boolean;
}) {
  const onCreated = vi.fn();
  render(
    <ManualBookingDialog
      providerId="p1"
      profile={PROFILE}
      dateTimeIso="2027-01-15T14:30:00.000Z"
      initialClient={initialClient}
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

const box = () => screen.getByRole('checkbox', { name: 'Client sans numéro' });
const phoneField = () => screen.getByLabelText('Téléphone (pour retrouver ce client)');
const create = () => fireEvent.click(screen.getByRole('button', { name: 'Créer' }));
const service = () => fireEvent.click(screen.getByRole('checkbox', { name: /Tresses/ }));

describe('ManualBookingDialog — the walk-in, like the app', () => {
  it('the number and « Client sans numéro » are there before any name is typed', () => {
    mockFetch();
    renderDialog();
    expect(phoneField()).toBeInTheDocument();
    expect(box()).not.toBeChecked();
  });

  it('« Créer » waits for a service and a time — not for a name', () => {
    mockFetch();
    renderDialog();
    expect(screen.getByRole('button', { name: 'Créer' })).toBeDisabled();
    service();
    expect(screen.getByRole('button', { name: 'Créer' })).toBeEnabled();
  });

  it('no name, no number: « Client sans numéro » books it — neither is sent', async () => {
    mockFetch();
    const onCreated = renderDialog();
    service();
    fireEvent.click(box());
    create();
    await waitFor(() => expect(posted).toHaveLength(1));
    expect(posted[0].clientName).toBeUndefined();
    expect(posted[0].clientPhone).toBeUndefined();
    await waitFor(() => expect(onCreated).toHaveBeenCalled());
  });

  it('a name and no number, box not ticked: the field says so, nothing is sent', async () => {
    mockFetch();
    renderDialog();
    fillBasics();
    create();
    expect(await screen.findByText('Saisissez un numéro de téléphone.')).toBeInTheDocument();
    expect(phoneField()).toHaveAttribute('aria-invalid', 'true');
    expect(posted).toHaveLength(0);
  });

  it('ticking the box clears that fault and turns the field off; unticking brings it back as it was', async () => {
    mockFetch();
    renderDialog();
    fillBasics();
    fireEvent.change(phoneField(), { target: { value: '0700' } });
    create();
    expect(await screen.findByText(/chiffres/)).toBeInTheDocument();
    fireEvent.click(box());
    expect(screen.queryByText(/chiffres/)).toBeNull();
    expect(phoneField()).toBeDisabled();
    fireEvent.click(box());
    expect(phoneField()).toBeEnabled();
    expect(phoneField()).toHaveValue('0700');
  });

  it('a number typed, then the box ticked: the number is not sent', async () => {
    mockFetch();
    renderDialog();
    fillBasics();
    fireEvent.change(phoneField(), { target: { value: '0700000042' } });
    fireEvent.click(box());
    create();
    await waitFor(() => expect(posted).toHaveLength(1));
    expect(posted[0].clientName).toBe('Awa');
    expect(posted[0].clientPhone).toBeUndefined();
  });

  it('a name and a number: both are sent (the client gets a card)', async () => {
    mockFetch();
    renderDialog();
    fillBasics();
    fireEvent.change(phoneField(), { target: { value: '0700000042' } });
    create();
    await waitFor(() => expect(posted).toHaveLength(1));
    expect(posted[0].clientName).toBe('Awa');
    expect(posted[0].clientPhone).toBe('+2250700000042');
  });

  it('a client picked from the search: no box, no number field', async () => {
    mockFetch({ clients: [{ id: 'c1', displayName: 'Koffi', phone: '+2250700000001' }] });
    renderDialog();
    fireEvent.change(screen.getByLabelText('Rechercher ou nommer le client'), {
      target: { value: 'Ko' },
    });
    fireEvent.click(await screen.findByRole('button', { name: /Koffi/ }));
    expect(screen.queryByRole('checkbox', { name: 'Client sans numéro' })).toBeNull();
    expect(screen.queryByLabelText('Téléphone (pour retrouver ce client)')).toBeNull();
  });
});
