import { type NextRequest, NextResponse } from 'next/server';
import { apiBase } from '../../../lib/server-api';
import { AT_COOKIE } from '../../../lib/session';

/// BFF: create a booking under the session (access token from the httpOnly
/// cookie). The server prices it + derives the deposit; we forward only the
/// selection. Booking happens seconds after OTP verify, so the access token is
/// fresh — silent refresh is a follow-up (M6).
export async function POST(req: NextRequest) {
  const accessToken = req.cookies.get(AT_COOKIE)?.value;
  if (!accessToken) {
    return NextResponse.json({ error: 'not_authenticated' }, { status: 401 });
  }

  const payload = await req.json().catch(() => ({}));
  const r = await fetch(`${apiBase}/appointments`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${accessToken}`,
    },
    body: JSON.stringify({
      providerId: payload.providerId,
      serviceIds: payload.serviceIds,
      appointmentDateTime: payload.appointmentDateTime,
      artistId: payload.artistId ?? undefined,
    }),
  });
  const body = await r.json().catch(() => ({}));
  if (!r.ok) {
    return NextResponse.json({ error: body.error ?? 'error' }, { status: r.status });
  }
  return NextResponse.json({ ok: true, appointment: body });
}
