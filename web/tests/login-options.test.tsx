import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { LoginOptions } from '../components/auth/LoginOptions';

const user = (phone: string | null) => ({
  id: 'u1',
  name: 'Awa',
  email: 'awa@x.com',
  authProvider: 'email',
  phoneNumber: phone,
  phoneVerified: false,
});

/// Route the BFF calls the component makes. Returns the fetch mock.
function mockFetch(opts: { verifyUserPhone: string | null; verifyOk?: boolean }) {
  const calls: { url: string; body: Record<string, unknown> }[] = [];
  const fn = vi.fn(async (url: string, init?: RequestInit) => {
    const body = init?.body ? JSON.parse(init.body as string) : {};
    calls.push({ url, body });
    if (url === '/api/auth/email/request') {
      return new Response(
        JSON.stringify({ expiresInSeconds: 300, devCode: '123456' }),
        { status: 202 },
      );
    }
    if (url === '/api/auth/email/verify') {
      return opts.verifyOk === false
        ? new Response(JSON.stringify({ error: 'otp_invalid' }), { status: 400 })
        : new Response(
            JSON.stringify({ ok: true, user: user(opts.verifyUserPhone) }),
            { status: 200 },
          );
    }
    if (url === '/api/me') {
      return new Response(JSON.stringify(user('+2250700000000')), {
        status: 200,
      });
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
  fireEvent.change(screen.getByLabelText('Votre e-mail'), {
    target: { value: 'awa@x.com' },
  });
  fireEvent.click(screen.getByRole('button', { name: 'Continuer avec e-mail' }));
  await screen.findByLabelText('Code à 6 chiffres');
  fireEvent.change(screen.getByLabelText('Code à 6 chiffres'), {
    target: { value: '123456' },
  });
  fireEvent.click(screen.getByRole('button', { name: 'Se connecter' }));
}

describe('LoginOptions', () => {
  it('email happy path: user with a phone → onSuccess directly', async () => {
    mockFetch({ verifyUserPhone: '+2250700000000' });
    const onSuccess = vi.fn();
    render(<LoginOptions onSuccess={onSuccess} />);
    await loginByEmail();
    await waitFor(() => expect(onSuccess).toHaveBeenCalled());
  });

  it('MANDATORY phone step blocks a fresh registration without a phone', async () => {
    const { calls } = mockFetch({ verifyUserPhone: null });
    const onSuccess = vi.fn();
    render(<LoginOptions onSuccess={onSuccess} />);
    await loginByEmail();

    // Blocked on the phone step — not signed through yet.
    await screen.findByText('Votre numéro de téléphone');
    expect(onSuccess).not.toHaveBeenCalled();

    // Enter a CI number (international-mode input → full E.164) → PATCH /me.
    fireEvent.change(screen.getByPlaceholderText('07 00 00 00 00'), {
      target: { value: '+2250700000001' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Continuer' }));
    await waitFor(() => expect(onSuccess).toHaveBeenCalled());
    const patch = calls.find((c) => c.url === '/api/me');
    expect(patch?.body.phone).toBe('+2250700000001');
  });

  it('wrong code shows the French error', async () => {
    mockFetch({ verifyUserPhone: '+2250700000000', verifyOk: false });
    render(<LoginOptions onSuccess={vi.fn()} />);
    await loginByEmail();
    await screen.findByText('Code incorrect ou expiré.');
  });

  it('invalid email: the button stays ENABLED and submit answers with a field error (§14 rule 5)', () => {
    mockFetch({ verifyUserPhone: null });
    render(<LoginOptions onSuccess={vi.fn()} />);
    const email = screen.getByLabelText('Votre e-mail');
    fireEvent.change(email, { target: { value: 'not-an-email' } });
    const submit = screen.getByRole('button', { name: 'Continuer avec e-mail' });
    // The old pattern was `disabled={!emailValid}` — a dead end with no
    // explanation. §14 rule 5: disable only WHILE submitting.
    expect(submit).not.toBeDisabled();
    fireEvent.click(submit);
    const alert = screen.getByRole('alert');
    expect(alert).toHaveTextContent('Saisissez une adresse e-mail valide.');
    expect(email).toHaveAttribute('aria-invalid', 'true');
    expect(email.getAttribute('aria-describedby')).toBe(alert.id);
    // §14 rule 2: once errored, a change re-validates — a good value clears it.
    fireEvent.change(email, { target: { value: 'ok@exemple.ci' } });
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('Google/Apple render only when configured (env-gated)', () => {
    mockFetch({ verifyUserPhone: null });
    render(<LoginOptions onSuccess={vi.fn()} />);
    // No NEXT_PUBLIC_* ids in tests → email-only.
    expect(screen.queryByRole('button', { name: 'Continuer avec Apple' })).toBeNull();
    expect(screen.getByLabelText('Votre e-mail')).toBeInTheDocument();
  });
});
