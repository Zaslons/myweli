// @vitest-environment node
import { NextRequest } from 'next/server';
import { afterEach, describe, expect, it, vi } from 'vitest';

const callApiPro = vi.fn();
// Only the API call is faked: `respondPro` is the real one.
vi.mock('../lib/bff-pro', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../lib/bff-pro')>()),
  callApiPro: (...a: unknown[]) => callApiPro(...a),
}));

const route = await import('../app/api/pro/notification-preferences/route');

const put = (body: string) =>
  new NextRequest('http://localhost/api/pro/notification-preferences', {
    method: 'PUT',
    body,
  });

/// docs/design/salon-email-alerts.md §5 — the member's own preferences
/// through the PRO session; web Pro writes « Alertes par e-mail » and
/// nothing else.
describe('Pro notification-preferences BFF', () => {
  afterEach(() => callApiPro.mockReset());

  it('GET → GET /me/notification-preferences on the pro session', async () => {
    callApiPro.mockResolvedValue({ status: 200, body: { emailAlerts: true } });
    const res = await route.GET({} as NextRequest);
    expect(callApiPro.mock.calls[0][1]).toBe('/me/notification-preferences');
    expect(await res.json()).toEqual({ emailAlerts: true });
  });

  it('PUT forwards emailAlerts — and only it', async () => {
    callApiPro.mockResolvedValue({ status: 200, body: { emailAlerts: false } });
    await route.PUT(put('{"emailAlerts":false,"marketing":false,"push":false}'));
    const [, path, init] = callApiPro.mock.calls[0] as [unknown, string, RequestInit];
    expect(path).toBe('/me/notification-preferences');
    expect(init.method).toBe('PUT');
    expect(JSON.parse(String(init.body))).toEqual({ emailAlerts: false });
  });

  it('a body that is not JSON, or no boolean → 400, nothing sent', async () => {
    for (const b of ['not json', '{"emailAlerts":"non"}', '{}']) {
      const res = await route.PUT(put(b));
      expect(res.status, b).toBe(400);
    }
    expect(callApiPro).not.toHaveBeenCalled();
  });

  it('no session → the 401 crosses as it is', async () => {
    callApiPro.mockResolvedValue({ status: 401, body: { error: 'unauthorized' } });
    expect((await route.GET({} as NextRequest)).status).toBe(401);
  });
});
