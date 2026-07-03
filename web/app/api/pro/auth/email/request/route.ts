import { type NextRequest, NextResponse } from 'next/server';
import { apiBase } from '../../../../../../lib/server-api';

/// Pro BFF: request a salon email OTP (passthrough — no session yet).
export async function POST(req: NextRequest) {
  const { email } = await req.json().catch(() => ({}));
  const r = await fetch(`${apiBase}/auth/provider/email/otp/request`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email }),
  });
  const body = await r.json().catch(() => ({}));
  return NextResponse.json(body, { status: r.status });
}
