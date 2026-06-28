import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../../lib/bff-pro';

/// Pro BFF: add a team member. Client sends its own providerId; the backend
/// enforces ownership.
export async function POST(req: NextRequest) {
  const { providerId, artist } = await req.json().catch(() => ({}));
  if (!providerId || !artist) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/providers/${providerId}/artists`, {
      method: 'POST',
      body: JSON.stringify(artist),
    }),
  );
}
