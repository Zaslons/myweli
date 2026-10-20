import type { NextRequest } from 'next/server';
import { proLoginViaBackend } from '../../../../../lib/auth-bff';

/// Pro BFF: Sign in with Apple — the token and its nonce to the backend
/// verifier (`POST /auth/provider/apple`), then the pro session cookies.
/// docs/design/web-pro-apple.md.
export async function POST(req: NextRequest) {
  const { identityToken, nonce } = await req.json().catch(() => ({}));
  return proLoginViaBackend('/auth/provider/apple', { identityToken, nonce });
}
