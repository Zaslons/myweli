import { NextResponse } from 'next/server';
import { apiBase } from './server-api';
import { setSessionCookies } from './session';

/// Shared login BFF: forward a login payload to a backend auth endpoint, then
/// store the (NESTED — AuthSession) token pair in httpOnly cookies. The browser
/// never sees tokens; the backend is the verifier (JWKS/OTP — threat T31/T32).
/// Design: docs/design/web-auth-social.md §2.
export async function loginViaBackend(
  backendPath: string,
  payload: unknown,
): Promise<NextResponse> {
  const r = await fetch(`${apiBase}${backendPath}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
  });
  const body = await r.json().catch(() => ({}));
  const tokens = body.tokens;
  if (!r.ok || !tokens?.accessToken || !tokens?.refreshToken) {
    return NextResponse.json(
      { error: body.error ?? 'login_failed' },
      { status: r.ok ? 502 : r.status },
    );
  }
  const res = NextResponse.json({ ok: true, user: body.user ?? null });
  setSessionCookies(res, tokens.accessToken, tokens.refreshToken);
  return res;
}
