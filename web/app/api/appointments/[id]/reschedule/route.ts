import type { NextRequest } from 'next/server';
import { callApi, respond } from '../../../../../lib/bff';

/// BFF: the consumer moves their own booking (« Reporter » — parity 1.1).
/// The role-aware endpoint re-validates the new slot server-side; a taken
/// slot → 409 slot_unavailable.
export async function POST(
  req: NextRequest,
  { params }: { params: { id: string } },
) {
  const body = await req.json().catch(() => ({}));
  return respond(
    await callApi(req, `/appointments/${params.id}/reschedule`, {
      method: 'POST',
      body: JSON.stringify({ newDateTime: body.newDateTime }),
    }),
  );
}
