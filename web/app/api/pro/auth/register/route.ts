import { type NextRequest, NextResponse } from 'next/server';
import { proLoginViaBackend } from '../../../../../lib/auth-bff';

/// Pro BFF: salon registration (docs/design/web-pro-registration.md) —
/// identity proof (Google idToken | email+code) + business fields in ONE
/// request. A 201 returns the flat ProviderSession → pro httpOnly cookies
/// (the shared helper keys on the token pair, not the status).
export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  const { businessName, businessType, phoneNumber } = body;
  const hasIdentity = body.idToken || (body.email && body.code);
  if (!businessName || !businessType || !phoneNumber || !hasIdentity) {
    return NextResponse.json({ error: 'invalid_input' }, { status: 400 });
  }
  return proLoginViaBackend('/auth/provider/register', body);
}
