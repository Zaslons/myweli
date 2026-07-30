import { afterEach, describe, expect, it, vi } from 'vitest';
import { getMyProvider } from '../lib/api/pro';

/// Team access R5b — getMyProvider surfaces the machine code on a non-2xx so
/// the membership probe can tell a REVOKED member (403 not_a_member) from a
/// plain expired session (401).

afterEach(() => vi.unstubAllGlobals());

describe('getMyProvider error surfacing', () => {
  it('403 {error:not_a_member} → {status:403, error:not_a_member}', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        new Response(JSON.stringify({ error: 'not_a_member' }), {
          status: 403,
        }),
      ),
    );
    const r = await getMyProvider();
    expect(r.status).toBe(403);
    expect(r.error).toBe('not_a_member');
    expect(r.profile).toBeUndefined();
  });

  it('401 without a body → status only (no crash)', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(new Response(null, { status: 401 })),
    );
    const r = await getMyProvider();
    expect(r.status).toBe(401);
    expect(r.error).toBeUndefined();
  });

  it('200 → the profile, no error', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({
            account: { id: 'acc1' },
            provider: { id: 'p1', name: 'Beauté Divine' },
          }),
          { status: 200 },
        ),
      ),
    );
    const r = await getMyProvider();
    expect(r.status).toBe(200);
    expect(r.profile?.provider.id).toBe('p1');
    expect(r.error).toBeUndefined();
  });
});
