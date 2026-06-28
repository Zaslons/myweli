import type { NextRequest } from 'next/server';
import { callApi, respond } from '../../../../../lib/bff';

/// BFF: cancel the caller's own booking (server enforces the policy + ownership).
export async function POST(
  req: NextRequest,
  { params }: { params: { id: string } },
) {
  return respond(
    await callApi(req, `/appointments/${params.id}/cancel`, { method: 'POST' }),
  );
}
