import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';

/// Pro BFF: the journal day view (module journal J1). The client sends its own
/// providerId; the backend enforces ownership + returns the one-payload day.
export async function GET(req: NextRequest) {
  const p = req.nextUrl.searchParams;
  const providerId = p.get('providerId');
  const date = p.get('date');
  if (!providerId || !date) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(
      req,
      `/providers/${providerId}/journal?date=${encodeURIComponent(date)}`,
      { method: 'GET' },
    ),
  );
}
