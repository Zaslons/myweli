import type { NextRequest } from 'next/server';
import { appleCodeFields } from '../../../../lib/auth/apple-bff';
import { loginViaBackend } from '../../../../lib/auth-bff';

/// BFF: Sign in with Apple — forward the identity token (+ raw nonce and the
/// first-auth name hint) to the backend verifier, then cookie the session.
/// Apple's code (B6.7) goes with the redirect of THIS origin — never one the
/// browser names (lib/auth/apple-bff.ts).
export async function POST(req: NextRequest) {
  const { identityToken, nonce, fullName, authorizationCode } = await req
    .json()
    .catch(() => ({}));
  return loginViaBackend('/auth/apple', {
    identityToken,
    nonce,
    fullName,
    ...appleCodeFields(req, authorizationCode),
  });
}
