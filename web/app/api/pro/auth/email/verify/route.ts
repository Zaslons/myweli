import type { NextRequest } from 'next/server';
import { proLoginViaBackend } from '../../../../../../lib/auth-bff';

/// Pro BFF: verify a salon email OTP → pro cookies (login-only).
export async function POST(req: NextRequest) {
  const { email, code } = await req.json().catch(() => ({}));
  return proLoginViaBackend('/auth/provider/email/otp/verify', { email, code });
}
