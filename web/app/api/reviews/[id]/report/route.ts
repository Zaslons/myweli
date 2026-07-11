import type { NextRequest } from 'next/server';
import { callApi, respond } from '../../../../../lib/bff';

/// BFF: flag a review for moderation (parity 2.14 — FR-REV-005). Consumer
/// session; idempotent per (review, reporter) server-side; reason optional.
export async function POST(
  req: NextRequest,
  { params }: { params: { id: string } },
) {
  const body = await req.json().catch(() => ({}));
  return respond(
    await callApi(req, `/reviews/${params.id}/report`, {
      method: 'POST',
      body: JSON.stringify(
        typeof body.reason === 'string' && body.reason.trim()
          ? { reason: body.reason.trim().slice(0, 500) }
          : {},
      ),
    }),
  );
}
