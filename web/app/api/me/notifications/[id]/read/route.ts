import type { NextRequest } from 'next/server';
import { callApi, respond } from '../../../../../../lib/bff';

/// BFF: mark one notification read (self-scoped — parity 5.1).
export async function POST(
  req: NextRequest,
  { params }: { params: { id: string } },
) {
  return respond(
    await callApi(req, `/me/notifications/${params.id}/read`, {
      method: 'POST',
    }),
  );
}
