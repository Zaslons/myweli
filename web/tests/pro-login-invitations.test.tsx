import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { ProLoginOptions } from '../components/pro/ProLoginOptions';

/// Team access R5a — the « Invitations » step of the salon login. An email-OTP
/// verify that returns 202 {invitations} must land on the invitation cards
/// (never a session), and « Rejoindre » accepts with the retained proof.

const invitation = {
  id: 'inv1',
  providerId: 'p1',
  salonName: 'Beauté Divine',
  role: 'manager',
  roleLabel: 'Manager',
  expiresAt: '2099-01-01T00:00:00.000Z',
};

function mockFetch(handlers: {
  verifyStatus: number;
  verifyBody: unknown;
  acceptOk?: boolean;
}) {
  const calls: { url: string; body: Record<string, unknown> }[] = [];
  const fn = vi.fn(async (url: string, init?: RequestInit) => {
    const body = init?.body ? JSON.parse(init.body as string) : {};
    calls.push({ url, body });
    if (url === '/api/pro/auth/email/request') {
      return new Response(
        JSON.stringify({ expiresInSeconds: 300, devCode: '123456' }),
        { status: 202 },
      );
    }
    if (url === '/api/pro/auth/email/verify') {
      return new Response(JSON.stringify(handlers.verifyBody), {
        status: handlers.verifyStatus,
      });
    }
    if (url === '/api/pro/auth/invitations/accept') {
      return handlers.acceptOk === false
        ? new Response(JSON.stringify({ error: 'invitation_expired' }), {
            status: 409,
          })
        : new Response(JSON.stringify({ ok: true }), { status: 200 });
    }
    if (url === '/api/pro/auth/invitations/decline') {
      return new Response(JSON.stringify({ declined: true }), { status: 200 });
    }
    return new Response('{}', { status: 404 });
  });
  vi.stubGlobal('fetch', fn);
  return { fn, calls };
}

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

async function loginByEmail() {
  fireEvent.change(screen.getByPlaceholderText('Votre e-mail'), {
    target: { value: 'invitee@equipe.test' },
  });
  fireEvent.click(screen.getByRole('button', { name: 'Continuer avec e-mail' }));
  await screen.findByPlaceholderText('Code à 6 chiffres');
  fireEvent.change(screen.getByPlaceholderText('Code à 6 chiffres'), {
    target: { value: '123456' },
  });
  fireEvent.click(screen.getByRole('button', { name: 'Se connecter' }));
}

describe('ProLoginOptions — invitation bridge', () => {
  it('202 verify → the invitations step (no onSuccess yet)', async () => {
    mockFetch({ verifyStatus: 202, verifyBody: { invitations: [invitation] } });
    const onSuccess = vi.fn();
    render(<ProLoginOptions onSuccess={onSuccess} />);
    await loginByEmail();

    await screen.findByTestId('pro-login-invitations');
    expect(screen.getByText(/vous invite comme Manager/)).toBeTruthy();
    expect(onSuccess).not.toHaveBeenCalled();
  });

  it('« Rejoindre » accepts with the retained email+code proof → onSuccess', async () => {
    const { calls } = mockFetch({
      verifyStatus: 202,
      verifyBody: { invitations: [invitation] },
    });
    const onSuccess = vi.fn();
    render(<ProLoginOptions onSuccess={onSuccess} />);
    await loginByEmail();
    await screen.findByTestId('pro-login-invitations');

    fireEvent.click(screen.getByRole('button', { name: 'Rejoindre' }));
    await waitFor(() => expect(onSuccess).toHaveBeenCalled());

    const accept = calls.find(
      (c) => c.url === '/api/pro/auth/invitations/accept',
    );
    expect(accept?.body).toMatchObject({
      invitationId: 'inv1',
      email: 'invitee@equipe.test',
      code: '123456',
    });
  });

  it('« Refuser » the only invitation → back to the options', async () => {
    mockFetch({ verifyStatus: 202, verifyBody: { invitations: [invitation] } });
    render(<ProLoginOptions onSuccess={vi.fn()} />);
    await loginByEmail();
    await screen.findByTestId('pro-login-invitations');

    fireEvent.click(screen.getByRole('button', { name: 'Refuser' }));
    await screen.findByPlaceholderText('Votre e-mail');
  });
});
