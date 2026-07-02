import type { Me } from '../api/account';

/// Browser → BFF wrappers for the auth overhaul (Google + Apple + email OTP).
/// Session lives in httpOnly cookies set by the BFF — no tokens here.
/// Design: docs/design/web-auth-social.md.

export type LoginResult = { ok: boolean; user?: Me | null; error?: string };

async function postLogin(path: string, payload: unknown): Promise<LoginResult> {
  const res = await fetch(path, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
  });
  const body = await res.json().catch(() => ({}));
  return res.ok
    ? { ok: true, user: (body.user as Me | null) ?? null }
    : { ok: false, error: body.error };
}

export const loginWithGoogle = (idToken: string): Promise<LoginResult> =>
  postLogin('/api/auth/google', { idToken });

export const loginWithApple = (payload: {
  identityToken: string;
  nonce?: string;
  fullName?: string;
}): Promise<LoginResult> => postLogin('/api/auth/apple', payload);

export async function requestEmailOtp(
  email: string,
): Promise<{ ok: boolean; devCode?: string; error?: string }> {
  const res = await fetch('/api/auth/email/request', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email }),
  });
  const body = await res.json().catch(() => ({}));
  return res.ok
    ? { ok: true, devCode: body.devCode }
    : { ok: false, error: body.error };
}

export const verifyEmailOtp = (
  email: string,
  code: string,
): Promise<LoginResult> => postLogin('/api/auth/email/verify', { email, code });

/// Save the CONTACT phone on the profile (unverified until proven via SMS).
export async function updateContactPhone(
  phone: string,
): Promise<{ ok: boolean; error?: string }> {
  const res = await fetch('/api/me', {
    method: 'PATCH',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ phone }),
  });
  if (res.ok) return { ok: true };
  const body = await res.json().catch(() => ({}));
  return { ok: false, error: body.error };
}
