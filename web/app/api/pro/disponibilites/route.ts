import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';

/// Pro BFF: save the salon's availability (full object). Client sends its own
/// providerId; the backend enforces ownership + re-validates the time windows.
export async function PUT(req: NextRequest) {
  const { providerId, availability } = await req.json().catch(() => ({}));
  if (!providerId || !availability) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/providers/${providerId}/availability`, {
      method: 'PUT',
      body: JSON.stringify(availability),
    }),
  );
}
