import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
const routerMock = { replace };
vi.mock('next/navigation', () => ({ useRouter: () => routerMock }));

import { ProRegisterClient } from '../components/pro/ProRegisterClient';
import { resetLocalitiesClientCache } from '../lib/use-localities';
import { fixtureTree } from './localities.test';

/// Pro registration « Téléphone du salon » (docs/design/phone-national-length.md
/// §2.5): the shared rule and its two sentences. The old single sentence —
/// « Saisissez le numéro de téléphone du salon. » — asked an owner who HAD
/// typed a short number to type one.

const calls: string[] = [];

/// `register`: what the BFF answers « S’inscrire » with (the 404 fallback
/// when a test never gets that far).
function mockFetch({
  register,
}: { register?: { status: number; error: string } } = {}) {
  calls.length = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) => {
      calls.push(url);
      if (url === '/api/localities') {
        return new Response(JSON.stringify(fixtureTree), { status: 200 });
      }
      if (url === '/api/pro/auth/email/request') {
        return new Response(JSON.stringify({ expiresInSeconds: 300 }), {
          status: 202,
        });
      }
      if (url === '/api/pro/auth/register' && register) {
        return new Response(JSON.stringify({ error: register.error }), {
          status: register.status,
        });
      }
      return new Response('{}', { status: 404 });
    }),
  );
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
  resetLocalitiesClientCache();
});

function fillBusinessAndEmail() {
  fireEvent.change(screen.getByLabelText('Nom de l’entreprise'), {
    target: { value: 'Salon Awa' },
  });
  fireEvent.change(screen.getByLabelText('Votre e-mail'), {
    target: { value: 'awa@salon.ci' },
  });
}

describe('ProRegisterClient — « Téléphone du salon »', () => {
  it('empty: asks for a number', async () => {
    mockFetch();
    render(<ProRegisterClient />);
    fillBusinessAndEmail();
    fireEvent.click(screen.getByRole('button', { name: 'Recevoir un code' }));

    expect(await screen.findByRole('alert')).toHaveTextContent(
      /^Saisissez un numéro de téléphone\.$/,
    );
    expect(calls).not.toContain('/api/pro/auth/email/request');
  });

  it('7 digits after +225: says how many — and no code is sent', async () => {
    mockFetch();
    render(<ProRegisterClient />);
    fillBusinessAndEmail();
    const phone = screen.getByLabelText('Téléphone du salon');
    fireEvent.change(phone, { target: { value: '+2250700000' } });
    fireEvent.click(screen.getByRole('button', { name: 'Recevoir un code' }));

    expect(await screen.findByRole('alert')).toHaveTextContent(
      'Le numéro doit comporter 10 chiffres après +225.',
    );
    expect(phone).toHaveAttribute('aria-invalid', 'true');
    expect(calls).not.toContain('/api/pro/auth/email/request');
  });
});

/// docs/design/phone-leftovers.md §2: `POST /auth/provider/register` now says
/// `invalid_phone` for the phone (it said `invalid_input`, shared with the name
/// and the type). The client branch existed and was dead — and it put the
/// fault in the form-level line, under the buttons, far from the field.
describe('ProRegisterClient — the server refuses the number', () => {
  /// A number the client rule accepts, a code sent and typed, « S’inscrire ».
  async function registerWith(phoneValue: string) {
    render(<ProRegisterClient />);
    fillBusinessAndEmail();
    const phone = screen.getByLabelText('Téléphone du salon');
    fireEvent.change(phone, { target: { value: phoneValue } });
    fireEvent.click(screen.getByRole('button', { name: 'Recevoir un code' }));
    fireEvent.change(await screen.findByLabelText('Code à 6 chiffres'), {
      target: { value: '123456' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'S’inscrire' }));
    await waitFor(() => expect(calls).toContain('/api/pro/auth/register'));
    return phone;
  }

  it('invalid_phone lands UNDER « Téléphone du salon », tied to it', async () => {
    mockFetch({ register: { status: 400, error: 'invalid_phone' } });
    const phone = await registerWith('+2250707123456');

    await waitFor(() => expect(phone).toHaveAttribute('aria-invalid', 'true'));
    const describedBy = phone.getAttribute('aria-describedby');
    expect(describedBy).toBeTruthy();
    expect(document.getElementById(describedBy!)).toHaveTextContent(
      /^Saisissez un numéro de téléphone valide\.$/,
    );
    // Not ALSO in the form-level line (§14: one fault, one place).
    expect(screen.queryByText('Numéro de téléphone invalide.')).toBeNull();
    expect(screen.queryByText('Une erreur est survenue. Réessayez.')).toBeNull();
  });

  it('another refusal keeps its form-level line — the phone is not blamed', async () => {
    mockFetch({ register: { status: 409, error: 'provider_exists' } });
    const phone = await registerWith('+2250707123456');

    await screen.findByText(
      'Un compte existe déjà pour cette identité. Connectez-vous.',
    );
    expect(phone).not.toHaveAttribute('aria-invalid');
  });
});
