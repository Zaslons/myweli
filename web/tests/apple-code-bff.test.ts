// @vitest-environment node
import type { NextRequest } from 'next/server';
import { afterEach, describe, expect, it, vi } from 'vitest';

const loginViaBackend = vi.fn(async () => new Response('{}', { status: 200 }));
const proLoginViaBackend = vi.fn(async () => new Response('{}', { status: 200 }));
vi.mock('../lib/auth-bff', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../lib/auth-bff')>()),
  loginViaBackend: (...a: unknown[]) => loginViaBackend(...(a as [])),
  proLoginViaBackend: (...a: unknown[]) => proLoginViaBackend(...(a as [])),
}));

const client = await import('../app/api/auth/apple/route');
const pro = await import('../app/api/pro/auth/apple/route');
const register = await import('../app/api/pro/auth/register/route');

/// A request as the BFF sees it: its JSON, and the origin the page is on.
const req = (body: unknown, origin = 'https://myweli.com') =>
  ({
    json: () => Promise.resolve(body),
    nextUrl: new URL(`${origin}/api/x`),
  }) as unknown as NextRequest;

const sentTo = (fn: typeof loginViaBackend) =>
  (fn.mock.calls[0] as unknown as [string, Record<string, unknown>])[1];

/// docs/design/backend-integrity-batch6.md §13 (B6.7) — the BFFs pass Apple's
/// code on, with the redirect URI Apple requires for a WEB code: the one the
/// page gave Apple (`<origin>/connexion`, lib/auth/apple.ts), derived here
/// from this request's own origin — NEVER one the browser names.
describe('Apple code through the BFFs', () => {
  afterEach(() => {
    loginViaBackend.mockClear();
    proLoginViaBackend.mockClear();
  });

  it('client: the code, and the redirect of this origin', async () => {
    await client.POST(
      req({ identityToken: 't', nonce: 'n', authorizationCode: 'c-1' }),
    );
    expect(sentTo(loginViaBackend)).toEqual({
      identityToken: 't',
      nonce: 'n',
      fullName: undefined,
      authorizationCode: 'c-1',
      redirectUri: 'https://myweli.com/connexion',
    });
  });

  it('client: a browser-named redirect is never forwarded', async () => {
    await client.POST(
      req({
        identityToken: 't',
        authorizationCode: 'c-1',
        redirectUri: 'https://evil.example/cb',
      }),
    );
    expect(sentTo(loginViaBackend).redirectUri).toBe('https://myweli.com/connexion');
  });

  it('client: no code → neither field', async () => {
    await client.POST(req({ identityToken: 't', redirectUri: 'https://evil.example/cb' }));
    const sent = sentTo(loginViaBackend);
    expect(sent).not.toHaveProperty('authorizationCode');
    expect(sent).not.toHaveProperty('redirectUri');
  });

  it('Pro sign-in: the code, and the redirect of this origin', async () => {
    await pro.POST(
      req({ identityToken: 't', nonce: 'n', authorizationCode: 'c-1' }, 'https://www.myweli.com'),
    );
    expect(sentTo(proLoginViaBackend)).toEqual({
      identityToken: 't',
      nonce: 'n',
      authorizationCode: 'c-1',
      redirectUri: 'https://www.myweli.com/connexion',
    });
  });

  it('Pro sign-up: the code with an Apple identity; the browser’s redirect dropped', async () => {
    await register.POST(
      req({
        identityToken: 't',
        nonce: 'n',
        authorizationCode: 'c-1',
        redirectUri: 'https://evil.example/cb',
        businessName: 'Salon Awa',
        businessType: 'salon',
        phoneNumber: '+2250707123456',
      }),
    );
    const sent = sentTo(proLoginViaBackend);
    expect(sent.authorizationCode).toBe('c-1');
    expect(sent.redirectUri).toBe('https://myweli.com/connexion');
    expect(sent.businessName).toBe('Salon Awa');
  });

  it('Pro sign-up with Google: no Apple field crosses', async () => {
    await register.POST(
      req({
        idToken: 'g',
        authorizationCode: 'c-1',
        redirectUri: 'https://evil.example/cb',
        businessName: 'Salon Awa',
        businessType: 'salon',
        phoneNumber: '+2250707123456',
      }),
    );
    const sent = sentTo(proLoginViaBackend);
    expect(sent).not.toHaveProperty('authorizationCode');
    expect(sent).not.toHaveProperty('redirectUri');
    expect(sent.idToken).toBe('g');
  });
});
