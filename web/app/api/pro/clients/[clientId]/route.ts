import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../../lib/bff-pro';

type Params = { params: { clientId: string } };

/// Pro BFF: the client card (GET, audited read) + tag updates (PATCH).
export async function GET(req: NextRequest, { params }: Params) {
  const { clientId } = params;
  const providerId = req.nextUrl.searchParams.get('providerId');
  if (!providerId) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/providers/${providerId}/clients/${clientId}`, {
      method: 'GET',
    }),
  );
}

export async function PATCH(req: NextRequest, { params }: Params) {
  const { clientId } = params;
  const { providerId, tags } = await req.json().catch(() => ({}));
  if (!providerId || !Array.isArray(tags)) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/providers/${providerId}/clients/${clientId}`, {
      method: 'PATCH',
      body: JSON.stringify({ tags }),
    }),
  );
}
