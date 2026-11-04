import { type NextRequest, NextResponse } from 'next/server';
import { appleCodeFields } from '../../../../../lib/auth/apple-bff';
import { proLoginViaBackend } from '../../../../../lib/auth-bff';

/// Pro BFF: salon registration (docs/design/web-pro-registration.md) —
/// identity proof (Google idToken | email+code) + business fields in ONE
/// request. A 201 returns the flat ProviderSession → pro httpOnly cookies
/// (the shared helper keys on the token pair, not the status).
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  const { businessName, businessType, phoneNumber } = body;
  // Google, Apple (web-pro-apple.md) or an e-mail code.
  const hasIdentity = body.idToken || body.identityToken || (body.email && body.code);
  if (!businessName || !businessType || !phoneNumber || !hasIdentity) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  // B6.7: Apple's code crosses with an Apple identity only, and the redirect
  // is THIS origin's — a browser-named one is dropped (lib/auth/apple-bff.ts).
  const { authorizationCode, redirectUri: _ignored, ...rest } = body;
  return proLoginViaBackend('/auth/provider/register', {
    ...rest,
    ...(body.identityToken ? appleCodeFields(req, authorizationCode) : {}),
  });
}
