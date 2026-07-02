import type { NextRequest } from 'next/server';
import { callApi, respond } from '../../../lib/bff';

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
