import type { NextRequest } from 'next/server';
import { afterEach, describe, expect, it, vi } from 'vitest';

const callApiPro = vi.fn();
vi.mock('../lib/bff-pro', () => ({
  callApiPro: (...a: unknown[]) => callApiPro(...a),
  respondPro: (r: { status: number; body?: unknown }) =>
    new Response(JSON.stringify(r.body ?? {}), { status: r.status }),
}));

const { POST } = await import('../app/api/pro/uploads/sign/route');

function reqWith(body: unknown): NextRequest {
  return { json: () => Promise.resolve(body) } as unknown as NextRequest;
}

/// The pro presign BFF's purpose allowlist (salon-logo.md §5): `logo` is a
/// pro purpose alongside `gallery` and `kyc`; anything else — `deposit` is
/// consumer-only, and an unknown string must not reach the API where it
/// would inherit some default namespace — is refused HERE, before the API.
describe('POST /api/pro/uploads/sign purpose allowlist', () => {
  afterEach(() => callApiPro.mockReset());

  it('forwards purpose=logo to the API', async () => {
    callApiPro.mockResolvedValue({ status: 200, body: { uploadUrl: 'u' } });
    const res = await POST(reqWith({ contentType: 'image/jpeg', purpose: 'logo' }));
    expect(res.status).toBe(200);
    const [, , init] = callApiPro.mock.calls[0] as [unknown, string, { body: string }];
    expect(JSON.parse(init.body).purpose).toBe('logo');
  });

  it('refuses a purpose outside {gallery, kyc, logo} without calling the API', async () => {
    for (const purpose of ['deposit', 'avatar', 'x']) {
      const res = await POST(reqWith({ contentType: 'image/jpeg', purpose }));
      expect(res.status).toBe(400);
    }
    expect(callApiPro).not.toHaveBeenCalled();
  });

  it('no purpose defaults to gallery', async () => {
    callApiPro.mockResolvedValue({ status: 200, body: {} });
    await POST(reqWith({ contentType: 'image/jpeg' }));
    const [, , init] = callApiPro.mock.calls[0] as [unknown, string, { body: string }];
    expect(JSON.parse(init.body).purpose).toBe('gallery');
  });
});
