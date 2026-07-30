import type { NextRequest } from 'next/server';
import { callApi, respond } from '../../../../lib/bff';

/// BFF: the caller's in-app notification feed (parity 5.1 — self-scoped ≤50).
export async function GET(req: NextRequest) {
  return respond(await callApi(req, '/me/notifications'));
}
