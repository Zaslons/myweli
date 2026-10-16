import type { NextRequest } from 'next/server';
import { callApi, enrichAppointments, respond } from '../../../lib/bff';

/// BFF: the signed-in user's bookings (incl. salon-entered, via FR-APPT-008),
/// enriched server-side with provider name/slug + service names. A 200
/// without its list is a 502 (`enrichAppointments`).
export async function GET(req: NextRequest) {
  return respond(enrichAppointments(await callApi(req, '/appointments')));
}
