import type { NextRequest } from 'next/server';
import { loginViaBackend } from '../../../../lib/auth-bff';

/// BFF: Sign in with Apple — forward the identity token (+ raw nonce and the
/// first-auth name hint) to the backend verifier, then cookie the session.
export async function POST(req: NextRequest) {
  const { identityToken, nonce, fullName } = await req.json().catch(() => ({}));
  return loginViaBackend('/auth/apple', { identityToken, nonce, fullName });
}
