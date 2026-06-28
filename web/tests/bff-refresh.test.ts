import { afterEach, describe, expect, it, vi } from 'vitest';
import type { NextRequest } from 'next/server';
import { callApi } from '../lib/bff';

function reqWith(cookies: Record<string, string>): NextRequest {
  return {
    cookies: {
      get: (k: string) =>
        cookies[k] ? { value: cookies[k] } : undefined,
    },
  } as unknown as NextRequest;
}

describe('BFF silent refresh (callApi)', () => {
  afterEach(() => vi.restoreAllMocks());

  it('401 → refresh → retry succeeds, surfaces rotated tokens', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(new Response(null, { status: 401 })) // first call
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({ accessToken: 'na', refreshToken: 'nr' }),
          { status: 200 },
        ),
      ) // refresh
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ ok: true }), { status: 200 }),
      ); // retry
    vi.stubGlobal('fetch', fetchMock);

    const r = await callApi(
      reqWith({ myweli_web_at: 'old', myweli_web_rt: 'rt' }),
      '/me',
    );
    expect(r.status).toBe(200);
    expect(r.tokens).toEqual({ at: 'na', rt: 'nr' });
    expect(fetchMock).toHaveBeenCalledTimes(3);
  });

  it('401 + refresh fails → 401 (no infinite retry)', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(new Response(null, { status: 401 }))
      .mockResolvedValueOnce(new Response(null, { status: 401 })); // refresh fails
    vi.stubGlobal('fetch', fetchMock);

    const r = await callApi(
      reqWith({ myweli_web_at: 'old', myweli_web_rt: 'rt' }),
      '/me',
    );
    expect(r.status).toBe(401);
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it('no cookies → 401 without calling the API', async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);

    const r = await callApi(reqWith({}), '/me');
    expect(r.status).toBe(401);
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
