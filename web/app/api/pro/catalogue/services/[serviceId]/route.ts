import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../../../lib/bff-pro';

/// Pro BFF: update / delete a service (backend enforces ownership). The client
/// passes its own providerId (body for PATCH, query for DELETE).
export async function PATCH(
  req: NextRequest,
  { params }: { params: { serviceId: string } },
) {
  const { providerId, service } = await req.json().catch(() => ({}));
  if (!providerId || !service) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(
      req,
      `/providers/${providerId}/services/${params.serviceId}`,
      { method: 'PATCH', body: JSON.stringify(service) },
    ),
  );
}

export async function DELETE(
  req: NextRequest,
  { params }: { params: { serviceId: string } },
) {
  const providerId = req.nextUrl.searchParams.get('providerId');
  if (!providerId) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(
      req,
      `/providers/${providerId}/services/${params.serviceId}`,
      { method: 'DELETE' },
    ),
  );
}
