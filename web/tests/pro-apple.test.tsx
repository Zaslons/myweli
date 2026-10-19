import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const replace = vi.fn();
vi.mock('next/navigation', () => ({
  useRouter: () => ({ replace, push: vi.fn() }),
  useSearchParams: () => ({ get: () => null }),
}));
// jsdom never loads a <script>: the Apple JS is stubbed on `window` below.
vi.mock('../lib/loadScript', () => ({ loadScript: async () => {} }));

import { ProLoginOptions } from '../components/pro/ProLoginOptions';
import { ProRegisterClient } from '../components/pro/ProRegisterClient';

/// Sign in with Apple on the web Pro side (docs/design/web-pro-apple.md) —
/// the app has it on both screens; a salon that signed up with Apple on its
/// iPhone could not open the web, where it chooses its offer.

let signIn: ReturnType<typeof vi.fn>;
const posts: { url: string; body: Record<string, unknown> }[] = [];
let answer: { status: number; body: unknown } = { status: 200, body: {} };

beforeEach(() => {
  vi.stubEnv('NEXT_PUBLIC_APPLE_CLIENT_ID', 'com.myweli.signin');
  signIn = vi.fn(async () => ({
    authorization: { id_token: 'apple-token' },
    user: { name: { firstName: 'Awa', lastName: 'Koné' } },
  }));
  (window as unknown as { AppleID: unknown }).AppleID = {
    auth: { init: vi.fn(), signIn },
  };
  posts.length = 0;
  answer = { status: 200, body: {} };
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string, init?: RequestInit) => {
      posts.push({ url: String(url), body: JSON.parse(String(init?.body ?? '{}')) });
      return new Response(JSON.stringify(answer.body), { status: answer.status });
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

describe('Pro sign-in — « Continuer avec Apple »', () => {
  it('signs in with the Apple token and its nonce', async () => {
    const onSuccess = vi.fn();
    render(<ProLoginOptions onSuccess={onSuccess} />);
    fireEvent.click(screen.getByRole('button', { name: 'Continuer avec Apple' }));
    await waitFor(() => expect(onSuccess).toHaveBeenCalled());
    expect(posts[0].url).toBe('/api/pro/auth/apple');
    expect(posts[0].body.identityToken).toBe('apple-token');
    // The nonce the popup was given is the one that is sent.
    const nonce = signIn.mock.calls[0][0].nonce as string;
    expect(nonce).toMatch(/^[0-9a-f]{32}$/);
    expect(posts[0].body.nonce).toBe(nonce);
  });

  it('an unknown salon gets Google’s answer — and the way to sign up', async () => {
    answer = { status: 404, body: { error: 'provider_not_found' } };
    render(<ProLoginOptions onSuccess={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: 'Continuer avec Apple' }));
    expect(await screen.findByText('Compte introuvable.')).toBeInTheDocument();
    expect(screen.getAllByRole('link', { name: 'Créer mon compte' }).length).toBeGreaterThan(0);
  });

  it('a refusal says so', async () => {
    answer = { status: 401, body: { error: 'token_rejected' } };
    render(<ProLoginOptions onSuccess={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: 'Continuer avec Apple' }));
    expect(await screen.findByText('Connexion Apple impossible.')).toBeInTheDocument();
  });

  it('a closed popup says nothing and sends nothing', async () => {
    signIn.mockRejectedValueOnce({ error: 'popup_closed_by_user' });
    render(<ProLoginOptions onSuccess={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: 'Continuer avec Apple' }));
    await waitFor(() => expect(signIn).toHaveBeenCalled());
    expect(posts).toHaveLength(0);
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('no Apple client id → no Apple button', () => {
    vi.stubEnv('NEXT_PUBLIC_APPLE_CLIENT_ID', '');
    render(<ProLoginOptions onSuccess={vi.fn()} />);
    expect(screen.queryByRole('button', { name: 'Continuer avec Apple' })).toBeNull();
  });
});

describe('Pro sign-up — « S’inscrire avec Apple »', () => {
  it('checks the salon’s fields BEFORE opening Apple', async () => {
    render(<ProRegisterClient />);
    fireEvent.click(screen.getByRole('button', { name: 'S’inscrire avec Apple' }));
    expect(await screen.findByText('Saisissez le nom de l’entreprise.')).toBeInTheDocument();
    expect(signIn).not.toHaveBeenCalled();
    expect(posts.filter((p) => p.url === '/api/pro/auth/register')).toHaveLength(0);
  });

  it('registers with the Apple identity and the salon’s fields', async () => {
    render(<ProRegisterClient />);
    fireEvent.change(screen.getByLabelText('Nom de l’entreprise'), {
      target: { value: 'Salon Awa' },
    });
    fireEvent.change(screen.getByLabelText('Téléphone du salon'), {
      target: { value: '+2250707123456' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'S’inscrire avec Apple' }));
    await waitFor(() => expect(replace).toHaveBeenCalledWith('/pro'));
    const reg = posts.find((p) => p.url === '/api/pro/auth/register')!;
    expect(reg.body).toMatchObject({
      identityToken: 'apple-token',
      businessName: 'Salon Awa',
      fullName: 'Awa Koné',
    });
    expect(reg.body.nonce).toMatch(/^[0-9a-f]{32}$/);
  });
});
