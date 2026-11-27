import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';
import { forwardRevenueParams } from '../../../../lib/pro/revenue-bff';

/// Pro BFF: the salon's revenue analytics — one period, its comparison, the
/// figures and the breakdowns (docs/design/pro-revenue-analytics.md §7.1).
/// The client passes its own providerId; the backend enforces `finances.view`
/// on that salon (→ 403) and validates every parameter (→ 400).
export async function GET(req: NextRequest) {
  const providerId = req.nextUrl.searchParams.get('providerId');
  if (!providerId) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  const qs = forwardRevenueParams(req.nextUrl.searchParams, 'analytics');
  return respondPro(
    await callApiPro(
      req,
      `/providers/${encodeURIComponent(providerId)}/analytics/revenue${qs}`,
    ),
  );
}
