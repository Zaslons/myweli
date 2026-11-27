import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../../lib/bff-pro';
import { forwardRevenueParams } from '../../../../../lib/pro/revenue-bff';

/// Pro BFF: the bookings behind the revenue figures, a page at a time
/// (docs/design/pro-revenue-analytics.md §7.2). Same gate as the figures;
/// client names come only with `clients.view` (the backend's field gate).
export async function GET(req: NextRequest) {
  const providerId = req.nextUrl.searchParams.get('providerId');
  if (!providerId) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  const qs = forwardRevenueParams(req.nextUrl.searchParams, 'ledger');
  return respondPro(
    await callApiPro(
      req,
      `/providers/${encodeURIComponent(providerId)}/analytics/revenue/appointments${qs}`,
    ),
  );
}
