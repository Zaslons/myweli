import type { NextRequest } from 'next/server';
import { callApi, enrichAppointments, respond } from '../../../lib/bff';

/// BFF: the signed-in user's bookings (incl. salon-entered, via FR-APPT-008),
/// enriched server-side with provider name/slug + service names.
export async function GET(req: NextRequest) {
  const result = await callApi(req, '/appointments');
  if (result.status === 200) {
    result.body = await enrichAppointments(result.body);
  }
  return respond(result);
}
