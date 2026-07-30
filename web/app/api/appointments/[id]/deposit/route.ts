import type { NextRequest } from 'next/server';
import { callApi, respond } from '../../../../../lib/bff';

/// BFF: attach the deposit-payment screenshot to the caller's own pending
/// booking (the server re-checks ownership + state + key prefix).
export async function POST(
  req: NextRequest,
  { params }: { params: { id: string } },
) {
  const body = await req.json().catch(() => ({}));
  const result = await callApi(req, `/appointments/${params.id}/deposit`, {
    method: 'POST',
    body: JSON.stringify({ screenshotKey: body.screenshotKey }),
  });
  return respond(result);
}
