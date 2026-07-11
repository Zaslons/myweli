import type { NextRequest } from 'next/server';
import { callApi, respond } from '../../../../lib/bff';

/// BFF: notification preferences (parity 5.2 — FR-NOTIF-004). GET returns
/// all-true defaults if never set; PUT is a partial merge of booleans.
export async function GET(req: NextRequest) {
  return respond(await callApi(req, '/me/notification-preferences'));
}

export async function PUT(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  return respond(
    await callApi(req, '/me/notification-preferences', {
      method: 'PUT',
      body: JSON.stringify(body),
    }),
  );
}
