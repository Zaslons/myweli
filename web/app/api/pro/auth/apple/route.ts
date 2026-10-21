import type { NextRequest } from 'next/server';
import { appleCodeFields } from '../../../../../lib/auth/apple-bff';
import { proLoginViaBackend } from '../../../../../lib/auth-bff';

/// Pro BFF: Sign in with Apple — the token and its nonce to the backend
/// verifier (`POST /auth/provider/apple`), then the pro session cookies.
/// docs/design/web-pro-apple.md. Apple's code (B6.7) goes with the redirect
/// of THIS origin — never one the browser names (lib/auth/apple-bff.ts).
export async function POST(req: NextRequest) {
  const { identityToken, nonce, authorizationCode } = await req.json().catch(() => ({}));
  return proLoginViaBackend('/auth/provider/apple', {
    identityToken,
    nonce,
    ...appleCodeFields(req, authorizationCode),
  });
}
