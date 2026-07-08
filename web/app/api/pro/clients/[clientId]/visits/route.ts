import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../../../lib/bff-pro';

type Params = { params: { clientId: string } };

/// Pro BFF: the client's visit history AT THIS SALON (paginated).
export async function GET(req: NextRequest, { params }: Params) {
  const { clientId } = params;
  const p = req.nextUrl.searchParams;
  const providerId = p.get('providerId');
  if (!providerId) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  const qs = new URLSearchParams();
  for (const key of ['page', 'pageSize']) {
    const v = p.get(key);
    if (v) qs.set(key, v);
  }
  const suffix = qs.size ? `?${qs}` : '';
  return respondPro(
    await callApiPro(
      req,
      `/providers/${providerId}/clients/${clientId}/visits${suffix}`,
      { method: 'GET' },
    ),
  );
}
