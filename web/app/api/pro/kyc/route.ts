import type { NextRequest } from 'next/server';
import { callApiPro, respondPro } from '../../../../lib/bff-pro';

/// Pro BFF: the signed-in provider's KYC (docs/design/web-pro-kyc.md).
/// Self-scoped upstream — /me/kyc resolves the account from the token.
export async function GET(req: NextRequest) {
  return respondPro(await callApiPro(req, '/me/kyc'));
}

export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  return respondPro(
    await callApiPro(req, '/me/kyc', {
      method: 'POST',
      body: JSON.stringify({ documents: body.documents ?? [] }),
    }),
  );
}
