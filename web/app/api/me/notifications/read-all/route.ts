import type { NextRequest } from 'next/server';
import { callApi, respond } from '../../../../../lib/bff';

/// BFF: mark every notification read (« Tout lire » — parity 5.1).
export async function POST(req: NextRequest) {
  return respond(
    await callApi(req, '/me/notifications/read-all', { method: 'POST' }),
  );
}
