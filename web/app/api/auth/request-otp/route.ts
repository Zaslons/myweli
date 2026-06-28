import { type NextRequest, NextResponse } from 'next/server';
import { apiBase } from '../../../../lib/server-api';

/// BFF: dispatch an OTP. Same-origin (no CORS); proxies the dart_frog API.
export async function POST(req: NextRequest) {
  const { phoneNumber } = await req.json().catch(() => ({}));
  const r = await fetch(`${apiBase}/auth/otp/request`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ phoneNumber }),
  });
  const body = await r.json().catch(() => ({}));
  if (!r.ok) {
    return NextResponse.json({ error: body.error ?? 'error' }, { status: r.status });
  }
  // devCode is only present when ENV != prod (the API gates it) — handy for dev/e2e.
  return NextResponse.json({ ok: true, devCode: body.devCode });
}
