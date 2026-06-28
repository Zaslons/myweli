import type { NextRequest } from 'next/server';
import { callApi, enrichAppointment, respond } from '../../../../lib/bff';

/// BFF: one of the signed-in user's bookings (server re-checks ownership).
export async function GET(
  req: NextRequest,
  { params }: { params: { id: string } },
) {
  const result = await callApi(req, `/appointments/${params.id}`);
  if (result.status === 200) {
    result.body = await enrichAppointment(result.body);
  }
  return respond(result);
}
