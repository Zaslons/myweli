import { type NextRequest, NextResponse } from 'next/server';
import { apiBase } from '../../../../../lib/server-api';
import { setProSessionCookies } from '../../../../../lib/session';

/// Pro BFF: verify a provider OTP, then store the token pair in the pro httpOnly
/// cookies. Unknown salon → 4xx (the UI nudges the pro app to register).
export async function POST(req: NextRequest) {
  const { phoneNumber, code } = await req.json().catch(() => ({}));
  const r = await fetch(`${apiBase}/auth/provider/otp/verify`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ phoneNumber, code }),
  });
  const body = await r.json().catch(() => ({}));
  if (!r.ok || !body.accessToken || !body.refreshToken) {
    return NextResponse.json(
      { error: body.error ?? 'invalid_code' },
      { status: r.ok ? 502 : r.status },
    );
  }
  const res = NextResponse.json({ ok: true });
  setProSessionCookies(res, body.accessToken, body.refreshToken);
  return res;
}
