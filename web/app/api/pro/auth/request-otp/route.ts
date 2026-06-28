import { type NextRequest, NextResponse } from 'next/server';
import { apiBase } from '../../../../../lib/server-api';

/// Pro BFF: dispatch a provider OTP.
export async function POST(req: NextRequest) {
  const { phoneNumber } = await req.json().catch(() => ({}));
  const r = await fetch(`${apiBase}/auth/provider/otp/request`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ phoneNumber }),
  });
  const body = await r.json().catch(() => ({}));
  if (!r.ok) {
    return NextResponse.json({ error: body.error ?? 'error' }, { status: r.status });
  }
  return NextResponse.json({ ok: true, devCode: body.devCode });
}
