import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
// Stable object: AccountClient's load effect depends on [router].
const routerMock = { replace };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { AccountClient } from '../components/account/AccountClient';
import { BookingFlow } from '../components/booking/BookingFlow';
import type { Me } from '../lib/api/account';
import { providerFixture } from './fixtures';

/// The CONTACT phone — « Réserver » (`BookingFlow`, confirm step) and « Mon
/// compte » (`AccountClient`) — docs/design/phone-leftovers.md §4.
///
/// Both said « invalid » with a disabled button and no word (§14 rule 5's dead
/// end), on bare `isPossiblePhoneNumber` — no E.164 floor, no national length.
/// A number stored before the rule (7 digits after +225) arrived PREFILLED and
/// greyed the button out with nothing to say why. Now: the button is disabled
/// only while sending, the shared rule answers under the field on submit, and
/// what crosses is `normalizePhone`'s output.
const TEN = 'Le numéro doit comporter 10 chiffres après +225.';
const REQUIRED = 'Saisissez un numéro de téléphone.';
const INVALID = 'Saisissez un numéro de téléphone valide.';

/// A time the hub offers (any instant — the server is the authority on it).
const SLOT = '2099-01-15T14:30:00.000Z';

/// Every mutation sent, in order.
const sent: { url: string; method: string; body: Record<string, unknown> }[] =
  [];

function mockFetch(
  me: Me,
  { phoneRefusal }: { phoneRefusal?: string } = {},
) {
  sent.length = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      const u = String(url);
      const method = init?.method ?? 'GET';
      if (method !== 'GET') {
        sent.push({
          url: u,
          method,
          body: JSON.parse(String(init?.body ?? '{}')),
        });
        if (u === '/api/me' && phoneRefusal) {
          return new Response(JSON.stringify({ error: phoneRefusal }), {
            status: 400,
          });
        }
        if (u === '/api/bookings') {
          return new Response(JSON.stringify({ id: 'a1', depositAmount: 0 }), {
            status: 201,
          });
        }
        return new Response('{}', { status: 200 });
      }
      if (u === '/api/me') {
        return new Response(JSON.stringify(me), { status: 200 });
      }
      if (u.startsWith('/api/availability')) {
        return new Response(JSON.stringify({ slots: [SLOT] }), { status: 200 });
      }
      if (u === '/api/appointments') {
        return new Response(JSON.stringify({ items: [] }), { status: 200 });
      }
      if (u === '/api/me/favorites') {
        return new Response(JSON.stringify({ favorites: [] }), { status: 200 });
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  replace.mockReset();
});

/// The fault is under the field and programmatically tied to it (WEB-SYSTEM §6).
function expectFieldFault(input: HTMLElement, message: string) {
  expect(input).toHaveAttribute('aria-invalid', 'true');
  const id = input.getAttribute('aria-describedby');
  expect(id).toBeTruthy();
  expect(document.getElementById(id!)).toHaveTextContent(message);
}

const ME: Me = { id: 'u1', name: 'Awa', phoneNumber: '+2250707123456' };

describe('« Réserver » — the contact phone at the confirm step', () => {
  /// Pick the hub's time (the service is prefilled), open « Confirmation »,
  /// and wait for the signed-in form.
  async function openConfirm(me: Me, opts?: { phoneRefusal?: string }) {
    mockFetch(me, opts);
    render(<BookingFlow provider={providerFixture} prefillServiceIds={['s1']} />);
    fireEvent.click(
      await screen.findByRole('button', { name: /^\d{2}:\d{2}$/ }),
    );
    // Two « Confirmer » render (the desktop aside and the mobile bar).
    fireEvent.click(screen.getAllByRole('button', { name: 'Confirmer' })[0]);
    const field = await screen.findByLabelText('Numéro de téléphone');
    const submit = screen.getByRole('button', {
      name: 'Confirmer la réservation',
    });
    return { field, submit };
  }

  it('a prefilled number the rule refuses: the button stays enabled, the fault is under the field, nothing is sent', async () => {
    const { field, submit } = await openConfirm({
      ...ME,
      phoneNumber: '+2250700000',
    });
    expect(submit).toBeEnabled();

    fireEvent.click(submit);
    await screen.findByText(TEN);
    expectFieldFault(field, TEN);
    expect(sent).toHaveLength(0);
  });

  it('no number yet: asks for one, under the field — nothing is sent', async () => {
    const { field, submit } = await openConfirm({ ...ME, phoneNumber: null });
    expect(submit).toBeEnabled();

    fireEvent.click(submit);
    await screen.findByText(REQUIRED);
    expectFieldFault(field, REQUIRED);
    expect(sent).toHaveLength(0);
  });

  it('fixed, the fault clears as typed, and the number and the booking cross', async () => {
    const { field, submit } = await openConfirm({
      ...ME,
      phoneNumber: '+2250700000',
    });
    fireEvent.click(submit);
    await screen.findByText(TEN);

    fireEvent.change(field, { target: { value: '+225 07 07 12 34 99' } });
    await waitFor(() => expect(field).not.toHaveAttribute('aria-invalid'));
    expect(screen.queryByText(TEN)).toBeNull();

    fireEvent.click(submit);
    await waitFor(() => expect(sent).toHaveLength(2));
    expect(sent[0]).toMatchObject({
      url: '/api/me',
      method: 'PATCH',
      body: { phone: '+2250707123499' },
    });
    expect(sent[1].url).toBe('/api/bookings');
    await screen.findByText('Réservation envoyée ✓');
  });

  it('an unchanged valid number books without a profile write', async () => {
    const { submit } = await openConfirm(ME);
    fireEvent.click(submit);

    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0].url).toBe('/api/bookings');
  });

  it('the server’s invalid_phone lands under the field — no booking is attempted', async () => {
    const { field, submit } = await openConfirm(
      { ...ME, phoneNumber: null },
      { phoneRefusal: 'invalid_phone' },
    );
    fireEvent.change(field, { target: { value: '+2250707123499' } });
    fireEvent.click(submit);

    await screen.findByText(INVALID);
    expectFieldFault(field, INVALID);
    expect(sent.map((s) => s.url)).toEqual(['/api/me']);
  });
});

describe('« Mon compte » — editing the contact phone', () => {
  async function openEdit(me: Me, opts?: { phoneRefusal?: string }) {
    mockFetch(me, opts);
    render(<AccountClient />);
    fireEvent.click(await screen.findByRole('button', { name: 'Modifier' }));
    const field = await screen.findByLabelText('Numéro de téléphone');
    const save = screen.getByRole('button', { name: 'Enregistrer' });
    return { field, save };
  }

  it('a prefilled number the rule refuses: the button stays enabled, the fault is under the field, nothing is sent', async () => {
    const { field, save } = await openEdit({ ...ME, phoneNumber: '+2250700000' });
    expect(save).toBeEnabled();

    fireEvent.click(save);
    await screen.findByText(TEN);
    expectFieldFault(field, TEN);
    expect(sent).toHaveLength(0);
  });

  it('a typed short number: the fault is under the field — nothing is sent', async () => {
    const { field, save } = await openEdit(ME);
    fireEvent.change(field, { target: { value: '+2250700000' } });
    expect(save).toBeEnabled();

    fireEvent.click(save);
    await screen.findByText(TEN);
    expectFieldFault(field, TEN);
    expect(sent).toHaveLength(0);
  });

  it('a valid number is saved as checked, and the row shows it', async () => {
    const { field, save } = await openEdit(ME);
    fireEvent.change(field, { target: { value: '+225 07 07 12 34 99' } });
    fireEvent.click(save);

    await waitFor(() => expect(sent).toHaveLength(1));
    expect(sent[0]).toMatchObject({
      url: '/api/me',
      method: 'PATCH',
      body: { phone: '+2250707123499' },
    });
    await screen.findByText('+2250707123499');
  });

  it('the server’s invalid_phone lands under the field', async () => {
    const { field, save } = await openEdit(ME, { phoneRefusal: 'invalid_phone' });
    fireEvent.change(field, { target: { value: '+2250707123499' } });
    fireEvent.click(save);

    await screen.findByText(INVALID);
    expectFieldFault(field, INVALID);
    // One fault, one place — not also the old form-level line.
    expect(screen.queryByText('Numéro invalide. Réessayez.')).toBeNull();
  });

  it('a fault does not outlive « Annuler »: reopened, the field is clean', async () => {
    const { save } = await openEdit({ ...ME, phoneNumber: '+2250700000' });
    fireEvent.click(save);
    await screen.findByText(TEN);

    fireEvent.click(screen.getByRole('button', { name: 'Annuler' }));
    fireEvent.click(screen.getByRole('button', { name: 'Modifier' }));
    const field = await screen.findByLabelText('Numéro de téléphone');
    expect(field).not.toHaveAttribute('aria-invalid');
    expect(screen.queryByText(TEN)).toBeNull();
  });
});
