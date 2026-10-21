import type { NextRequest } from 'next/server';
import { callApi, idempotencyKeyHeader, respond } from '../../../lib/bff';

/// BFF: create a booking under the session. The server prices it + derives the
/// deposit; we forward only the selection. Silent refresh via callApi (M6).
export async function POST(req: NextRequest) {
  const payload = await req.json().catch(() => ({}));
  const result = await callApi(req, '/appointments', {
    method: 'POST',
    // A lost answer is asked again under the same key: the server replays
    // the booking (docs/design/write-idempotency.md §4).
    headers: idempotencyKeyHeader(req),
    body: JSON.stringify({
      providerId: payload.providerId,
      serviceIds: payload.serviceIds,
      appointmentDateTime: payload.appointmentDateTime,
      artistId: payload.artistId ?? undefined,
      // Parity 2.10 — « Notes (optionnel) »; the journal shows it salon-side.
      notes: payload.notes || undefined,
    }),
  });
  // Keep the M5 client contract: { ok, appointment }.
  if (result.status >= 200 && result.status < 300) {
    return respond({ ...result, body: { ok: true, appointment: result.body } });
  }
  return respond(result);
}
