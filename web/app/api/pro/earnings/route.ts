import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';

/// Pro BFF: the salon's realized earnings ledger (parity 9.1 — B-earn).
/// Client passes its own providerId (+ optional UTC range); the backend
/// enforces ownership (→ 403) and validates the dates.
export async function GET(req: NextRequest) {
  const providerId = req.nextUrl.searchParams.get('providerId');
  if (!providerId) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  const qs = new URLSearchParams();
  const start = req.nextUrl.searchParams.get('startDate');
  const end = req.nextUrl.searchParams.get('endDate');
  if (start) qs.set('startDate', start);
  if (end) qs.set('endDate', end);
  const suffix = qs.toString() ? `?${qs.toString()}` : '';
  return respondPro(
    await callApiPro(req, `/providers/${providerId}/earnings${suffix}`),
  );
}
