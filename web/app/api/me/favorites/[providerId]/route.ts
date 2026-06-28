import type { NextRequest } from 'next/server';
import { callApi, respond } from '../../../../../lib/bff';

/// BFF: add / remove a favorite (idempotent; self-scoped server-side).
export async function POST(
  req: NextRequest,
  { params }: { params: { providerId: string } },
) {
  return respond(
    await callApi(req, `/me/favorites/${params.providerId}`, {
      method: 'POST',
    }),
  );
}

export async function DELETE(
  req: NextRequest,
  { params }: { params: { providerId: string } },
) {
  return respond(
    await callApi(req, `/me/favorites/${params.providerId}`, {
      method: 'DELETE',
    }),
  );
}
