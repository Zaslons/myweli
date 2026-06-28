import { type NextRequest, NextResponse } from 'next/server';
import { callApiPro, respondPro } from '../../../../../lib/bff-pro';

/// Pro BFF: presign a gallery upload. The object key is derived server-side from
/// the token's salon (the client can't target another salon). Only `gallery`.
export async function POST(req: NextRequest) {
  const { contentType } = await req.json().catch(() => ({}));
  if (!contentType) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return respondPro(
    await callApiPro(req, '/uploads/sign', {
      method: 'POST',
      body: JSON.stringify({ contentType, purpose: 'gallery' }),
    }),
  );
}
