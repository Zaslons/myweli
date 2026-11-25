import type { NextRequest } from 'next/server';
import {
  BOOKING_CHANNEL_HEADER,
  callApi,
  idempotencyKeyHeader,
  respond,
} from '../../../lib/bff';

/// BFF: create a booking under the session. The server prices it + derives the
/// deposit; we forward only the selection. Silent refresh via callApi (M6).
export async function POST(req: NextRequest) {
  const payload = await req.json().catch(() => ({}));
  const result = await callApi(req, '/appointments', {
    method: 'POST',
    headers: {
      // A lost answer is asked again under the same key: the server replays
      // the booking (docs/design/write-idempotency.md §4).
      ...idempotencyKeyHeader(req),
      // Made on the website: the salon's « Canaux » count it as « Site
      // MyWeli » (docs/design/pro-revenue-analytics.md §8.2).
      ...BOOKING_CHANNEL_HEADER,
    },
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
