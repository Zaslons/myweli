// @vitest-environment node
import type { NextRequest } from 'next/server';
import { afterEach, describe, expect, it, vi } from 'vitest';

const proLoginViaBackend = vi.fn(async () => new Response('{}', { status: 200 }));
vi.mock('../lib/auth-bff', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../lib/auth-bff')>()),
  proLoginViaBackend: (...a: unknown[]) => proLoginViaBackend(...(a as [])),
}));

const apple = await import('../app/api/pro/auth/apple/route');
const register = await import('../app/api/pro/auth/register/route');

const req = (body: unknown) =>
  ({ json: () => Promise.resolve(body) }) as unknown as NextRequest;

/// The Pro BFF for Sign in with Apple (docs/design/web-pro-apple.md §3): the
/// same backend routes the app calls.
describe('Pro Apple BFF', () => {
  afterEach(() => proLoginViaBackend.mockClear());

  it('sign-in → /auth/provider/apple with the token and its nonce', async () => {
    await apple.POST(req({ identityToken: 't', nonce: 'n', extra: 'dropped' }));
    expect(proLoginViaBackend).toHaveBeenCalledWith('/auth/provider/apple', {
      identityToken: 't',
      nonce: 'n',
    });
  });

  it('sign-up accepts an Apple identity (it took Google or e-mail only)', async () => {
    const body = {
      identityToken: 't',
      nonce: 'n',
      businessName: 'Salon Awa',
      businessType: 'salon',
      phoneNumber: '+2250707123456',
    };
    const res = await register.POST(req(body));
    expect(res.status).toBe(200);
    expect(proLoginViaBackend).toHaveBeenCalledWith('/auth/provider/register', body);
  });
});
