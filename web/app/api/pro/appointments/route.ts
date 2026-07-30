import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';

/// Pro BFF: the salon's bookings (provider-scoped server-side from the account).
/// Passes through an optional ?status= filter.
export async function GET(req: NextRequest) {
  const status = req.nextUrl.searchParams.get('status');
  const path = status
    ? `/appointments?status=${encodeURIComponent(status)}`
    : '/appointments';
  return respondPro(await callApiPro(req, path));
}

/// Pro BFF: salon-entered (manual) booking — used by the journal grid's
/// quick-create (module journal J1). The client sends its own providerId; the
/// backend enforces ownership + server-prices.
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  const { providerId } = body;
  if (!providerId) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/providers/${providerId}/appointments`, {
      method: 'POST',
      body: JSON.stringify(body),
    }),
  );
}
