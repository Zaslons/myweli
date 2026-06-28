import type { NextRequest } from 'next/server';
import { callApi, respond } from '../../../lib/bff';

/// BFF: the signed-in user's profile (+ session check).
export async function GET(req: NextRequest) {
  return respond(await callApi(req, '/me'));
}
