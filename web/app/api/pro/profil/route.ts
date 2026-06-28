import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';

/// Pro BFF: update the salon's public profile. Client sends its own providerId;
/// the backend enforces ownership + the field allowlist.
export async function PATCH(req: NextRequest) {
  const { providerId, profile } = await req.json().catch(() => ({}));
  if (!providerId || !profile) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/providers/${providerId}`, {
      method: 'PATCH',
      body: JSON.stringify(profile),
    }),
  );
}
