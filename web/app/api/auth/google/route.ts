import type { NextRequest } from 'next/server';
import { loginViaBackend } from '../../../../lib/auth-bff';

/// BFF: Google Sign-In — forward the GIS credential (ID token) to the backend
/// verifier, then cookie the session. Design: docs/design/web-auth-social.md.
export async function POST(req: NextRequest) {
  const { idToken } = await req.json().catch(() => ({}));
  return loginViaBackend('/auth/google', { idToken });
}
