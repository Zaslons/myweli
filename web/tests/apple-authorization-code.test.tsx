import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
vi.mock('next/navigation', () => ({
  useRouter: () => ({ replace, push: vi.fn() }),
  useSearchParams: () => ({ get: () => null }),
}));
// jsdom never loads a <script>: the Apple JS is stubbed on `window` below.
vi.mock('../lib/loadScript', () => ({ loadScript: async () => {} }));

import { LoginOptions } from '../components/auth/LoginOptions';
import { ProLoginOptions } from '../components/pro/ProLoginOptions';
import { ProRegisterClient } from '../components/pro/ProRegisterClient';

/// docs/design/backend-integrity-batch6.md §13 (B6.7) — every web Apple
/// sign-in sends Apple's one-time `code` along with the identity token: the
/// server exchanges it for the refresh token it revokes when the account is
/// deleted (App Store 5.1.1(v)). The browser never names a redirect URI —
/// the BFF does.

let signIn: ReturnType<typeof vi.fn>;
const posts: { url: string; body: Record<string, unknown> }[] = [];

const withCode = {
  authorization: { id_token: 'apple-token', code: 'apple-code' },
  user: { name: { firstName: 'Awa', lastName: 'Koné' } },
};

beforeEach(() => {
  vi.stubEnv('NEXT_PUBLIC_APPLE_CLIENT_ID', 'com.myweli.signin');
  signIn = vi.fn(async () => withCode);
  (window as unknown as { AppleID: unknown }).AppleID = {
    auth: { init: vi.fn(), signIn },
  };
  posts.length = 0;
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      posts.push({ url: String(url), body: JSON.parse(String(init?.body ?? '{}')) });
      const user = {
        id: 'u1',
        name: 'Awa',
        email: 'awa@x.com',
        authProvider: 'apple',
        phoneNumber: '+2250700000000',
        phoneVerified: true,
      };
      return new Response(JSON.stringify({ ok: true, user }), { status: 200 });
    }),
  );
});

afterEach(() => {
  cleanup();
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
  replace.mockReset();
  delete (window as unknown as { AppleID?: unknown }).AppleID;
});

describe('the Apple authorization code crosses (B6.7)', () => {
  it('client sign-in → /api/auth/apple carries the code, and no redirect', async () => {
    const onSuccess = vi.fn();
    render(<LoginOptions onSuccess={onSuccess} />);
    fireEvent.click(screen.getByRole('button', { name: 'Continuer avec Apple' }));
    await waitFor(() => expect(posts.some((p) => p.url === '/api/auth/apple')).toBe(true));
    const login = posts.find((p) => p.url === '/api/auth/apple')!;
    expect(login.body.identityToken).toBe('apple-token');
    expect(login.body.authorizationCode).toBe('apple-code');
    expect(login.body).not.toHaveProperty('redirectUri');
  });

  it('Pro sign-in → /api/pro/auth/apple carries the code', async () => {
    render(<ProLoginOptions onSuccess={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: 'Continuer avec Apple' }));
    await waitFor(() => expect(posts.some((p) => p.url === '/api/pro/auth/apple')).toBe(true));
    const login = posts.find((p) => p.url === '/api/pro/auth/apple')!;
    expect(login.body.authorizationCode).toBe('apple-code');
    expect(login.body).not.toHaveProperty('redirectUri');
  });

  it('Pro sign-up → /api/pro/auth/register carries the code', async () => {
    render(<ProRegisterClient />);
    fireEvent.change(screen.getByLabelText('Nom de l’entreprise'), {
      target: { value: 'Salon Awa' },
    });
    fireEvent.change(screen.getByLabelText('Téléphone du salon'), {
      target: { value: '+2250707123456' },
    });
    fireEvent.change(screen.getByLabelText('Adresse'), {
      target: { value: 'Rue des Jardins, Cocody' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'S’inscrire avec Apple' }));
    await waitFor(() =>
      expect(posts.some((p) => p.url === '/api/pro/auth/register')).toBe(true),
    );
    const reg = posts.find((p) => p.url === '/api/pro/auth/register')!;
    expect(reg.body.authorizationCode).toBe('apple-code');
    expect(reg.body).not.toHaveProperty('redirectUri');
  });

  it('Apple gave no code → none is sent, the sign-in as before', async () => {
    signIn.mockResolvedValueOnce({ authorization: { id_token: 'apple-token' } });
    render(<ProLoginOptions onSuccess={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: 'Continuer avec Apple' }));
    await waitFor(() => expect(posts.some((p) => p.url === '/api/pro/auth/apple')).toBe(true));
    const login = posts.find((p) => p.url === '/api/pro/auth/apple')!;
    expect(login.body.identityToken).toBe('apple-token');
    expect(login.body).not.toHaveProperty('authorizationCode');
  });
});
