import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../../lib/bff-pro';

/// Pro BFF: replace the salon's before/after pairs (≤12). Backend re-validates.
export async function PUT(req: NextRequest) {
  const { providerId, beforeAfters } = await req.json().catch(() => ({}));
  if (!providerId || !Array.isArray(beforeAfters)) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/providers/${providerId}/before-after`, {
      method: 'PUT',
      body: JSON.stringify({ beforeAfters }),
    }),
  );
}
