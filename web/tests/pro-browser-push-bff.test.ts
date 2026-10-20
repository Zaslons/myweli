// @vitest-environment node
import { NextRequest } from 'next/server';
import { afterEach, describe, expect, it, vi } from 'vitest';

const callApiPro = vi.fn();
// Only the API call is faked: `respondPro` is the real one.
vi.mock('../lib/bff-pro', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../lib/bff-pro')>()),
  callApiPro: (...a: unknown[]) => callApiPro(...a),
}));

const route = await import('../app/api/pro/devices/route');

const req = (method: 'POST' | 'DELETE', body: string) =>
  new NextRequest('http://localhost/api/pro/devices', { method, body });

/// docs/design/web-pro-browser-push.md §5 — this browser's notification token,
/// registered on the member's PRO session. The platform is the BFF's to say:
/// a browser is `web`, whatever a body claims.
describe('Pro devices BFF', () => {
  afterEach(() => callApiPro.mockReset());

  it('POST registers the token as web — the body’s platform is not forwarded', async () => {
    callApiPro.mockResolvedValue({ status: 200, body: { status: 'registered' } });
    const res = await route.POST(req('POST', '{"token":"fcm-1","platform":"ios","userId":"x"}'));
    const [, path, init] = callApiPro.mock.calls[0] as [unknown, string, RequestInit];
    expect(path).toBe('/me/devices');
    expect(init.method).toBe('POST');
    expect(JSON.parse(String(init.body))).toEqual({ token: 'fcm-1', platform: 'web' });
    expect(res.status).toBe(200);
  });

  it('DELETE unregisters exactly that token', async () => {
    callApiPro.mockResolvedValue({ status: 200, body: { status: 'unregistered' } });
    await route.DELETE(req('DELETE', '{"token":"fcm-1","platform":"web"}'));
    const [, path, init] = callApiPro.mock.calls[0] as [unknown, string, RequestInit];
    expect(path).toBe('/me/devices');
    expect(init.method).toBe('DELETE');
    expect(JSON.parse(String(init.body))).toEqual({ token: 'fcm-1' });
  });

  it('no token, a blank one, a non-text one, one past 4 096 characters, not JSON → 400, nothing sent', async () => {
    for (const b of ['not json', '{}', '{"token":"  "}', '{"token":42}', JSON.stringify({ token: 'x'.repeat(4097) })]) {
      for (const m of ['POST', 'DELETE'] as const) {
        const res = await route[m](req(m, b));
        expect(res.status, `${m} ${b.slice(0, 20)}`).toBe(400);
      }
    }
    expect(callApiPro).not.toHaveBeenCalled();
  });

  it('no session → the 401 crosses as it is', async () => {
    callApiPro.mockResolvedValue({ status: 401, body: { error: 'unauthorized' } });
    expect((await route.POST(req('POST', '{"token":"fcm-1"}'))).status).toBe(401);
  });
});
