import { cleanup, fireEvent, render, screen } from '@testing-library/react';
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

function mockFetch() {
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
