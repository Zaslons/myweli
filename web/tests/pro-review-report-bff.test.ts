// @vitest-environment node
import { NextRequest } from 'next/server';
import { afterEach, describe, expect, it, vi } from 'vitest';

const callApiPro = vi.fn();
vi.mock('../lib/bff-pro', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../lib/bff-pro')>()),
  callApiPro: (...a: unknown[]) => callApiPro(...a),
}));

const route = await import('../app/api/pro/reviews/[id]/report/route');

/// docs/design/backend-integrity-batch6.md §2.6 (B6.6): the BFF forwards the
/// salon's report to the session-scoped route — never a salon id of the
/// browser's choosing (the selection cookie is added by `callApiPro`).
describe('Pro review report BFF', () => {
  afterEach(() => callApiPro.mockReset());

  it('POST forwards the reason to /me/provider/reviews/{id}/report', async () => {
    callApiPro.mockResolvedValue({ status: 200, body: { status: 'reported' } });
    const res = await route.POST(
      new NextRequest('http://localhost/api/pro/reviews/r%2F1/report', {
        method: 'POST',
        body: JSON.stringify({ reason: 'Insultes', providerId: 'p9' }),
      }),
      { params: { id: 'r/1' } },
    );
    const [, path, init] = callApiPro.mock.calls[0] as [unknown, string, RequestInit];
    expect(path).toBe('/me/provider/reviews/r%2F1/report');
    expect(init.method).toBe('POST');
    expect(JSON.parse(String(init.body))).toEqual({ reason: 'Insultes' });
    expect(res.status).toBe(200);
  });

  it('no body: a report without a reason', async () => {
    callApiPro.mockResolvedValue({ status: 200, body: { status: 'reported' } });
    await route.POST(
      new NextRequest('http://localhost/api/pro/reviews/r1/report', { method: 'POST' }),
      { params: { id: 'r1' } },
    );
    const [, , init] = callApiPro.mock.calls[0] as [unknown, string, RequestInit];
    expect(JSON.parse(String(init.body))).toEqual({});
  });
});
