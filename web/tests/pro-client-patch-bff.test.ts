// @vitest-environment node
import type { NextRequest } from 'next/server';
import { afterEach, describe, expect, it, vi } from 'vitest';

const callApiPro = vi.fn();
// Only the API call is faked: `respondPro` is the real one, so what the
// browser receives is what the route really answers.
vi.mock('../lib/bff-pro', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../lib/bff-pro')>()),
  callApiPro: (...a: unknown[]) => callApiPro(...a),
}));

const { PATCH } = await import('../app/api/pro/clients/[clientId]/route');

function reqWith(body: unknown): NextRequest {
  return { json: () => Promise.resolve(body) } as unknown as NextRequest;
}

const params = { params: { clientId: 'sc1' } };

/// What the API is sent: path, method, and the parsed body.
function forwarded() {
  const [, path, init] = callApiPro.mock.calls[0] as [
    unknown,
    string,
    { method: string; body: string },
  ];
  return { path, method: init.method, body: JSON.parse(init.body) };
}

/// The Pro BFF's `PATCH /api/pro/clients/{id}` (docs/design/phone-leftovers.md
/// §8): it forwards `phone` beside `tags` — at least one — with the same
/// pass-through as the tags: only the fields the browser sent, never the
/// `providerId` (it is in the path), and the API's answer as it is, the 409
/// `client_exists` body with its `clientId` included.
describe('PATCH /api/pro/clients/[clientId] — phone beside tags', () => {
  afterEach(() => callApiPro.mockReset());

  it('forwards a phone alone — no tags key is invented', async () => {
    callApiPro.mockResolvedValue({ status: 200, body: { id: 'sc1' } });
    const res = await PATCH(reqWith({ providerId: 'p1', phone: '+2250505123456' }), params);
    expect(res.status).toBe(200);
    expect(forwarded()).toEqual({
      path: '/providers/p1/clients/sc1',
      method: 'PATCH',
      body: { phone: '+2250505123456' },
    });
  });

  it('forwards tags alone exactly as before', async () => {
    callApiPro.mockResolvedValue({ status: 200, body: {} });
    await PATCH(reqWith({ providerId: 'p1', tags: ['VIP'] }), params);
    expect(forwarded().body).toEqual({ tags: ['VIP'] });
  });

  it('forwards both when both are sent', async () => {
    callApiPro.mockResolvedValue({ status: 200, body: {} });
    await PATCH(
      reqWith({ providerId: 'p1', tags: ['VIP'], phone: '+2250505123456' }),
      params,
    );
    expect(forwarded().body).toEqual({ tags: ['VIP'], phone: '+2250505123456' });
  });

  it('an empty phone still crosses — the server is the one that refuses it', async () => {
    callApiPro.mockResolvedValue({ status: 400, body: { error: 'invalid_phone' } });
    const res = await PATCH(reqWith({ providerId: 'p1', phone: '' }), params);
    expect(forwarded().body).toEqual({ phone: '' });
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: 'invalid_phone' });
  });

  it('refuses a body with nothing to change, no salon, or a wrong type — without calling the API', async () => {
    // An API that would accept anything: a body that slips through answers
    // 200, and the assertion names it.
    callApiPro.mockResolvedValue({ status: 200, body: {} });
    for (const body of [
      { providerId: 'p1' },
      { phone: '+2250505123456' },
      { providerId: 'p1', tags: 'VIP' },
      { providerId: 'p1', phone: 2250505123456 },
      { providerId: 'p1', tags: ['VIP'], phone: 2250505123456 },
      { providerId: 'p1', phone: null },
    ]) {
      const res = await PATCH(reqWith(body), params);
      expect(res.status, JSON.stringify(body)).toBe(400);
      expect(await res.json()).toEqual({ error: 'invalid_input' });
    }
    expect(callApiPro).not.toHaveBeenCalled();
  });

  it('a 409 client_exists reaches the browser with the other card id', async () => {
    callApiPro.mockResolvedValue({
      status: 409,
      body: { error: 'client_exists', clientId: 'sc7' },
    });
    const res = await PATCH(reqWith({ providerId: 'p1', phone: '+2250707123456' }), params);
    expect(res.status).toBe(409);
    expect(await res.json()).toEqual({ error: 'client_exists', clientId: 'sc7' });
  });

  it('a 409 client_linked reaches the browser as it is', async () => {
    callApiPro.mockResolvedValue({ status: 409, body: { error: 'client_linked' } });
    const res = await PATCH(reqWith({ providerId: 'p1', phone: '+2250707123456' }), params);
    expect(res.status).toBe(409);
    expect(await res.json()).toEqual({ error: 'client_linked' });
  });
});
