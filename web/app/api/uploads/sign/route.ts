import type { NextRequest } from 'next/server';
import { callApi, respond } from '../../../../lib/bff';

/// BFF: presign a CONSUMER upload — deposit proofs and review photos only.
/// The purpose is whitelisted here (default `deposit`) — the consumer surface
/// can never sign gallery/KYC uploads (those live behind the pro BFF). The
/// API scopes each key under the caller's own `{purpose}/{userId}/` prefix.
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  const result = await callApi(req, '/uploads/sign', {
    method: 'POST',
    body: JSON.stringify({
      contentType: body.contentType,
      purpose: body.purpose === 'review' ? 'review' : 'deposit',
    }),
  });
  return respond(result);
}
