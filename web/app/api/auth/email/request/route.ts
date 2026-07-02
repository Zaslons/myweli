import { type NextRequest, NextResponse } from 'next/server';
import { apiBase } from '../../../../../lib/server-api';

/// BFF: request an email OTP (passthrough — no session yet). The backend
/// answers identically whether or not the address has an account (no
/// enumeration); dev builds echo `devCode`.
export async function POST(req: NextRequest) {
  const { email } = await req.json().catch(() => ({}));
  const r = await fetch(`${apiBase}/auth/email/otp/request`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email }),
  });
  const body = await r.json().catch(() => ({}));
  return NextResponse.json(body, { status: r.status });
}
