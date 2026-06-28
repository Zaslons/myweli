import { type NextRequest, NextResponse } from 'next/server';
import { apiBase } from '../../../../lib/server-api';
import { setSessionCookies } from '../../../../lib/session';

/// BFF: verify the OTP, then store the token pair in httpOnly cookies (the
/// tokens never reach the browser). Returns only minimal user info.
export async function POST(req: NextRequest) {
  const { phoneNumber, code } = await req.json().catch(() => ({}));
  const r = await fetch(`${apiBase}/auth/otp/verify`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ phoneNumber, code }),
  });
  const body = await r.json().catch(() => ({}));
  // The API returns the AuthSession shape: { tokens: { accessToken, refreshToken,
  // … }, user }. (Read tokens from `tokens`, not the top level.)
  const tokens = body.tokens;
  if (!r.ok || !tokens?.accessToken || !tokens?.refreshToken) {
    return NextResponse.json(
      { error: body.error ?? 'invalid_code' },
      { status: r.ok ? 502 : r.status },
    );
  }
  const res = NextResponse.json({ ok: true, user: body.user ?? null });
  setSessionCookies(res, tokens.accessToken, tokens.refreshToken);
  return res;
}
