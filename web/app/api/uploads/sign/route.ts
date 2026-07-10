import type { NextRequest } from 'next/server';
import { callApi, respond } from '../../../../lib/bff';

/// BFF: presign a consumer deposit-proof upload. The purpose is FIXED to
/// `deposit` here — the consumer surface can never sign gallery/KYC uploads
/// (those live behind the pro BFF). The API scopes the key under the caller's
/// own `deposit/{userId}/` prefix.
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  const result = await callApi(req, '/uploads/sign', {
    method: 'POST',
    body: JSON.stringify({
      contentType: body.contentType,
      purpose: 'deposit',
    }),
  });
  return respond(result);
}
