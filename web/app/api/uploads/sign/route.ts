import type { NextRequest } from 'next/server';
import { callApi, respond } from '../../../../lib/bff';

/// BFF: presign a CONSUMER upload — deposit proofs, review photos, avatars.
/// The purpose is allowlisted here, so the consumer surface can never sign
/// gallery/KYC uploads (those live behind the pro BFF). The API scopes each key
/// under the caller's own `{purpose}/{userId}/` prefix.
const CONSUMER_PURPOSES = ['deposit', 'review', 'avatar'] as const;

export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  // **Reject, do not coerce.** This read `body.purpose === 'review' ? 'review'
  // : 'deposit'`, so ANY other value — a typo, a new purpose a client learns
  // before this route does — silently signed a DEPOSIT: the wrong bucket, the
  // wrong prefix, and a 200 that looks like success. An unknown purpose is a
  // bad request, and the caller should be told so.
  if (!CONSUMER_PURPOSES.includes(body.purpose)) {
    return Response.json({ error: 'invalid_input' }, { status: 400 });
  }
  const result = await callApi(req, '/uploads/sign', {
    method: 'POST',
    body: JSON.stringify({
      contentType: body.contentType,
      purpose: body.purpose,
    }),
  });
  return respond(result);
}
