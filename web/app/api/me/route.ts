import type { NextRequest } from 'next/server';
import { callApi, respond } from '../../../lib/bff';
import { clearSessionCookies } from '../../../lib/session';

/// BFF: the signed-in user's profile (+ session check).
export async function GET(req: NextRequest) {
  return respond(await callApi(req, '/me'));
}

/// BFF: update own profile fields — used for the CONTACT phone (auth overhaul:
/// phone is contact data, unverified until proven via SMS later).
export async function PATCH(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  return respond(
    await callApi(req, '/me', { method: 'PATCH', body: JSON.stringify(body) }),
  );
}

/// BFF: delete the account (parity 11.1 — AUTH-004). The API anonymizes the
/// user across salon CRMs (T48); on success the web session ends too.
export async function DELETE(req: NextRequest) {
  const result = await callApi(req, '/me', { method: 'DELETE' });
  const res = respond(result);
  if (result.status >= 200 && result.status < 300) {
    clearSessionCookies(res);
  }
  return res;
}
