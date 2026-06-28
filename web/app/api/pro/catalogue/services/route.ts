import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../../lib/bff-pro';

/// Pro BFF: create a service. The client sends its own providerId; the backend
/// enforces ownership (account.providerId == pid → else 403).
export async function POST(req: NextRequest) {
  const { providerId, service } = await req.json().catch(() => ({}));
  if (!providerId || !service) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/providers/${providerId}/services`, {
      method: 'POST',
      body: JSON.stringify(service),
    }),
  );
}
