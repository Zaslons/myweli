import type { NextRequest } from 'next/server';
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
