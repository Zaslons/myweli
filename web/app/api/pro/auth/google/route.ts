import type { NextRequest } from 'next/server';
import { proLoginViaBackend } from '../../../../../lib/auth-bff';

/// Pro BFF: salon Google sign-in (LOGIN-ONLY — provider_not_found nudges the
/// pro app for registration). Design: docs/design/pro-auth-social.md.
export async function POST(req: NextRequest) {
  const { idToken } = await req.json().catch(() => ({}));
  return proLoginViaBackend('/auth/provider/google', { idToken });
}
