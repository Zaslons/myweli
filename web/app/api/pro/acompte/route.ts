import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';

/// Pro BFF: read / replace the salon's deposit policy (owner-only server-side).
export async function GET(req: NextRequest) {
  const providerId = req.nextUrl.searchParams.get('providerId');
  if (!providerId) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/providers/${providerId}/deposit-policy`),
  );
}

export async function PUT(req: NextRequest) {
  const { providerId, policy } = await req.json().catch(() => ({}));
  if (!providerId || !policy) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/providers/${providerId}/deposit-policy`, {
      method: 'PUT',
      body: JSON.stringify(policy),
    }),
  );
}
