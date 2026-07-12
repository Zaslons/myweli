import { afterEach, describe, expect, it, vi } from 'vitest';
import { proLoginViaBackend } from '../lib/auth-bff';

/// Team access R5a — the 202 invitation bridge in proLoginViaBackend. The
/// critical security property: a 202 NEVER sets a session cookie (a session
/// before an explicit accept would be an auth bypass).

describe('proLoginViaBackend — 202 invitation bridge', () => {
  afterEach(() => vi.restoreAllMocks());

  it('202 {invitations} → passthrough, NO Set-Cookie', async () => {
    const invitations = [
      {
        id: 'inv1',
        providerId: 'p1',
        salonName: 'Beauté Divine',
        role: 'manager',
        roleLabel: 'Manager',
        expiresAt: '2099-01-01T00:00:00.000Z',
      },
    ];
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        new Response(JSON.stringify({ invitations }), { status: 202 }),
      ),
    );

    const res = await proLoginViaBackend('/auth/provider/google', {
      idToken: 'x',
    });
    expect(res.status).toBe(202);
    expect(res.headers.get('set-cookie')).toBeNull();
    const body = await res.json();
    expect(body.invitations).toHaveLength(1);
    expect(body.invitations[0].salonName).toBe('Beauté Divine');
  });

  it('a normal flat session (200) DOES set the pro cookies', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({
            accessToken: 'a',
            refreshToken: 'r',
            provider: { id: 'acc1' },
          }),
          { status: 200 },
        ),
      ),
    );

    const res = await proLoginViaBackend('/auth/provider/google', {
      idToken: 'x',
    });
    expect(res.status).toBe(200);
    expect(res.headers.get('set-cookie')).toContain('myweli_pro_at');
  });

  it('a 202 without an invitations array is NOT treated as the bridge', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(new Response(JSON.stringify({}), { status: 202 })),
    );
    const res = await proLoginViaBackend('/auth/provider/google', {
      idToken: 'x',
    });
    // Falls through to the failure branch (no tokens) — never a session.
    expect(res.headers.get('set-cookie')).toBeNull();
    expect(res.status).not.toBe(200);
  });
});
