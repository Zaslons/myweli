import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../../lib/bff-pro';

/// Pro BFF: presign a pro upload. The object key is derived server-side from
/// the token's account (the client can't target another salon). Purpose is
/// allowlisted to the PRO purposes — `gallery` (default) or `kyc`; `deposit`
/// stays consumer-only on the consumer BFF (docs/design/web-pro-kyc.md §3).
export async function POST(req: NextRequest) {
  const { contentType, purpose } = await req.json().catch(() => ({}));
  if (!contentType || (purpose != null && !['gallery', 'kyc'].includes(purpose))) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, '/uploads/sign', {
      method: 'POST',
      body: JSON.stringify({ contentType, purpose: purpose ?? 'gallery' }),
    }),
  );
}
