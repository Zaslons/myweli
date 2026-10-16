import type { Me } from '../api/account';
import { readJson, send } from '../api/network';

/// Browser → BFF wrappers for the auth overhaul (Google + Apple + email OTP).
/// Session lives in httpOnly cookies set by the BFF — no tokens here.
/// Design: docs/design/web-auth-social.md.
///
/// None of them throws (docs/design/web-consumer-network-failure.md §2):
/// `status` 0 = no answer — the login says « Pas de connexion », never a
/// wrong e-mail or code it did not get to judge.

export type LoginResult = {
  ok: boolean;
  status: number;
  user?: Me | null;
  error?: string;
};

async function postLogin(path: string, payload: unknown): Promise<LoginResult> {
  const res = await send(path, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload),
  });
  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as { error?: string };
    return { ok: false, status: res.status, error: body.error };
  }
  const body = await readJson<{ user?: Me | null }>(res);
  return { ok: true, status: res.status, user: body?.user ?? null };
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
): Promise<{ ok: boolean; status: number; devCode?: string; error?: string }> {
  const res = await send('/api/auth/email/request', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email }),
  });
  const body = await res.json().catch(() => ({}));
  return res.ok
    ? { ok: true, status: res.status, devCode: body.devCode }
    : { ok: false, status: res.status, error: body.error };
}

export const verifyEmailOtp = (
  email: string,
  code: string,
): Promise<LoginResult> => postLogin('/api/auth/email/verify', { email, code });

/// Save the CONTACT phone on the profile (unverified until proven via SMS).
export async function updateContactPhone(
  phone: string,
): Promise<{ ok: boolean; status: number; error?: string }> {
  const res = await send('/api/me', {
    method: 'PATCH',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ phone }),
  });
  if (res.ok) return { ok: true, status: res.status };
  const body = await res.json().catch(() => ({}));
  return { ok: false, status: res.status, error: body.error };
}
