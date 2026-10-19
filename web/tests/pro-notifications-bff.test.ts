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

const feed = await import('../app/api/pro/notifications/route');
const readAll = await import('../app/api/pro/notifications/read-all/route');
const readOne = await import('../app/api/pro/notifications/[id]/read/route');

const req = {} as unknown as NextRequest;

/// The salon's feed through the PRO session (docs/design/web-pro-notifications.md
/// §5): the same `/me/notifications*` the app reads — the feed is per
/// ACCOUNT, so no salon is added — and the API's answer as it is, 401
/// included (the page sends it to /pro/connexion).
describe('Pro notifications BFF', () => {
  afterEach(() => callApiPro.mockReset());

  it('GET → GET /me/notifications on the pro session', async () => {
    callApiPro.mockResolvedValue({ status: 200, body: { items: [{ id: 'n1' }] } });
    const res = await feed.GET(req);
    expect(callApiPro.mock.calls[0][1]).toBe('/me/notifications');
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ items: [{ id: 'n1' }] });
  });

  it('no session → the 401 crosses as it is', async () => {
    callApiPro.mockResolvedValue({ status: 401, body: { error: 'unauthorized' } });
    expect((await feed.GET(req)).status).toBe(401);
  });

  it('read-all → POST /me/notifications/read-all', async () => {
    callApiPro.mockResolvedValue({ status: 200, body: {} });
    await readAll.POST(req);
    const [, path, init] = callApiPro.mock.calls[0] as [unknown, string, RequestInit];
    expect(path).toBe('/me/notifications/read-all');
    expect(init.method).toBe('POST');
  });

  it('one → POST /me/notifications/{id}/read, the id encoded', async () => {
    callApiPro.mockResolvedValue({ status: 200, body: {} });
    await readOne.POST(req, { params: { id: 'n/1' } });
    const [, path, init] = callApiPro.mock.calls[0] as [unknown, string, RequestInit];
    expect(path).toBe('/me/notifications/n%2F1/read');
    expect(init.method).toBe('POST');
  });
});
