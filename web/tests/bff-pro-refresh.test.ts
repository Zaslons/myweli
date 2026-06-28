import type { NextRequest } from 'next/server';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { callApiPro } from '../lib/bff-pro';

function reqWith(cookies: Record<string, string>): NextRequest {
  return {
    cookies: {
      get: (k: string) => (cookies[k] ? { value: cookies[k] } : undefined),
    },
  } as unknown as NextRequest;
}

describe('pro BFF silent refresh (callApiPro)', () => {
  afterEach(() => vi.restoreAllMocks());

  it('401 → /auth/provider/refresh → retry, surfaces rotated tokens', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(new Response(null, { status: 401 }))
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({ accessToken: 'na', refreshToken: 'nr' }),
          { status: 200 },
        ),
      )
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ ok: true }), { status: 200 }),
      );
    vi.stubGlobal('fetch', fetchMock);

    const r = await callApiPro(
      reqWith({ myweli_pro_at: 'old', myweli_pro_rt: 'rt' }),
      '/me/provider',
    );
    expect(r.status).toBe(200);
    expect(r.tokens).toEqual({ at: 'na', rt: 'nr' });
    // Refresh hit the provider endpoint.
    expect(String(fetchMock.mock.calls[1][0])).toContain('/auth/provider/refresh');
  });

  it('no pro cookies → 401 without calling the API', async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    const r = await callApiPro(reqWith({}), '/me/provider');
    expect(r.status).toBe(401);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
