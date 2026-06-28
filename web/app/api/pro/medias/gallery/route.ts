import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../../lib/bff-pro';

/// Pro BFF: replace the salon's gallery (ordered imageUrls). Backend re-validates
/// the URL allowlist/cap + ownership.
export async function PUT(req: NextRequest) {
  const { providerId, imageUrls } = await req.json().catch(() => ({}));
  if (!providerId || !Array.isArray(imageUrls)) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, `/providers/${providerId}/gallery`, {
      method: 'PUT',
      body: JSON.stringify({ imageUrls }),
    }),
  );
}
