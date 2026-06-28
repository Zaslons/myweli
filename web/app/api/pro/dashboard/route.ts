import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';

/// Pro BFF: server-computed dashboard stats for the salon (owner-only). Client
/// passes its own providerId; the backend enforces ownership.
export async function GET(req: NextRequest) {
  const providerId = req.nextUrl.searchParams.get('providerId');
  if (!providerId) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(await callApiPro(req, `/providers/${providerId}/dashboard`));
}
