import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
  within,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
const push = vi.fn();
// Stable object: the load effect depends on [router].
const routerMock = { replace, push };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { ClientsClient } from '../components/pro/ClientsClient';

/// Pro « Ajouter un client » (docs/design/phone-national-length.md §2.5): it
/// used to send the raw text with no check at all, so 7 digits after +225
/// reached the server — whose generic rule let them through — and the
/// placeholder's own spaced format was refused there. The number is now
/// checked UNDER the field and sent bare.

/// Every POST /api/pro/clients body, in order.
const posted: Record<string, unknown>[] = [];

function mockFetch({ createStatus = 201, createBody = { id: 'sc9' } as object } = {}) {
  posted.length = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      if (url === '/api/pro/me') {
        return new Response(
          JSON.stringify({
            account: { id: 'acc1', email: 'salon@example.com' },
            provider: { id: 'p1', name: 'Beauté Divine', timezone: 'Africa/Abidjan' },
          }),
          { status: 200 },
        );
      }
      if (url === '/api/pro/clients' && init?.method === 'POST') {
        posted.push(JSON.parse(String(init.body)));
        return new Response(JSON.stringify(createBody), { status: createStatus });
      }
      if (String(url).startsWith('/api/pro/clients?')) {
        return new Response(
          JSON.stringify({ items: [], total: 0, page: 1, pageSize: 20 }),
          { status: 200 },
        );
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
  push.mockReset();
});

async function openAddClient() {
  render(<ClientsClient />);
  fireEvent.click(await screen.findByRole('button', { name: '+ Ajouter un client' }));
  const dialog = screen.getByRole('dialog', { name: 'Ajouter un client' });
  fireEvent.change(within(dialog).getByLabelText('Nom'), {
    target: { value: 'Awa' },
  });
  return dialog;
}

describe('ClientsClient — « Ajouter un client » checks the phone', () => {
  it('7 digits after +225 are refused UNDER the field — nothing is sent', async () => {
    mockFetch();
    const dialog = await openAddClient();
    const phone = within(dialog).getByLabelText('Téléphone');
    fireEvent.change(phone, { target: { value: '+2250700000' } });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Ajouter' }));

    const alert = await within(dialog).findByRole('alert');
    expect(alert).toHaveTextContent(
      'Le numéro doit comporter 10 chiffres après +225.',
    );
    expect(phone).toHaveAttribute('aria-invalid', 'true');
    expect(phone.getAttribute('aria-describedby')).toContain(alert.id);
    expect(posted).toHaveLength(0);
  });

  it('an empty phone asks for one — the button is not a silent dead end', async () => {
    mockFetch();
    const dialog = await openAddClient();
    const add = within(dialog).getByRole('button', { name: 'Ajouter' });
    expect(add).not.toBeDisabled();
    fireEvent.click(add);

    expect(await within(dialog).findByRole('alert')).toHaveTextContent(
      /^Saisissez un numéro de téléphone\.$/,
    );
    expect(posted).toHaveLength(0);
  });

  it("the placeholder's own spaced format is accepted, and sent bare", async () => {
    mockFetch();
    const dialog = await openAddClient();
    const phone = within(dialog).getByLabelText('Téléphone');
    // First a fault, then the fix: §14 rule 2 clears it on change.
    fireEvent.change(phone, { target: { value: '+225 07 07 12 34 5' } });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Ajouter' }));
    await within(dialog).findByRole('alert');
    fireEvent.change(phone, { target: { value: '+225 07 07 12 34 56' } });
    expect(within(dialog).queryByRole('alert')).toBeNull();
    fireEvent.click(within(dialog).getByRole('button', { name: 'Ajouter' }));

    await waitFor(() => expect(posted).toHaveLength(1));
    expect(posted[0]).toMatchObject({ name: 'Awa', phone: '+2250707123456' });
    await waitFor(() => expect(push).toHaveBeenCalledWith('/pro/clients/sc9'));
  });

  it('a server invalid_phone lands under the field too, not in a form-level line', async () => {
    // Defence in depth: the server stays the authority (BACKEND.md §3.4).
    mockFetch({ createStatus: 400, createBody: { error: 'invalid_phone' } });
    const dialog = await openAddClient();
    const phone = within(dialog).getByLabelText('Téléphone');
    fireEvent.change(phone, { target: { value: '+2250707123456' } });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Ajouter' }));

    const alert = await within(dialog).findByRole('alert');
    expect(alert).toHaveTextContent(
      'Numéro invalide (format international, ex. +2250700000000).',
    );
    expect(phone).toHaveAttribute('aria-invalid', 'true');
    expect(phone.getAttribute('aria-describedby')).toContain(alert.id);
    expect(push).not.toHaveBeenCalled();
  });
});
