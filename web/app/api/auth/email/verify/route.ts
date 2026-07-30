import type { NextRequest } from 'next/server';
import { loginViaBackend } from '../../../../../lib/auth-bff';

/// BFF: verify an email OTP → cookie the session.
export async function POST(req: NextRequest) {
  const { email, code } = await req.json().catch(() => ({}));
  return loginViaBackend('/auth/email/otp/verify', { email, code });
}
